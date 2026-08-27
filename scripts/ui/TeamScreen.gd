## 팀 편성 — **누구랑**만 고른다. (BRIEF §3.9 ★ v3.17 · ui/screens.json)
##
## ★ **한 화면에 결정 하나.** 지도에 동료 줄을 붙였더니 커서가 2차원이 됐고,
##   7살에게 그건 무겁다. 지도는 **어디로**, 여기는 **누구랑**.
##   흐름은 **지도 → 팀 편성 → 출발**이다.
##
## ★ 얼굴로 고른다. 이름을 나열하지 않는다 — 7살은 이름을 읽는 것보다
##   얼굴을 알아보는 게 빠르다.
## ⚠️ **손잡이로 설계하지 않는다.** "코가 좋은 애를 데려가면 유리해요" 같은 말을 하지 않는다 —
##    아이는 애착으로 고르고 상성은 여러 번 갔다 온 뒤에 몸으로 안다 (§3.3).
##    감각 아이콘은 **그 아이가 무엇을 잘하는지**지 유불리가 아니다.
## ⚠️ Control 의 `_draw` 로 텍스처·글자를 그리지 않는다. 전부 노드다 (RUN.md).
extends Control

const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
const FIELD_SCENE := "res://scenes/field/Field.tscn"
const MAP_SCENE := "res://scenes/ui/WorldMap.tscn"
const ROW_Y := 118.0
const STEP := 74.0

@onready var _art: Node2D = $Art
@onready var _text: Control = $Text

var _pickable: Array = []
var _at := 0
var _on_go := false
var _species := {}
var _schema: TagSchema = null
var _region := {}


func _ready() -> void:
	var result := DataLoader.load_all(true)
	_species = result.species
	_schema = result.schema
	_region = result.regions.get(Game.region_id, {})
	# 동료가 될 수 있는 것만 — 감각이 없는 종은 유도를 못 한다 (두꺼비가 그 경우다).
	# 종 이름으로 거르지 않는다: `senses` 가 비었는지만 본다.
	for one in Game.collection:
		var config: Dictionary = _species.get(String(one["species_id"]), {})
		if (config.get("senses", []) as Array).is_empty():
			continue
		_pickable.append(one)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed("ui_left"):
		_move(-1)
	elif event.is_action_pressed("ui_right"):
		_move(1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		_on_go = not _on_go
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_accept()
		return
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact_cancel"):
		get_tree().call_deferred("change_scene_to_file", MAP_SCENE)
		return
	else:
		return
	_refresh()


func _move(by: int) -> void:
	if _on_go or _pickable.is_empty():
		return
	_at = posmod(_at + by, _pickable.size())


func _accept() -> void:
	if _on_go:
		Game.save_game()
		get_tree().call_deferred("change_scene_to_file", FIELD_SCENE)
		return
	if _pickable.is_empty():
		return
	Game.toggle_party(int(_pickable[_at]["uid"]))
	_refresh()


func _refresh() -> void:
	for node in _art.get_children() + _text.get_children():
		node.get_parent().remove_child(node)
		node.queue_free()

	_label("같이 갈 아이", 22, Vector2(20, 32))
	# 자리는 숫자를 써도 되는 칸이다 (screens.json 의 kind: count)
	var seats := _label("%d / %d" % [Game.party.size(), Game.PARTY_MAX], 11, Vector2(0, 44))
	seats.size.x = 620
	seats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var start := 30.0
	for i in _pickable.size():
		var one: Dictionary = _pickable[i]
		var config: Dictionary = _species.get(String(one["species_id"]), {})
		var x := start + i * STEP
		var going := Game.going(int(one["uid"]))
		var here := i == _at and not _on_go

		var face := Faces.place(_art, Faces.of(config, _schema), Vector2(x, ROW_Y), 2)
		if face != null:
			face.modulate = Color.WHITE if going else Color(1, 1, 1, 0.45)
		# 지금 커서가 있는 자리 — 발바닥으로 가리킨다 (로고·메뉴와 같은 그림)
		if here:
			var paw := Sprite2D.new()
			paw.texture = SpriteLibrary.ui_texture("cursor_paw")
			paw.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			paw.centered = false
			paw.position = Vector2(x + 6, ROW_Y - 22)
			_art.add_child(paw)
		# 같이 가는 아이는 하트로 — 규칙을 짊어지는 것은 하트다 (§4.9)
		if going:
			var mark := Sprite2D.new()
			mark.texture = SpriteLibrary.pair_ui_texture("paired")
			mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			mark.centered = false
			mark.position = Vector2(x + 28, ROW_Y + 30)
			_art.add_child(mark)

		var name_label := _label(String(config.get("name", "?")), 11, Vector2(x - 6, ROW_Y + 46))
		name_label.modulate = Color.WHITE if going else Color(1, 1, 1, 0.55)
		# 감각 — 아이콘으로. 이 아이가 무엇을 잘하는지지 유불리가 아니다.
		var icon_x := x
		for sense in config.get("senses", []):
			var icon := Sprite2D.new()
			icon.texture = SpriteLibrary.emote_texture(_schema.sense_icon(String(sense)))
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.centered = false
			if icon.texture != null:
				icon.position = Vector2(icon_x, ROW_Y + 64)
				_art.add_child(icon)
				icon_x += 18.0

	_show_destination()
	var go := _label("출발!", 22, Vector2(0, 292))
	go.size.x = 640
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go.modulate = Color(1.0, 0.92, 0.55) if _on_go else Color(1, 1, 1, 0.5)
	Keycap.place(_art, "고르기", Vector2(20, 328))
	Keycap.place(_art, "인사·정하기", Vector2(64, 328))


## 어디로 가는지는 여기서 **다시 고르지 않는다.** 확인만 한다 — 한 화면에 결정 하나다.
func _show_destination() -> void:
	if _region.is_empty():
		return
	_label(String(_region.get("name", "")), 11, Vector2(20, 232))
	var mix: Dictionary = _region.get("terrain", {}).get("patches", {})
	var order: Array = mix.keys()
	order.sort_custom(func(a, b): return int(mix[a]) > int(mix[b]))
	var x := 20.0
	for name in order:
		var tile := SpriteLibrary.terrain_tile(String(name))
		if tile == null:
			continue
		var node := Sprite2D.new()
		node.texture = tile
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node.centered = false
		node.position = Vector2(x, 250)
		node.scale = Vector2.ONE * 2
		_art.add_child(node)
		x += 36.0
	# 만난 적 있는 아이 — **얼굴 줄**이다. 이름을 나열하지 않는다.
	x = 300.0
	var unmet := false
	for id in _region.get("ecology", {}):
		if not (id in Game.seen):
			unmet = true
			continue
		Faces.place(_art, Faces.of(_species.get(id, {}), _schema), Vector2(x, 246), 1)
		x += 22.0
	if unmet:
		# 못 만난 게 있으면 **실루엣 하나.** 몇 종인지 세지 않는다 — 그건 스포일러다.
		Faces.place(_art, Faces.unknown(Faces.of(_species.get("squirrel", {}), _schema)),
			Vector2(x + 4, 246), 1)


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
	label.size.x = 600
	_text.add_child(label)
	return label
