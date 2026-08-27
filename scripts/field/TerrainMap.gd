## 필드 지형. habitat 태그와 같은 어휘를 쓴다 — 초원 / 물가 / 숲 / 바위.
##
## 지형은 두 가지를 한다:
##   1. 감각 반경을 깎는다 (tags.json 의 sense_profile.terrain_scale) — 숲에 있으면 눈에 안 띈다
##   2. 동물이 어디서 시작하는지를 정한다 (species.habitat)
##
## LDtk 로 손으로 그리기 전까지의 자리채움이다. 덩어리 몇 개를 찍는 것으로 충분하다.
class_name TerrainMap
extends RefCounted

const BASE := "초원"

var size := Vector2i(64, 48)
var tile_size := 16

var _tiles := PackedStringArray()
## 못 밟는 지형 이름들. 이것들은 얇게 찍는다 — 두꺼우면 안에 선 동물을 부를 수 없다.
var blocked_terrains: Array = []

func generate(map_size: Vector2i, tile_px: int, patches: Dictionary, rng: RandomNumberGenerator,
		base := BASE, streams := {}) -> void:
	size = map_size
	tile_size = tile_px
	_tiles.resize(size.x * size.y)
	_tiles.fill(base)
	for terrain in patches:
		# 못 밟는 지형은 얇게. 통행 규칙은 tags.json 이 갖고 있지만
		# 여기서는 이름만으로 판단하지 않도록 호출자가 넘긴 목록을 쓴다.
		var thin: bool = String(terrain) in blocked_terrains
		for i in int(patches[terrain]):
			_blob(String(terrain), rng, thin)
	for terrain in streams:
		var shape: Dictionary = streams[terrain]
		for i in int(shape.get("count", 1)):
			_stream(String(terrain), rng, int(shape.get("width", 2)))


## 물줄기 하나. 한쪽 끝에서 반대쪽 끝까지 **이어져서** 지나간다.
##
## ★ **냇가는 덩어리가 아니라 줄기다.** 웅덩이 아홉 개로 찍었더니 물이 3% 뿐이었고
##   그마저 흩어져서 "냇가에 물이 없다" 가 됐다 (사용자 지적).
##   줄기는 이어져 있어서 **찾아가면 반드시 만난다** — 그게 지역을 고르는 이유가 된다.
## ★ 얇게 찍는 이유(막힌 지형 한가운데 선 동물에게 다가갈 수 없다)는 줄기에서 저절로
##   해결된다 — 두세 타일 폭이라 **어느 물 타일에서도 뭍이 한 발짝**이다.
func _stream(terrain: String, rng: RandomNumberGenerator, width: int) -> void:
	# 가로로 흐를지 세로로 흐를지부터 정한다. 늘 같은 방향이면 지도가 한 장으로 보인다.
	var sideways := rng.randf() < 0.5
	var along: int = size.x if sideways else size.y
	var across: int = size.y if sideways else size.x
	var at := float(rng.randi_range(int(across * 0.25), int(across * 0.75)))
	var drift := rng.randf_range(-0.35, 0.35)
	var wide := float(width)
	for step in along:
		# 이리저리 굽는다. 곧게 흐르면 물이 아니라 도랑으로 보인다.
		drift = clampf(drift + rng.randf_range(-0.12, 0.12), -0.5, 0.5)
		at = clampf(at + drift, 1.0, float(across - 2))
		# ★ 폭도 흔들린다 — 좁아졌다 넓어지는 게 실제 냇가고,
		#   **넓기만 하면 한가운데 선 동물에게 다가갈 수 없다.**
		#   폭 4로 곧게 뻗었더니 물 타일의 절반이 뭍에서 2타일 넘게 떨어졌다.
		wide = clampf(wide + rng.randf_range(-0.35, 0.35), 2.0, float(width))
		var here := int(round(at))
		var span := int(round(wide))
		var half := int(span / 2.0)
		for side in range(-half, span - half):
			var tile := Vector2i(step, here + side) if sideways \
				else Vector2i(here + side, step)
			if _inside(tile):
				_tiles[tile.y * size.x + tile.x] = terrain


## 원 하나를 찍는다. 가장자리를 조금 흐트러뜨려 네모로 안 보이게만 한다.
##
## ★ 막힌 지형(물가·바위)은 **얇게** 찍는다. 두껍게 찍으면 한가운데 선 동물이
##   교감 반경(1.5타일) 안으로 다가갈 수 없어 초대가 아예 불가능해진다 —
##   측정해보니 두꺼운 덩어리에서는 물가 타일의 60%가 그랬다.
##   `물가` 는 물가(가장자리)이지 호수가 아니다.
func _blob(terrain: String, rng: RandomNumberGenerator, thin := false) -> void:
	var center := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
	var radius := rng.randf_range(1.6, 2.6) if thin else rng.randf_range(3.0, 7.0)
	var span := int(ceil(radius)) + 1
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var tile := center + Vector2i(dx, dy)
			if not _inside(tile):
				continue
			if Vector2(dx, dy).length() <= radius * rng.randf_range(0.85, 1.05):
				_tiles[tile.y * size.x + tile.x] = terrain


## 화면 전체를 한 지형으로 채운다. 타이틀 배경이 쓴다 —
## 거기서는 "이 종이 어디 사는가" 한 가지만 말해야 해서 지형이 섞이면 안 된다.
func fill(terrain: String) -> void:
	_tiles.fill(terrain)


## 타일 하나를 바꾼다. 테스트가 판을 깔 때 쓴다.
func set_tile(tile: Vector2i, terrain: String) -> void:
	if _inside(tile):
		_tiles[tile.y * size.x + tile.x] = terrain


func at_tile(tile: Vector2i) -> String:
	if not _inside(tile):
		return BASE
	return _tiles[tile.y * size.x + tile.x]


## 이 자리에 설 수 있는가.
##
## 기본 지형(terrain_walkable=true)은 **누구나** 지나간다 — 청설모가 숲에만 갇히면
## 마당만 한 조각에서 못 나온다. habitat 은 사는 곳이지 갈 수 있는 곳의 전부가 아니다.
## 막힌 지형(물가·바위)은 **그 지형이 habitat 인 동물만** 들어간다 —
## 수영 안 하는 개가 호수를 가로지르면 안 되고, 수달은 물가에 살아야 한다.
## 플레이어는 habitat 이 없으므로 막힌 지형에 못 들어간다.
func can_stand(position: Vector2, schema: TagSchema, habitat: Array) -> bool:
	var name := at_world(position)
	if schema == null or schema.walkable(name):
		return true
	return name in habitat


## 막힌 데로 들어가면 **미끄러진다.** 그냥 되돌리면 물가에 비스듬히 붙었을 때
## 아예 안 움직여서 갇힌 것처럼 느껴진다.
func slide(from: Vector2, to: Vector2, schema: TagSchema, habitat: Array = []) -> Vector2:
	if can_stand(to, schema, habitat):
		return to
	# ★ **못 서는 자리에 있으면 나가는 것은 언제나 된다.** (원칙 2)
	#   스폰 자리가 물이나 바위면 어느 쪽으로도 못 움직여 그대로 갇혔다 (사용자 지적).
	#   들어가는 것만 막으면 될 일이지, **나가는 것까지 막을 이유가 없다.**
	#   이 한 줄이 "어쩌다 갇혔는가" 를 전부 덮는다 — 스폰이든 지형이 바뀌었든.
	if not can_stand(from, schema, habitat):
		return to
	var along_x := Vector2(to.x, from.y)
	if can_stand(along_x, schema, habitat):
		return along_x
	var along_y := Vector2(from.x, to.y)
	if can_stand(along_y, schema, habitat):
		return along_y
	return from


func at_world(position: Vector2) -> String:
	return at_tile(Vector2i(floori(position.x / tile_size), floori(position.y / tile_size)))


## 여기서 가장 가까운, 설 수 있는 자리. 스폰 자리가 막혔을 때 쓴다.
## ⚠️ 못 찾으면 원래 자리를 돌려준다 — 그래도 `slide` 가 나가는 길을 열어 둔다.
func nearest_standing(around: Vector2, schema: TagSchema, habitat: Array = []) -> Vector2:
	if can_stand(around, schema, habitat):
		return around
	for ring in range(1, maxi(size.x, size.y)):
		for step in ring * 8:
			var way := Vector2.RIGHT.rotated(TAU * float(step) / float(ring * 8))
			var probe := around + way * float(ring) * float(tile_size)
			if probe.x < 0.0 or probe.y < 0.0:
				continue
			if probe.x >= float(size.x * tile_size) or probe.y >= float(size.y * tile_size):
				continue
			if can_stand(probe, schema, habitat):
				return probe
	return around


## 이 종이 살 만한 지형 위의 점 하나. 못 찾으면 빈 벡터를 돌려준다.
func random_point_in(habitats: Array, rng: RandomNumberGenerator) -> Vector2:
	if habitats.is_empty():
		return Vector2.ZERO
	for attempt in 200:
		var tile := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
		if at_tile(tile) in habitats:
			return (Vector2(tile) + Vector2(0.5, 0.9)) * tile_size
	return Vector2.ZERO


func _inside(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y
