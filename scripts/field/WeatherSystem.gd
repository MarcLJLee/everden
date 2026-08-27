## 날씨 — **이름이 아니라 축**이다. (BRIEF §6.8 · weather/weather.json)
##
## cloud · fog · rain · snow · wind 각각 0~1. 이름(맑음·폭우…)은 한 점에 붙인 별명일 뿐이라
## 새 날씨를 추가해도 코드를 안 고친다.
##
## ★ **자연스럽게 흘러간다.** 목표 지점을 하나 잡고 그쪽으로 천천히 옮겨간다 —
##   툭툭 바뀌면 날씨가 아니라 스위치로 보인다.
## ★ **지형이 어느 축이 잘 서는지를 정한다.** 필드는 지형이 섞여 있으므로
##   타일 수로 가중평균한다 — 물가가 넓으면 안개가 잦고 바위가 많으면 바람이 세다.
class_name WeatherSystem
extends RefCounted

const DATA_PATH := "res://sprites/extracted/weather/weather.json"
## 틴트가 당겨가는 색. 축의 합만큼 이쪽으로 간다 (weather.json 의 tint_from_axes).
const TINT_TOWARD := Color(0.66, 0.73, 0.88)

var axes := {"cloud": 0.15, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.3}
var target := {}
## 이 필드의 지형 구성이 정한 축별 가중치
var weights := {}
var data := {}

var _schema: TagSchema = null
var _rng: RandomNumberGenerator = null
var _hold := 0.0
var _last_name := ""


func setup(schema: TagSchema, rng: RandomNumberGenerator, terrain_mix: Dictionary) -> void:
	_schema = schema
	_rng = rng
	if FileAccess.file_exists(DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	_weigh(terrain_mix)
	target = axes.duplicate()
	_pick_target()


## 지형 구성으로 축별 가중치를 만든다. 타일 수로 가중평균한다.
func _weigh(terrain_mix: Dictionary) -> void:
	var total := 0.0
	for name in terrain_mix:
		total += float(terrain_mix[name])
	for axis in axes:
		var sum := 0.0
		for name in terrain_mix:
			sum += _schema.weather_weight(String(name), axis) * float(terrain_mix[name])
		weights[axis] = sum / maxf(total, 1.0)


## 프리셋 하나를 골라 지형 가중치로 흔든다.
## 프리셋을 쓰는 것은 축을 따로따로 굴리면 "비 오는데 구름은 없는" 그림이 나오기 때문이다.
func _pick_target() -> void:
	var presets: Dictionary = data.get("presets", {})
	var caps: Dictionary = data.get("caps", {})
	var names: Array = presets.keys()
	if names.is_empty():
		return
	# 눈은 계절이 생긴 뒤에만 (weather.json 의 season_note)
	var pool: Array = []
	for name in names:
		if float(presets[name].get("snow", 0.0)) <= 0.0:
			pool.append(name)
	if pool.is_empty():
		pool = names

	# 가중 추첨.
	#
	# ★ 처음엔 축 합이 큰 프리셋이 이기도록 짰다가 **늘 폭우만 나왔다.**
	#   축 합은 "얼마나 사나운가"이지 "얼마나 잦은가"가 아니다. 둘을 갈라야 한다:
	#     사나울수록 드물게  ·  지형이 받쳐주면 그만큼 자주  ·  같은 날씨 연달아는 덜
	var entries: Array = []
	var total_weight := 0.0
	for name in pool:
		var preset: Dictionary = presets[name]
		var intensity := 0.0
		var fit := 0.0
		for axis in axes:
			var value := float(preset.get(axis, 0.0))
			intensity += value
			# 가중치가 1 보다 크면 그 지형이 그 축을 받쳐준다는 뜻이다
			fit += value * (float(weights.get(axis, 1.0)) - 1.0)
		# 지형 영향을 약하게 주면 "물가에선 안개가 잦다"를 아이가 못 배운다 —
		# 재보니 1.5 에서는 33% 대 24% 라 알아챌 수 없었다. 세게 준다.
		var weight := (1.0 / (1.0 + intensity * 1.6)) * exp(fit * 4.0)
		if String(name) == _last_name:
			weight *= 0.2
		entries.append({"name": String(name), "weight": weight})
		total_weight += weight

	var roll := _rng.randf() * total_weight
	var best: String = String(entries[0]["name"])
	for entry in entries:
		roll -= float(entry["weight"])
		if roll <= 0.0:
			best = String(entry["name"])
			break
	_last_name = best

	target = {}
	for axis in axes:
		var value := float(presets[best].get(axis, 0.0))
		# 상한 — 짙은 안개에서 화면이 안 보이면 7살은 그냥 못 논다
		if caps.has(axis):
			value = minf(value, float(caps[axis]))
		target[axis] = value
	_hold = _rng.randf_range(24.0, 60.0)


## drift_seconds 동안 목표까지 간다. 도착하면 잠시 머물다 다음 목표를 잡는다.
func update(delta: float, drift_seconds: float) -> void:
	var step := delta / maxf(drift_seconds, 0.01)
	var settled := true
	for axis in axes:
		var goal := float(target.get(axis, 0.0))
		axes[axis] = move_toward(float(axes[axis]), goal, step)
		if absf(float(axes[axis]) - goal) > 0.001:
			settled = false
	if not settled:
		return
	_hold -= delta
	if _hold <= 0.0:
		_pick_target()


## 지금 축에 가장 가까운 프리셋 이름. **화면에 쓰는 별명일 뿐이다** —
## 규칙은 축이 갖는다.
func nickname() -> String:
	return nickname_of(axes)


## 아무 축 묶음에나 가장 가까운 별명. 측정할 때 쓴다.
func nickname_of(values: Dictionary) -> String:
	var presets: Dictionary = data.get("presets", {})
	var best := "맑음"
	var best_distance := INF
	for name in presets:
		var distance := 0.0
		for axis in axes:
			distance += pow(float(values.get(axis, 0.0)) - float(presets[name].get(axis, 0.0)), 2.0)
		if distance < best_distance:
			best_distance = distance
			best = String(name)
	return best


## 틴트를 표로 적지 않는다. 축에서 뽑아야 강도가 저절로 따라온다 —
## 가랑비와 폭우가 같은 색일 수 없다.
func tint() -> Color:
	var pull := clampf(float(axes["cloud"]) * 0.9 + float(axes["rain"]) * 0.55
		+ float(axes["snow"]) * 0.18 + float(axes["fog"]) * 0.2, 0.0, 1.0)
	return Color.WHITE.lerp(TINT_TOWARD, pull)


## 이 감각이 지금 날씨에서 얼마나 깎이는가
func sense_scale(sense: String) -> float:
	return _schema.sense_weather_scale(sense, axes)


func summary() -> String:
	return "구름 %.2f · 안개 %.2f · 비 %.2f · 바람 %.2f" % [
		axes["cloud"], axes["fog"], axes["rain"], axes["wind"]]
