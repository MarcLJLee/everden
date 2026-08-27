## 바닥 타일. 지형 이름이 곧 파일명이라 분기가 없다. (HANDOFF §2-1, BRIEF §6.2)
##
##   sprites/extracted/terrain/<지형 이름>.png  — 가로 스트립, 프레임 폭 16
##
## 변형 개수는 지형마다 다르고 이미지 폭에서 그대로 나온다(초원 6 · 숲 3 · 물가 3 · 바위 1).
## 변형은 **타일 좌표 해시**로 고른다 — 규칙적으로 고르면 세로 줄무늬가 생긴다.
class_name Ground
extends Node2D

const TERRAIN_ROOT := "res://sprites/extracted/terrain"
const SOURCE_TILE := 16
## 물줄기 한가운데에 까는 그림. 물가 타일이 사방으로 이어질 때만 쓴다.
const DEEP := ["extra/water_0", "extra/water_1"]
## 물과 뭍이 만나는 자리. 키는 **뭍이 있는 쪽**이다.
const SHORE := {
	"N": "extra/shore_N", "S": "extra/shore_S", "E": "extra/shore_E", "W": "extra/shore_W",
	"NE": "extra/shore_NE", "NW": "extra/shore_NW",
	"SE": "extra/shore_SE", "SW": "extra/shore_SW",
}
## 이 지형은 **가장자리일 때와 한가운데일 때 다르게 그린다** (아래 _water_piece 참조).
const WET := "물가"

## 타일 그림이 없을 때만 쓰는 자리채움
const FALLBACK_COLOR := {
	"초원": Color(0.35, 0.46, 0.30),
	"숲": Color(0.20, 0.33, 0.22),
	"물가": Color(0.30, 0.45, 0.55),
	"바위": Color(0.44, 0.43, 0.40),
}

var _tuning: FieldTuning = null
var _terrain: TerrainMap = null
var _sheets := {}      ## 지형 이름 -> Texture2D
var _variants := {}    ## 지형 이름 -> 프레임 수

func setup(tuning: FieldTuning, terrain: TerrainMap) -> void:
	_tuning = tuning
	_terrain = terrain
	_load_sheets()
	queue_redraw()


## 팔레트가 바뀌면(밤낮) 텍스처를 갈아끼우고 다시 그린다.
func refresh_textures() -> void:
	_load_sheets()
	queue_redraw()


func _load_sheets() -> void:
	_sheets.clear()
	_variants.clear()
	var wanted: Array = FALLBACK_COLOR.keys()
	wanted.append_array(DEEP)
	wanted.append_array(SHORE.values())
	for name in wanted:
		var path := "%s/%s.png" % [TERRAIN_ROOT, name]
		if not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = DayPalette.texture_for(path)
		_sheets[name] = texture
		_variants[name] = maxi(1, int(texture.get_width() / float(SOURCE_TILE)))


func _draw() -> void:
	if _tuning == null or _terrain == null:
		return
	var tile := _tuning.tile_size
	for y in _tuning.map_size.y:
		for x in _tuning.map_size.x:
			var name := _terrain.at_tile(Vector2i(x, y))
			if name == WET:
				name = _water_piece(x, y)
			var destination := Rect2(x * tile, y * tile, tile, tile)
			if not _sheets.has(name):
				draw_rect(destination, FALLBACK_COLOR.get(name, Color(0.3, 0.4, 0.3)))
				continue
			var variant := _variant_for(x, y, _variants[name])
			draw_texture_rect_region(_sheets[name], destination,
				Rect2(variant * SOURCE_TILE, 0, SOURCE_TILE, SOURCE_TILE))
	var edge := Rect2(0, 0, _tuning.map_size.x * tile, _tuning.map_size.y * tile)
	draw_rect(edge, Color(0.16, 0.20, 0.15), false, 2.0)


## ★ **축척이 바뀌면 표현도 바뀐다** — 지도에서 배운 것이 필드 안에서도 그대로다.
##   `물가` 는 **젖은 흙** 타일이라 얇은 가장자리일 때는 물가로 읽히지만,
##   물줄기 폭이 넷이 되니 그냥 **흙길**로 보였다 (사용자 지적).
##
## 그래서 같은 타일을 자리에 따라 다르게 그린다 — 지형은 하나 그대로다:
##   · 사방이 물이면 **물**(extra/water_*)
##   · 뭍과 만나면 그쪽 **물가**(extra/shore_*)
##   · 맞는 조각이 없으면 원래 젖은 흙
##
## ⚠️ 지형 이름을 늘리지 않는다. 늘리면 통행·서식지·생태 표가 전부 따라 늘어난다 —
##    이건 **그리는 문제**지 세계의 문제가 아니다.
func _water_piece(x: int, y: int) -> String:
	var north := _terrain.at_tile(Vector2i(x, y - 1)) == WET
	var south := _terrain.at_tile(Vector2i(x, y + 1)) == WET
	var east := _terrain.at_tile(Vector2i(x + 1, y)) == WET
	var west := _terrain.at_tile(Vector2i(x - 1, y)) == WET
	if north and south and east and west:
		return String(DEEP[_variant_for(x, y, DEEP.size())])
	var side := ""
	if not north:
		side += "N"
	elif not south:
		side += "S"
	if not east:
		side += "E"
	elif not west:
		side += "W"
	if SHORE.has(side) and _sheets.has(SHORE[side]):
		return String(SHORE[side])
	return WET


## 좌표 해시. x·y 를 서로 다른 큰 소수로 섞어야 줄무늬가 안 생긴다.
static func _variant_for(x: int, y: int, count: int) -> int:
	if count <= 1:
		return 0
	var h := (x * 73856093) ^ (y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16)) % count
