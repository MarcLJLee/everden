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
	terrain.generate(tuning.map_size, tile, {
		"숲": tuning.forest_patches,
		"물가": tuning.water_patches,
		"바위": tuning.rock_patches,
	}, _rng)
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

	_target_species = _collect_targets(result.species)
	sim.spawn(_target_species, player.position)
	_palette_from = _palette_of(daypart)
	_palette_to = _palette_from
	_palette_t = 1.0
	weather.setup(schema, _rng, _terrain_mix())
	guide.set_weather_axes(weather.axes)
	_apply_daypart(daypart)
	_advance_palette(0.0)


func _process(delta: float) -> void:
	if not _load_error.is_empty():
		return

	_handle_debug_input()
	player.move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_follow_player(delta)

	sim.update(delta, player.position)
	_current_hit = guide.update(_active_companions(), sim.active_animals())
	if _current_hit != null:
		metrics.note_guide()

	_clues = _apply_reveal()
	_sync_clue_markers(_clues)
	_age_puffs(delta)
	weather.update(delta, tuning.weather_drift_seconds)
	guide.set_weather_axes(weather.axes)
	_advance_palette(delta)
	_apply_eyeshine()
	_update_interaction(delta)
	metrics.update(delta)

	_camera.global_position = player.position
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
			"eye_style": "round", "mouth_style": "small",
			"eye_anchor": {"front": [16, 10], "side": [21, 10]},
			"mouth_anchor": {"front": [16, 15], "side": [24, 14]},
			"head_anchor": [16, 3],
		},
	}
	player = _make_actor(config)
	player.position = _bounds.size * 0.5
	player.speed_tiles = tuning.move_speed
	# 물가·바위는 못 밟는다. **동물에게는 걸리지 않는다** — 서식지이기 때문이다.
	# 교감은 근처에서 되므로 물가에 선 수달을 물가 밖에서 부를 수 있다.
	player.confine = _terrain_confine(player)


func _spawn_companions(species_by_id: Dictionary) -> void:
	for index in tuning.companion_ids.size():
		var id := tuning.companion_ids[index]
		if not species_by_id.has(id):
			push_warning("동료로 지정된 '%s' 가 데이터에 없습니다" % id)
			continue
		var companion := _make_actor(species_by_id[id])
		companion.position = player.position + Vector2(-tuning.tile_size * (index + 1), 8)
		companion.speed_tiles = tuning.move_speed * tuning.companion_speed_scale
		companions.append(companion)
	_active_companion_ids.assign(tuning.companions_active_at_start)
	_sync_companion_visibility()


## 동료로 데려가는 종을 뺀 나머지가 필드의 대상이다. 코드가 종을 고르지 않는다 —
## 누구를 데려갈지는 tuning 의 companion_ids 에 적혀 있다.
func _collect_targets(species_by_id: Dictionary) -> Array:
	var targets: Array = []
	for id in species_by_id:
		if id in tuning.companion_ids:
			continue
		targets.append(species_by_id[id])
	return targets


## 막힌 지형을 그 액터의 habitat 으로 판정한다. 개는 물을 못 건너고 수달은 건넌다.
func _terrain_confine(actor: Actor) -> Callable:
	return func(from: Vector2, at: Vector2) -> Vector2:
		return terrain.slide(from, at.clamp(_bounds.position, _bounds.end), schema, actor.habitat)


func _make_actor(config: Dictionary) -> Actor:
	var actor: Actor = actor_scene.instantiate()
	_actors.add_child(actor)
	actor.setup(config, schema, tuning, _rng)
	actor.bounds = _bounds
	return actor


# --- 동료 ------------------------------------------------------------------

func _active_companions() -> Array:
	var out: Array = []
	for companion in companions:
		if companion.species_id in _active_companion_ids:
			out.append(companion)
	return out


func _follow_player(_delta: float) -> void:
	var active := _active_companions()
	for index in active.size():
		var companion: Actor = active[index]
		var lateral := tuning.tile_size * 0.9 * (1.0 if index % 2 == 0 else -1.0)
		var goal := player.position + Vector2(lateral, tuning.follow_distance * tuning.tile_size)
		var to_goal := goal - companion.position
		var distance := to_goal.length()
		if distance < 4.0:
			companion.move_vector = Vector2.ZERO
		else:
			companion.move_vector = to_goal.normalized()
			companion.speed_tiles = minf(
				tuning.move_speed * tuning.companion_speed_scale,
				distance / tuning.tile_size * 2.5)


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

## 멀리 있는 동물은 그냥 보이지 않는다. 보이게 만드는 것은 둘 중 하나다 —
## 가까이 가거나, 몸을 드러내는 감각(tags.json 의 sense_reveals)을 가진 동료를 데려가거나.
## 그 밖의 감각은 방향과 단서까지만 알려준다. (BRIEF §3.3)
func _apply_reveal() -> Array:
	var reveal_px := tuning.reveal_radius * tuning.tile_size
	var clues: Array = []
	for animal in sim.active_animals():
		var near := player.position.distance_to(animal.position) <= reveal_px
		animal.actor.visible = near or guide.reveals_body(animal)
		# 보이던 게 그냥 없어지면 아이는 무슨 일이 났는지 모른다. 먼지를 남긴다.
		if animal.actor.visible != animal.was_visible:
			_puffs.append({
				"position": animal.actor.head_position() + Vector2(0, 10),
				"age": 0.0,
				"hiding": animal.was_visible,
			})
		animal.was_visible = animal.actor.visible
		if animal.actor.visible:
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


## 감각이 닿는 곳보다 승격 거리가 좁으면 코가 헛돈다 — 조용히 넘어가지 않는다.
func _promotion_radius_px() -> float:
	var widest := tuning.activation_radius * tuning.tile_size
	var needed := 0.0
	for companion in companions:
		for sense in companion.senses:
			needed = maxf(needed, guide.max_reach(companion, String(sense)))
	if needed > widest:
		push_warning("activation_radius(%.1f타일)가 가장 먼 감각(%.1f타일)보다 좁아 %.1f타일로 올려 씁니다"
			% [tuning.activation_radius, needed / tuning.tile_size, needed / tuning.tile_size])
		return needed
	return widest


# --- 교감 ------------------------------------------------------------------

func _update_interaction(delta: float) -> void:
	if gauge.active:
		player.look_direction = gauge.target.position - player.position
		if Input.is_action_just_pressed("interact_cancel"):
			gauge.cancel()  # 취소는 플레이어가 명시적으로 누를 때만
			return
		if gauge.update(delta, player.position.distance_to(gauge.target.position)):
			sim.invite(gauge.target)
			metrics.note_invited()
			gauge.close()
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
	if Input.is_action_just_pressed("debug_cycle_daypart"):
		_apply_daypart(DAYPARTS[(DAYPARTS.find(daypart) + 1) % DAYPARTS.size()])
	if Input.is_action_just_pressed("debug_reset_run"):
		_restart_run()


func _apply_daypart(next: String) -> void:
	# 지금 색에서 새 색으로 넘어간다. 튀지 않게 보간하는 것이 핵심이다 (HANDOFF §2-4).
	_palette_from = _blended_palette_name()
	daypart = next
	# ★ 시간대는 감각 반경만 바꾸는 게 아니라 **누가 나와 있는가**를 바꾼다.
	#   밤에만 나오는 동물은 낮에 아예 없다.
	if schema != null:
		for change in sim.apply_daypart(schema, daypart):
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
	player.position = _bounds.size * 0.5
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
