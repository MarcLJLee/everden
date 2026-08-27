## 초대 카드 — 게이지가 끝나면 **누구를 초대했는지** 띄운다. (BRIEF §3.12)
##
## ★ **축하지 평가가 아니다.** 능력치 숫자를 넣지 않는다 — 넣는 순간
##   "다시 뽑을까" 가 생기고, 그건 수집이 벌이 되는 길이다 (원칙 6).
## ★ 주인공은 **성별 + 단계**다 (§3.15). 아이가 묻는 것은 숫자가 아니라 관계다 —
##   "얘는 엄마 사슴인가, 아기인가?" 숫자 나이는 곁들이다.
## ★ 설명 두 줄은 **실존에서 가져온 사실**이다. 부가가치(§3.5)는 진짜 지식에서 나오고,
##   아이가 남에게 옮길 수 있는 말이어야 한다.
##
## 새로 그리는 도트 **0장** — 몸도 눈도 뱃지도 이미 있는 것을 크게 얹을 뿐이다.
## ⚠️ Control 의 `_draw` 로 텍스처·글자를 그리지 않는다. 전부 노드다 (RUN.md).
extends CanvasLayer

signal closed

const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
## 몸을 이만큼 높이로 키운다. **정수배로만** 키운다 — 실수배면 도트가 뭉개진다.
const BODY_HEIGHT := 92.0

@onready var _art: Node2D = $Art
@onready var _text: Control = $Text

var _open := false


## ⚠️ **처음에는 꺼져 있어야 한다.** 씬에 어둡게 덮는 판이 있어서, 안 끄면
##    게임을 켜자마자 화면 전체가 어두워진다 (실제로 그렇게 나갔다).
func _ready() -> void:
	visible = false


## one 은 개체({species_id, sex, stage, age_years}), species 는 종 정의다.
func show_for(one: Dictionary, species: Dictionary, is_new: bool,
		schema: TagSchema = null) -> void:
	# ⚠️ `queue_free()` 만 하면 이번 프레임 안에서는 **옛 글자가 아직 붙어 있다.**
	#    같은 프레임에 다시 띄우면 두 장이 겹쳐 읽힌다 — 떼고 나서 버린다.
	for node in _art.get_children() + _text.get_children():
		node.get_parent().remove_child(node)
		node.queue_free()
	var middle := 320.0

	# 몸 — 있는 그림을 정수배로 키운다
	var frames: Dictionary = SpriteLibrary.body_frames(species, SpriteLibrary.canvas_for(
		String(species.get("id", "")), Vector2i(32, 32)))
	var sheet: SpriteFrames = frames["frames"]
	if sheet != null and sheet.has_animation("idle") and sheet.get_frame_count("idle") > 0:
		var body := Sprite2D.new()
		body.texture = sheet.get_frame_texture("idle", 0)
		body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var grow: int = clampi(int(BODY_HEIGHT / maxf(body.texture.get_height(), 1.0)), 2, 4)
		body.scale = Vector2.ONE * grow
		body.position = Vector2(middle, 96.0)
		_art.add_child(body)

	# 종 이름이 가장 크다
	var title := _label(String(species.get("name", "?")), 22)
	title.position = Vector2(0, 132)
	title.size.x = 640
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 성별 뱃지 — 같은 회색이고 모양만 다르다. 색으로 성별을 나누지 않는다 (§4.9)
	var badge := Sprite2D.new()
	badge.texture = SpriteLibrary.pair_ui_texture(String(one.get("sex", "male")))
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if badge.texture != null:
		badge.position = Vector2(middle + 52, 143)
		badge.scale = Vector2.ONE * 2
		_art.add_child(badge)

	# 단계가 먼저, 숫자는 곁들이 — 아기는 숫자를 안 붙인다
	var grown := String(one.get("stage", "adult")) == "adult"
	var age := "어른 · %d살" % int(one.get("age_years", 1)) if grown else "아기"
	var age_label := _label(age, 11)
	age_label.position = Vector2(0, 164)
	age_label.size.x = 640
	age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 감각 — 아이콘으로. 이 아이가 무엇을 잘하는지는 그림이 말한다
	var senses: Array = species.get("senses", [])
	var at := middle - (senses.size() * 20.0) * 0.5
	for sense in senses:
		var icon := Sprite2D.new()
		# ⚠️ 아이콘 파일은 **감각 이름이 아니라 icon 이름**으로 되어 있다
		#    (후각 → emote_냄새). sense_profile 이 그 매핑을 들고 있다.
		var icon_name := String(sense)
		if schema != null:
			var named := schema.sense_icon(String(sense))
			if not named.is_empty():
				icon_name = named
		icon.texture = SpriteLibrary.emote_texture(icon_name)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if icon.texture != null:
			icon.position = Vector2(at, 184)
			_art.add_child(icon)
			at += 20.0

	# 설명 두 줄
	var lines: Array = species.get("blurb", [])
	for i in lines.size():
		var line := _label(String(lines[i]), 11)
		line.position = Vector2(0, 208 + i * 18)
		line.size.x = 640
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.modulate = Color(1, 1, 1, 0.88)

	if is_new:
		var mark := _label("도감에 새로 실렸어요", 11)
		mark.position = Vector2(0, 254)
		mark.size.x = 640
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.modulate = Color(1.0, 0.92, 0.55)

	# 어떻게 닫는지는 **그림이 말한다** — 문장에 키 이름을 넣지 않는다 (§2.10)
	Keycap.place(_art, "인사·정하기", Vector2(middle - 11, 292))

	_open = true
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not event.is_pressed():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") \
			or event.is_action_pressed("ui_cancel"):
		_open = false
		visible = false
		get_viewport().set_input_as_handled()
		closed.emit()


func is_open() -> bool:
	return _open


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	if ResourceLoader.exists(HANGUL_FONT):
		label.add_theme_font_override("font", load(HANGUL_FONT))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.text = text
	_text.add_child(label)
	return label
