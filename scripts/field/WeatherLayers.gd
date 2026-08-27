## 날씨를 화면에 얹는 겹들. (BRIEF §6.8 · weather/weather.json 의 layer_order)
##
##   … 팔레트 보간(시간대) → 오버레이 틴트 → **구름 그림자(곱연산)** → 이펙트(비·안개) → 국소 광원
##
## ★ 구름 그림자가 이 레이어의 핵심이다. **맑은 날에도 흐른다** —
##   날씨가 "없는" 상태를 만들지 않는 장치라, 맑은 화면이 정지 화면처럼 보이는 것을 막는다.
##   땅에만 깔면 필터처럼 보이므로 **캐릭터 위에도 떨어져야 한다** (액터 다음에 그린다).
##
## ★ 전부 이어 붙는 타일이다. 엔진은 스크롤만 한다 — 화면 크기 텍스처를 굽지 않으므로
##   해상도가 바뀌어도 그대로 쓴다.
## ⚠️ **정수 픽셀로만 스크롤한다.** 반픽셀로 움직이면 디더 무늬가 자글거려서
##   도트가 아니라 노이즈로 보인다 (§6.2 Nearest 규칙의 연장).
class_name WeatherLayers
extends Node2D

const ROOT := "res://sprites/extracted/weather/"

## 각 겹이 어떤 축을 읽고 어떻게 흐르는가.
## 바람은 **하나가 구름 방향·빗줄기 기울기를 동시에 정한다** — 따로 놀면 화면이 어긋나 보인다.
## ⚠️ 타일은 전부 **디더 마스크**다 — 구름 그림자는 53%가 거의 검정이고 안개는 57%가 밝은 회색이다.
##   곱연산으로 통째로 깔면 맑은 날에도 화면이 까매진다 (실제로 그렇게 만들었다가 못 볼 화면이 나왔다).
##   세기는 **알파**로 준다. weather.json 의 "multiply/alpha" 에서 alpha 쪽이다.
const LAYERS := [
	{"name": "cloud", "file": "cloud_shadow.png", "axis": "cloud", "base": 0.06, "gain": 0.34,
		"drift": Vector2(9.0, 3.0), "wind": 26.0, "from": 0.0, "cover": 0.53},
	{"name": "fog", "file": "fog.png", "axis": "fog", "base": 0.0, "gain": 0.72,
		"drift": Vector2(4.0, 1.0), "wind": 10.0, "from": 0.0, "cover": 0.58},
	{"name": "rain", "file": "rain.png", "axis": "rain", "base": 0.0, "gain": 0.85,
		"drift": Vector2(-14.0, 260.0), "wind": 150.0, "from": 0.0, "cover": 0.06},
	# 폭우는 별개 날씨가 아니라 rain 이 센 것이다 — 센 겹은 늦게 들어온다
	{"name": "rain_heavy", "file": "rain_heavy.png", "axis": "rain", "base": 0.0, "gain": 0.8,
		"drift": Vector2(-22.0, 380.0), "wind": 210.0, "from": 0.55, "cover": 0.20},
]

var _sprites: Array = []
var _elapsed := 0.0


## 이 겹이 지금 얼마나 짙은가. 화면을 덮어버리지 않는지 회귀로 재기 위해 따로 뺐다.
static func alpha_for(spec: Dictionary, axes: Dictionary) -> float:
	var raw: float = clampf(float(axes.get(String(spec["axis"]), 0.0)), 0.0, 1.0)
	var from: float = float(spec["from"])
	# from 위에서만 들어오는 겹이 있다 (폭우는 비가 센 것이다)
	var strength: float = 0.0 if raw <= from else (raw - from) / maxf(1.0 - from, 0.01)
	return clampf(float(spec["base"]) + strength * float(spec["gain"]), 0.0, 1.0)


## 이 축 묶음에서 겹들이 화면을 덮는 총량. 1 에 가까우면 아무것도 안 보인다.
##
## ⚠️ 알파가 곧 덮개가 아니다 — 타일이 **디더 마스크**라 절반쯤은 구멍이다.
##    cover 는 그 타일이 실제로 칠하는 픽셀 비율이다(재서 적었다).
static func total_cover(axes: Dictionary) -> float:
	var left := 1.0
	for spec in LAYERS:
		left *= 1.0 - alpha_for(spec, axes) * float(spec.get("cover", 1.0))
	return 1.0 - left


func build() -> void:
	for spec in LAYERS:
		var path: String = ROOT + String(spec["file"])
		if not ResourceLoader.exists(path):
			continue
		var sprite := Sprite2D.new()
		sprite.texture = load(path)
		sprite.centered = false
		sprite.region_enabled = true
		# 타일을 이어 붙이려면 반복을 켜야 한다. 필터는 Nearest 그대로.
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(sprite)
		_sprites.append({"node": sprite, "spec": spec})


## view 는 지금 화면이 덮는 월드 사각형이다. 겹은 그 위에 딱 맞춰 놓인다.
func update(delta: float, axes: Dictionary, view: Rect2) -> void:
	_elapsed += delta
	var wind := float(axes.get("wind", 0.3))
	for entry in _sprites:
		var spec: Dictionary = entry["spec"]
		var sprite: Sprite2D = entry["node"]
		var alpha := alpha_for(spec, axes)
		sprite.visible = alpha > 0.01
		if not sprite.visible:
			continue
		sprite.modulate = Color(1, 1, 1, alpha)

		var drift: Vector2 = spec["drift"]
		var travel := drift * _elapsed + Vector2(float(spec["wind"]) * wind * _elapsed, 0.0)
		# ⚠️ 정수 픽셀로만. 반픽셀이면 디더가 자글거린다.
		sprite.position = view.position.floor()
		sprite.region_rect = Rect2((view.position + travel).floor(), view.size.ceil())
