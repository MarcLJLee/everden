## 집 — 마당을 짓는다. (BRIEF §2.7 · home/home.json)
##
## 640×360 한 화면. 마당을 울타리가 두르고 **집이 위쪽 담장을 대신한다.**
## 집 문에서 대문까지 흙길이 곧게 나 있고 **대문은 열려 있다** —
## 닫힌 문은 "못 나간다"로 읽힌다. 나가는 곳이 어디인지가 화면에 보여야 한다.
class_name HomeYard
extends RefCounted

const ART_ROOT := "res://sprites/extracted/"
const DATA_PATH := "res://sprites/extracted/home/home.json"
const DIRT := "res://sprites/extracted/terrain/extra/dirt.png"

var data := {}
## 마당 안쪽(동물이 돌아다닐 수 있는 곳). 픽셀.
var yard := Rect2()
## 대문 한가운데. 여기로 나간다.
var gate := Vector2.ZERO
## 대문이 뚫려 있는 폭(픽셀). 울타리는 이 구간에서만 지나갈 수 있다.
var gate_width := 32.0
var door := Vector2.ZERO


func load_data() -> bool:
	if not FileAccess.file_exists(DATA_PATH):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	data = parsed
	return true


## 바닥 → 흙길 → 울타리 → 집 순서로 얹는다. 전부 parent 의 자식이 된다.
func build(parent: Node2D, screen: Vector2i, tile: int) -> void:
	var house_size := _size(data.get("house", {}).get("size", [96, 80]))
	var door_x := float(data.get("house", {}).get("door_x", 48))

	var fence_h := _texture(String(data.get("fence", {}).get("h", "")))
	var fence_v := _texture(String(data.get("fence", {}).get("v", "")))
	var fence_gate := _texture(String(data.get("fence", {}).get("gate", "")))
	var post := fence_h.get_width() if fence_h != null else tile

	var house_at := Vector2(round((screen.x - house_size.x) * 0.5), 8.0)
	door = Vector2(house_at.x + door_x, house_at.y + house_size.y)
	gate = Vector2(door.x, screen.y - 26.0)

	# 마당 안쪽 — 집 아래부터 대문 줄까지
	yard = Rect2(post, door.y + 4, screen.x - post * 2, gate.y - door.y - 8)

	_path(parent, screen, tile)
	_fence(parent, screen, house_at, house_size, fence_h, fence_v, fence_gate, post)
	_house(parent, house_at)


## 흙길 — 문에서 대문까지 곧게. 길이 있으면 어디로 나가는지 묻지 않아도 안다.
func _path(parent: Node2D, screen: Vector2i, tile: int) -> void:
	if not ResourceLoader.exists(DIRT):
		return
	var dirt: Texture2D = load(DIRT)
	var columns := 2
	var left := door.x - columns * tile * 0.5
	var y := door.y - tile
	while y < screen.y:
		for i in columns:
			var patch := Sprite2D.new()
			patch.texture = dirt
			patch.centered = false
			patch.position = Vector2(left + i * tile, y)
			parent.add_child(patch)
		y += tile


func _fence(parent: Node2D, screen: Vector2i, house_at: Vector2, house_size: Vector2,
		fence_h: Texture2D, fence_v: Texture2D, fence_gate: Texture2D, post: int) -> void:
	var bottom := screen.y - 30
	# 위 — 집이 담장을 대신하므로 집 좌우만 두른다
	var x := 0
	while x < screen.x:
		var covered: bool = x + post > house_at.x and x < house_at.x + house_size.x
		if not covered:
			_put(parent, fence_h, Vector2(x, house_at.y + house_size.y - 22))
		x += post
	# 아래 — 가운데를 비우고 대문을 놓는다. **대문은 열려 있다.**
	var gate_half := (fence_gate.get_width() if fence_gate != null else 32) * 0.5
	x = 0
	while x < screen.x:
		if absf(x + post * 0.5 - gate.x) > gate_half + 2:
			_put(parent, fence_h, Vector2(x, bottom))
		x += post
	_put(parent, fence_gate, Vector2(gate.x - gate_half, bottom - 2))
	gate_width = gate_half * 2.0
	# 옆
	var y := int(house_at.y + house_size.y)
	while y < bottom:
		_put(parent, fence_v, Vector2(0, y))
		_put(parent, fence_v, Vector2(screen.x - post, y))
		y += post


func _house(parent: Node2D, at: Vector2) -> void:
	_put(parent, _texture(String(data.get("house", {}).get("file", ""))), at)


func _put(parent: Node2D, texture: Texture2D, at: Vector2) -> void:
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = at.round()
	parent.add_child(sprite)


func _texture(relative: String) -> Texture2D:
	var path := ART_ROOT + relative
	return load(path) if not relative.is_empty() and ResourceLoader.exists(path) else null


static func _size(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


## 울타리는 막는다. 대문 구간에서만 아래로 나갈 수 있다 —
## 사각형으로 자르면 아래쪽 울타리를 아무 데서나 통과한다.
func confine_walker(at: Vector2, exit_y: float) -> Vector2:
	var inside := at.clamp(yard.position, yard.end)
	if absf(at.x - gate.x) <= gate_width * 0.5 - 4.0:
		# 대문 앞이면 아래로 더 갈 수 있다. 좌우는 대문 폭 안으로 모은다.
		inside.x = clampf(at.x, gate.x - gate_width * 0.5 + 4.0, gate.x + gate_width * 0.5 - 4.0)
		inside.y = clampf(at.y, yard.position.y, exit_y)
	return inside


## 동물은 마당을 못 나간다. 대문은 플레이어만 쓴다.
func confine_resident(at: Vector2) -> Vector2:
	return at.clamp(yard.position, yard.end)
