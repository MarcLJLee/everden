## 밸런싱 지표 측정. (DEMO-SPEC §3.7, BRIEF §8)
##
## 지표는 하나로 고정한다: **입장 후 첫 유도까지 걸린 시간 ≤ 30초**
class_name Metrics
extends RefCounted

var elapsed := 0.0
var first_guide_time := -1.0
var invited_count := 0

func update(delta: float) -> void:
	elapsed += delta

## 첫 유도가 뜬 순간에 호출된다. 두 번째부터는 무시한다.
func note_guide() -> void:
	if first_guide_time < 0.0:
		first_guide_time = elapsed

func note_invited() -> void:
	invited_count += 1

func reset() -> void:
	elapsed = 0.0
	first_guide_time = -1.0
	invited_count = 0

func first_guide_text() -> String:
	if first_guide_time < 0.0:
		return "아직 (%.1f초 경과)" % elapsed
	return "%.1f초 %s" % [first_guide_time, "OK" if first_guide_time <= 30.0 else "초과!"]
