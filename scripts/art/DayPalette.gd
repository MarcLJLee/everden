## 밤낮 — 배경 팔레트 보간 + 오버레이 틴트. (HANDOFF §2-4, BRIEF §6.3)
##
##   1) 인덱스 아트    한 벌뿐. 변하지 않는다
##   2) 팔레트 보간    dawn→day→dusk→night 를 t 로 섞는다      ← 색조 (여기)
##   3) 오버레이 틴트  CanvasModulate 전역 곱연산               ← 밝기·채도 (여기)
##   4) 이펙트 레이어  반딧불·안개
##   5) 국소 광원      모닥불 같은 것만 Light2D
##
## 전역 조명을 Light2D 로 하지 않으므로 BRIEF §7 이 걱정한 셰이더 충돌이 생기지 않는다.
##
## 배경 아트(지형·프롭·지면 단서)는 전부 background 팔레트로 그려져 있다 — 확인함.
## 액터와 표현 아이콘은 자기 팔레트가 따로 있어 여기서 건드리지 않는다. 틴트만 받는다.
class_name DayPalette
extends RefCounted

const PALETTES_PATH := "res://sprites/extracted/palettes.json"
## 보간을 몇 단계로 끊어 텍스처를 다시 만들 것인가. 매 프레임 다시 만들 이유가 없다.
const BLEND_STEPS := 8

static var _data := {}
static var _source: Array = []          ## 아트가 그려진 팔레트 (= day)
static var _cache := {}                 ## "경로|단계" -> ImageTexture
static var _from := "day"
static var _to := "day"
static var _step := BLEND_STEPS          ## 0 = from, BLEND_STEPS = to


static func load_data() -> void:
	if not _data.is_empty():
		return
	if not ResourceLoader.exists(PALETTES_PATH) and not FileAccess.file_exists(PALETTES_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PALETTES_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed
		_source = _data.get("background", {}).get("day", [])


static func has_data() -> bool:
	load_data()
	return not _source.is_empty()


## 지금 어느 팔레트에서 어느 팔레트로 얼마나 왔는가.
## 단계가 바뀌었으면 true — 그때만 텍스처를 다시 만들면 된다.
static func set_blend(from_palette: String, to_palette: String, t: float) -> bool:
	load_data()
	var step := int(round(clampf(t, 0.0, 1.0) * BLEND_STEPS))
	if from_palette == _from and to_palette == _to and step == _step:
		return false
	_from = from_palette
	_to = to_palette
	_step = step
	return true


## 화면 전체에 곱할 색. CanvasModulate 에 넣는다.
static func tint() -> Color:
	load_data()
	var table: Dictionary = _data.get("overlay_tint", {})
	return _lerp_color(_tint_of(table, _from), _tint_of(table, _to), float(_step) / BLEND_STEPS)


## 배경 아트를 현재 시간대 팔레트로 바꿔 돌려준다. 팔레트 정보가 없으면 원본 그대로.
static func texture_for(path: String) -> Texture2D:
	load_data()
	if _source.is_empty() or (_from == "day" and _to == "day"):
		return load(path)

	var key := "%s|%s|%s|%d" % [path, _from, _to, _step]
	if _cache.has(key):
		return _cache[key]

	var target := _blended_palette()
	var image: Image = (load(path) as Texture2D).get_image().duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)

	var mapping := {}
	for i in mini(_source.size(), target.size()):
		mapping[_color_of(_source[i])] = target[i]
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a == 0.0:
				continue
			var replacement = mapping.get(_quantize(pixel))
			if replacement != null:
				image.set_pixel(x, y, Color(replacement.r, replacement.g, replacement.b, pixel.a))

	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func _blended_palette() -> Array:
	var background: Dictionary = _data.get("background", {})
	var from_colors: Array = background.get(_from, _source)
	var to_colors: Array = background.get(_to, _source)
	var t := float(_step) / BLEND_STEPS
	var out := []
	for i in _source.size():
		var a := _color_of(from_colors[i]) if i < from_colors.size() else Color.WHITE
		var b := _color_of(to_colors[i]) if i < to_colors.size() else Color.WHITE
		out.append(_lerp_color(a, b, t))
	return out


static func _color_of(entry) -> Color:
	if typeof(entry) == TYPE_ARRAY and entry.size() >= 3:
		var alpha := float(entry[3]) / 255.0 if entry.size() > 3 else 1.0
		return Color(float(entry[0]) / 255.0, float(entry[1]) / 255.0, float(entry[2]) / 255.0, alpha)
	return Color.WHITE


## 팔레트 대조는 정확히 같은 색이어야 걸린다. 8비트로 끊어서 비교한다.
static func _quantize(color: Color) -> Color:
	return Color(roundi(color.r * 255) / 255.0, roundi(color.g * 255) / 255.0,
		roundi(color.b * 255) / 255.0, 1.0)


static func _tint_of(table: Dictionary, key: String) -> Color:
	var rgb: Array = table.get(key, [1.0, 1.0, 1.0])
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


static func _lerp_color(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), lerpf(a.a, b.a, t))
