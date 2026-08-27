## 눈·입 앵커 배치와 북향 숨김. Body 노드에 붙는다. (DEMO-SPEC §3.1, §3.2)
##
## 앵커는 animals.json 의 값을 그대로 쓴다. **프레임별 앵커는 만들지 않는다.**
## 얼굴 파츠가 Body 의 자식이므로 바운스는 부모를 따라간다.
extends Node2D

var _eye: Sprite2D = null
var _mouth: Sprite2D = null
var _dimorph: Sprite2D = null

var _canvas := Vector2i(32, 32)
var _canvas_offset := Vector2.ZERO
var _eye_anchor := {}
var _mouth_anchor := {}
var _drawn_art := false
var _species_id := ""
var _has_mouth := true
var _expression := "기본"
var _placeholder_eye_style := "round"
var _eye_style_texture := {}
var _shine_color := Color.WHITE
var _shine_on := false
var _last_angle := ""
## 이 종의 암수 이형 (palettes.json 의 dimorphism). 표에 없는 종은 비어 있다.
var _dimorph_spec := {}

func setup(sprite_set: Dictionary, canvas: Vector2i, canvas_offset: Vector2,
		drawn_art := false, species_id := "", sex := "") -> void:
	_eye = get_node("Eye")
	_mouth = get_node("Mouth")
	_dimorph = get_node("Dimorph")
	_canvas = canvas
	_drawn_art = drawn_art
	_species_id = species_id
	# 캔버스 좌상단의 위치는 Actor 가 접지선까지 반영해 계산해 넘겨준다.
	_canvas_offset = canvas_offset
	_eye_anchor = sprite_set.get("eye_anchor", {})
	_mouth_anchor = sprite_set.get("mouth_anchor", {})
	_placeholder_eye_style = String(sprite_set.get("eye_style", "round"))
	# 입은 프로토타입에서 생략한다 — 눈이 매력의 90%다 (BRIEF §8).
	# 앵커는 데이터에 남겨두되, 그려진 종에 입 그림이 없으면 레이어를 두지 않는다.
	# 색 사각형 입을 그린 그림 위에 얹으면 그게 더 이상하다.
	_has_mouth = _mouth_anchor.size() > 0
	if _has_mouth and _drawn_art:
		var drawn_mouth := SpriteLibrary.mouth_texture(_species_id)
		_has_mouth = drawn_mouth != null
		_mouth.texture = drawn_mouth
	elif _has_mouth:
		_mouth.texture = PlaceholderArt.mouth_texture(String(sprite_set.get("mouth_style", "small")))
	_mouth.visible = _has_mouth

	# ★ 암수 이형은 **눈·입과 같은 파츠**다 (BRIEF §4.9). 몸통 시트를 성별로 나누지 않는다 —
	#   나눴다면 종당 16장이 32장이 됐다. 파츠면 정면·측면 2장이다.
	#   ⚠️ 표에 그 종이 있는지만 본다. `if species == "water_deer"` 를 쓰면 설계가 틀린 것이다.
	_dimorph_spec = SpriteLibrary.dimorphism_for(_species_id)
	if not _dimorph_spec.is_empty() and sex == String(_dimorph_spec.get("shown_on", "")):
		var files: Dictionary = _dimorph_spec.get("file", {})
		_dimorph.texture = SpriteLibrary.dimorph_texture(String(files.get("front", "")))
	else:
		_dimorph_spec = {}
	_dimorph.visible = _dimorph.texture != null
	_apply_expression("기본")

## facing: "north" | "south" | "east" | "west"
func apply_facing(facing: String) -> void:
	if _eye == null:
		return
	# 뒷모습엔 얼굴이 없다. (DEMO-SPEC §3.1)
	var visible_face := facing != "north"
	_eye.visible = visible_face   # 텍스처가 없으면 _set_eye_texture 가 다시 끈다
	_mouth.visible = visible_face and _has_mouth
	# 뒷모습에서는 이형도 숨는다 — 눈·입에 이미 있는 규칙을 그대로 쓴다
	_dimorph.visible = visible_face and not _dimorph_spec.is_empty()
	if not visible_face:
		return

	var angle := "front" if facing == "south" else "side"
	var mirror := facing == "west"
	_set_eye_texture(angle)
	_place(_eye, _eye_anchor.get(angle, [16, 11]), mirror)
	if _has_mouth:
		_place(_mouth, _mouth_anchor.get(angle, [16, 16]), mirror)
	if not _dimorph_spec.is_empty():
		var files: Dictionary = _dimorph_spec.get("file", {})
		_dimorph.texture = SpriteLibrary.dimorph_texture(String(files.get(angle, "")))
		_dimorph.visible = _dimorph.texture != null
		if _dimorph.visible:
			_place(_dimorph, _dimorph_spec.get("anchor", {}).get(angle, [16, 16]), mirror)


## 어두울 때 눈이 되비춘다. (tags.json 의 eyeshine)
## cancel 은 화면 전체 틴트를 되돌리는 값이다 — 되비추는 빛은 어둠에 같이 묻히지 않는다.
func set_eyeshine(on: bool, color: Color, cancel: Color) -> void:
	if on == _shine_on and color == _shine_color:
		if on:
			_eye.self_modulate = cancel
		return
	_shine_on = on
	_shine_color = color
	_eye_style_texture.clear()
	_eye.self_modulate = cancel if on else Color.WHITE
	if _eye != null:
		_set_eye_texture("front" if _last_angle.is_empty() else _last_angle)


## 표정을 바꿔도 몸통은 그대로다 — 눈만 갈아끼운다. (BRIEF §4.6)
func set_expression(expression: String) -> void:
	if expression == _expression:
		return
	_apply_expression(expression)


func _apply_expression(expression: String) -> void:
	_expression = expression
	_eye_style_texture.clear()


func _set_eye_texture(angle: String) -> void:
	_last_angle = angle
	if _eye_style_texture.has(angle):
		_eye.texture = _eye_style_texture[angle]
		return
	var texture: Texture2D = null
	if _drawn_art:
		# 그려진 종인데 눈 그림이 없으면 몸통에 얼굴이 이미 있다는 뜻이다. 얹지 않는다.
		texture = SpriteLibrary.eye_texture(_species_id, angle, _expression, _placeholder_eye_style)
		_eye.visible = texture != null
	else:
		texture = PlaceholderArt.eye_texture(_placeholder_eye_style)
	if _shine_on:
		texture = SpriteLibrary.eyeshine_texture(texture, _shine_color)
	_eye_style_texture[angle] = texture
	_eye.texture = texture

func _place(part: Sprite2D, anchor: Array, mirror: bool) -> void:
	if part.texture == null:
		return
	var size := part.texture.get_size()
	var anchor_x := float(anchor[0])
	if mirror:
		anchor_x = _canvas.x - anchor_x
	part.flip_h = mirror
	# 앵커는 파츠의 중심점이다. 정수 픽셀로 스냅한다.
	part.position = Vector2(
		int(anchor_x - size.x / 2.0),
		int(float(anchor[1]) - size.y / 2.0)) + _canvas_offset
