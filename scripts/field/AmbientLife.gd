## 앰비언트 생물 — **잡을 수 없는 것들.** (BRIEF §3.10)
##
## > 보이는 것이 전부 수집 대상이면 숲이 아니라 **쇼핑 목록**이다.
##
## 도감에 없고, 자리를 안 먹고, 데이터도 없고, 상호작용도 없다.
## 지형 태그 하나만 들고 있다. 종당 도트 한두 장이라
## 수집종(종당 16장) 대비 10분의 1 값으로 생태를 열 배로 만든다.
##
## ★ **무엇이 어디 사는지는 설계 세션이 정한다** (`ambient/ambient.json`).
##   어떻게 움직이는지만 `data/ambient_motion.json` 이 정한다. 둘 다 표라서
##   생물이 늘어도 코드는 안 고친다 — 이름으로 분기하지 않는다.
##
## ★ 층이 셋이다. **새는 그리지 않고 그림자만 그린다** — 하늘은 화면 밖이다.
##   · 공중(나비·벌·잠자리) — Y-sort 밖, 지면보다 10px 위. 캐릭터 위로 지나간다
##   · 수면(물고기) · 지면(개미·새그림자) — Y-sort 대상이라 캐릭터에 가린다
class_name AmbientLife
extends Node2D

const SPEC_PATH := "res://sprites/extracted/ambient/ambient.json"
const MOTION_PATH := "res://data/ambient_motion.json"
## 공중 생물이 지면보다 얼마나 위에 있는가. (ambient.json 의 layers)
const AIR_LIFT := 10.0
## 화면 밖 이만큼까지는 살려 둔다. 가장자리에서 툭 생기면 그게 보인다.
const MARGIN := 40.0

var _lives: Array = []
var _terrain: TerrainMap = null
var _rng: RandomNumberGenerator = null
var _view := Rect2()
var _ground_parent: Node2D = null


## ground_parent 는 Y-sort 가 켜진 노드다 — 지면·수면 생물이 캐릭터에 가리려면 거기 있어야 한다.
func setup(terrain: TerrainMap, rng: RandomNumberGenerator, ground_parent: Node2D,
		region := {}) -> void:
	_terrain = terrain
	_rng = rng
	_ground_parent = ground_parent
	var spec: Dictionary = _read_json(SPEC_PATH).get("creatures", {})
	var motion: Dictionary = _read_json(MOTION_PATH)
	var defaults: Dictionary = motion.get("defaults", {})
	var overrides: Dictionary = motion.get("creatures", {})
	# ★ **얼마나 사는지는 지역이 정한다** (regions.json 의 ambient · §3.10).
	#   수집종 ecology 와 같은 규칙이다 — 적히지 않은 생물은 그 지역에 없다.
	#   어디에 나타날지는 그 생물의 지형 태그가 따로 정한다. 뒷산에 나비가 많고
	#   도시에 없는 것은 여기서 갈린다.
	var ambient: Dictionary = region.get("ambient", {})
	for name in spec:
		var entry: Dictionary = spec[name]
		var abundance := 1.0
		if not ambient.is_empty():
			if not ambient.has(name):
				continue
			abundance = float(ambient[name])
		var texture: Texture2D = load("res://sprites/extracted/" + String(entry["file"]))
		if texture == null:
			continue
		var layer := String(entry.get("layer", "지면"))
		var rule: Dictionary = (defaults.get(layer, {}) as Dictionary).duplicate()
		for key in overrides.get(name, {}):
			rule[key] = overrides[name][key]
		var frame := Vector2i(int(entry.get("frame_w", texture.get_width())), texture.get_height())
		# 반올림이 아니라 소수점을 굴린다 — 0.4 마리는 "열에 넷은 있다" 는 뜻이다
		var many := float(rule.get("count", 3)) * abundance
		var count := int(floor(many))
		if _rng.randf() < many - floor(many):
			count += 1
		for i in count:
			_lives.append(_make(name, entry, rule, texture, frame, layer))


func _make(name: String, entry: Dictionary, rule: Dictionary, texture: Texture2D,
		frame: Vector2i, layer: String) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, Vector2(frame))
	sprite.modulate = Color(1, 1, 1, float(rule.get("alpha", 1.0)))
	sprite.visible = false
	# 공중은 Y-sort 밖이라 이 노드에, 지면·수면은 캐릭터와 같이 정렬돼야 하므로 저쪽에.
	if layer == "공중":
		add_child(sprite)
	else:
		_ground_parent.add_child(sprite)
	return {
		"name": name, "sprite": sprite, "layer": layer,
		"terrain": entry.get("terrain", []),
		"frames": int(entry.get("frames", 1)), "frame": frame,
		"motion": String(rule.get("motion", "crawl")),
		"speed": float(rule.get("speed", 10.0)),
		"fps": float(rule.get("fps", 5.0)),
		"pos": Vector2.ZERO, "velocity": Vector2.ZERO,
		"turn": 0.0, "clock": 0.0, "alive": false,
	}


## view 는 지금 화면이 덮는 월드 사각형이다.
func update(delta: float, view: Rect2) -> void:
	_view = view
	var room := view.grow(MARGIN)
	for life in _lives:
		life["clock"] += delta
		if not life["alive"]:
			_place(life, room)
			continue
		_move(life, delta)
		# 화면을 벗어났거나 살 수 없는 땅으로 나갔으면 다른 데서 다시 시작한다
		if not room.has_point(life["pos"]) or not _fits(life, life["pos"]):
			life["alive"] = false
			life["sprite"].visible = false
			continue
		_draw_life(life)


func _place(life: Dictionary, room: Rect2) -> void:
	# 글라이드는 **가장자리에서 들어온다** — 화면 한가운데서 생기면 나타나는 게 보인다
	var glide: bool = String(life["motion"]) == "glide"
	for attempt in 24:
		var spot := Vector2(
			_rng.randf_range(room.position.x, room.end.x),
			_rng.randf_range(room.position.y, room.end.y))
		if glide:
			spot.x = room.position.x if _rng.randf() < 0.5 else room.end.x
			spot.y = _rng.randf_range(room.position.y, room.end.y)
		if not _fits(life, spot):
			continue
		life["pos"] = spot
		life["alive"] = true
		life["turn"] = 0.0
		life["velocity"] = _new_velocity(life, spot, room)
		life["sprite"].visible = true
		_draw_life(life)
		return


## 그 생물이 살 수 있는 땅인가. **지형 태그 하나뿐이다** — 그 이상 들고 있지 않다.
func _fits(life: Dictionary, spot: Vector2) -> bool:
	if _terrain == null:
		return true
	return _terrain.at_world(spot) in life["terrain"]


func _new_velocity(life: Dictionary, spot: Vector2, room: Rect2) -> Vector2:
	var speed := float(life["speed"])
	match String(life["motion"]):
		"glide":
			# 들어온 쪽 반대로 곧게 지나간다
			var toward: float = 1.0 if spot.x <= room.get_center().x else -1.0
			return Vector2(toward, _rng.randf_range(-0.22, 0.22)).normalized() * speed
		"dart":
			return Vector2.ZERO
		_:
			return Vector2.from_angle(_rng.randf() * TAU) * speed


func _move(life: Dictionary, delta: float) -> void:
	var motion := String(life["motion"])
	life["turn"] -= delta
	match motion:
		"flutter":
			if life["turn"] <= 0.0:
				life["turn"] = _rng.randf_range(0.5, 1.3)
				life["velocity"] = Vector2.from_angle(_rng.randf() * TAU) * float(life["speed"])
		"crawl":
			if life["turn"] <= 0.0:
				life["turn"] = _rng.randf_range(2.5, 6.0)
				life["velocity"] = Vector2.from_angle(_rng.randf() * TAU) * float(life["speed"])
		"dart":
			# 대부분 멈춰 있다가 가끔 짧게 튄다. 튀는 동안만 지느러미가 움직인다.
			if life["turn"] <= 0.0:
				if life["velocity"] == Vector2.ZERO:
					life["turn"] = _rng.randf_range(0.18, 0.4)
					life["velocity"] = Vector2.from_angle(_rng.randf() * TAU) * float(life["speed"])
				else:
					life["turn"] = _rng.randf_range(0.8, 2.6)
					life["velocity"] = Vector2.ZERO
	var step: Vector2 = life["velocity"] * delta
	if motion == "flutter":
		# 갈지자 — 나비가 곧게 날면 나비가 아니다
		step.y += sin(float(life["clock"]) * 6.4) * 14.0 * delta
	var ahead: Vector2 = life["pos"] + step
	# 살 수 없는 땅에는 안 들어간다. 물고기가 뭍으로 나가면 그게 버그로 읽힌다.
	if _fits(life, ahead):
		life["pos"] = ahead
	else:
		life["velocity"] = -life["velocity"]
		life["turn"] = _rng.randf_range(0.4, 1.2)


func _draw_life(life: Dictionary) -> void:
	var sprite: Sprite2D = life["sprite"]
	var frames := int(life["frames"])
	if frames > 1:
		# 멈춰 있는 물고기는 프레임도 멈춘다
		var still: bool = String(life["motion"]) == "dart" and life["velocity"] == Vector2.ZERO
		var index: int = 0 if still else int(float(life["clock"]) * float(life["fps"])) % frames
		sprite.region_rect = Rect2(Vector2(float(index * life["frame"].x), 0.0),
			Vector2(life["frame"]))
	# 왼쪽으로 가면 뒤집는다. 앵커가 어긋나지 않게 폭만큼 되민다.
	var facing_left: bool = life["velocity"].x < -0.01
	sprite.flip_h = facing_left
	var lift := AIR_LIFT if String(life["layer"]) == "공중" else 0.0
	# ⚠️ 정수 픽셀. 반픽셀이면 도트가 흔들린다.
	sprite.position = Vector2(life["pos"].x - float(life["frame"].x) * 0.5,
		life["pos"].y - float(life["frame"].y) - lift).floor()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
