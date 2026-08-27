## 눈. **여기만 타일이 아니라 낱개로 그린다.**
##
## ★ 다른 날씨는 전부 이어 붙는 타일을 스크롤한다 — 그게 싸고, 구름·비·안개는
##   낱개가 눈에 안 띄므로 그걸로 충분하다. 눈은 다르다. **눈송이는 하나씩 보인다.**
##   타일로 만들었다가 세 가지가 한꺼번에 어긋났다 (전부 사용자 지적):
##     · 96 타일이 화면에 세 번 들어가 **같은 배열이 반복돼 패턴이 읽혔다**
##     · 2×2 눈을 2배로 키워 **4×4 덩어리**가 됐다 (눈은 커지는 게 아니라 큰 게 섞인다)
##     · 타일이 통째로 움직이니 **모든 눈이 한 몸처럼 흔들렸다**
##   셋 다 "낱개를 낱개로 다루지 않아서" 생긴 것이라, 낱개로 그리면 한꺼번에 없어진다.
##
## ★ 텍스처가 아니라 **네모**를 그린다. 눈송이가 원래 1~3px 흰 네모라
##   `draw_rect` 가 곧 도트다 — Control 의 `_draw` 에서 텍스처를 그리면 안 된다는
##   그 규칙에 걸리지 않는다 (RUN.md 참조).
##
## ⚠️ 자리는 **월드에 고정**한다. 화면 기준으로 감으면 카메라를 따라 눈이 통째로
##    끌려다녀서 유리창에 붙은 것처럼 보인다 — 비·구름과 같은 원칙이다.
##    월드를 PERIOD 크기 격자로 감아서 어디를 가도 눈이 있게 한다.
## ⚠️ 정수 픽셀로만 찍는다. 반픽셀이면 도트가 아니라 노이즈가 된다.
class_name SnowField
extends Node2D

## 월드를 이 크기로 감는다. 화면(320×180)보다 커야 반복이 안 읽힌다.
const PERIOD := Vector2(512.0, 288.0)
## 한 주기에 뿌리는 눈송이. 화면에 보이는 것은 이 중 3분의 1쯤이다.
const POOL := 640
const TINT := Color(0.93, 0.96, 0.99)

var _flakes: Array = []
var _elapsed := 0.0
var _amount := 0.0
var _wind := 0.0
var _view := Rect2()


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	for i in POOL:
		# 큰 눈일수록 가깝다 — 빨리 떨어지고 크게 흔들리고 진하다.
		var size := 1
		var roll := rng.randf()
		if roll > 0.86:
			size = 3
		elif roll > 0.52:
			size = 2
		_flakes.append({
			"pos": Vector2(rng.randf() * PERIOD.x, rng.randf() * PERIOD.y),
			"size": size,
			"fall": 9.0 + float(size) * 7.0 + rng.randf() * 5.0,
			"wind": 8.0 + float(size) * 9.0,
			"amp": 3.0 + float(size) * 2.6 + rng.randf() * 3.0,
			"period": rng.randf_range(2.4, 6.2),
			"phase": rng.randf() * TAU,
			"alpha": 0.55 + float(size) * 0.14,
			# 눈이 세질수록 더 많이 나온다. 한꺼번에 켜지면 스위치처럼 보인다.
			"at": rng.randf(),
		})


## snow 는 축 값(0~1), view 는 지금 화면이 덮는 월드 사각형이다.
func update(delta: float, snow: float, wind: float, view: Rect2) -> void:
	_elapsed += delta
	_amount = clampf(snow, 0.0, 1.0)
	_wind = wind
	_view = view
	visible = _amount > 0.01
	if not visible:
		return
	for flake in _flakes:
		flake["pos"] += Vector2(float(flake["wind"]) * wind, float(flake["fall"])) * delta
	queue_redraw()


func _draw() -> void:
	for flake in _flakes:
		# 세기 문턱을 넘은 눈만. 문턱 근처에서는 옅게 들어온다 — 툭 나타나면 버그로 읽힌다.
		var lead: float = (_amount - float(flake["at"])) / 0.15
		if lead <= 0.0:
			continue
		# ★ 흔들림은 눈송이마다 진폭도 주기도 위상도 다르다. 이게 없어서 한 몸으로 놀았다.
		var sway: float = float(flake["amp"]) \
			* sin(TAU * _elapsed / float(flake["period"]) + float(flake["phase"]))
		var at := Vector2(
			fposmod(float(flake["pos"].x) + sway, PERIOD.x),
			fposmod(float(flake["pos"].y), PERIOD.y))
		# 월드 격자에서 지금 화면에 걸리는 칸으로 옮긴다
		at += (Vector2((_view.position / PERIOD).floor()) * PERIOD)
		var size := float(flake["size"])
		for tile_x in 2:
			for tile_y in 2:
				var spot := at + Vector2(float(tile_x), float(tile_y)) * PERIOD
				if spot.x + size < _view.position.x or spot.x > _view.end.x:
					continue
				if spot.y + size < _view.position.y or spot.y > _view.end.y:
					continue
				draw_rect(Rect2(spot.floor(), Vector2(size, size)),
					Color(TINT.r, TINT.g, TINT.b,
						float(flake["alpha"]) * minf(lead, 1.0)))
