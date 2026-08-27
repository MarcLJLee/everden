## 세계 지도 — **어디로**만 고른다. (BRIEF §3.9 ★ v3.17)
##
## 원정은 목표 사냥이 아니라 **여행**이다. 지도가 그 프레이밍을 짊어진다.
##
## ★ 배경을 새로 그리지 않는다. 지형 타일을 넓게 깔아 지역 덩어리를 만들고
##   길은 **발자국으로 잇는다** — 로고·메뉴 커서와 같은 물건이다.
##   새로 그린 도트는 핀 하나와 집 아이콘 하나뿐이다.
##
## ⚠️ **날씨는 여기 안 들어온다** (§3.12). 예보도 지역별 날씨 표시도 없다 —
##    날씨는 나가서 겪는 것이지 고르는 재료가 아니다.
## ⚠️ **"누구랑" 은 여기서 안 고른다.** 팀 편성 화면으로 넘긴다 —
##    **한 화면에 결정 하나**다. 지도에 동료 줄을 붙였더니 커서가 2차원이 됐고,
##    7살에게 그건 무겁다. 흐름은 **지도 → 팀 편성 → 출발**.
## ⚠️ **손잡이로 설계하지 않는다.** "코가 좋은 애를 데려가면 유리해요" 같은 말을 하지 않는다.
##    동료 얼굴에 기쁨 눈을 얹는 것까지가 한계다 — 유불리가 아니라 **그 아이의 기분**이다.
## ⚠️ `art` 로 표시된 자리에 라벨이 들어가 있으면 **인계 실패**다 (§6.9).
##    "지형: 물가 · 숲" 처럼 글로 쓰지 않고 **타일 그림**으로, 만난 아이는
##    이름이 아니라 **얼굴**로 보여준다.
## ⚠️ Control 의 `_draw` 로 텍스처·글자를 그리면 네모가 된다. 전부 노드로 얹는다 (RUN.md).
extends Control

const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
const TEAM_SCENE := "res://scenes/ui/TeamScreen.tscn"
const HOME_SCENE := "res://scenes/home/Home.tscn"
const TILE := 8
const MAP_RECT := Rect2(Vector2(8, 8), Vector2(624, 196))
## 고르는 것은 하나뿐이다 — 어디로.
## ⚠️ **축척이 다르면 표현도 달라진다** (§3.9). 필드에서 "물가" 는 젖은 흙 타일이지만
##    지도에서 그것만 깔면 그냥 갈색 땅이다 — 가운데를 **물**로 채워야 물가로 읽힌다.
const MAP_CORE := {"물가": "extra/water_0"}

@onready var _map: Node2D = $Map
@onready var _panel: Node2D = $Panel
@onready var _text: Control = $Text

var _regions: Array = []
var _at_region := 0
var _pins: Array = []
var _rng := RandomNumberGenerator.new()
var _species := {}
var _schema: TagSchema = null
var _map_home_at: Array = [68, 19]


func _ready() -> void:
	_rng.seed = 20260827
	var result := DataLoader.load_all(true)
	_species = result.species
	_schema = result.schema
	for id in result.regions:
		_regions.append(result.regions[id])
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions.json"))
	if raw is Dictionary and raw.has("map_home_at"):
		_map_home_at = raw["map_home_at"]
	# 가 본 곳이 앞, 안 가 본 곳이 뒤 — 길이 그 순서로 이어진다
	_regions.sort_custom(func(a, b): return int(bool(a.get("open", true))) > int(bool(b.get("open", true))))
	for i in _regions.size():
		if String(_regions[i].get("id", "")) == Game.region_id:
			_at_region = i

	_draw_map()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_leave()
		return
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact_cancel"):
		get_tree().call_deferred("change_scene_to_file", HOME_SCENE)
		return
	else:
		return
	_refresh()


func _step(by: int) -> void:
	if _regions.is_empty():
		return
	_at_region = posmod(_at_region + by, _regions.size())


## 어디로만 정하고 넘긴다. 누구랑은 다음 화면이다.
func _leave() -> void:
	var region: Dictionary = _regions[_at_region]
	if not bool(region.get("open", true)):
		return
	Game.region_id = String(region["id"])
	Game.save_game()
	get_tree().call_deferred("change_scene_to_file", TEAM_SCENE)


# --- 지도 --------------------------------------------------------------------

## 지형 타일을 덩어리로 깔아 지역을 만들고, 발자국으로 잇는다.
## ⚠️ 축척이 다르면 표현도 달라진다 — 필드에서 "물가" 는 젖은 흙이지만 지도에서는
##    그것만 깔면 갈색 땅이다. 가운데를 **물**로 채워야 물가로 읽힌다 (§3.9).
func _draw_map() -> void:
	var ground := SpriteLibrary.terrain_tile("초원")
	if ground != null:
		var back := TextureRect.new()
		back.texture = ground
		back.stretch_mode = TextureRect.STRETCH_TILE
		back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		back.position = MAP_RECT.position
		back.size = MAP_RECT.size
		add_child(back)
		move_child(back, 0)

	for region in _regions:
		_blob(region)
	_paths()
	var home := _sprite(SpriteLibrary.ui_texture("map_home"), _home_spot())
	if home != null:
		home.z_index = 3
	for region in _regions:
		_pins.append(_pin(region))


## ★ **가장 많은 지형이 그 지역의 얼굴이다.** 처음엔 적은 지형을 가운데 두었더니
##   뒷산 한가운데가 바위가 돼서 "돌산" 으로 읽혔다. 많은 것이 덩어리를 채우고,
##   적은 것은 **한쪽에 치우친 작은 자국**으로 얹는다.
const PATCH := [{"r": 5, "at": Vector2(0, 0)}, {"r": 3, "at": Vector2(2, -1)},
	{"r": 2, "at": Vector2(-3, 2)}]

func _blob(region: Dictionary) -> void:
	var mix: Dictionary = region.get("terrain", {}).get("patches", {})
	var order: Array = mix.keys()
	order.sort_custom(func(a, b): return int(mix[a]) > int(mix[b]))
	# 바탕 지형이 맨 아래 — 덩어리 가장자리가 들판에 스며든다
	order.push_front(String(region.get("terrain", {}).get("base", "초원")))
	var center := _spot(region)
	var closed := not bool(region.get("open", true))
	for i in mini(order.size(), PATCH.size()):
		var texture := SpriteLibrary.terrain_tile(String(order[i]))
		if texture == null:
			continue
		var radius := int(PATCH[i]["r"])
		var shift: Vector2 = PATCH[i]["at"]
		_disc(texture, center + shift * TILE, radius, closed)
		# 축척이 바뀌면 얼굴도 바뀐다 — 물가 덩어리는 가운데가 물이어야 물가로 읽힌다
		if MAP_CORE.has(String(order[i])):
			var core := SpriteLibrary.terrain_tile(String(MAP_CORE[String(order[i])]))
			if core != null:
				_disc(core, center + shift * TILE, maxi(radius - 2, 1), closed)


func _disc(texture: Texture2D, center: Vector2, radius: int, closed: bool) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var at := center + Vector2(dx, dy) * TILE
			if not MAP_RECT.has_point(at):
				continue
			var tile := _sprite(texture, at)
			tile.scale = Vector2.ONE * (float(TILE) / float(texture.get_width()))
			# 안 가 본 곳은 흐리다 — 여는 조건을 수치로 쓰지 않는다 (§3.9)
			tile.modulate = Color(0.6, 0.62, 0.66) if closed else Color.WHITE


## 길은 **발자국으로 잇는다.** 로고·메뉴 커서와 같은 물건이라 새 도트가 없다.
func _paths() -> void:
	var paw := SpriteLibrary.ui_texture("logo_paw_small")
	if paw == null:
		return
	# 집에서 가까운 곳으로, 거기서 다음 곳으로 — 발자국이 순서를 만든다
	var stops: Array = [_home_spot()]
	for region in _regions:
		stops.append(_spot(region))
	for i in range(1, stops.size()):
		var from: Vector2 = stops[i - 1]
		var to: Vector2 = stops[i]
		var faded := not bool(_regions[i - 1].get("open", true))
		var steps := int(from.distance_to(to) / 14.0)
		for step in range(1, maxi(steps, 2)):
			var at: Vector2 = from.lerp(to, float(step) / float(maxi(steps, 2)))
			if not MAP_RECT.has_point(at):
				continue
			var print_mark := _sprite(paw, at.floor())
			print_mark.z_index = 1
			print_mark.centered = true
			# 발자국은 로고에서 쓰는 그림이라 지도에서는 **작아야** 한다
			print_mark.scale = Vector2.ONE * 0.45
			# 안 가 본 곳으로 가는 길은 **흐리게** 그려진다 (§3.9)
			print_mark.modulate = Color(1, 1, 1, 0.2 if faded else 0.6)
			print_mark.rotation = (to - from).angle() + PI * 0.5


func _pin(region: Dictionary) -> Sprite2D:
	# 짝 없이 혼자인 종이 여기 살면 **하트 핀**이 뜬다 — 짝을 찾는 것이 원정 동기가 된다 (§2.4)
	var wants_pair := false
	for id in Game.lonely_species():
		if float(region.get("ecology", {}).get(id, 0.0)) > 0.0:
			wants_pair = true
	var texture := SpriteLibrary.ui_texture("map_pin_pair" if wants_pair else "map_pin")
	var pin := _sprite(texture, _spot(region) + Vector2(0, -14))
	if pin != null:
		pin.z_index = 4
	return pin


func _home_spot() -> Vector2:
	var at: Array = _map_home_at
	return (MAP_RECT.position + Vector2(float(at[0]), float(at[1])) * TILE).floor()


func _spot(region: Dictionary) -> Vector2:
	var at: Array = region.get("at", [30, 20])
	return (MAP_RECT.position + Vector2(float(at[0]), float(at[1])) * TILE).floor()


# --- 아래 판 ------------------------------------------------------------------

func _refresh() -> void:
	for node in _panel.get_children() + _text.get_children():
		node.get_parent().remove_child(node)
		node.queue_free()
	var region: Dictionary = _regions[_at_region]
	var open := bool(region.get("open", true))
	for i in _pins.size():
		if _pins[i] != null:
			_pins[i].modulate = Color(1, 1, 1, 1.0 if i == _at_region else 0.5)
			_pins[i].scale = Vector2.ONE * (1.0 if i == _at_region else 0.8)

	_label("◀ %s ▶" % String(region.get("name", "???")), 22, Vector2(16, 208))
	if not open:
		# 여는 조건을 확률이나 수치로 쓰지 않는다 — 조건이 아니라 **약속**이다 (§3.9)
		_label(String(region.get("promise", "")), 11, Vector2(18, 246))
	else:
		_show_terrain(region)
		_show_mood(region)
		_show_known(region)
	Keycap.place(_panel, "고르기", Vector2(18, 328))
	Keycap.place(_panel, "인사·정하기", Vector2(62, 328))
	Keycap.place(_panel, "그만두기", Vector2(106, 328))


## ★ **"지형: 물가 · 숲" 처럼 글로 쓰지 않는다** (§6.9). 타일 그림 + 아래 이름이다.
func _show_terrain(region: Dictionary) -> void:
	var mix: Dictionary = region.get("terrain", {}).get("patches", {})
	var order: Array = mix.keys()
	order.sort_custom(func(a, b): return int(mix[a]) > int(mix[b]))
	var x := 18.0
	for name in order:
		var tile := SpriteLibrary.terrain_tile(String(name))
		if tile == null:
			continue
		var node := Sprite2D.new()
		node.texture = tile
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node.centered = false
		node.position = Vector2(x, 244)
		node.scale = Vector2.ONE * 2
		_panel.add_child(node)
		var under := _label(String(name), 11, Vector2(x - 4, 278))
		under.modulate = Color(1, 1, 1, 0.8)
		x += 44.0


## 동료가 좋아할지 — **얼굴 + 기쁨 눈**. 유불리를 말하지 않는다.
## 여행이 동료에게도 놀이라는 §3.7 이 여기서 보인다.
func _show_mood(region: Dictionary) -> void:
	var shape: Array = (region.get("terrain", {}).get("patches", {}) as Dictionary).keys()
	shape.append(String(region.get("terrain", {}).get("base", "")))
	var x := 236.0
	var glad_any := false
	for one in Game.party_members():
		var config: Dictionary = _species.get(String(one["species_id"]), {})
		var glad := false
		for place in config.get("habitat", []):
			if String(place) in shape:
				glad = true
		if not glad:
			continue
		glad_any = true
		Faces.place(_panel, Faces.glad(config, _schema), Vector2(x, 240), 2)
		x += 46.0
	if glad_any:
		var say := _label("좋아할 거예요", 11, Vector2(236, 284))
		say.modulate = Color(1, 1, 1, 0.8)


## 만난 적 있는 아이 — **얼굴 줄**. 이름을 나열하지 않는다.
## 못 만난 게 있으면 **실루엣 하나** — 몇 종인지 세지 않는다. 그건 스포일러다 (§3.2).
func _show_known(region: Dictionary) -> void:
	var x := 396.0
	var unmet := false
	for id in region.get("ecology", {}):
		if not (id in Game.seen):
			unmet = true
			continue
		Faces.place(_panel, Faces.of(_species.get(id, {}), _schema), Vector2(x, 244), 1)
		x += 22.0
	if unmet:
		Faces.place(_panel, Faces.unknown(Faces.of(_species.get("squirrel", {}), _schema)),
			Vector2(x + 6, 244), 1)
	if x > 396.0 or unmet:
		var say := _label("여기서 만난 아이", 11, Vector2(396, 278))
		say.modulate = Color(1, 1, 1, 0.8)


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


func _sprite(texture: Texture2D, at: Vector2) -> Sprite2D:
	if texture == null:
		return null
	var node := Sprite2D.new()
	node.texture = texture
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.position = at
	_map.add_child(node)
	return node
