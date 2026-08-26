## data/*.json 로드 + 검증. (DEMO-SPEC §2)
##
## 검증 규칙 4개를 그대로 구현한다:
##   1. required_tags 에 없는 값  → 로드 거부. 어느 종의 어느 필드인지 출력
##   2. optional_tags 에 없는 값  → 기본값으로 대체하고 경고만
##   3. requires_behavior_schema > 본체 지원 버전 → 로드 거부
##   4. size_class 가 파생 규칙과 다름 → 경고 (수동 오버라이드 허용)
class_name DataLoader
extends RefCounted

## 본체가 해석할 수 있는 behavior 스키마 버전. 팩은 게임 버전이 아니라 이것에 의존한다.
const SUPPORTED_BEHAVIOR_SCHEMA := 1

const TAGS_PATH := "res://data/tags.json"
const ANIMALS_PATH := "res://data/animals.json"

## 종 정의에 반드시 있어야 하는 필드
const REQUIRED_FIELDS := [
	"id", "name", "diet", "activity", "habitat", "social", "temperament",
	"noise", "size", "size_class", "growth", "stats_range", "sprite_set",
]
## 열거형 대조 대상 — 값이 하나인 것
const SCALAR_TAG_FIELDS := ["diet", "activity", "social", "temperament", "noise", "size_class"]
## 열거형 대조 대상 — 값이 배열인 것
const ARRAY_TAG_FIELDS := ["habitat", "senses", "traits", "likes", "fears"]
## sprite_set 안의 선택 태그 (연출 전용)
const OPTIONAL_SPRITE_FIELDS := ["idle_animation", "move_effect", "eye_style", "mouth_style", "animation_rig"]


class Result extends RefCounted:
	var ok := true
	var reject_reason := ""
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var schema: TagSchema = null
	var species := {}  ## id -> Dictionary (검증·보정을 마친 종 정의)

	func reject(reason: String) -> void:
		ok = false
		if reject_reason.is_empty():
			reject_reason = reason

	func error(message: String) -> void:
		errors.append(message)
		reject("태그 검증 실패")

	func warn(message: String) -> void:
		warnings.append(message)

	func report() -> String:
		var lines := PackedStringArray()
		for w in warnings:
			lines.append("  [경고] " + w)
		for e in errors:
			lines.append("  [오류] " + e)
		if ok:
			lines.append("로드 성공 — 종 %d개, 경고 %d건" % [species.size(), warnings.size()])
		else:
			lines.append("로드 거부 — %s (오류 %d건)" % [reject_reason, errors.size()])
		return "\n".join(lines)


## 전체 로드. prototype_only 면 prototype:true 인 종만 담는다.
static func load_all(prototype_only := true, tags_path := TAGS_PATH, animals_path := ANIMALS_PATH) -> Result:
	var result := Result.new()

	var tags_raw := _read_json(tags_path, result)
	var animals_raw := _read_json(animals_path, result)
	if not result.ok:
		return result

	result.schema = TagSchema.from_dict(tags_raw)

	# 규칙 3 — 스키마 버전
	var required_version := int(animals_raw.get("requires_behavior_schema", 0))
	if required_version > SUPPORTED_BEHAVIOR_SCHEMA:
		result.reject("게임을 업데이트해주세요 — 이 데이터는 behavior 스키마 v%d가 필요한데 본체는 v%d까지 지원합니다"
			% [required_version, SUPPORTED_BEHAVIOR_SCHEMA])
		return result
	if result.schema.behavior_schema_version != required_version:
		result.warn("tags.json 의 behavior_schema_version(%d)과 animals.json 의 requires_behavior_schema(%d)가 다릅니다"
			% [result.schema.behavior_schema_version, required_version])

	for entry in animals_raw.get("species", []):
		var species: Dictionary = entry
		if prototype_only and not bool(species.get("prototype", false)):
			continue
		_validate_species(species, result.schema, result)
		if result.ok:
			result.species[String(species["id"])] = species

	if not result.ok:
		result.species.clear()
	return result


static func _read_json(path: String, result: Result) -> Dictionary:
	if not FileAccess.file_exists(path):
		result.reject("파일 없음: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		result.reject("JSON 파싱 실패: " + path)
		return {}
	return parsed


static func _validate_species(species: Dictionary, schema: TagSchema, result: Result) -> void:
	var id := String(species.get("id", "(id 없음)"))

	for field in REQUIRED_FIELDS:
		if not species.has(field):
			result.error("%s: 필수 필드 '%s' 가 없습니다" % [id, field])

	# 규칙 1 — 필수 태그 열거형 대조
	for field in SCALAR_TAG_FIELDS:
		if species.has(field):
			_check_value(id, field, String(species[field]), schema, result)
	for field in ARRAY_TAG_FIELDS:
		if species.has(field):
			for value in species[field]:
				_check_value(id, field, String(value), schema, result)

	for stage_entry in species.get("growth", []):
		var stage: Dictionary = stage_entry
		if stage.has("stage"):
			_check_value(id, "stage", String(stage["stage"]), schema, result)
		for tag in stage.get("behavior_tags", []):
			_check_value(id, "behavior_tags", String(tag), schema, result)

	# 규칙 2 — 선택 태그는 기본값으로 대체하고 경고만
	var sprite_set: Dictionary = species.get("sprite_set", {})
	for field in OPTIONAL_SPRITE_FIELDS:
		if not sprite_set.has(field):
			continue
		var value := String(sprite_set[field])
		if value in schema.allowed(field):
			continue
		var fallback := schema.optional_default(field)
		sprite_set[field] = fallback
		result.warn("%s.sprite_set.%s = '%s' 는 모르는 값입니다 → '%s' 로 대체했습니다"
			% [id, field, value, fallback])

	# presence — 종이 활동 조건을 직접 들 수 있다. 키와 범위를 본다.
	for daypart in species.get("presence", {}):
		var known := schema.dayparts()
		if not known.is_empty() and not (String(daypart) in known):
			result.error("%s.presence 에 모르는 시간대 '%s' 가 있습니다 (가능: %s)"
				% [id, daypart, ", ".join(PackedStringArray(known))])
		var chance := float(species["presence"][daypart])
		if chance < 0.0 or chance > 1.0:
			result.error("%s.presence.%s = %s 는 0~1 이어야 합니다" % [id, daypart, chance])

	# 규칙 4 — size_class 파생 불일치는 경고까지만 (수동 오버라이드 허용)
	var adult_size := String(species.get("size", {}).get("adult", ""))
	var derived := schema.derive_size_class(adult_size)
	var declared := String(species.get("size_class", ""))
	if not derived.is_empty() and not declared.is_empty() and derived != declared:
		result.warn("%s: size_class 가 '%s' 인데 size.adult('%s') 로 파생하면 '%s' 입니다 (수동 오버라이드로 간주)"
			% [id, declared, adult_size, derived])


static func _check_value(id: String, field: String, value: String, schema: TagSchema, result: Result) -> void:
	var allowed := schema.allowed(field)
	if allowed.is_empty():
		result.error("%s: 스키마에 '%s' 열거형이 정의되어 있지 않습니다" % [id, field])
		return
	if not (value in allowed):
		result.error("%s.%s = '%s' 는 허용되지 않는 값입니다 (가능: %s)"
			% [id, field, value, ", ".join(PackedStringArray(allowed))])
