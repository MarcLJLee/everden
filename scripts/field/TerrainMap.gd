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

func generate(map_size: Vector2i, tile_px: int, patches: Dictionary, rng: RandomNumberGenerator) -> void:
	size = map_size
	tile_size = tile_px
	_tiles.resize(size.x * size.y)
	_tiles.fill(BASE)
	for terrain in patches:
		for i in int(patches[terrain]):
			_blob(String(terrain), rng)


## 원 하나를 찍는다. 가장자리를 조금 흐트러뜨려 네모로 안 보이게만 한다.
func _blob(terrain: String, rng: RandomNumberGenerator) -> void:
	var center := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
	var radius := rng.randf_range(3.0, 7.0)
	var span := int(ceil(radius)) + 1
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var tile := center + Vector2i(dx, dy)
			if not _inside(tile):
				continue
			if Vector2(dx, dy).length() <= radius * rng.randf_range(0.85, 1.05):
				_tiles[tile.y * size.x + tile.x] = terrain


func at_tile(tile: Vector2i) -> String:
	if not _inside(tile):
		return BASE
	return _tiles[tile.y * size.x + tile.x]


func at_world(position: Vector2) -> String:
	return at_tile(Vector2i(floori(position.x / tile_size), floori(position.y / tile_size)))


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
