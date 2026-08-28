## Demo 1: 필드 슬라이스 — 전체를 엮는 곳. (DEMO-SPEC)
##
## 답해야 할 질문: 필드를 돌아다니다 동료가 이끄는 대로 가서 동물을 만나는 것이 재미있는가?
##
## 조작:
##   WASD / 방향키 — 이동          스페이스 — 교감 시작       ESC — 교감 취소
##   1 / 2         — 동료 켜고 끄기  T — 시간대 전환           R — 측정 다시 시작
extends Node2D

@export var tuning: FieldTuning
@export var actor_scene: PackedScene

const DAYPARTS := ["낮", "여명", "밤"]

@onready var _ground: Node2D = $Ground
@onready var _actors: Node2D = $Actors
@onready var _markers: Node2D = $Markers
## 날씨 겹을 화면보다 얼마나 넓게 까는가. 1.0 이면 가장자리가 빈다.
const WEATHER_MARGIN := 1.6

@onready var _weather_layers: WeatherLayers = $Weather
@onready var _snow: SnowField = $Snow
@onready var _ambient: AmbientLife = $AmbientAir
@onready var _card: CanvasLayer = $InviteCard
@onready var _go_home: CanvasLayer = $GoHome
@onready var _hud: CanvasLayer = $FieldHud
@onready var _gauge_marks: GaugeMarks = $GaugeMarks
@onready var _camera: Camera2D = $Camera2D
@onready var _overlay = $DebugOverlay
@onready var _modulate: CanvasModulate = $CanvasModulate

var schema: TagSchema = null
var sim := FieldSim.new()
var guide := GuideSystem.new()
var gauge := Gauge.new()
var metrics := Metrics.new()

var terrain := TerrainMap.new()
var player: Actor = null
var companions: Array[Actor] = []
var daypart := "낮"
## 날씨는 이름이 아니라 축이다. 지형이 어느 축을 잘 세우는지 정하고,
## 축은 목표를 향해 천천히 흘러간다. (BRIEF §6.8)
var weather := WeatherSystem.new()

var _rng := RandomNumberGenerator.new()
var _bounds := Rect2()
var _target_species: Array = []
var _active_companion_ids: Array[String] = []
var _current_hit: GuideSystem.Hit = null
var _clues: Array = []
var _puffs: Array = []
var _promotion_px := 0.0
var _props: Array = []
var _region_name := ""
## 동료마다의 어슬렁 목표. 잡은 게 없을 때 곁에서 조금씩 돌아다닌다.
var _strolls := {}
var _last_weather_name := ""
## 지금 원정 중인 지역. 세계 지도가 생기면 거기서 정해진다 (BRIEF §3.9).
@export var region_id := "home_hills"
var _clue_markers: Array = []
var _palette_from := "day"
var _palette_to := "day"
var _palette_t := 1.0

## 사라짐/나타남 이펙트가 화면에 남아 있는 시간
const PUFF_LIFE := 0.45
var _load_error := ""


func _ready() -> void:
	_rng.randomize()

	var result := DataLoader.load_all(true)
	print(result.report())
	if not result.ok:
		# 로드 거부는 조용히 넘어가면 안 된다. 화면에도 남긴다.
		_load_error = result.reject_reason + "\n" + "\n".join(result.errors)
		_overlay.show_load_error(_load_error)
		return
	schema = result.schema

	var tile := tuning.tile_size
	_bounds = Rect2(Vector2.ZERO, Vector2(tuning.map_size) * tile)
	for name in schema.terrain_walkable:
		if not schema.walkable(String(name)):
			terrain.blocked_terrains.append(String(name))
	# ★ 지형은 **지역이 정한다.** 모든 필드에 물가가 조금씩 섞이면
	#   뒷산에 늘 개울이 있는 셈이 되어 "뒷산에 수달이 산다"가 되어버린다.
	var region: Dictionary = result.regions.get(Game.region_id, result.regions.get(region_id, {}))
	var shape: Dictionary = region.get("terrain", {})
	var patches: Dictionary = shape.get("patches", {
		"숲": tuning.forest_patches, "물가": tuning.water_patches, "바위": tuning.rock_patches,
	})
	terrain.generate(tuning.map_size, tile, patches, _rng, String(shape.get("base", "초원")),
		shape.get("streams", {}))
	_ground.setup(tuning, terrain)
	_props = PropScatter.scatter(_actors, terrain, tuning, _rng)
	_camera.zoom = Vector2.ONE * tuning.camera_zoom
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(_bounds.size.x)
	_camera.limit_bottom = int(_bounds.size.y)

	guide.setup(schema, tuning, terrain)
	gauge.setup(tuning, schema)

	_spawn_player()
	_spawn_companions(result.species)
	for companion in companions:
		companion.confine = _terrain_confine(companion)
	_promotion_px = _promotion_radius_px()
	sim.setup(_actors, actor_scene, schema, tuning, _rng, _bounds, terrain, _promotion_px)
	# 이 필드가 어느 지역인가. 지역이 늘면 여기만 갈아끼운다.
	sim.region = region
	_region_name = String(region.get("name", ""))
	# 짝 없이 혼자인 종이 있으면 그 종의 반대 성별이 반드시 정의된다 (BRIEF §2.4 확정 배치)
	sim.pair_needed = Game.lonely_species()

	_target_species = _collect_targets(result.species)
	sim.spawn(_target_species, player.position)
	_palette_from = _palette_of(daypart)
	_palette_to = _palette_from
	_palette_t = 1.0
	weather.setup(schema, _rng, _terrain_mix())
	# 잡을 수 없는 생명. 지면·수면 생물은 Y-sort 안으로 들어가 캐릭터에 가린다.
	_ambient.setup(terrain, _rng, _actors, region)
	# ★ **나가는 길.** 이게 없어서 원정을 나가면 못 돌아왔다 (BRIEF §3.13).
	#   여는 키는 저쪽이 갖는다 — 양쪽이 같은 키를 보면 열자마자 닫힌다.
	_go_home.faces_provider = _going_home_faces
	_go_home.schema_provider = func() -> TagSchema: return schema
	# 늘 보이는 것은 **지명과 자리 둘뿐**이다 (BRIEF §3.4).
	_hud.refresh(String(region.get("name", "")), Game.collection.size(), tuning.home_seats)
	_go_home.go_home.connect(func() -> void:
		# ★ 짝은 **돌아올 때** 정해진다. 데려오자마자 바로 되는 게 아니다 (사용자 지적).
		Game.rolled_pairs = Game.roll_pairs()
		get_tree().call_deferred("change_scene_to_file", "res://scenes/home/Home.tscn"))
	_weather_layers.build()
	# `godot --path . -- --snow` 로 켜면 눈부터 시작한다. 계절이 없는 동안 눈을 보려는 용도다.
	if "--snow" in OS.get_cmdline_user_args():
		var snowy: Dictionary = weather.data.get("presets", {}).get("함박눈", {})
		if not snowy.is_empty():
			weather.axes = snowy.duplicate()
			weather.target = snowy.duplicate()
	guide.set_weather_axes(weather.axes)
	_apply_daypart(daypart)
	_advance_palette(0.0)


func _process(delta: float) -> void:
	if not _load_error.is_empty():
		return

	_handle_debug_input()
	# 무언가 물어보는 동안에는 걸어 다니지 않는다
	var asking: bool = _card.is_open() or _go_home.is_open()
	player.move_vector = Vector2.ZERO if asking \
		else Input.get_vector("move_left", "move_right", "move_up", "move_down")

	_follow_player(delta)

	sim.update(delta, player.position)
	# 유도는 **놓인 개체 전부**를 본다. 노드가 붙었는지는 상관없다 —
	# 코는 저 너머의 냄새도 맡는다.
	_current_hit = guide.update(_active_companions(), sim.present_animals())
	if _current_hit != null:
		metrics.note_guide()

	_clues = _apply_reveal()
	_sync_clue_markers(_clues)
	_age_puffs(delta)
	weather.update(delta, tuning.weather_drift_seconds)
	guide.set_weather_axes(weather.axes)
	_follow_weather()
	# 겹은 지금 화면이 덮는 월드 사각형 위에 얹는다. 액터 다음이라 캐릭터 위에도 떨어진다.
	# ⚠️ **카메라를 먼저 옮기고** 재야 한다. 뒤에 옮기면 겹이 한 프레임 늦게 따라와
	#    빠르게 달릴 때 진행 방향 가장자리가 빈다.
	_camera.global_position = player.position
	_weather_layers.update(delta, weather.axes, weather_view_rect(),
		float(tuning.daypart_daylight.get(daypart, 1.0)),
		float(tuning.daypart_sun_height.get(daypart, 1.0)))
	_snow.update(delta, float(weather.axes.get("snow", 0.0)),
		float(weather.axes.get("wind", 0.3)), camera_visible_rect())
	_ambient.update(delta, camera_visible_rect())
	# 풀과 나무는 바람에 흔들린다. 바람 축 하나가 세기와 빈도를 둘 다 정한다.
	PropScatter.sway(_props, delta, float(weather.axes.get("wind", 0.3)),
		camera_visible_rect())
	_advance_palette(delta)
	_apply_eyeshine()
	_update_interaction(delta)
	metrics.update(delta)
	_hud.refresh(String(_region_name), Game.collection.size(), tuning.home_seats)
	_gauge_marks.show_marks(_gauge_marks_now())
	_overlay.refresh(_build_state())


# --- 스폰 -------------------------------------------------------------------

## 플레이어는 종 데이터가 없다. 같은 모양의 딕셔너리를 만들어 넘겨서
## Actor 안에 "플레이어면 이렇게" 하는 분기가 생기지 않게 한다.
func _spawn_player() -> void:
	var config := {
		"id": "player", "name": "나", "diet": "잡식", "activity": "주행성",
		"size_class": "중", "senses": [], "traits": [],
		"stats_range": {"sense_range": [1.0, 1.0], "charm": [1.0, 1.0]},
		"sprite_set": {
			"eye_style": "player", "mouth_style": "small",
			"head_anchor": [16, 3],
			# 플레이어만 4방향이다 — 동물은 측면 1방향 (BRIEF §4.5 ★ v3.16)
			"facing": "four",
		},
	}
	player = _make_actor(config)
	# ⚠️ 한가운데가 물이나 바위면 그대로 갇힌다 — 설 수 있는 가장 가까운 자리로 옮긴다.
	player.position = terrain.nearest_standing(_bounds.size * 0.5, schema, [])
	player.speed_tiles = tuning.move_speed
	# 물가·바위는 못 밟는다. **동물에게는 걸리지 않는다** — 서식지이기 때문이다.
	# 교감은 근처에서 되므로 물가에 선 수달을 물가 밖에서 부를 수 있다.
	player.confine = _terrain_confine(player)


## 누구를 데려왔는가는 **지도에서 고른 것**이다 (BRIEF §3.9).
## 저장에 아무도 없으면(DEMO 로 바로 들어온 경우) 튜닝의 기본값을 쓴다.
func _spawn_companions(species_by_id: Dictionary) -> void:
	var going: Array = []
	for one in Game.party_members():
		if species_by_id.has(String(one["species_id"])):
			going.append(one)
	if going.is_empty():
		for id in tuning.companion_ids:
			if species_by_id.has(id):
				going.append({"species_id": id, "sex": ""})
	for index in going.size():
		var one: Dictionary = going[index]
		var companion := _make_actor(species_by_id[String(one["species_id"])],
			String(one.get("sex", "")))
		companion.position = player.position + Vector2(-tuning.tile_size * (index + 1), 8)
		companion.speed_tiles = tuning.move_speed * tuning.companion_speed_scale
		companions.append(companion)
	# 데려온 아이는 처음부터 같이 다닌다 — 지도에서 이미 골랐다.
	_active_companion_ids.clear()
	for companion in companions:
		_active_companion_ids.append(companion.species_id)
	_sync_companion_visibility()


## 동료로 데려가는 종을 뺀 나머지가 필드의 대상이다. 코드가 종을 고르지 않는다 —
## 누구를 데려갈지는 tuning 의 companion_ids 에 적혀 있다.
func _collect_targets(species_by_id: Dictionary) -> Array:
	var going: Array = []
	for companion in companions:
		going.append(companion.species_id)
	var targets: Array = []
	for id in species_by_id:
		if id in going:
			continue
		targets.append(species_by_id[id])
	return targets


## 막힌 지형을 그 액터의 habitat 으로 판정한다. 개는 물을 못 건너고 수달은 건넌다.
func _terrain_confine(actor: Actor) -> Callable:
	return func(from: Vector2, at: Vector2) -> Vector2:
		return terrain.slide(from, at.clamp(_bounds.position, _bounds.end), schema, actor.habitat)


## 같이 가는 아이들 — 데려온 동료와 오늘 초대한 아이.
## ⚠️ **숫자로 적지 않는다.** "동료 2 / 초대 1" 이라고 쓰면 그게 성적표가 된다 (§6.9).
func _going_home_faces() -> Array:
	var faces: Array = []
	for companion in companions:
		faces.append(companion.species)
	for animal in sim.animals:
		if animal.invited:
			faces.append(animal.species)
	return faces


func _make_actor(config: Dictionary, sex := "") -> Actor:
	var actor: Actor = actor_scene.instantiate()
	_actors.add_child(actor)
	actor.setup(config, schema, tuning, _rng, sex)
	actor.bounds = _bounds
	return actor


# --- 동료 ------------------------------------------------------------------

func _active_companions() -> Array:
	var out: Array = []
	for companion in companions:
		if companion.species_id in _active_companion_ids:
			out.append(companion)
	return out


## 동료는 평소에 따라오고, **무언가를 잡으면 그쪽으로 앞장선다.**
##
## ★ **유도의 방향은 몸이 말한다** (BRIEF §4.5 ★ v3.16). 화면 가장자리 화살표를
##   그리지 않는다 — 그건 게임이 알려주는 것이지 세계의 사건이 아니다.
##   개가 그쪽으로 당기는 것을 보고 아이가 따라가는 것, 그게 유도다.
## ★ 도착하면 **거기서 꼬리를 흔든다** — 특징 동작은 서 있을 때만 나온다.
##   걸어가는 동안 흔들면 그건 이동이지 "여기야" 가 아니다.
## ★ **줄에 매인 것처럼 굴어야 한다.** 앞장서되 플레이어에게서 `lead_leash` 만큼만
##   멀어진다. 그 끝에서 멈춰 돌아본다 — 아이가 따라오면 그만큼 더 간다.
##   안 그러면 개가 혼자 화면 밖으로 달려가고, 그건 유도가 아니라 이별이다.
func _follow_player(delta: float) -> void:
	var active := _active_companions()
	var leash := tuning.lead_leash * tuning.tile_size
	for index in active.size():
		var companion: Actor = active[index]
		var lateral := tuning.tile_size * 0.9 * (1.0 if index % 2 == 0 else -1.0)
		var goal := player.position + Vector2(lateral, tuning.follow_distance * tuning.tile_size)
		# ★ **잡은 게 없으면 곁에서 어슬렁거린다** (사용자 지적).
		#   자리에 딱 붙여 세웠더니 플레이어에게 들러붙은 것처럼 보였다 —
		#   개는 따라오면서도 여기저기 코를 박는다. 그게 살아 있는 것으로 읽힌다.
		goal += _stroll(companion, delta)
		goal = lead_goal(companion, goal)
		var to_goal := goal - companion.position
		var distance := to_goal.length()
		# ⚠️ 목표가 가까우면 속도도 같이 줄어드는데, **바닥이 없으면 기어간다** —
		#   곁에서 한 뼘 어슬렁거리는 데 몇 초가 걸려서 걷는 걸로 안 보인다.
		companion.speed_tiles = clampf(distance / tuning.tile_size * 2.5,
			tuning.move_speed * 0.45, tuning.move_speed * tuning.companion_speed_scale)
		# ⚠️ 한 걸음 안쪽이면 **딱 붙여 세운다.** 지나쳤다 돌아오기를 반복하면
		#    줄 끝에서 부르르 떨고, 멈춰야 나오는 **꼬리 흔들기가 안 나온다**
		#    (특징 동작은 서 있을 때만 재생된다).
		var step := companion.speed_tiles * companion.move_scale * tuning.tile_size * delta
		if distance <= maxf(step, 2.0):
			companion.position = goal
			companion.move_vector = Vector2.ZERO
		else:
			companion.move_vector = to_goal.normalized()


## 이 동료가 가려는 자리. 잡은 게 있으면 **그쪽으로, 줄 길이까지만.**
## ⚠️ 따로 뺀 이유는 회귀가 이걸 직접 재기 위해서다 — 움직인 결과를 재면
##    다른 판정이 남긴 걸음이 섞여 들어와 값이 깜빡인다.
func lead_goal(companion: Actor, resting: Vector2) -> Vector2:
	var hit: GuideSystem.Hit = guide.leads.get(companion)
	if hit == null:
		return resting
	var toward: Vector2 = hit.animal.position - player.position
	var far: float = minf(toward.length(), tuning.lead_leash * tuning.tile_size)
	return player.position + toward.normalized() * far


## 곁에서의 어슬렁. 잡은 게 있으면 lead_goal 이 이 값을 덮어쓴다.
## ⚠️ 목표를 **가끔만** 바꾼다. 매 프레임 흔들면 걷는 게 아니라 떠는 것으로 보인다.
func _stroll(companion: Actor, delta: float) -> Vector2:
	var state: Dictionary = _strolls.get(companion, {"at": Vector2.ZERO, "left": 0.0})
	state["left"] = float(state["left"]) - delta
	if float(state["left"]) <= 0.0:
		state["left"] = _rng.randf_range(1.4, 3.2)
		# 반쯤은 제자리에 선다 — 늘 움직이면 그것대로 부산하다
		if _rng.randf() < 0.45:
			state["at"] = Vector2.ZERO
		else:
			state["at"] = Vector2.from_angle(_rng.randf() * TAU) \
				* _rng.randf_range(0.4, 1.3) * tuning.tile_size
	_strolls[companion] = state
	return state["at"]


func _sync_companion_visibility() -> void:
	for companion in companions:
		var on := companion.species_id in _active_companion_ids
		companion.visible = on
		if not on:
			companion.hide_sense_icon()


func _toggle_companion(index: int) -> void:
	if index >= tuning.companion_ids.size():
		return
	var id := tuning.companion_ids[index]
	if id in _active_companion_ids:
		_active_companion_ids.erase(id)
	else:
		_active_companion_ids.append(id)
	_sync_companion_visibility()


# --- 무엇이 보이는가 ---------------------------------------------------------

## ★ **보이는 것은 언제나 내 시야 안에 있는 것이다.** (BRIEF §3.14 · 사용자 지적)
##   동료가 감지했다고 저 멀리 있는 동물을 화면에 그리는 건 세계의 사건이 아니라
##   **게임이 알려주는 것**이다. 감각은 전부 "거기에 뭔가 있다" 까지만 말한다.
##   그래서 발견의 순간이 아이에게 남는다 — 동료는 데려다주고, 보는 것은 아이가 한다.
##
## ★ 단서는 **놓인 개체 전부**에서 나온다. 노드가 붙은 개체만 보면
##   승격 반경이 감각 반경 전체를 덮어야 했다 — 이제 보이는 반경만 덮으면 된다.
func _apply_reveal() -> Array:
	var reveal_px := tuning.reveal_radius * tuning.tile_size
	var clues: Array = []
	for animal in sim.active_animals():
		var near := player.position.distance_to(animal.position) <= reveal_px
		animal.actor.visible = near
		# 보이던 게 그냥 없어지면 아이는 무슨 일이 났는지 모른다. 먼지를 남긴다.
		if animal.actor.visible != animal.was_visible:
			_puffs.append({
				"position": animal.actor.head_position() + Vector2(0, 10),
				"age": 0.0,
				"hiding": animal.was_visible,
			})
		animal.was_visible = animal.actor.visible
	# 노드가 없는 개체도 단서는 남긴다 — 흔적은 몸이 아니라 자리에 있는 것이다
	for animal in sim.animals:
		if animal.invited or not animal.present:
			continue
		if animal.is_active() and animal.actor != null and animal.actor.visible:
			continue
		var senses := guide.detected_senses(animal)
		if senses.is_empty():
			continue
		clues.append({
			"position": animal.position,
			"sense": String(senses[0]),
			"clue": guide.clue_of(animal),
		})
	return clues


## 단서는 그 자리에 있는 것이지 화면 장식이 아니다 — 월드 노드로 둔다.
## 그래야 카메라 배율·밤낮 틴트가 따로 손대지 않아도 맞는다.
func _sync_clue_markers(clues: Array) -> void:
	while _clue_markers.size() < clues.size():
		var marker := Sprite2D.new()
		_markers.add_child(marker)
		_clue_markers.append(marker)
	for i in _clue_markers.size():
		var marker: Sprite2D = _clue_markers[i]
		if i >= clues.size():
			marker.visible = false
			continue
		var clue: Dictionary = clues[i]
		var texture := SpriteLibrary.airborne_clue_texture(String(clue["sense"]))
		if texture == null:
			texture = PlaceholderArt.emote_texture(String(clue["sense"]))
		marker.texture = texture
		marker.position = (clue["position"] as Vector2).round() + Vector2(0, -18)
		marker.visible = true


## 어두울 때 눈이 되비춘다. 종이 아니라 activity 로 정해지므로
## 야행성·박명성이면 어느 종이든 자동으로 따라온다. (tags.json 의 eyeshine)
func _apply_eyeshine() -> void:
	var tint := DayPalette.tint()
	# 되비추는 빛은 화면 전체 어둠에 같이 묻히면 안 된다 — 틴트를 되돌린다.
	var cancel := Color(1.0 / maxf(tint.r, 0.05), 1.0 / maxf(tint.g, 0.05), 1.0 / maxf(tint.b, 0.05))
	for actor in _all_actors():
		actor.set_eyeshine(schema.eyeshines_at(actor.activity, daypart), tuning.eyeshine_color, cancel)


func _all_actors() -> Array:
	var out: Array = [player]
	out.append_array(companions)
	for animal in sim.active_animals():
		out.append(animal.actor)
	return out


func _age_puffs(delta: float) -> void:
	for puff in _puffs:
		puff["age"] += delta
	_puffs = _puffs.filter(func(puff): return puff["age"] < PUFF_LIFE)


## 승격은 **보이는 반경**만 덮으면 된다. (BRIEF §3.14)
##
## ⚠️ 예전에는 여기서 승격 반경을 **감각 반경까지 되올렸다.** 저 멀리서 감지된 몸을
##    그려야 했기 때문이다 — 그 이유가 없어졌는데 장치만 남아 있어서, 튜닝을 8타일로
##    낮춰도 조용히 26타일로 돌아가고 있었다. 안 쓰는 안전장치가 제일 위험하다.
## ⚠️ 그래도 **보이는 반경보다는 넉넉해야** 한다. 딱 맞으면 몸이 화면에 들어오는 순간
##    노드가 붙어서, 걷던 자세가 아니라 선 자세로 툭 나타난다.
func _promotion_radius_px() -> float:
	var widest := tuning.activation_radius * tuning.tile_size
	var needed := tuning.reveal_radius * tuning.tile_size * 1.5
	if widest < needed:
		push_warning("activation_radius(%.1f타일)가 보이는 반경(%.1f타일)보다 좁아 %.1f타일로 올려 씁니다"
			% [tuning.activation_radius, tuning.reveal_radius, needed / tuning.tile_size])
		return needed
	return widest


# --- 교감 ------------------------------------------------------------------

func _update_interaction(delta: float) -> void:
	if _card.is_open() or _go_home.is_open():
		return
	if gauge.active:
		player.look_direction = gauge.target.position - player.position
		if Input.is_action_just_pressed("interact_cancel"):
			gauge.cancel()  # 취소는 플레이어가 명시적으로 누를 때만
			return
		if gauge.update(delta, player.position.distance_to(gauge.target.position)):
			# ★ 친구가 생긴 순간은 **바로 저장한다** (사용자 지적).
			#   원정 중에 창을 닫아도 만난 아이가 사라지면 되돌릴 수 없는 손실이다 (원칙 2).
			var species: Dictionary = gauge.target.species
			var fresh := not (String(species.get("id", "")) in Game.seen)
			var one := Game.add(String(species.get("id", "")), gauge.target.sex)
			one["stage"] = gauge.target.stage
			one["age_years"] = gauge.target.age_years
			Game.save_game()
			sim.invite(gauge.target)
			metrics.note_invited()
			gauge.close()
			# 누구를 초대했는지 보여준다. 축하지 평가가 아니다 (§3.12).
			_card.show_for(one, species, fresh, schema)
			return
		# 멈춰 있는 동안에는 다른 아이에게 갈 수 있다. 점유 중일 때는 못 바꾼다 —
		# 지금 하고 있는 일이 있는데 딴 데를 누르면 그게 더 이상하다.
		if not (gauge.paused and Input.is_action_just_pressed("interact")):
			return
		var other := _nearest_interactable()
		if other == null or other == gauge.target:
			return
		gauge.close()   # 쏟은 시간은 그 아이에게 남는다
		gauge.start(other, _lead_companion_for(other), daypart)
		return

	player.look_direction = Vector2.ZERO
	if not Input.is_action_just_pressed("interact"):
		return
	var animal := _nearest_interactable()
	if animal == null:
		return
	gauge.start(animal, _lead_companion_for(animal), daypart)


func _nearest_interactable() -> FieldSim.WildAnimal:
	var radius := tuning.interact_radius * tuning.tile_size
	var best: FieldSim.WildAnimal = null
	var best_distance := INF
	for animal in sim.active_animals():
		if not animal.actor.visible:
			continue  # 안 보이는 것과 교감할 수는 없다
		var distance := player.position.distance_to(animal.position)
		if distance <= radius and distance < best_distance:
			best = animal
			best_distance = distance
	return best


## 게이지 계수를 결정하는 동료. 그 대상을 감지한 동료가 있으면 그쪽이고,
## 없으면 데려온 동료 중 첫 번째다.
func _lead_companion_for(animal: FieldSim.WildAnimal) -> Actor:
	if _current_hit != null and _current_hit.animal == animal:
		return _current_hit.companion
	var active := _active_companions()
	return active[0] if not active.is_empty() else null


# --- 디버그 ----------------------------------------------------------------

func _handle_debug_input() -> void:
	if Input.is_action_just_pressed("debug_toggle_companion_1"):
		_toggle_companion(0)
	if Input.is_action_just_pressed("debug_toggle_companion_2"):
		_toggle_companion(1)
	if Input.is_action_just_pressed("debug_cycle_weather"):
		weather._pick_target()   # 다음 날씨로 넘어가는 것을 눈으로 보려고 두는 치트
	if Input.is_action_just_pressed("debug_cycle_snow"):
		# 눈은 계절이 생긴 뒤에만 저절로 온다 (weather.json 의 season_note).
		# 그 전에도 눈으로 확인할 수 있게 열어두는 치트다.
		_cycle_snow()
	if Input.is_action_just_pressed("debug_cycle_daypart"):
		_apply_daypart(DAYPARTS[(DAYPARTS.find(daypart) + 1) % DAYPARTS.size()])
	if Input.is_action_just_pressed("debug_reset_run"):
		_restart_run()


const SNOW_CHEAT := ["진눈깨비", "눈", "함박눈"]

func _cycle_snow() -> void:
	var presets: Dictionary = weather.data.get("presets", {})
	# 지금 목표가 눈이면 다음 단계로, 아니면 처음부터. 끝까지 갔으면 평소 날씨로 돌아간다.
	var at := -1
	for i in SNOW_CHEAT.size():
		if presets.has(SNOW_CHEAT[i]) \
				and is_equal_approx(float(weather.target.get("snow", 0.0)),
					float(presets[SNOW_CHEAT[i]].get("snow", 0.0))):
			at = i
	var next: String = SNOW_CHEAT[at + 1] if at + 1 < SNOW_CHEAT.size() else ""
	if next.is_empty() or not presets.has(next):
		weather._pick_target()
		return
	weather.target = (presets[next] as Dictionary).duplicate()


## 날씨 겹을 깔 월드 사각형.
##
## ⚠️ **카메라가 실제로 보는 곳에 깐다.** `global_position` 은 카메라가 *가려는* 곳이지
##    보고 있는 곳이 아니다 — 맵 끝에서는 `limit_*` 이 잡아 세우고, 달리는 동안은
##    `position_smoothing` 이 뒤처진다. 플레이어 위치로 깔았더니 구석에서 화면 한쪽이
##    맨땅으로 남았다 (사용자 지적). `get_screen_center_position()` 이 둘 다 반영한다.
## ⚠️ 화면 크기를 그대로 쓰면 **가장자리에서 겹이 끝난다**. 창 종횡비가 기준과 어긋나면
##    뷰포트가 기준 해상도보다 커지는데 겹은 기준값으로 깔린다.
##    타일 반복이라 넓게 까는 값은 공짜다. 넉넉히 덮는다.
func weather_view_rect() -> Rect2:
	var half := get_viewport_rect().size / (2.0 * tuning.camera_zoom) * WEATHER_MARGIN
	return Rect2(_camera.get_screen_center_position() - half, half * 2.0)


## 카메라가 지금 실제로 비추는 월드 사각형. 겹이 이걸 덮는지 회귀로 잰다.
func camera_visible_rect() -> Rect2:
	var size := get_viewport_rect().size / tuning.camera_zoom
	return Rect2(_camera.get_screen_center_position() - size * 0.5, size)


func _apply_daypart(next: String) -> void:
	# 지금 색에서 새 색으로 넘어간다. 튀지 않게 보간하는 것이 핵심이다 (HANDOFF §2-4).
	_palette_from = _blended_palette_name()
	daypart = next
	# ★ 시간대는 감각 반경만 바꾸는 게 아니라 **누가 나와 있는가**를 바꾼다.
	#   밤에만 나오는 동물은 낮에 아예 없다.
	if schema != null:
		for change in sim.apply_daypart(schema, daypart, weather.axes):
			if not change["was_visible"]:
				continue
			# 눈앞에서 사라졌다면 먼지를 남긴다. 그냥 없어지면 사라진 줄도 모른다.
			var animal: FieldSim.WildAnimal = change["animal"]
			_puffs.append({
				"position": animal.position + Vector2(0, -10),
				"age": 0.0,
				"hiding": not change["present"],
			})
	_palette_to = _palette_of(daypart)
	_palette_t = 0.0 if _palette_from != _palette_to else 1.0
	guide.set_daypart(daypart)


## 날씨가 **누가 나오는지**를 바꾼다. 축이 계속 흐르므로 매 프레임 다시 굴리면
## 동물이 깜빡인다 — 날씨의 **이름이 바뀔 때만** 다시 정한다.
func _follow_weather() -> void:
	var name := weather.nickname()
	if name == _last_weather_name:
		return
	_last_weather_name = name
	for change in sim.apply_daypart(schema, daypart, weather.axes):
		if not change["was_visible"]:
			continue
		var animal: FieldSim.WildAnimal = change["animal"]
		_puffs.append({
			"position": animal.position + Vector2(0, -10),
			"age": 0.0,
			"hiding": not change["present"],
		})


## 지형 구성 — 어느 지형이 몇 타일인가. 날씨가 이걸 보고 어느 축을 세울지 정한다.
func _terrain_mix() -> Dictionary:
	var mix := {}
	for y in tuning.map_size.y:
		for x in tuning.map_size.x:
			var name := terrain.at_tile(Vector2i(x, y))
			mix[name] = int(mix.get(name, 0)) + 1
	return mix


func _palette_of(name: String) -> String:
	return String(tuning.daypart_palette.get(name, "day"))


## 전환 도중에 또 바꾸면 지금 보이는 색에서 출발해야 한다.
## 보간 중간값에 이름이 없으므로 절반을 넘겼는지로 가른다.
func _blended_palette_name() -> String:
	return _palette_to if _palette_t >= 0.5 else _palette_from


## 팔레트는 단계로 끊어 다시 만들고(텍스처 재생성 비용), 틴트는 매 프레임 부드럽게 간다.
func _advance_palette(delta: float) -> void:
	if not DayPalette.has_data():
		return
	if _palette_t < 1.0:
		_palette_t = minf(1.0, _palette_t + delta / maxf(tuning.daypart_fade, 0.01))
	if DayPalette.set_blend(_palette_from, _palette_to, _palette_t):
		_ground.refresh_textures()
		PropScatter.refresh_textures(_props)
	# 시간대 틴트 × 날씨 틴트. 팔레트는 시간대만 건드린다 — 곱셈이 아니라 덧셈이 되는 자리다.
	_modulate.color = DayPalette.tint() * weather.tint()


## 첫 유도까지 걸린 시간을 다시 재려면 필드를 다시 깔아야 한다.
func _restart_run() -> void:
	gauge.cancel()
	for animal in sim.animals:
		if animal.is_active():
			animal.actor.queue_free()
	sim.animals.clear()
	# ⚠️ 한가운데가 물이나 바위면 그대로 갇힌다 — 설 수 있는 가장 가까운 자리로 옮긴다.
	player.position = terrain.nearest_standing(_bounds.size * 0.5, schema, [])
	for companion in companions:
		companion.position = player.position + Vector2(-tuning.tile_size, 8)
		companion.hide_sense_icon()
	sim.spawn(_target_species, player.position)
	metrics.reset()
	_current_hit = null
	_clues = []
	_puffs.clear()


func _build_state() -> Dictionary:
	return {
		"metrics": metrics,
		"gauge": gauge,
		"hit": _current_hit,
		"daypart": daypart,
		"weather": weather.nickname(),
		"weather_axes": weather.axes,
		"weather_summary": weather.summary(),
		"present_count": sim.count_present(),
		"roster": sim.roster(),
		"sex_mix": sim.sex_mix(),
		"total_count": sim.animals.size(),
		"active_count": sim.count_active(),
		"shallow_count": sim.count_shallow(),
		"companions": _companion_status(),
		"clues": _clues,
		"partial": _partial_invites(),
		"puffs": _puffs,
		"puff_life": PUFF_LIFE,
		"visible_count": _visible_count(),
		"senses": _sense_status(),
		"terrain": terrain.at_world(player.position),
		"promotion_tiles": _promotion_px / tuning.tile_size,
		"player": player,
	}


## 지금 각 동료의 감각이 몇 타일까지 닿는가. 규칙은 눈에 보여야 한다.
func _sense_status() -> String:
	var parts := PackedStringArray()
	for companion in _active_companions():
		for sense in companion.senses:
			parts.append("%s %s %.0f타일" % [
				companion.display_name, sense, guide.reach_tiles(companion, String(sense))])
	return "   ".join(parts) if not parts.is_empty() else "(데려간 동료 없음)"


## 쏟다 만 아이들. 진행은 누적으로 보여야 한다(원칙 3) —
## 어디까지 했는지 안 보이면 다시 찾아갈 이유가 안 생긴다.
## 지금 화면에 띄울 게이지들. 채우는 중인 하나와, **쏟다 만 자국들**.
func _gauge_marks_now() -> Array:
	var marks: Array = _partial_invites()
	if gauge.active and gauge.target != null and gauge.target.actor != null:
		marks.append({
			"position": gauge.target.actor.head_position(),
			"progress": gauge.progress,
			"active": true,
			"paused": gauge.paused,
		})
	return marks


func _partial_invites() -> Array:
	var out: Array = []
	for animal in sim.active_animals():
		if animal.invite_progress <= 0.01:
			continue
		if gauge.active and animal == gauge.target:
			continue
		if not animal.actor.visible:
			continue
		out.append({"position": animal.actor.head_position(), "progress": animal.invite_progress})
	return out


func _visible_count() -> int:
	var total := 0
	for animal in sim.active_animals():
		if animal.actor.visible:
			total += 1
	return total


func _companion_status() -> String:
	var parts := PackedStringArray()
	for index in companions.size():
		var companion: Actor = companions[index]
		var on := companion.species_id in _active_companion_ids
		parts.append("[%d] %s(%s) %s" % [
			index + 1, companion.display_name,
			", ".join(PackedStringArray(companion.senses)),
			"ON" if on else "off"])
	return "   ".join(parts)
