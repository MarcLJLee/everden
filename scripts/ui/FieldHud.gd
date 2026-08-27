## 필드에서 늘 보이는 것 — **지명과 자리 둘뿐이다.** (BRIEF §3.3 · §3.4)
##
## ★ 집이 재화·자리 둘만 두는 것과 같은 규칙이다(§2.7). 배고픔·청결·기분 게이지를
##   두지 않는 이유와 같다 — **늘 보이는 것이 늘어나면 화면이 할 일 목록이 된다.**
## ★ 나머지(동료 감각 아이콘 · 방향 · 점유 시간 게이지)는 **그때만** 뜬다.
##   상시 HUD 에 올리면 아이가 볼 것이 많아진다.
##
## ⚠️ 개발용 숫자는 여기 오지 않는다. 그건 디버그 오버레이가 갖고 있고
##    평소에는 꺼져 있다 — `F3`.
extends CanvasLayer

const HANGUL_FONT := "res://fonts/Galmuri11.ttf"

@onready var _where: Label = $Where
@onready var _seats: Label = $Seats


func _ready() -> void:
	for label in [_where, _seats]:
		if ResourceLoader.exists(HANGUL_FONT):
			label.add_theme_font_override("font", load(HANGUL_FONT))
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)


## seats 는 집에 남은 자리다 — 몇 아이를 더 데려올 수 있는지가 여기서 보인다.
func refresh(place: String, taken: int, seats: int) -> void:
	_where.text = place
	_seats.text = "자리  %d / %d" % [taken, seats]
