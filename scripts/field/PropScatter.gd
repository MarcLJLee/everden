## 지형 위에 프롭을 뿌린다. (HANDOFF §2-3)
##
## 어느 프롭이 어느 지형에 어울리는지는 `palettes.json` 의 `prop_terrain` 에 있다 —
## 코드가 지형 이름으로 분기하지 않는다.
##
## 앵커는 **바닥 중앙**이고 루트 노드 하나가 Y-sort 대상이다. 액터와 같은 규칙이다.
class_name PropScatter
extends RefCounted

## 타일보다 높은 것만 발밑 그림자를 받는다 (BRIEF §4.4).
## 땅에 깔린 것(자갈·진흙)에 그림자를 넣으면 오히려 떠 보인다.
const STANDING_HEIGHT := 16
const SWAY_PATH := "res://data/prop_sway.json"

## 기운 판을 종류마다 한 번만 굽고 돌려 쓴다. "이름:기울기" 로 찾는다.
static var _sway_cache := {}
static var _sway_table := {}
## 흔들림의 위상. **시간에 곱하지 않고 더해서 쌓는다** — 아래 sway() 의 경고 참조.
static var _clock := 0.0


## parent 아래에 프롭을 만들고, 밤낮으로 텍스처를 갈아끼울 수 있게 목록을 돌려준다.
static func scatter(parent: Node2D, terrain: TerrainMap, tuning: FieldTuning,
		rng: RandomNumberGenerator) -> Array:
	var placed: Array = []
	for y in tuning.map_size.y:
		for x in tuning.map_size.x:
			if rng.randf() >= tuning.prop_density:
				continue
			var names := SpriteLibrary.props_for_terrain(terrain.at_tile(Vector2i(x, y)))
			if names.is_empty():
				continue
			var name := String(names[rng.randi_range(0, names.size() - 1)])
			var texture := SpriteLibrary.prop_texture(name)
			if texture == null:
				continue
			placed.append(_make(parent, name, texture,
				Vector2(x + 0.5, y + 0.95) * tuning.tile_size, rng))
	return placed


static func _sway_spec(name: String) -> Dictionary:
	if _sway_table.is_empty():
		_sway_table = {"props": {}}
		if FileAccess.file_exists(SWAY_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(SWAY_PATH))
			if parsed is Dictionary:
				_sway_table = parsed
	return _sway_table.get("props", {}).get(name, {})


static func _make(parent: Node2D, name: String, texture: Texture2D, position: Vector2,
		rng: RandomNumberGenerator) -> Dictionary:
	var root := Node2D.new()
	root.position = position.round()
	parent.add_child(root)

	var size := texture.get_size()
	if size.y > STANDING_HEIGHT:
		var shadow := Sprite2D.new()
		shadow.centered = false
		# 나무 줄기가 캔버스 폭을 다 쓰지는 않는다. 밑동만큼만 잡는다.
		shadow.texture = PlaceholderArt.shadow_texture(int(size.x * 0.6))
		shadow.position = -shadow.texture.get_size() * 0.5
		root.add_child(shadow)

	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = texture
	# 바닥 중앙이 앵커 — 액터와 같다
	sprite.position = Vector2(-int(size.x / 2.0), -size.y)
	root.add_child(sprite)
	# 흔들릴 것만 흔든다 — 바위와 통나무가 흔들리면 그게 더 이상하다.
	#
	# ★ **한 박자로 흔들리면 바람이 아니라 화면이 떠는 것으로 보인다** (사용자 지적 —
	#   눈에서 똑같은 실수를 했다). 어긋나게 하는 장치가 셋이다:
	#     ① 자리에서 뽑는 위상 — 돌풍이 들판을 **가로질러** 지나간다
	#     ② 포기마다의 위상 흔들기 — 옆 포기와 딱 붙어 놀지 않는다
	#     ③ 포기마다의 빈도 흔들기 — 시간이 갈수록 서로 벌어진다. 이게 제일 크다
	#   ⚠️ 빈도를 포기마다 달리해도 **한 포기 안에서는 상수**라 위상이 튀지 않는다.
	var spec := _sway_spec(name)
	var beat := float(spec.get("hz", 0.0))
	return {
		"name": name, "sprite": sprite, "position": root.position,
		"lean": int(spec.get("lean", 0)), "wave": 0.0,
		"hz": beat * rng.randf_range(0.72, 1.34),
		"phase": position.x * 0.055 + position.y * 0.031 + rng.randf_range(-1.4, 1.4),
		"at": 0,
	}


## 바람이 세기와 빈도를 **둘 다** 정한다. 무풍이면 아무것도 안 움직인다.
## view 안에 있는 것만 갈아끼운다 — 안 보이는 데서 흔들 이유가 없다.
##
## ⚠️ 위상은 **더해서 쌓는다.** `sin(경과시간 × 속도)` 로 쓰면 바람이 변하는 동안
##    위상이 `경과시간 × 속도변화` 만큼 통째로 건너뛰어서, **날씨가 바뀌는 순간
##    나무가 크게 휘청인다** (사용자 지적 — 날씨 겹에서 똑같은 실수를 했다).
##    빈도가 겹마다 다르지 않고 hz 배수뿐이라, 시계 하나만 쌓으면 전부 해결된다.
##
## ★ 눈금은 **실제로 부는 바람**에 맞춘다. 재보니 0.1~0.5 사이에서 살고
##   0.6 이상은 100시간에 0.8% 뿐이다(폭우 하나). 0~1 을 눈금으로 쓰면
##   기울어지는 모습을 평생 못 본다 (사용자 지적).
static func sway(placed: Array, delta: float, wind: float, view: Rect2) -> void:
	var room := view.grow(48.0)
	# 0.55 를 "센 바람" 으로 놓는다 — 흐림 0.46 이 눈에 띄고 폭우 0.66 이 다 눕는다
	var force: float = clampf(wind / 0.55, 0.0, 1.2)
	_clock += delta * (0.45 + 1.25 * force)
	for entry in placed:
		if int(entry["lean"]) == 0:
			continue
		if not room.has_point(entry["position"]):
			continue
		var most := float(entry["lean"])
		var bend: float = smoothstep(0.34, 0.62, wind)
		# ★ 센 바람에서는 **기운 채로 떤다.** 제자리에서 좌우로 흔들리는 것은 산들바람이다 —
		#   바람이 세지면 흔들림의 한가운데가 바람 쪽으로 밀려간다 (사용자 지적).
		#   기우는 쪽은 구름·비가 흐르는 쪽과 같다(+x). 따로 놀면 화면이 어긋나 보인다.
		var bias: float = most * bend
		# 다 누운 뒤에는 크게 흔들릴 자리가 없다 — 잔떨림만 남는다.
		# 무풍이면 정말로 안 움직인다. 바람이 없는데 풀이 흔들리면 그게 더 이상하다.
		var swing: float = most * (0.12 + 0.88 * force) * (1.0 - 0.6 * bend)
		# 빈도는 시계에 이미 들어가 있다. 여기서는 프롭마다의 배수만 곱한다.
		var wave: float = sin(TAU * _clock * float(entry["hz"]) + float(entry["phase"]))
		entry["wave"] = bias + swing * wave
		var lean := int(round(float(entry["wave"])))
		if lean == int(entry["at"]):
			continue
		entry["at"] = lean
		entry["sprite"].texture = _swayed(String(entry["name"]), lean)


static func _swayed(name: String, lean: int) -> Texture2D:
	var key := "%s:%d" % [name, lean]
	if _sway_cache.has(key):
		return _sway_cache[key]
	var source := SpriteLibrary.prop_texture(name)
	if source == null:
		return null
	var made: Texture2D = source if lean == 0 else PlaceholderArt.swayed_texture(source, lean)
	_sway_cache[key] = made
	return made


## 팔레트가 바뀌면 텍스처만 갈아끼운다. 노드는 그대로 둔다.
static func refresh_textures(placed: Array) -> void:
	# ⚠️ 기울인 판도 같이 버려야 한다. 안 그러면 밤이 됐는데 흔들리는 풀만 낮 색으로 남는다.
	_sway_cache.clear()
	for entry in placed:
		var texture := SpriteLibrary.prop_texture(String(entry["name"]))
		if texture != null:
			entry["sprite"].texture = texture
			entry["at"] = 0
