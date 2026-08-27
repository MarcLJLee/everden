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
			placed.append(_make(parent, name, texture, Vector2(x + 0.5, y + 0.95) * tuning.tile_size))
	return placed


static func _sway_spec(name: String) -> Dictionary:
	if _sway_table.is_empty():
		_sway_table = {"props": {}}
		if FileAccess.file_exists(SWAY_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(SWAY_PATH))
			if parsed is Dictionary:
				_sway_table = parsed
	return _sway_table.get("props", {}).get(name, {})


static func _make(parent: Node2D, name: String, texture: Texture2D, position: Vector2) -> Dictionary:
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
	# 위상을 자리에서 뽑으므로 **돌풍이 들판을 가로질러 지나간다.** 전부 한 박자로
	# 흔들리면 바람이 아니라 화면이 떠는 것으로 보인다 (눈에서 같은 실수를 했다).
	var spec := _sway_spec(name)
	return {
		"name": name, "sprite": sprite, "position": root.position,
		"lean": int(spec.get("lean", 0)), "hz": float(spec.get("hz", 0.0)),
		"phase": position.x * 0.035 + position.y * 0.014,
		"at": 0,
	}


## 바람이 세기와 빈도를 **둘 다** 정한다. 무풍이면 아무것도 안 움직인다.
## view 안에 있는 것만 갈아끼운다 — 안 보이는 데서 흔들 이유가 없다.
static func sway(placed: Array, elapsed: float, wind: float, view: Rect2) -> void:
	var room := view.grow(48.0)
	var gust: float = clampf(wind, 0.0, 1.0)
	for entry in placed:
		if int(entry["lean"]) == 0:
			continue
		if not room.has_point(entry["position"]):
			continue
		var most := float(entry["lean"])
		# ★ 센 바람에서는 **기운 채로 떤다.** 제자리에서 좌우로 흔들리는 것은 산들바람이다 —
		#   바람이 세지면 흔들림의 한가운데가 바람 쪽으로 밀려간다 (사용자 지적).
		#   기우는 쪽은 구름·비가 흐르는 쪽과 같다(+x). 따로 놀면 화면이 어긋나 보인다.
		var bend: float = smoothstep(0.42, 1.0, gust)
		var bias: float = most * bend
		# 다 누운 뒤에는 크게 흔들릴 자리가 없다 — 잔떨림만 남는다.
		# 무풍이면 정말로 안 움직인다. 바람이 없는데 풀이 흔들리면 그게 더 이상하다.
		var swing: float = most * (0.18 + 0.82 * gust) * (1.0 - 0.6 * bend)
		# 빈도 — 바람이 세면 빨라진다
		var speed: float = float(entry["hz"]) * (0.45 + 1.25 * gust)
		var wave: float = sin(TAU * elapsed * speed + float(entry["phase"]))
		var lean := int(round(bias + swing * wave))
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
