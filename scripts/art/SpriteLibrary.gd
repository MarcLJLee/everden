## 그려진 스프라이트를 찾아 쓰고, 없으면 색 사각형으로 떨어진다. (DEMO-SPEC §3.8)
##
## 종을 늘릴 때 코드를 고치지 않는다 — `sprites/extracted/<종 id>/<애니메이션>.png`
## 가 있으면 그것을 쓰고, 없으면 플레이스홀더가 그 자리를 메운다.
## 스트립은 가로로 이어붙인 프레임이고, 프레임 폭은 캔버스 폭과 같다.
class_name SpriteLibrary
extends RefCounted

const ROOT := "res://sprites/extracted"

## palettes.json 의 표들 — 단서·프롭이 어느 태그·지형에 붙는지가 여기 적혀 있다.
## 종 이름으로 분기하지 않는 것과 같은 이유로, 이 짝도 코드에 박지 않는다.
static var _index := {}

static func index() -> Dictionary:
	if _index.is_empty():
		var path := ROOT + "/palettes.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				_index = parsed
	return _index


## 후각·청각은 지면에 실물이 없다 — 공중에 뜨는 표시다. (HANDOFF §4)
static func airborne_clue_texture(sense: String) -> Texture2D:
	# 냄새·소리 표시는 배경이 아니라 표현이다. 밤이라고 색이 바뀌면 안 읽힌다.
	return _texture_from(index().get("clue_airborne", {}).get(sense, ""), false)


## 시야 계열 흔적은 땅에 찍힌 실물이다.
static func ground_clue_texture(trait_name: String) -> Texture2D:
	return _texture_from(index().get("clue_by_trait", {}).get(trait_name, ""))


## 이 지형에 어울리는 프롭 이름 목록
static func props_for_terrain(terrain: String) -> Array:
	return index().get("prop_terrain", {}).get(terrain, [])


static func prop_texture(name: String) -> Texture2D:
	return _texture_from("props/%s.png" % name)


static func _texture_from(relative: String, remap := true) -> Texture2D:
	if relative.is_empty():
		return null
	var path := ROOT + "/" + relative
	if not ResourceLoader.exists(path):
		return null
	return DayPalette.texture_for(path) if remap else load(path)


## 아트가 스스로 말하는 것 — 캔버스 크기와 앵커. `extracted/<종 id>/<종 id>.json`
## 플레이어처럼 캔버스가 종 데이터의 size_class 로 안 나오는 경우가 있다(32×48).
## 그림에서 나온 값이므로 있으면 이쪽이 이긴다.
static var _meta_cache := {}

static func art_meta(species_id: String) -> Dictionary:
	if _meta_cache.has(species_id):
		return _meta_cache[species_id]
	var meta := {}
	var path := "%s/%s/%s.json" % [ROOT, species_id, species_id]
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			meta = parsed
	_meta_cache[species_id] = meta
	return meta


## 그림이 캔버스를 말하면 그것을, 아니면 size_class 버킷을 쓴다.
static func canvas_for(species_id: String, fallback: Vector2i) -> Vector2i:
	var declared = art_meta(species_id).get("canvas")
	if typeof(declared) == TYPE_ARRAY and declared.size() >= 2:
		return Vector2i(int(declared[0]), int(declared[1]))
	return fallback


## 그림이 앵커를 말하면 sprite_set 에 덮어쓴다.
static func apply_meta_anchors(species_id: String, sprite_set: Dictionary) -> Dictionary:
	var anchors: Dictionary = art_meta(species_id).get("anchors", {})
	if anchors.is_empty():
		return sprite_set
	var merged := sprite_set.duplicate(true)
	if anchors.has("eye_front") or anchors.has("eye_side"):
		merged["eye_anchor"] = {
			"front": anchors.get("eye_front", [16, 11]),
			"side": anchors.get("eye_side", [16, 11]),
		}
	if anchors.has("head"):
		merged["head_anchor"] = anchors["head"]
	return merged


## 눈이 되비추는 판. 원본 눈의 명암을 유지한 채 색만 갈아끼운다 —
## 통째로 칠하면 눈동자가 사라져서 점 두 개로 보인다.
static var _shine_cache := {}

static func eyeshine_texture(source: Texture2D, color: Color) -> Texture2D:
	if source == null:
		return null
	var key := "%s|%s" % [source.resource_path if not source.resource_path.is_empty()
		else str(source.get_instance_id()), color]
	if _shine_cache.has(key):
		return _shine_cache[key]
	var image := source.get_image().duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a == 0.0:
				continue
			# 원래 밝던 곳은 더 밝게, 어둡던 곳도 되비추게 — 명암 대비는 남긴다
			var luminance: float = (pixel.r + pixel.g + pixel.b) / 3.0
			var strength: float = 0.55 + 0.45 * luminance
			image.set_pixel(x, y, Color(color.r * strength, color.g * strength,
				color.b * strength, pixel.a))
	var texture := ImageTexture.create_from_image(image)
	_shine_cache[key] = texture
	return texture


## 종별 접지 정보. 같은 종을 여러 마리 만들 때마다 이미지를 훑을 이유가 없다.
static var _ground_cache := {}

## 그림의 **접지선**은 캔버스 맨 아래가 아니다 — build.py 는 발끝을 y=27 에 둔다.
## 캔버스 바닥을 발밑으로 삼으면 동물이 그림자 위에 떠 보인다.
## 그래서 아래쪽 빈 줄 수(gap)와 발이 닿는 폭(foot_width)을 그림에서 직접 읽는다.
static func ground_info(species_id: String, frames: SpriteFrames, canvas: Vector2i) -> Dictionary:
	if _ground_cache.has(species_id):
		return _ground_cache[species_id]

	var result := {"gap": 0, "foot_width": maxi(canvas.x - 4, 4)}
	var image := _first_frame_image(frames)
	if image != null:
		var gap := 0
		var bottom := -1
		for y in range(image.get_height() - 1, -1, -1):
			if _row_is_empty(image, y):
				gap += 1
				continue
			bottom = y
			break
		if bottom >= 0:
			var first := -1
			var last := -1
			for x in image.get_width():
				if image.get_pixel(x, bottom).a > 0.0:
					if first < 0:
						first = x
					last = x
			result["gap"] = mini(gap, int(canvas.y / 2))
			if first >= 0:
				result["foot_width"] = clampi(last - first + 3, 4, canvas.x)
	_ground_cache[species_id] = result
	return result


static func _first_frame_image(frames: SpriteFrames) -> Image:
	if frames == null:
		return null
	for anim in ANIMATIONS:
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			var texture := frames.get_frame_texture(anim, 0)
			if texture != null:
				return texture.get_image()
	return null


static func _row_is_empty(image: Image, y: int) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, y).a > 0.0:
			return false
	return true


## 어떤 종에 대해 대역 경고를 이미 남겼는가. 같은 말을 승격마다 반복하지 않는다.
static var _warned := {}

static func warn_once(species_id: String, message: String) -> void:
	if _warned.has(species_id):
		return
	_warned[species_id] = true
	push_warning(message)
const ANIMATIONS := ["idle", "move_side", "move_north", "move_south", "special"]
## 그림이 없을 때 대신 쓸 애니메이션. 없는 걸 그냥 비우면 캐릭터가 사라진다.
const SUBSTITUTES := {
	"idle": "move_side",
	"move_side": "move_south",
	"move_north": "move_south",
	"move_south": "move_side",
	"special": "idle",
}

## 이 동작에 실제로 쓸 파일 이름. 없으면 대역을 찾고, 그것도 없으면 빈 문자열.
##
## ★ 대역 사슬에 **고리**가 있다 (move_south → move_side → move_south).
##   방문한 곳을 기억하지 않으면 없는 파일을 그대로 로드해서 터진다 —
##   실제로 idle 만 있는 종이 들어왔을 때 그렇게 터졌다.
static func _substitute_for(species_id: String, anim: String) -> String:
	var seen := {}
	var source := anim
	while not seen.has(source):
		if ResourceLoader.exists(_strip_path(species_id, source)):
			return source
		seen[source] = true
		source = String(SUBSTITUTES.get(source, ""))
		if source.is_empty():
			break
	# 사슬이 고리를 돌았다. 있는 것 아무거나 쓴다 — idle 이 먼저다.
	for candidate in ANIMATIONS:
		if ResourceLoader.exists(_strip_path(species_id, candidate)):
			return candidate
	return ""


## 이 종의 그림이 하나라도 있는가
static func has_art(species_id: String) -> bool:
	for anim in ANIMATIONS:
		if ResourceLoader.exists(_strip_path(species_id, anim)):
			return true
	return false


## 몸통 SpriteFrames. 반환값의 missing 은 대역으로 때운 애니메이션 목록이다.
static func body_frames(species: Dictionary, canvas: Vector2i) -> Dictionary:
	var id := String(species.get("id", ""))
	if not has_art(id):
		return {"frames": PlaceholderArt.body_frames(species, canvas), "real": false, "missing": []}

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var missing := PackedStringArray()
	for anim in ANIMATIONS:
		frames.add_animation(anim)
		frames.set_animation_loop(anim, true)
		frames.set_animation_speed(anim, 6.0)
		var source := _substitute_for(id, anim)
		if source.is_empty():
			# 그림이 하나도 없다. 이 종은 통째로 색 사각형으로 간다 —
			# 한 동작만 사각형이면 걷다가 갑자기 네모가 된다.
			return {"frames": PlaceholderArt.body_frames(species, canvas), "real": false, "missing": []}
		if source != anim:
			missing.append(anim)
		for texture in _slice(_strip_path(id, source), canvas):
			frames.add_frame(anim, texture)
	return {"frames": frames, "real": true, "missing": missing}


## 눈은 공용이 원칙이다 (BRIEF §4.6). `shared/` 에는 **round 스타일**이 구워져 있고,
## 스타일이 다른 종만 종 폴더에 따로 구워진다 (export_godot.py 규약).
##
## 그래서 어느 쪽을 볼지는 **데이터의 eye_style 이 정한다** — 폴더가 있느냐로 정하면
## 종 폴더가 다시 생성되는 순간 조용히 그쪽으로 끌려간다.
## 둘 다 없으면 눈 레이어를 두지 않는다 — 얼굴이 이미 몸통에 있는 종을 위한 것이다.
const SHARED_EYE_STYLE := "round"

static func eye_texture(species_id: String, angle: String, expression := "기본",
		style := SHARED_EYE_STYLE) -> Texture2D:
	var folders := ["shared", species_id] if style == SHARED_EYE_STYLE else [species_id, "shared"]
	for folder in folders:
		var path := "%s/%s/eye_%s_%s.png" % [ROOT, folder, angle, expression]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## 입도 눈과 같다. 없으면 null — 그리지 않았다는 뜻이다.
static func mouth_texture(species_id: String, expression := "기본") -> Texture2D:
	for folder in [species_id, "shared"]:
		var path := "%s/%s/mouth_%s.png" % [ROOT, folder, expression]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## 표현 아이콘. 배경이 아니라 표현이라 밤낮 팔레트를 타지 않는다.
static func emote_texture(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null
	return _texture_from("shared/emote_%s.png" % icon_name, false)


static func _strip_path(species_id: String, anim: String) -> String:
	return "%s/%s/%s.png" % [ROOT, species_id, anim]


## 가로 스트립을 캔버스 폭으로 잘라 프레임 목록을 만든다.
static func _slice(path: String, canvas: Vector2i) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if not ResourceLoader.exists(path):
		return out
	var sheet: Texture2D = load(path)
	if sheet == null:
		return out
	var count := int(sheet.get_width() / float(canvas.x))
	for i in maxi(count, 1):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * canvas.x, 0, canvas.x, canvas.y)
		atlas.filter_clip = true
		out.append(atlas)
	return out
