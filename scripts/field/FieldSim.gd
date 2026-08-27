## 필드 시뮬레이션 — 얕은 시뮬 / 풀 AI 승격. (DEMO-SPEC §3.3)
##
##   화면 밖 (얕은 시뮬)  : position += velocity * dt. 노드도 애니메이션도 없다
##   근접 반경 안 (풀 AI) : Actor 노드를 만들어 붙이고 유도·상호작용 대상이 된다
##
## 승격/강등 경계는 activation_radius 하나로 제어한다.
class_name FieldSim
extends RefCounted

## 야생 개체 하나. 노드가 없어도 존재한다 — 그게 얕은 시뮬의 요점이다.
class WildAnimal extends RefCounted:
	var species := {}
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var actor: Actor = null
	var turn_timer := 0.0
	var invited := false
	## 지난 프레임에 눈에 보였는가. 사라지는 순간을 잡아 이펙트를 띄우는 데 쓴다.
	var was_visible := false
	## 지금 시간대에 필드에 나와 있는가. 밤에만 나오는 동물이 낮에 없는 것이 이것이다.
	var present := true
	## 개체마다 한 번 굴린 값. 시간대가 바뀔 때 이 값으로 다시 판정한다.
	var presence_roll := 0.0
	## 이 개체의 이동속도 배율과 개성. 승격 전(얕은 시뮬)에도 걸려야
	## 멀리서 보던 놈이 가까이 왔을 때 갑자기 빨라지지 않는다.
	var move_scale := 1.0
	var quirks: Array = []

	func is_active() -> bool:
		return actor != null

	func display_name() -> String:
		return String(species.get("name", species.get("id", "?")))

var animals: Array[WildAnimal] = []

var _root: Node2D = null
var _actor_scene: PackedScene = null
var _schema: TagSchema = null
var _tuning: FieldTuning = null
var _rng: RandomNumberGenerator = null
var _bounds := Rect2()
var _terrain: TerrainMap = null
## 풀 AI 로 승격하는 거리(픽셀). 가장 멀리 닿는 감각보다 넓어야 코가 헛돌지 않는다.
var _promotion_px := 0.0


func setup(root: Node2D, actor_scene: PackedScene, schema: TagSchema, tuning: FieldTuning,
		rng: RandomNumberGenerator, bounds: Rect2, terrain: TerrainMap, promotion_px: float) -> void:
	_root = root
	_actor_scene = actor_scene
	_schema = schema
	_tuning = tuning
	_rng = rng
	_bounds = bounds
	_terrain = terrain
	_promotion_px = promotion_px


## 대상 종마다 animal_count 마리씩 뿌린다.
## 자기 habitat 위에서 시작한다 — 숲에 사는 애가 숲에 있어야 지형이 규칙으로 읽힌다.
func spawn(target_species: Array, player_position: Vector2) -> void:
	# 감지 반경 안에서 시작하면 "첫 유도까지 시간"이 항상 0에 가깝게 나와 지표가 죽는다.
	var min_distance := _promotion_px
	for species in target_species:
		for i in _tuning.animal_count:
			var animal := WildAnimal.new()
			animal.species = species
			animal.position = _spawn_point(species, player_position, min_distance)
			animal.velocity = _random_velocity()
			animal.turn_timer = _rng.randf_range(1.0, 4.0)
			animal.presence_roll = _rng.randf()
			animal.quirks = Actor.roll_quirks(species, _schema, _rng)
			animal.move_scale = _roll_speed(species) * _schema.quirk_product(animal.quirks, "move_scale")
			animal.velocity *= animal.move_scale
			animals.append(animal)


func _spawn_point(species: Dictionary, player_position: Vector2, min_distance: float) -> Vector2:
	if _terrain != null:
		for attempt in 30:
			var point := _terrain.random_point_in(species.get("habitat", []), _rng)
			if point != Vector2.ZERO and point.distance_to(player_position) >= min_distance:
				return point
	return _random_point_away_from(player_position, min_distance)


func update(delta: float, player_position: Vector2) -> void:
	var activation_px := _promotion_px
	for animal in animals:
		if animal.invited or not animal.present:
			continue
		_wander(animal, delta, player_position)
		var distance := animal.position.distance_to(player_position)
		if distance <= activation_px and not animal.is_active():
			_promote(animal)
		elif distance > activation_px * 1.15 and animal.is_active():
			_demote(animal)  # 경계에서 깜빡이지 않도록 여유를 준다

		if animal.is_active():
			animal.actor.position = animal.position


## 얕은 시뮬 — 랜덤 워크. 정교한 AI는 필요 없다.
func _wander(animal: WildAnimal, delta: float, player_position: Vector2) -> void:
	animal.turn_timer -= delta
	if animal.turn_timer <= 0.0:
		animal.velocity = _random_velocity() * animal.move_scale
		animal.turn_timer = _rng.randf_range(1.5, 4.5)

	# 수줍은 개체는 가까이 가면 물러선다. 개성이 화면에서 보이는 자리다 (BRIEF §2.5).
	var flee := _schema.quirk_product(animal.quirks, "flee_tiles") if not animal.quirks.is_empty() else 1.0
	if flee > 1.0:
		var away := animal.position - player_position
		if away.length() < flee * _tuning.tile_size and away.length() > 0.1:
			animal.velocity = away.normalized() * _tuning.wild_speed * _tuning.tile_size * animal.move_scale
	var stepped := animal.position + animal.velocity * delta
	# 수영 안 하는 동물이 호수를 가로지르지 않는다. 갈 수 있는 곳은 habitat 이 정한다.
	var settled := _terrain.slide(animal.position, stepped, _schema,
		animal.species.get("habitat", [])) if _terrain != null else stepped
	if settled != stepped:
		animal.velocity = -animal.velocity   # 막히면 돌아선다. 벽에 붙어 떠는 것보다 낫다
	animal.position = settled
	# 경계에서 튕긴다
	if animal.position.x < _bounds.position.x or animal.position.x > _bounds.end.x:
		animal.velocity.x *= -1.0
	if animal.position.y < _bounds.position.y or animal.position.y > _bounds.end.y:
		animal.velocity.y *= -1.0
	animal.position = animal.position.clamp(_bounds.position, _bounds.end)
	if animal.is_active():
		animal.actor.move_vector = animal.velocity


func _promote(animal: WildAnimal) -> void:
	var actor: Actor = _actor_scene.instantiate()
	_root.add_child(actor)
	actor.setup(animal.species, _schema, _tuning, _rng)
	# 개체값은 이미 굴려뒀다. 다시 굴리면 멀리서 보던 놈이 가까이 오며 딴 놈이 된다.
	actor.quirks = animal.quirks
	actor.move_scale = animal.move_scale
	actor.position = animal.position
	actor.bounds = _bounds
	actor.speed_tiles = 0.0  # 위치는 FieldSim 이 직접 준다. Actor 는 방향·연출만 맡는다
	animal.actor = actor


func _demote(animal: WildAnimal) -> void:
	animal.actor.queue_free()
	animal.actor = null


func invite(animal: WildAnimal) -> void:
	animal.invited = true
	if animal.is_active():
		_demote(animal)


## 시간대가 바뀌면 누가 나와 있는지 다시 정한다.
## 사라지는 것들은 노드를 내린다 — 낮에 박쥐가 서 있으면 안 된다.
## 방금 사라진/나타난 것들을 돌려준다 (먼지 이펙트를 띄우기 위해).
func apply_daypart(schema: TagSchema, daypart: String) -> Array:
	var changed: Array = []
	for animal in animals:
		if animal.invited:
			continue
		var chance := schema.presence_chance(animal.species, daypart)
		var present := animal.presence_roll < chance
		if present == animal.present:
			continue
		changed.append({"animal": animal, "present": present, "was_visible": animal.was_visible})
		animal.present = present
		if not present and animal.is_active():
			_demote(animal)
		animal.was_visible = false
	return changed


func count_present() -> int:
	var total := 0
	for animal in animals:
		if animal.present and not animal.invited:
			total += 1
	return total


func active_animals() -> Array[WildAnimal]:
	var out: Array[WildAnimal] = []
	for animal in animals:
		if animal.is_active() and animal.present and not animal.invited:
			out.append(animal)
	return out


func count_active() -> int:
	return active_animals().size()


func count_shallow() -> int:
	var total := 0
	for animal in animals:
		if not animal.is_active() and animal.present and not animal.invited:
			total += 1
	return total


func _roll_speed(species: Dictionary) -> float:
	var span: Array = species.get("stats_range", {}).get("move_speed", [1.0, 1.0])
	if span.size() < 2:
		return 1.0
	return _rng.randf_range(float(span[0]), float(span[1]))


func _random_velocity() -> Vector2:
	var speed := _tuning.wild_speed * _tuning.tile_size
	return Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) * speed * _rng.randf_range(0.4, 1.0)


func _random_point_away_from(origin: Vector2, min_distance: float) -> Vector2:
	for attempt in 40:
		var point := Vector2(
			_rng.randf_range(_bounds.position.x, _bounds.end.x),
			_rng.randf_range(_bounds.position.y, _bounds.end.y))
		if point.distance_to(origin) >= min_distance:
			return point
	return Vector2(_bounds.end.x, _bounds.end.y)
