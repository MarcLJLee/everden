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
	for name in FALLBACK_COLOR:
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
			var destination := Rect2(x * tile, y * tile, tile, tile)
			if not _sheets.has(name):
				draw_rect(destination, FALLBACK_COLOR.get(name, Color(0.3, 0.4, 0.3)))
				continue
			var variant := _variant_for(x, y, _variants[name])
			draw_texture_rect_region(_sheets[name], destination,
				Rect2(variant * SOURCE_TILE, 0, SOURCE_TILE, SOURCE_TILE))
	var edge := Rect2(0, 0, _tuning.map_size.x * tile, _tuning.map_size.y * tile)
	draw_rect(edge, Color(0.16, 0.20, 0.15), false, 2.0)


## 좌표 해시. x·y 를 서로 다른 큰 소수로 섞어야 줄무늬가 안 생긴다.
static func _variant_for(x: int, y: int, count: int) -> int:
	if count <= 1:
		return 0
	var h := (x * 73856093) ^ (y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16)) % count
