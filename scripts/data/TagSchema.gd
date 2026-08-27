## tags.json 을 읽어 열거형·파생 규칙·매핑 테이블을 노출한다. (DEMO-SPEC §2)
##
## 이 클래스는 "무엇이 허용된 값인가"만 안다. 종 이름은 하나도 모른다.
class_name TagSchema
extends RefCounted

var behavior_schema_version: int = 0
var required_tags: Dictionary = {}      ## field -> Array[String]
var optional_tags: Dictionary = {}      ## field -> Array[String]
var trait_to_sense: Dictionary = {}     ## trait -> {sense, clue}
var sense_profile: Dictionary = {}
var eyeshine: Dictionary = {}
var terrain_walkable: Dictionary = {}   ## 지형 -> 플레이어가 밟을 수 있는가
var weather_bias: Dictionary = {}       ## 지형 -> {축: 가중치}
var activity_presence: Dictionary = {}  ## activity -> {시간대: 나와 있을 확률}
var quirks: Dictionary = {}             ## 개성 이름 -> {move_scale, gauge_scale, flee_tiles, shows}           ## activity -> 눈이 빛나 보이는 시간대 목록      ## sense -> {reveals, range_scale, daypart_scale, terrain_scale}
var emote_icons: Dictionary = {}
var expression_set: Dictionary = {}
var derivations: Dictionary = {}
var canvas_by_size_class: Dictionary = {}  ## size_class -> Vector2i
var sprite_directions: Dictionary = {}

static func from_dict(raw: Dictionary) -> TagSchema:
	var s := TagSchema.new()
	s.behavior_schema_version = int(raw.get("behavior_schema_version", 0))
	s.required_tags = _strip_comments(raw.get("required_tags", {}))
	s.optional_tags = _strip_comments(raw.get("optional_tags", {}))
	s.trait_to_sense = _strip_comments(raw.get("trait_to_sense", {}))
	s.sense_profile = _strip_comments(raw.get("sense_profile", {}))
	s.eyeshine = _strip_comments(raw.get("eyeshine", {})).get("by_activity", {})
	s.terrain_walkable = _strip_comments(raw.get("terrain_walkable", {}))
	s.weather_bias = _strip_comments(raw.get("weather_bias", {}))
	s.activity_presence = _strip_comments(raw.get("activity_presence", {}))
	s.quirks = _strip_comments(raw.get("quirks", {}))
	s.emote_icons = _strip_comments(raw.get("emote_icons", {}))
	s.expression_set = _strip_comments(raw.get("expression_set", {}))
	s.derivations = _strip_comments(raw.get("derivations", {}))
	s.sprite_directions = _strip_comments(raw.get("sprite_directions", {}))
	for key in _strip_comments(raw.get("canvas_by_size_class", {})):
		var wh: Array = raw["canvas_by_size_class"][key]
		s.canvas_by_size_class[key] = Vector2i(int(wh[0]), int(wh[1]))
	return s

## "$comment" 키는 사람이 읽으라고 넣은 것이다. 스키마에서 걷어낸다.
static func _strip_comments(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		if key != "$comment":
			out[key] = d[key]
	return out

func allowed(field: String) -> Array:
	if required_tags.has(field):
		return required_tags[field]
	if optional_tags.has(field):
		return optional_tags[field]
	return []

## 선택 태그가 이상할 때 대체할 값. 열거형의 첫 항목을 기본값으로 삼는다.
func optional_default(field: String) -> String:
	var values: Array = optional_tags.get(field, [])
	return String(values[0]) if not values.is_empty() else ""

## ★ 유도의 전부. 대상의 trait 하나가 어떤 감각에 걸리는지만 답한다. (DEMO-SPEC §3.4)
func sense_for_trait(trait_name: String) -> String:
	var entry: Dictionary = trait_to_sense.get(trait_name, {})
	return String(entry.get("sense", ""))

## 이 감각으로 감지하면 몸까지 보이는가, 단서(방향)까지인가. (BRIEF §3.3)
func sense_reveals_body(sense: String) -> bool:
	return bool(_profile(sense).get("reveals", false))

## guide_radius 에 곱할 감각 고유 배율. 후각이 제일 멀리 간다.
func sense_range_scale(sense: String) -> float:
	return float(_profile(sense).get("range_scale", 1.0))

## 시간대 배율. 밤의 시야가 여기서 줄어든다.
func sense_daypart_scale(sense: String, daypart: String) -> float:
	var table: Dictionary = _profile(sense).get("daypart_scale", {})
	return float(table.get(daypart, 1.0))

## 대상이 서 있는 지형의 배율. 숲에 있으면 눈에 안 띈다.
func sense_terrain_scale(sense: String, terrain: String) -> float:
	var table: Dictionary = _profile(sense).get("terrain_scale", {})
	return float(table.get(terrain, 1.0))

## 이 감각을 머리 위에 무슨 아이콘으로 보여줄 것인가.
func sense_icon(sense: String) -> String:
	return String(_profile(sense).get("icon", ""))

## 이 활동 시간대의 동물이 눈을 빛내는 시간대들. 종은 묻지 않는다.
func eyeshines_at(activity: String, daypart: String) -> bool:
	return daypart in eyeshine.get(activity, [])

## 플레이어가 밟을 수 있는 지형인가. 동물에게는 걸리지 않는다 —
## 물가·바위는 서식지라 막으면 그 종이 자기 집에 못 산다.
func walkable(terrain: String) -> bool:
	return bool(terrain_walkable.get(terrain, true))

## 날씨가 이 감각에 곱하는 배율. **이름이 아니라 축에 건다** (BRIEF §6.8) —
## 그래야 "옅은 안개는 시야가 조금만 깎인다"가 된다.
## 축이 0 이면 1.0, 1 이면 표에 적힌 값, 사이는 그 사이다.
func sense_weather_scale(sense: String, axes: Dictionary) -> float:
	var table: Dictionary = _profile(sense).get("weather_axis_scale", {})
	var value := 1.0
	for axis in table:
		value *= lerpf(1.0, float(table[axis]), clampf(float(axes.get(axis, 0.0)), 0.0, 1.0))
	return value


## 이 지형에서 그 축이 얼마나 잘 서는가. 적히지 않은 지형은 1.0.
func weather_weight(terrain: String, axis: String) -> float:
	return float(weather_bias.get(terrain, {}).get(axis, 1.0))


## 이 종이 그 시간대에 나와 있을 확률.
##
## 기본값은 activity 태그가 준다. 종이 다르게 굴면 animals.json 의 `presence` 가 덮는다 —
## 같은 야행성이라도 "주로 밤"과 "낮에는 절대 없음"이 갈리기 때문이다.
## 0 이면 그 시간대엔 아예 없다 — 박쥐를 낮에 못 찾는 것이 이 값이다.
func presence_chance(species: Dictionary, daypart: String, axes := {}) -> float:
	var base := 1.0
	var override: Dictionary = species.get("presence", {})
	if override.has(daypart):
		base = clampf(float(override[daypart]), 0.0, 1.0)
	else:
		base = float(activity_presence.get(String(species.get("activity", "")), {}).get(daypart, 1.0))
	return clampf(base * weather_presence_factor(species, axes), 0.0, 1.0)


## 날씨가 **누가 나오는지**를 바꾼다. 성공·실패는 바꾸지 않는다 (BRIEF §6.8).
## 종이 좋아하는 축이 셀수록 잘 나오고, 싫어하는 축이 세면 덜 나온다.
## 축이 0 이면 아무 영향이 없다 — 맑은 날은 모두에게 평등하다.
func weather_presence_factor(species: Dictionary, axes: Dictionary) -> float:
	var likes: Dictionary = species.get("weather_likes", {})
	var factor := 1.0
	for axis in likes:
		factor *= lerpf(1.0, float(likes[axis]), clampf(float(axes.get(axis, 0.0)), 0.0, 1.0))
	return factor


## 시간대 이름들 — 검증기가 presence 의 키를 대조할 때 쓴다.
func dayparts() -> Array:
	for activity in activity_presence:
		return activity_presence[activity].keys()
	return []


## 개성이 무엇을 바꾸는가. 없는 개성이면 아무것도 안 바꾼다.
func quirk_effect(quirk: String, key: String, fallback := 1.0) -> float:
	return float(quirks.get(quirk, {}).get(key, fallback))


func quirk_shows(quirk: String) -> String:
	return String(quirks.get(quirk, {}).get("shows", ""))


func quirk_names() -> Array:
	return quirks.keys()


## 개성 목록을 하나의 배율로 합친다. 여러 개면 곱한다.
func quirk_product(names: Array, key: String) -> float:
	var value := 1.0
	for name in names:
		value *= quirk_effect(String(name), key, 1.0)
	return value


func known_senses() -> Array:
	return sense_profile.keys()

func _profile(sense: String) -> Dictionary:
	return sense_profile.get(sense, {})

func clue_for_trait(trait_name: String) -> String:
	var entry: Dictionary = trait_to_sense.get(trait_name, {})
	return String(entry.get("clue", ""))

func canvas_for(size_class: String) -> Vector2i:
	return canvas_by_size_class.get(size_class, Vector2i(32, 32))

func face_hidden_when_facing() -> String:
	return String(sprite_directions.get("face_hidden_when_facing", "north"))

## size.adult 문자열("55-65cm")의 중앙값으로 size_class 를 파생한다. (tags.json derivations)
func derive_size_class(adult_size: String) -> String:
	var median := _median_cm(adult_size)
	if median < 0.0:
		return ""
	var rule: Dictionary = derivations.get("size_class", {})
	for threshold in rule.get("thresholds", []):
		var max_value = threshold.get("max")
		if max_value == null or median <= float(max_value):
			return String(threshold["value"])
	return ""

static func _median_cm(text: String) -> float:
	var numbers := PackedFloat32Array()
	var regex := RegEx.new()
	regex.compile("[0-9]+(\\.[0-9]+)?")
	for m in regex.search_all(text):
		numbers.append(float(m.get_string()))
	if numbers.is_empty():
		return -1.0
	var total := 0.0
	for n in numbers:
		total += n
	return total / numbers.size()
