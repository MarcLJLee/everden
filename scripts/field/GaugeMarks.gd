## 초대 게이지 — **동물 머리 위에 뜬다.** (BRIEF §3.4 · ui/screens.json)
##
## ★ 화면 구석의 막대가 아니라 **그 아이 위에** 있어야 한다. 누구와 친해지는 중인지가
##   막대 하나로 보여야지, 아이가 눈을 화면 구석까지 옮겨야 하면 그 순간을 놓친다.
##
## ★ **쏟은 시간은 그 아이에게 남는다.** 멀어지면 멈출 뿐 안 지워진다(원칙 2) —
##   그래서 지금 채우는 중이 아닌 아이에게도 **흐린 막대**가 남아 있다.
##   그게 "아까 걔한테 좀 쏟았지" 를 화면이 기억해 주는 방식이다.
##
## ⚠️ 판을 두르지 않는다. 검은 판을 깔면 세계 밖 UI 위젯이 된다 (BRIEF §3.3) —
##    1px 테두리와 채움 두 줄이면 충분하다.
## ⚠️ 텍스처가 아니라 **네모**를 그린다. 눈송이와 같은 이유다 — 막대는 원래 네모다.
## ⚠️ 정수 픽셀. 반픽셀이면 막대가 자글거린다.
class_name GaugeMarks
extends Node2D

const WIDE := 20.0
const TALL := 3.0
const LIFT := 5.0
const EDGE := Color(0.08, 0.09, 0.10, 0.75)
const FILL := Color(1.0, 0.86, 0.45)
const HELD := Color(0.62, 0.58, 0.44)
## 쏟다 만 자국. 지금 채우는 중이 아닌 아이에게 남는다.
const LEFTOVER := Color(0.86, 0.78, 0.52, 0.5)

var _marks: Array = []


## marks 는 [{position, progress, active, paused}] 다.
func show_marks(marks: Array) -> void:
	_marks = marks
	queue_redraw()


func _draw() -> void:
	for mark in _marks:
		var at: Vector2 = (Vector2(mark["position"]) + Vector2(-WIDE * 0.5, -LIFT)).floor()
		var active: bool = bool(mark.get("active", false))
		var full: float = clampf(float(mark["progress"]), 0.0, 1.0)
		# 테두리 먼저 — 채움이 0 일 때도 "여기 뭔가 시작됐다" 가 보여야 한다
		draw_rect(Rect2(at - Vector2.ONE, Vector2(WIDE + 2.0, TALL + 2.0)), EDGE)
		var tint := LEFTOVER
		if active:
			tint = HELD if bool(mark.get("paused", false)) else FILL
		draw_rect(Rect2(at, Vector2(maxf(round(WIDE * full), 1.0), TALL)), tint)
