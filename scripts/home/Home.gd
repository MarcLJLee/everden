## 집 화면 — 게임을 켜면 처음 서는 곳. (BRIEF §2.7)
##
## 나간다 → 만난다 → 데려온다 → **집이 달라진다.** 집이 없으면
## "데려온다"가 어디로 가는지가 화면에 없다.
##
## ★ **집은 보는 곳이지 해야 하는 곳이 아니다.**
##   HUD 는 재화와 자리 둘뿐이다. 배고픔·청결·기분 게이지를 두지 않는다 —
##   그게 생기는 순간 집이 할 일 목록이 되고 "수집이 벌이 되면 안 된다"를 어긴다.
extends Control

const ACTOR_SCENE := "res://scenes/actors/Actor.tscn"
const TUNING_PATH := "res://tuning/field_tuning.tres"
const MAP_SCENE := "res://scenes/ui/WorldMap.tscn"
const HANGUL_FONT := "res://fonts/Galmuri11.ttf"

@onready var _world: Node2D = $World
@onready var _ground: Node2D = $World/Ground
@onready var _yard_nodes: Node2D = $World/Yard
@onready var _actors: Node2D = $World/Actors
@onready var _weather_layers: WeatherLayers = $World/Weather
@onready var _hud: Control = $Hud
@onready var _coin_label: Label = $Hud/Coins
@onready var _seat_label: Label = $Hud/Seats

var schema: TagSchema = null
var tuning: FieldTuning = null
var terrain := TerrainMap.new()
var yard := HomeYard.new()
var player: Actor = null
## 마당에 놓인 사물. [{ name, for_tags, price, position, node }]
var objects: Array = []
## 여기 사는 동물들
var residents: Array = []

## 재화와 자리 — HUD 는 이 둘뿐이다
var coins := 120
var seats := 4

var _rng := RandomNumberGenerator.new()
var _leaving := false
## 집은 **맑고 구름이 흐르는 정도**만 한다. 비도 안개도 오지 않는다 —
## 마당은 보는 곳이지 견디는 곳이 아니다.
var _sky := {"cloud": 0.18, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.28}
var _sky_target := 0.18
var _sky_hold := 0.0


func _ready() -> void:
	_rng.randomize()
	var result := DataLoader.load_all(true)
	schema = result.schema
	tuning = load(TUNING_PATH)

	var screen := Vector2i(640, 360)
	var tiles := Vector2i(ceili(screen.x / float(tuning.tile_size)), ceili(screen.y / float(tuning.tile_size)))
	var view: FieldTuning = tuning.duplicate()
	view.map_size = tiles
	terrain.generate(tiles, view.tile_size, {}, _rng)
	terrain.fill("초원")
	_ground.setup(view, terrain)

	if yard.load_data():
		yard.build(_yard_nodes, screen, view.tile_size)
		_place_objects()
	_spawn_residents(result.species, view)
	_spawn_player(view)
	# 집은 맑고 구름이 흐르는 정도만 한다. 비·안개·빛줄기는 없다.
	_weather_layers.build(["cloud", "sun"])
	_hud.draw.connect(_hud_draw)
	for label in [_coin_label, _seat_label]:
		if ResourceLoader.exists(HANGUL_FONT):
			label.add_theme_font_override("font", load(HANGUL_FONT))
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)


# --- 사물 — 사서 놓는다 -----------------------------------------------------

## 자리는 흙길을 피해 좌우로 나눈다. 길 위에 놓으면 나가는 길이 막힌 것처럼 보인다.
func _place_objects() -> void:
	var defined: Dictionary = yard.data.get("objects", {})
	var slots := _object_slots(defined.size())
	var index := 0
	for name in defined:
		var entry: Dictionary = defined[name]
		var texture := yard._texture(String(entry.get("file", "")))
		if texture == null or index >= slots.size():
			continue
		var node := Sprite2D.new()
		node.texture = texture
		node.centered = false
		# 앵커는 바닥 중앙 — 액터·프롭과 같은 규칙이다
		var at: Vector2 = slots[index]
		node.position = (at - Vector2(texture.get_width() * 0.5, texture.get_height())).round()
		_actors.add_child(node)
		objects.append({
			"name": String(name),
			"for_tags": entry.get("for_tags", []),
			"price": int(entry.get("price", 0)),
			"position": at,
			"node": node,
		})
		index += 1


func _object_slots(count: int) -> Array:
	var slots: Array = []
	var rows := 2
	var per_row := int(ceil(count / float(rows)))
	for row in rows:
		for column in per_row:
			var left: bool = column % 2 == 0
			var lane := yard.gate.x + (-1.0 if left else 1.0) * (52.0 + int(column / 2) * 58.0)
			slots.append(Vector2(lane, yard.yard.position.y + 46.0 + row * 74.0))
	return slots


# --- 동물 ------------------------------------------------------------------

## ★ 마당에 있는 것은 **모아온 아이들**이지 데이터에 있는 종이 아니다.
##   예전엔 "그림이 있는 모든 종" 을 뿌렸더니 아트가 들어올 때마다 식구가 늘었다
##   (사용자 지적 — "껐다 킬 때마다 자꾸 집에 있는 동물이 늘어나고 있다").
func _spawn_residents(species_by_id: Dictionary, view: FieldTuning) -> void:
	for one in Game.collection:
		var id := String(one["species_id"])
		var species: Dictionary = species_by_id.get(id, {})
		if species.is_empty():
			# 저장에 있는데 지금 데이터에 없는 종 — 팩이 빠졌을 수 있다. 조용히 넘긴다.
			continue
		var actor: Actor = load(ACTOR_SCENE).instantiate()
		_actors.add_child(actor)
		actor.setup(species, schema, view, _rng, String(one["sex"]))
		actor.speed_tiles = view.wild_speed
		actor.confine = yard.confine_resident
		actor.position = Vector2(
			_rng.randf_range(yard.yard.position.x + 24, yard.yard.end.x - 24),
			_rng.randf_range(yard.yard.position.y + 12, yard.yard.end.y - 12))
		var resident := Resident.new()
		resident.actor = actor
		resident.tags = Resident.tags_of(species)
		residents.append(resident)
	_show_pair_marks()


## ★ **규칙을 짊어지는 것은 ♂♀ 가 아니라 하트다** (BRIEF §4.9 · 원칙 3).
##   7살은 기호를 읽어서 아기가 왜 안 생기는지 아는 게 아니라,
##   **반쪽 하트**를 보고 "얘는 혼자예요" 를 안다. ♂♀ 는 그 다음에 붙는 이름표다.
## ⚠️ 텍스처는 Sprite2D 로 얹는다 — Control 의 `_draw` 로 그리면 네모가 된다 (RUN.md).
func _show_pair_marks() -> void:
	var by_species := {}
	for resident in residents:
		var id: String = resident.actor.species_id
		if not by_species.has(id):
			by_species[id] = {}
		by_species[id][resident.actor.sex] = true
	for resident in residents:
		var kinds: Dictionary = by_species[resident.actor.species_id]
		var paired: bool = kinds.size() >= 2
		var heart := Sprite2D.new()
		heart.texture = SpriteLibrary.pair_ui_texture("paired" if paired else "alone")
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# ⚠️ 캔버스 높이만큼 올리면 **그림에서 한참 떠서 누구 것인지 안 보인다** —
		#    캔버스 바닥은 그림의 접지선이 아니다. 그림 윗변(canvas_offset.y)에 붙인다.
		var above := Vector2(0, float(int(resident.actor.canvas_offset.y) - 4))
		if heart.texture != null:
			heart.position = above + Vector2(-5, 0)
			resident.actor.add_child(heart)
		var badge := Sprite2D.new()
		badge.texture = SpriteLibrary.pair_ui_texture(resident.actor.sex)
		badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if badge.texture != null:
			badge.position = above + Vector2(4, 1)
			resident.actor.add_child(badge)


## 짝 없이 혼자인 종 → 필드에 반드시 있어야 하는 성별. (BRIEF §2.4 확정 배치)
## 아직 집과 필드가 상태를 주고받지 않으므로 지금은 쓰이지 않는다 —
## 수집 목록이 생기면 Field 가 이 값을 FieldSim.pair_needed 로 넘긴다.
func lonely_species() -> Dictionary:
	var kinds := {}
	for resident in residents:
		var id: String = resident.actor.species_id
		if not kinds.has(id):
			kinds[id] = {}
		kinds[id][resident.actor.sex] = true
	var needed := {}
	for id in kinds:
		if kinds[id].size() >= 2:
			continue
		needed[id] = "female" if kinds[id].has("male") else "male"
	return needed


func _spawn_player(view: FieldTuning) -> void:
	var config := {
		"id": "player", "name": "나", "diet": "잡식", "activity": "주행성",
		"size_class": "중", "senses": [], "traits": [],
		"stats_range": {"sense_range": [1.0, 1.0], "charm": [1.0, 1.0]},
		"sprite_set": {"eye_style": "round", "head_anchor": [16, 3]},
	}
	player = load(ACTOR_SCENE).instantiate()
	_actors.add_child(player)
	player.setup(config, schema, view, _rng)
	player.speed_tiles = view.move_speed
	# 울타리를 못 지나간다. 대문 구간에서만 아래로 나갈 수 있다.
	player.confine = func(from: Vector2, at: Vector2) -> Vector2:
		return yard.confine_walker(from, at, yard.gate.y + 12.0)
	player.position = yard.door + Vector2(0, 12)


func _process(delta: float) -> void:
	if _leaving:
		return
	player.move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	for resident in residents:
		resident.update(delta, objects, yard.yard, _rng)
	_drift_sky(delta)
	_weather_layers.update(delta, _sky, Rect2(Vector2(-160, -90), Vector2(960, 540)))
	_check_gate()
	_refresh_hud()
	_hud.queue_redraw()


## 구름만 천천히 오간다. 필드처럼 프리셋을 걷지 않는다 — 집에 날씨가 필요한 이유는
## 하늘이 멈춰 있지 않다는 것뿐이다.
func _drift_sky(delta: float) -> void:
	_sky_hold -= delta
	if _sky_hold <= 0.0:
		_sky_target = _rng.randf_range(0.08, 0.42)
		_sky_hold = _rng.randf_range(18.0, 40.0)
	_sky["cloud"] = move_toward(float(_sky["cloud"]), _sky_target, delta / 20.0)


## 대문으로 걸어 나가면 필드다. 열린 문이 곧 안내다 — 따로 묻지 않는다.
func _check_gate() -> void:
	if player.position.distance_to(yard.gate) > 18.0:
		return
	_leaving = true
	get_tree().change_scene_to_file.call_deferred(MAP_SCENE)


# --- HUD — 재화와 자리 둘뿐 ---------------------------------------------------

## ⚠️ 글자·아이콘은 **노드**로 둔다. Control 의 _draw 에서 draw_string 을 쓰면
## 글리프가 통짜 사각형이 된다 (텍스처를 그리는 것과 같은 문제다 — RUN.md 참조).
## _draw 에는 도형만 남긴다.
func _hud_draw() -> void:
	_hud.draw_rect(Rect2(6, 8, 104, 42), Color(0, 0, 0, 0.45))
	BitmapFont5.draw(_hud, "OUT", yard.gate + Vector2(-9, -34), Color(0.92, 0.90, 0.84, 0.85), 1)


func _refresh_hud() -> void:
	_coin_label.text = "재화  %d" % coins
	_seat_label.text = "자리  %d / %d" % [residents.size(), seats]
