## 동료의 유도 판정. (DEMO-SPEC §3.4)
##
## ★ 종 이름으로 분기하지 않는다. tags.json 의 trait_to_sense 테이블이 전부를 만들어낸다.
##   동료의 senses 와 대상의 traits 가 이 표를 통해 만나면 유도가 발생한다.
class_name GuideSystem
extends RefCounted

class Hit extends RefCounted:
	var companion: Actor = null
	var animal: FieldSim.WildAnimal = null
	var sense := ""
	var clue := ""
	var distance := INF

## 이번 프레임에 어떤 대상이 어떤 감각으로 잡혔는가. 대상 → {senses, clue}
## 유도 아이콘은 가장 가까운 하나만 쓰지만, 무엇이 보이는지는 전부를 봐야 정해진다.
var detections := {}

var _schema: TagSchema = null
var _tuning: FieldTuning = null
var _terrain: TerrainMap = null
var _daypart := "낮"
var _weather_axes := {}

func setup(schema: TagSchema, tuning: FieldTuning, terrain: TerrainMap) -> void:
	_schema = schema
	_tuning = tuning
	_terrain = terrain

func set_daypart(daypart: String) -> void:
	_daypart = daypart


func set_weather_axes(axes: Dictionary) -> void:
	_weather_axes = axes


## 이 동료가 이 감각으로 닿는 거리(픽셀). 대상이 어디에 서 있느냐까지 들어간다.
##   guide_radius × 개체 sense_range × 감각 배율 × 시간대 배율 × 대상 지형 배율
func reach(companion: Actor, sense: String, target_position := Vector2.INF) -> float:
	var reach_tiles := _tuning.guide_radius * companion.sense_scale
	reach_tiles *= _schema.sense_range_scale(sense)
	reach_tiles *= _schema.sense_daypart_scale(sense, _daypart)
	reach_tiles *= _schema.sense_weather_scale(sense, _weather_axes)
	if target_position != Vector2.INF and _terrain != null:
		reach_tiles *= _schema.sense_terrain_scale(sense, _terrain.at_world(target_position))
	return reach_tiles * _tuning.tile_size


## 시간대·지형을 빼고 잰 최대 반경. 두 배율 모두 1.0 이하라 이것이 상한이다.
## 풀 AI 승격 거리를 정할 때 쓴다 — 승격이 이보다 좁으면 감각이 헛돈다.
func max_reach(companion: Actor, sense: String) -> float:
	return _tuning.guide_radius * companion.sense_scale \
		* _schema.sense_range_scale(sense) * _tuning.tile_size


## 지형을 빼고 잰 반경. 디버그 오버레이에 "지금 이 동료는 몇 타일까지 닿는가"를 찍는 용도.
func reach_tiles(companion: Actor, sense: String) -> float:
	return reach(companion, sense) / _tuning.tile_size


## 동료마다 가장 가까운 감지 대상 하나씩 아이콘을 띄우고, 그중 최단거리 한 건을 돌려준다.
## 돌려준 것이 화면 가장자리 화살표와 밸런싱 지표에 쓰인다.
func update(companions: Array, animals: Array) -> Hit:
	detections.clear()
	var best: Hit = null
	for companion in companions:
		var hit := _nearest_for(companion, animals)
		companion.play_special = hit != null
		if hit == null:
			companion.hide_sense_icon()
			companion.look_direction = Vector2.ZERO
			continue
		companion.show_sense_icon(hit.sense, _schema.sense_icon(hit.sense))
		companion.look_direction = hit.animal.position - companion.position
		if best == null or hit.distance < best.distance:
			best = hit
	return best


func _nearest_for(companion: Actor, animals: Array) -> Hit:
	var best: Hit = null
	for animal in animals:
		var distance := companion.position.distance_to(animal.position)
		# 감각마다 닿는 거리가 다르다. 코는 멀리, 눈은 밤이나 숲에서 짧아진다.
		var landed := PackedStringArray()
		for sense in _detectable_senses(companion, animal):
			if distance <= reach(companion, String(sense), animal.position):
				landed.append(String(sense))
		if landed.is_empty():
			continue
		_record(animal, landed)
		if best != null and distance >= best.distance:
			continue
		best = Hit.new()
		best.companion = companion
		best.animal = animal
		best.sense = landed[0]
		best.clue = _schema.clue_for_trait(_trait_for_sense(animal, landed[0]))
		best.distance = distance
	return best


## 대상의 흔적 중 이 동료의 감각에 걸리는 것 전부. 하나로 줄이면
## "개는 방향만, 고양이는 몸까지"라는 차이를 만들 수 없다.
func _detectable_senses(companion: Actor, animal: FieldSim.WildAnimal) -> PackedStringArray:
	var found := PackedStringArray()
	for trait_name in animal.species.get("traits", []):
		var sense := _schema.sense_for_trait(String(trait_name))
		if sense in companion.senses and not (sense in found):
			found.append(sense)
	return found


func _trait_for_sense(animal: FieldSim.WildAnimal, sense: String) -> String:
	for trait_name in animal.species.get("traits", []):
		if _schema.sense_for_trait(String(trait_name)) == sense:
			return String(trait_name)
	return ""


func _record(animal: FieldSim.WildAnimal, senses: PackedStringArray) -> void:
	var entry: Dictionary = detections.get(animal, {"senses": PackedStringArray(), "clue": ""})
	for sense in senses:
		if not (sense in entry["senses"]):
			entry["senses"].append(sense)
		if entry["clue"].is_empty():
			entry["clue"] = _schema.clue_for_trait(_trait_for_sense(animal, sense))
	detections[animal] = entry


func detected_senses(animal: FieldSim.WildAnimal) -> PackedStringArray:
	var entry: Dictionary = detections.get(animal, {})
	return entry.get("senses", PackedStringArray())


func clue_of(animal: FieldSim.WildAnimal) -> String:
	var entry: Dictionary = detections.get(animal, {})
	return String(entry.get("clue", ""))
