## 세계 지도 — **어디로**와 **누구랑**, 둘만 고른다. (BRIEF §3.9)
##
## 원정은 목표 사냥이 아니라 **여행**이다. 지도가 그 프레이밍을 짊어진다.
##
## ★ 배경을 새로 그리지 않는다. 지형 타일을 넓게 깔아 지역 덩어리를 만들고
##   길은 **발자국으로 잇는다** — 로고·메뉴 커서와 같은 물건이다.
##   새로 그린 도트는 핀 하나와 집 아이콘 하나뿐이다.
##
## ⚠️ **날씨는 여기 안 들어온다** (§3.12). 예보도 지역별 날씨 표시도 없다 —
##    날씨는 나가서 겪는 것이지 고르는 재료가 아니다.
## ⚠️ **손잡이로 설계하지 않는다.** "코가 좋은 애를 데려가면 유리해요" 같은 말을 하지 않는다.
##    "누구랑" 은 애착으로 고르는 자리고, 상성은 여러 번 갔다 온 뒤에 몸으로 알게 된다.
##    그래서 안내는 **"좋아할 거예요"** 까지만이다 — 유불리가 아니라 그 아이의 기분이다.
## ⚠️ Control 의 `_draw` 로 텍스처·글자를 그리면 네모가 된다. 전부 노드로 얹는다 (RUN.md).
extends Control

const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
const FIELD_SCENE := "res://scenes/field/Field.tscn"
const HOME_SCENE := "res://scenes/home/Home.tscn"
const TILE := 8
const MAP_RECT := Rect2(Vector2(8, 8), Vector2(624, 196))
## 고르는 자리 — 목적지 · 동료 · 출발
const ROWS := ["곳", "동료", "출발"]
## ⚠️ **축척이 다르면 표현도 달라진다** (§3.9). 필드에서 "물가" 는 젖은 흙 타일이지만
##    지도에서 그것만 깔면 그냥 갈색 땅이다 — 가운데를 **물**로 채워야 물가로 읽힌다.
const MAP_CORE := {"물가": "extra/water_0"}

@onready var _map: Node2D = $Map
@onready var _panel: Node2D = $Panel
@onready var _text: Control = $Text

var _regions: Array = []
var _pickable: Array = []
var _row := 0
var _at_region := 0
var _at_friend := 0
var _labels := {}
var _pins: Array = []
var _friend_nodes: Array = []
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

	# 동료가 될 수 있는 것만 고르게 한다 — 감각이 없는 종은 유도를 못 한다 (§3.3).
	# 종 이름으로 거르지 않는다: `senses` 가 비었는지만 본다 (두꺼비가 그 경우다).
	for one in Game.collection:
		var config: Dictionary = _species.get(String(one["species_id"]), {})
		if (config.get("senses", []) as Array).is_empty():
			continue
		_pickable.append(one)

	_draw_map()
	_build_panel()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action("ui_down") and event.is_action_pressed("ui_down"):
		_row = mini(_row + 1, ROWS.size() - 1)
	elif event.is_action("ui_up") and event.is_action_pressed("ui_up"):
		_row = maxi(_row - 1, 0)
	elif event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	elif event.is_action_pressed("ui_accept"):
		_accept()
		return
	elif event.is_action_pressed("ui_cancel"):
		get_tree().call_deferred("change_scene_to_file", HOME_SCENE)
		return
	else:
		return
	_refresh()


func _step(by: int) -> void:
	if _row == 0 and not _regions.is_empty():
		_at_region = posmod(_at_region + by, _regions.size())
	elif _row == 1 and not _pickable.is_empty():
		_at_friend = posmod(_at_friend + by, _pickable.size())


func _accept() -> void:
	if _row == 1 and not _pickable.is_empty():
		var uid := int(_pickable[_at_friend]["uid"])
		if uid in Game.party:
			Game.party.erase(uid)
		elif Game.party.size() < Game.PARTY_MAX:
			Game.party.append(uid)
		else:
			# 꽉 찼으면 가장 먼저 고른 아이가 나간다. 막고 끝내면 왜 안 되는지 안 보인다.
			Game.party.pop_front()
			Game.party.append(uid)
		Game.save_game()
		_refresh()
		return
	if _row == 2:
		_leave()
		return
	# 목적지 줄에서 누르면 다음 줄로 — 고르고 나면 다음이 무엇인지 보여야 한다
	_row = 1
	_refresh()


func _leave() -> void:
	var region: Dictionary = _regions[_at_region]
	if not bool(region.get("open", true)):
		return
	Game.region_id = String(region["id"])
	Game.save_game()
	get_tree().call_deferred("change_scene_to_file", FIELD_SCENE)


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

func _build_panel() -> void:
	for key in ["곳", "지형", "기분", "만난", "동료", "안내"]:
		_labels[key] = _label(key)
	_labels["곳"].position = Vector2(12, 210)
	_labels["곳"].add_theme_font_size_override("font_size", 22)
	_labels["지형"].position = Vector2(12, 240)
	_labels["기분"].position = Vector2(12, 256)
	_labels["만난"].position = Vector2(12, 272)
	_labels["동료"].position = Vector2(12, 296)
	_labels["안내"].position = Vector2(12, 338)
	_labels["안내"].modulate = Color(1, 1, 1, 0.7)


func _refresh() -> void:
	var region: Dictionary = _regions[_at_region]
	var open := bool(region.get("open", true))
	for i in _pins.size():
		if _pins[i] != null:
			_pins[i].modulate = Color(1, 1, 1, 1.0 if i == _at_region else 0.55)
			_pins[i].scale = Vector2.ONE * (1.0 if i == _at_region else 0.8)

	_labels["곳"].text = ("◀ %s ▶" if _row == 0 else "  %s") % String(region.get("name", "???"))
	if not open:
		# 여는 조건을 확률이나 수치로 쓰지 않는다 — 조건이 아니라 **약속**이다 (§3.9)
		_labels["지형"].text = String(region.get("promise", ""))
		_labels["기분"].text = ""
		_labels["만난"].text = ""
	else:
		var mix: Dictionary = region.get("terrain", {}).get("patches", {})
		var shape: Array = mix.keys()
		shape.sort_custom(func(a, b): return int(mix[a]) > int(mix[b]))
		_labels["지형"].text = "지형: " + " · ".join(shape)
		_labels["기분"].text = _mood(region)
		_labels["만난"].text = _known(region)
	_show_friends()
	_labels["안내"].text = _hint(open)


## 동료의 habitat 과 목적지 지형이 겹치면 "좋아할 거예요".
## ⚠️ **확률이 아니라 안내다.** 유불리를 말하지 않는다 — 여행이 동료에게도 놀이라는 §3.7 이
##    여기서 보인다. 종 이름으로 분기하지 않고 habitat 태그만 본다.
func _mood(region: Dictionary) -> String:
	var shape: Array = (region.get("terrain", {}).get("patches", {}) as Dictionary).keys()
	shape.append(String(region.get("terrain", {}).get("base", "")))
	var glad: Array = []
	for one in Game.party_members():
		var config: Dictionary = _species.get(String(one["species_id"]), {})
		for place in config.get("habitat", []):
			if String(place) in shape and not (String(config.get("name", "")) in glad):
				glad.append(String(config.get("name", "")))
	if glad.is_empty():
		return ""
	# 조사는 받침을 따라간다 — "개 가" 처럼 띄면 아이가 읽다가 걸린다
	return "%s 좋아할 거예요" % Josa.이가(" · ".join(glad))


## 만난 적 있는 아이 — 도감 연동. **여기 없는 종도 나온다는 것을 함께 적는다** (§3.9).
func _known(region: Dictionary) -> String:
	var met: Array = []
	var unmet := 0
	for id in region.get("ecology", {}):
		if id in Game.seen:
			var config: Dictionary = _species.get(id, {})
			met.append(String(config.get("name", id)))
		else:
			unmet += 1
	if met.is_empty():
		return "아직 아무도 못 만나 봤어요" if unmet > 0 else ""
	var line := "만난 적 있는 아이: " + " · ".join(met)
	if unmet > 0:
		line += "  (처음 보는 아이도 있어요)"
	return line


func _show_friends() -> void:
	for node in _friend_nodes:
		node.queue_free()
	_friend_nodes.clear()
	var x := 12.0
	for i in _pickable.size():
		var one: Dictionary = _pickable[i]
		var config: Dictionary = _species.get(String(one["species_id"]), {})
		var going := int(one["uid"]) in Game.party
		var chip := _label("chip%d" % i)
		chip.text = "%s%s%s" % [
			"[" if going else " ",
			String(config.get("name", one["species_id"])),
			"]" if going else " "]
		chip.position = Vector2(x, 316)
		chip.modulate = Color(1, 1, 1, 1.0 if going else 0.5)
		if _row == 1 and i == _at_friend:
			chip.modulate = Color(1.0, 0.92, 0.55)
		_friend_nodes.append(chip)
		x += 62.0
	_labels["동료"].text = "같이 갈 아이  (%d / %d)" % [Game.party.size(), Game.PARTY_MAX]


func _hint(open: bool) -> String:
	match _row:
		0:
			return "◀ ▶ 로 고르고 [스페이스] 로 정해요   ·   [Esc] 집으로"
		1:
			return "◀ ▶ 로 옮기고 [스페이스] 로 데려가요   ·   ▼ 다음"
		_:
			return "[스페이스] 로 나가요" if open else "여기는 아직 갈 수 없어요"


func _label(_key: String) -> Label:
	var label := Label.new()
	if ResourceLoader.exists(HANGUL_FONT):
		label.add_theme_font_override("font", load(HANGUL_FONT))
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
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
