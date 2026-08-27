## 디버그 오버레이 — Label 몇 개. 슬라이더 UI를 만들지 않는다. (DEMO-SPEC §3.7)
## 값은 리모트 인스펙터로 만진다.
extends CanvasLayer

@onready var _label: Label = $StatsLabel
@onready var _hud: Control = $Hud

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Apple SD Gothic Neo", "Noto Sans CJK KR", "Malgun Gothic", "Sans-Serif"])
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)


func show_load_error(text: String) -> void:
	_label.text = "데이터 로드 거부\n" + text
	_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))


func refresh(state: Dictionary) -> void:
	var metrics: Metrics = state["metrics"]
	var gauge: Gauge = state["gauge"]
	var hit: GuideSystem.Hit = state["hit"]

	var lines := PackedStringArray()
	lines.append("첫 유도까지: %s" % metrics.first_guide_text())
	lines.append("초대 성공: %d마리" % metrics.invited_count)
	lines.append("날씨: %s   [Y] 전환   ·   %s" % [state["weather"], state["weather_shows"]])
	lines.append("시간대: %s   [T] 전환   ·   발밑: %s   ·   승격 %.0f타일" % [
		state["daypart"], state["terrain"], state["promotion_tiles"]])
	lines.append("감각 반경: %s" % state["senses"])
	lines.append("동물: 나와있음 %d/%d · 보임 %d · 단서만 %d · 활성 %d · 얕은시뮬 %d" % [
		state["present_count"], state["total_count"],
		state["visible_count"], state["clues"].size(),
		state["active_count"], state["shallow_count"]])
	lines.append("동료: %s" % state["companions"])
	if hit != null:
		lines.append("유도: %s → %s (%s · %s, %.1f타일)" % [
			hit.companion.display_name, hit.animal.display_name(), hit.sense, hit.clue,
			hit.distance / 16.0])
	else:
		lines.append("유도: 없음")
	if gauge.active:
		lines.append("게이지: %.1f초 (×%.2f — %s)%s" % [
			gauge.duration, gauge.factor, ", ".join(gauge.reasons),
			"   ⏸ 멀어져서 멈춤 (줄지는 않는다)" if gauge.paused else ""])
	else:
		lines.append("게이지: 대기 — 대상에 붙어 [스페이스]")
	_label.text = "\n".join(lines)
	_hud.set_state(state)
