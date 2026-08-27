## 부팅 화면 — 제작사 로고 `RUN II`. (sprites/build_logo.py · ui/logo.json)
##
## 큰 발자국이 하나씩 찍히다가 어느 지점부터 작은 발자국이 나란히 붙고,
## 그다음 이름이 떠오른다. 좌표와 타이밍은 전부 `ui/logo.json` 에 있다 —
## 로고를 다시 그려도 이 스크립트는 안 고친다.
##
## "아이는 이 화면을 수백 번 본다" — **아무 키나 누르면 즉시 건너뛴다.**
extends Control

const DATA_PATH := "res://sprites/extracted/ui/logo.json"
const ART_ROOT := "res://sprites/extracted/"
const NEXT_SCENE := "res://scenes/ui/Title.tscn"

## 마지막 프레임에서 머무는 시간. json 의 시퀀스가 끝난 뒤다.
@export var hold_after := 0.7
@export var fade_out := 0.45

@onready var _background: ColorRect = $Background

var _frame_seconds := 0.08
var _sequence_frames := 32
var _paws: Array = []          ## [{ "node": Sprite2D, "frame": int }]
var _mark: Sprite2D = null
var _mark_from := 0
var _mark_fade := 1
var _skippable := true
var _elapsed := 0.0
var _leaving := false


func _ready() -> void:
	if not _build_from_data():
		# logo_screen.png 은 검수용이라 게임에서 읽지 않는다.
		# 조각이 없으면 로고를 건너뛴다 — 로고가 게임을 막지 않는다.
		_leave()


## json 이 있으면 조각을 놓고 애니메이션한다. 없으면 false.
func _build_from_data() -> bool:
	if not FileAccess.file_exists(DATA_PATH):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed

	var background: Array = data.get("background", [14, 15, 19])
	_background.color = Color8(int(background[0]), int(background[1]), int(background[2]))

	var timing: Dictionary = data.get("timing", {})
	_sequence_frames = int(timing.get("frames", 32))
	_frame_seconds = float(timing.get("frame_ms", 80)) / 1000.0
	_mark_from = int(timing.get("mark_from", 17))
	_mark_fade = maxi(1, int(timing.get("mark_fade_frames", 7)))
	_skippable = bool(data.get("skippable", true))

	var big := _place_paws(data.get("big", []), String(data.get("paw_big", "")),
		int(timing.get("big_from", 3)), int(timing.get("big_every", 2)))
	var small := _place_paws(data.get("small", []), String(data.get("paw_small", "")),
		int(timing.get("small_from", 11)), int(timing.get("small_every", 2)))
	if not (big and small):
		return false

	_mark = _sprite(String(data.get("wordmark", "")), data.get("wordmark_at", [0, 0]))
	if _mark == null:
		return false
	_mark.modulate.a = 0.0
	return true


func _place_paws(positions: Array, relative: String, from_frame: int, every: int) -> bool:
	for i in positions.size():
		var paw := _sprite(relative, positions[i])
		if paw == null:
			return false
		paw.visible = false
		_paws.append({"node": paw, "frame": from_frame + i * every})
	return true


## 좌표는 스프라이트의 **좌상단** 기준이다 (logo.json).
func _sprite(relative: String, at) -> Sprite2D:
	var path := ART_ROOT + relative
	if relative.is_empty() or not ResourceLoader.exists(path):
		return null
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.centered = false
	sprite.position = Vector2(float(at[0]), float(at[1]))
	add_child(sprite)
	return sprite


func _process(delta: float) -> void:
	if _leaving:
		return
	_elapsed += delta
	var frame := _elapsed / _frame_seconds
	for entry in _paws:
		entry["node"].visible = frame >= float(entry["frame"])
	if _mark != null:
		_mark.modulate.a = clampf((frame - _mark_from) / float(_mark_fade), 0.0, 1.0)

	var sequence_seconds := _sequence_frames * _frame_seconds
	var leave_at := sequence_seconds + hold_after
	if _elapsed >= leave_at + fade_out:
		_leave()
	elif _elapsed >= leave_at:
		modulate.a = 1.0 - (_elapsed - leave_at) / fade_out


## 아무 키·버튼·클릭이면 된다. 무엇을 눌러야 하는지 알아낼 필요가 없어야 한다.
func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not _skippable:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or event is InputEventScreenTouch
	if pressed:
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	# _ready 안에서 부를 수도 있다 (로고 파일이 없을 때). 그때 바로 바꾸면
	# "Parent node is busy adding/removing children" 로 터진다.
	get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
