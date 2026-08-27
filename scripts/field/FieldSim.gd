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
	## 이 개체에 쏟은 점유 시간 (0~1). **게이지가 아니라 개체가 들고 있다** —
	## 다른 데 갔다 와도 이어서 찰 수 있어야 한다. 한 번 쏟은 시간은 사라지지 않는다.
	var invite_progress := 0.0

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
## 이 필드가 속한 지역의 생태
var region := {}


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


## ★ 1단계 — **개체 정의는 필드에 들어갈 때 한 번뿐이다.** (BRIEF §3.11)
##
## 종 목록이 아니라 **개체 목록**이다 — 수달 두 마리, 너구리 셋, 고라니 0마리.
## **개체수 0 은 정상이다.** 어떤 종은 이번 원정에 아예 없다 —
## 그것이 "조건을 다 맞췄는데 왜 없지"의 정직한 답이고,
## 확률 파라미터가 아니라 **개체 수 분포**다.
##
## 마릿수는 **그 필드에 그 종의 서식지가 얼마나 있는가**에서 나온다.
## 물가가 거의 없는 필드에 수달이 많으면 그게 이상하다.
## 화면에서 "오늘은 수달이 많네"로 보이는 값이지 숨은 수치가 아니다.
##
## ⚠️ 이 단계는 원정 중에 다시 돌지 않는다. **날씨가 바뀌어도 개체는 늘지도 줄지도 않는다** —
##    바뀌는 것은 지금 나와 있는가(2단계)뿐이다.
func spawn(target_species: Array, player_position: Vector2) -> void:
	# 감지 반경 안에서 시작하면 "첫 유도까지 시간"이 항상 0에 가깝게 나와 지표가 죽는다.
	var min_distance := _promotion_px
	var mix := _terrain_mix()
	for species in target_species:
		for i in roster_count(species, mix, region, _tuning.animal_count, _rng):
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


## 이 필드에서 이 종이 몇 마리인가. 서식지가 넓을수록 많고, 0 도 정상이다.
## region 은 그 지역의 생태(`regions.json` 의 ecology)다.
## **같은 종이라도 지역마다 마릿수가 다르다** — 뒷산에 흔한 청설모가 다른 곳에선 드물 수 있다.
## 지역에 적히지 않은 종은 그 지역에 **살지 않는다** (0 마리).
static func roster_count(species: Dictionary, terrain_mix: Dictionary, region: Dictionary,
		base: int, rng: RandomNumberGenerator) -> int:
	var ecology: Dictionary = region.get("ecology", {})
	var abundance := 1.0
	if not ecology.is_empty():
		if not ecology.has(species.get("id", "")):
			return 0
		abundance = float(ecology[species["id"]])
	var total := 0.0
	var home := 0.0
	for name in terrain_mix:
		var tiles := float(terrain_mix[name])
		total += tiles
		if String(name) in species.get("habitat", []):
			home += tiles
	var share: float = home / maxf(total, 1.0)
	# 서식지가 하나도 없어도 아주 없지는 않다 — 지나가는 개체가 있을 수 있다.
	# 다만 기대값이 1 아래로 떨어지면 **0 마리가 자주 나온다.** 그것이 의도다.
	# 지역 생태 × 이 필드의 서식지 비율.
	#
	# ★ 처음엔 "지나가는 개체"를 위해 하한(0.15)을 뒀는데, 그러면 **물가가 없는
	#   뒷산에도 수달이 두 마리씩** 나왔다. 서식지가 없으면 기대값도 0 이어야 한다.
	#   0.6 제곱은 좁은 서식지에도 기회를 조금 남기려는 것이다 —
	#   개울 한 줄기뿐인 뒷산에서 수달은 **가끔** 보여야지 늘 있으면 안 된다.
	var expected: float = abundance * float(base) * pow(share, 0.6)
	var count := int(floor(expected))
	if rng.randf() < expected - floor(expected):
		count += 1
	# 흔들림은 기대값이 1 을 넘을 때만. 0.1 짜리에 +1 을 더하면 없던 개체가 생긴다.
	if expected >= 1.0:
		count += rng.randi_range(-1, 1)
	return maxi(count, 0)


func _terrain_mix() -> Dictionary:
	var mix := {}
	if _terrain == null:
		return mix
	for y in _terrain.size.y:
		for x in _terrain.size.x:
			var name := _terrain.at_tile(Vector2i(x, y))
			mix[name] = int(mix.get(name, 0)) + 1
	return mix


## 이번 원정의 개체 목록. "오늘은 수달이 많네"가 여기서 보인다.
func roster() -> Dictionary:
	var out := {}
	for animal in animals:
		if animal.invited:
			continue
		var name := animal.display_name()
		out[name] = int(out.get(name, 0)) + 1
	return out


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
func apply_daypart(schema: TagSchema, daypart: String, axes := {}) -> Array:
	var changed: Array = []
	for animal in animals:
		if animal.invited:
			continue
		var chance := schema.presence_chance(animal.species, daypart, axes)
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
