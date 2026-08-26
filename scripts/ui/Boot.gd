## 부팅 화면 — 제작사 로고. (sprites/build_logo.py)
##
## "아이는 이 화면을 수백 번 본다" — 그래서 **아무 키나 누르면 즉시 건너뛴다.**
## 건너뛰기가 없는 로고 화면은 두 번째부터 벌이 된다.
extends Control

const LOGO_PATH := "res://sprites/extracted/ui/logo_screen.png"
const FIELD_SCENE := "res://scenes/field/Field.tscn"

@export var fade_in := 0.6
@export var hold := 1.3
@export var fade_out := 0.4

@onready var _logo: TextureRect = $Logo

var _elapsed := 0.0
var _leaving := false


func _ready() -> void:
	if ResourceLoader.exists(LOGO_PATH):
		_logo.texture = load(LOGO_PATH)
	else:
		# 로고가 없어도 게임은 떠야 한다. 바로 필드로 넘긴다.
		_leave()
	modulate.a = 0.0


func _process(delta: float) -> void:
	if _leaving:
		return
	_elapsed += delta
	if _elapsed < fade_in:
		modulate.a = _elapsed / fade_in
	elif _elapsed < fade_in + hold:
		modulate.a = 1.0
	elif _elapsed < fade_in + hold + fade_out:
		modulate.a = 1.0 - (_elapsed - fade_in - hold) / fade_out
	else:
		_leave()


## 아무 키·버튼·클릭이면 된다. 무엇을 눌러야 하는지 알아낼 필요가 없어야 한다.
func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
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
	get_tree().change_scene_to_file(FIELD_SCENE)
