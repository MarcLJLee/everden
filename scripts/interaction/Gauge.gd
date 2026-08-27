## 교감 점유 시간 게이지. (DEMO-SPEC §3.5)
##
## ★ 절대 규칙: 게이지는 중간에 끊기지 않는다.
##   방해 요소도 실패 조건도 없다. 거리가 멀어져도 계속 찬다.
##   취소는 플레이어가 취소 키를 명시적으로 누를 때만.
class_name Gauge
extends RefCounted

var active := false
## 지금 멈춰 있는가. 멀어져서 멈춘 것이지 실패한 것이 아니다.
var paused := false
var progress := 0.0        ## 0.0 ~ 1.0
var duration := 0.0
var factor := 1.0
var reasons := PackedStringArray()
var target: FieldSim.WildAnimal = null
var lead: Actor = null

var _tuning: FieldTuning = null
var _schema: TagSchema = null

func setup(tuning: FieldTuning, schema: TagSchema = null) -> void:
	_tuning = tuning
	_schema = schema


func start(animal: FieldSim.WildAnimal, companion: Actor, daypart: String) -> void:
	if active:
		return
	target = animal
	lead = companion
	# 전에 쏟다 만 시간이 있으면 그 자리에서 이어 찬다 — 개체가 들고 있다
	progress = animal.invite_progress
	var computed := compute_factor(animal.species, companion, daypart, _tuning, animal.quirks, _schema)
	factor = computed["factor"]
	reasons = computed["reasons"]
	duration = _tuning.base_gauge_time * factor
	active = true


## 방금 다 찼으면 true. 한 번만 true 를 돌려준다.
## distance 를 넘기면 점유 판정을 한다 — 멀면 멈춘다(줄지는 않는다).
func update(delta: float, distance := -1.0) -> bool:
	if not active:
		return false
	paused = distance >= 0.0 and distance > _tuning.hold_radius * _tuning.tile_size
	if paused:
		return false
	progress += delta / maxf(duration, 0.01)
	target.invite_progress = minf(progress, 1.0)
	if progress < 1.0:
		return false
	progress = 1.0
	active = false
	return true


## 게이지 창을 닫는다. **쏟은 시간은 개체에 남는다** — 다시 오면 이어서 찬다.
## 되돌릴 수 없는 실패를 만들지 않는다(원칙 2)는 여기에도 걸린다.
func close() -> void:
	active = false
	paused = false
	progress = 0.0
	target = null
	lead = null
	reasons = PackedStringArray()


## 플레이어가 명시적으로 취소를 누른 경우. 지금은 창만 닫는다 —
## 쏟은 시간까지 버리면 그게 되돌릴 수 없는 실패다.
func cancel() -> void:
	close()


## 상성 계수. 프로토타입에서 켜는 축은 먹이 유형 + 활동 시간 2개뿐이다. (BRIEF §8)
static func compute_factor(species: Dictionary, companion: Actor, daypart: String,
		tuning: FieldTuning, target_quirks: Array = [], schema: TagSchema = null) -> Dictionary:
	var factor := 1.0
	var reasons := PackedStringArray()

	if companion != null:
		var target_diet := String(species.get("diet", ""))
		var companion_diet := companion.diet
		if _diet_clash(target_diet, companion_diet):
			factor *= tuning.mismatch_factor
			reasons.append("먹이 %s↔%s ×%.2f" % [companion_diet, target_diet, tuning.mismatch_factor])
		if companion.charm > 0.0:
			factor /= companion.charm
			reasons.append("매력 ÷%.2f" % companion.charm)

	if not activity_matches(String(species.get("activity", "")), daypart):
		factor *= tuning.mismatch_factor
		reasons.append("시간대 ×%.2f" % tuning.mismatch_factor)

	# 개체의 개성 — 붙임성이 있으면 게이지가 눈에 띄게 짧다 (BRIEF §2.5)
	if schema != null and not target_quirks.is_empty():
		var quirk_scale := schema.quirk_product(target_quirks, "gauge_scale")
		if not is_equal_approx(quirk_scale, 1.0):
			factor *= quirk_scale
			reasons.append("개성 ×%.2f" % quirk_scale)

	if reasons.is_empty():
		reasons.append("상성 맞음")
	return {"factor": factor, "reasons": reasons}


static func _diet_clash(a: String, b: String) -> bool:
	return (a == "육식" and b == "초식") or (a == "초식" and b == "육식")


## 밤낮이 없는 데모라 시간대는 디버그 오버레이에서 강제 전환한다. (DEMO-SPEC §3.5)
const DAYPART_FOR_ACTIVITY := {"주행성": "낮", "야행성": "밤", "박명성": "여명"}

static func activity_matches(activity: String, daypart: String) -> bool:
	return DAYPART_FOR_ACTIVITY.get(activity, "") == daypart
