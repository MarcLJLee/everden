## 커플 카드 — 집에서 가끔 일어나는 일. (BRIEF §2.11 · ui/screens.json)
##
## ★ **거절이 없다.** "허락하시겠습니까? 예/아니오" 를 만들지 않는다 —
##   7살에게 두 동물이 친해지는 걸 거절하게 하는 것이 이상하고,
##   거절이 있으면 **"잘못 눌렀다"** 가 생긴다(원칙 2).
##   아이가 하는 것은 **축하 한 번**이고 버튼은 「잘됐다!」 하나뿐이다.
##
## ★ 초대 카드(§3.12)와 **같은 모양**이다. 아이가 이미 배운 화면이라 새로 가르칠 게 없다.
## ★ **다음에 무슨 일이 생기는지 여기서 말한다.** §2.4 의 "여분 자리가 있어야 아기" 를
##   여기서 안 보여주면 아이는 "왜 아기가 안 나와?" 를 영영 모른다(원칙 3).
##   그리고 꽉 찼으면 **빠져나갈 길**을 같이 적는다 — 막다른 길을 만들지 않는다.
##
## 새로 그리는 도트 **0장** — 오른쪽 한 마리를 뒤집어 마주 보게 할 뿐이다.
extends CanvasLayer

signal closed

const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
const BODY_HEIGHT := 78.0

@onready var _art: Node2D = $Art
@onready var _text: Control = $Text

var _open := false


func _ready() -> void:
	visible = false


## species 는 종 정의, pair 는 그 종의 개체 둘이다.
func show_for(species: Dictionary, pair: Array, seats_taken: int, seats: int,
		schema: TagSchema = null) -> void:
	for node in _art.get_children() + _text.get_children():
		node.get_parent().remove_child(node)
		node.queue_free()
	var middle := 320.0

	var title := _label("가족이 됐어요!", 22, Vector2(0, 40))
	title.size.x = 640
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ★ **마주 본다** — 오른쪽 한 마리를 뒤집으면 된다. 도트 0장.
	var frames: Dictionary = SpriteLibrary.body_frames(species,
		SpriteLibrary.canvas_of(species, schema))
	var sheet: SpriteFrames = frames["frames"]
	var grow := 2
	if sheet != null and sheet.has_animation("idle") and sheet.get_frame_count("idle") > 0:
		var art: Texture2D = sheet.get_frame_texture("idle", 0)
		grow = clampi(int(BODY_HEIGHT / maxf(art.get_height(), 1.0)), 2, 4)
		for side in 2:
			var body := Sprite2D.new()
			body.name = "Body%d" % side
			body.texture = art
			body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			body.scale = Vector2.ONE * grow
			body.flip_h = side == 1
			body.position = Vector2(middle + (-58.0 if side == 0 else 58.0), 104.0)
			_art.add_child(body)

	# 하트는 **두 얼굴 사이**에. 위로 띄우면 제목에 붙어 버린다.
	var heart := Sprite2D.new()
	heart.texture = SpriteLibrary.pair_ui_texture("paired")
	heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if heart.texture != null:
		heart.scale = Vector2.ONE * 2
		heart.position = Vector2(middle - heart.texture.get_width(), 92.0)
		_art.add_child(heart)

	# 이름 + 성별 뱃지. 뱃지가 이름 **왼쪽**에 붙어 한 덩어리로 읽힌다.
	for side in 2:
		var one: Dictionary = pair[side] if side < pair.size() else {}
		var at := Vector2(middle + (-96.0 if side == 0 else 34.0), 150.0)
		var badge := Sprite2D.new()
		badge.texture = SpriteLibrary.pair_ui_texture(String(one.get("sex", "male")))
		badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if badge.texture != null:
			badge.position = at
			_art.add_child(badge)
		var named := _label(String(species.get("name", "?")), 11,
			at + Vector2(badge.texture.get_width() + 3 if badge.texture else 12, -3))

	# ★ 다음에 무슨 일이 생기는지 — 여기서 안 말하면 "왜 아기가 안 나와" 가 된다
	var room := seats_taken < seats
	var next_line := _label(
		"이제 아기를 기다려요" if room else "자리가 하나 생기면 아기가 와요",
		11, Vector2(0, 190))
	next_line.size.x = 640
	next_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 자리 — **꽉 찼을 때만 강조한다.** 여유가 있을 때도 강조하면 잔소리가 된다.
	var seat_line := _label("자리  %d / %d" % [seats_taken, seats], 11, Vector2(0, 214))
	seat_line.size.x = 640
	seat_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat_line.modulate = Color(1.0, 0.86, 0.45) if not room else Color(1, 1, 1, 0.6)

	# 꽉 찼을 때만 **빠져나갈 길**을 적는다 — 막다른 길을 만들지 않는다
	if not room:
		var way_out := _label("쉼터로 보내면 자리가 나요", 11, Vector2(0, 236))
		way_out.size.x = 640
		way_out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		way_out.modulate = Color(1, 1, 1, 0.75)

	# ★ 버튼은 **하나뿐**이다. 거절을 만들지 않는다.
	var cheer := _label("잘됐다!", 22, Vector2(0, 274))
	cheer.size.x = 640
	cheer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cheer.modulate = Color(1.0, 0.92, 0.55)
	Keycap.place(_art, "인사·정하기", Vector2(middle - 20, 310))

	_open = true
	visible = true


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not event.is_pressed():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") \
			or event.is_action_pressed("ui_cancel"):
		_open = false
		visible = false
		get_viewport().set_input_as_handled()
		closed.emit()


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
