## 필드를 나오는 문. (BRIEF §3.13 · ui/screens.json)
##
## ★ **지금까지 나가는 길이 아예 없었다** — 원정을 나가면 못 돌아왔다.
##   그게 이 화면이 생긴 이유다.
## ★ **쏟다 만 게이지는 개체에 남는다.** 그러니 나가는 것이 손해가 아니다 (원칙 2) —
##   묻는 말도 그렇게 생겨야 한다: 경고가 아니라 물음이다.
## ★ 같이 가는 아이는 **얼굴 줄**로 보여준다. "동료 2 / 초대 1" 처럼 숫자로 적지 않는다 —
##   숫자를 적으면 그게 성적표가 된다 (§6.9 의 `art` 자리).
## ⚠️ 고를 것은 둘뿐이다. 기본은 언제나 안전한 쪽 — **더 놀래요**.
extends CanvasLayer

signal go_home

const HANGUL_FONT := "res://fonts/Galmuri11.ttf"

@onready var _art: Node2D = $Art
@onready var _text: Control = $Text

var _open := false
var _leaving := false
## 무엇을 데리고 가는지 물어볼 때 필드가 알려준다.
var faces_provider := Callable()


func _ready() -> void:
	visible = false


## faces 는 데려온 동료와 오늘 초대한 아이의 종 정의 목록이다.
func open(faces: Array) -> void:
	for node in _art.get_children() + _text.get_children():
		node.get_parent().remove_child(node)
		node.queue_free()

	var house := Sprite2D.new()
	house.texture = SpriteLibrary.ui_texture("map_home")
	house.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	house.centered = false
	house.scale = Vector2.ONE * 2
	if house.texture != null:
		house.position = Vector2(304, 96)
		_art.add_child(house)

	var ask := _label("집에 갈까요?", 22, Vector2(0, 140))
	ask.size.x = 640
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 같이 가는 아이 — 얼굴 줄. 숫자로 적지 않는다.
	var x := 320.0 - faces.size() * 16.0
	for species in faces:
		Faces.place(_art, Faces.of(species), Vector2(x, 184), 2)
		x += 32.0

	_leaving = false
	_draw_choice()
	Keycap.place(_art, "메뉴", Vector2(300, 296))
	_open = true
	visible = true


func _draw_choice() -> void:
	for node in _text.get_children():
		if node.has_meta("choice"):
			node.get_parent().remove_child(node)
			node.queue_free()
	var yes := _label("갈래요", 11, Vector2(0, 244))
	yes.size.x = 300
	yes.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	yes.modulate = Color(1.0, 0.92, 0.55) if _leaving else Color(1, 1, 1, 0.5)
	yes.set_meta("choice", true)
	var no := _label("더 놀래요", 11, Vector2(340, 244))
	no.size.x = 300
	no.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	no.modulate = Color(1, 1, 1, 0.5) if _leaving else Color(1.0, 0.92, 0.55)
	no.set_meta("choice", true)


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


## ⚠️ **여는 키도 여기서 받는다.** 필드가 따로 폴링하면 같은 한 번의 누름을
##    양쪽이 보게 되어 **열자마자 닫힌다.** 키 하나는 한 곳이 갖는다.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed("open_menu"):
		if _open:
			close()
		elif faces_provider.is_valid():
			open(faces_provider.call())
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_leaving = not _leaving
		_draw_choice()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		if _leaving:
			close()
			go_home.emit()
		else:
			close()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()


func _label(text: String, size: int, at: Vector2) -> Label:
	var label := Label.new()
	if ResourceLoader.exists(HANGUL_FONT):
		label.add_theme_font_override("font", load(HANGUL_FONT))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.text = text
	label.position = at
	_text.add_child(label)
	return label
