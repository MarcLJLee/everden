## 머리 위 아이콘. head_anchor 에 맞춰 놓고 감각별로 색을 바꾼다. (DEMO-SPEC §3.4)
extends Sprite2D

var _head_anchor := Vector2i(16, 4)
var _canvas_offset := Vector2.ZERO
var _current_sense := ""

func setup(sprite_set: Dictionary, canvas_offset: Vector2) -> void:
	var anchor: Array = sprite_set.get("head_anchor", [16, 4])
	_head_anchor = Vector2i(int(anchor[0]), int(anchor[1]))
	_canvas_offset = canvas_offset
	hide_icon()

## icon_name 이 비어 있으면 색 사각형으로 떨어진다.
func show_sense(sense: String, icon_name := "") -> void:
	if sense == _current_sense and visible:
		return
	_current_sense = sense
	var drawn := SpriteLibrary.emote_texture(icon_name)
	texture = drawn if drawn != null else PlaceholderArt.emote_texture(sense)
	var size := texture.get_size()
	# 아이콘은 머리 위에 뜬다 — 앵커보다 한 뼘 더 위로.
	position = Vector2(
		int(_head_anchor.x - size.x / 2.0),
		int(_head_anchor.y - size.y - 2)) + _canvas_offset
	visible = true

func hide_icon() -> void:
	_current_sense = ""
	visible = false
