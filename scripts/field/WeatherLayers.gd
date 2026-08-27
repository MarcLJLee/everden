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
	# ★ 빛줄기 — 구름 사이로 쏟아지는 선형 빛. 빛이 닿는 자리가 화사하게 빛난다.
	#   구름이 **아주 없으면 안 생긴다** — 새어 나올 틈이 있어야 줄기가 된다.
	#   그래서 세기가 구름 중간에서 가장 크다(peak).
	# ★ 빛은 한 겹이면 판때기로 보인다. **같은 타일을 2배로 키운 먼 겹**을 뒤에 깔고
	#   다른 속도로 흘리면 굵기가 섞이고 서로 스쳐 지나가면서 산란처럼 읽힌다 (사용자 지적).
	#   도트는 그대로 한 장이고, 배율은 **정수배** 라 픽셀 규칙도 그대로다.
	{"name": "rays_far", "file": "light_shaft.png", "axis": "cloud", "base": 0.0, "gain": 0.17,
		"drift": Vector2(2.0, 0.6), "wind": 7.0, "from": 0.35, "cover": 0.0,
		"peak": 0.26, "blend": "add", "color": Color(1.0, 0.95, 0.80), "scale": 2,
		"damp": {"rain": 1.0, "fog": 0.6, "snow": 0.8},
		"pulse": {"period": 13.0, "amount": 0.45, "phase": 2.1},
		"phase": Vector2(211.0, 143.0), "daylight": true, "sun_height": true},
	{"name": "rays", "file": "light_shaft.png", "axis": "cloud", "base": 0.0, "gain": 0.30,
		"drift": Vector2(5.0, 1.5), "wind": 18.0, "from": 0.35, "cover": 0.0,
		"peak": 0.26, "blend": "add", "color": Color(1.0, 0.96, 0.82),
		# 안개는 빛줄기를 오히려 **보이게** 한다 (빛이 물방울에 걸려야 줄기가 보인다).
		# 그래서 비만큼 깎지 않는다 — 짙어지면 그때 사라진다.
		"damp": {"rain": 1.0, "fog": 0.6, "snow": 0.8},
		"pulse": {"period": 8.0, "amount": 0.35, "phase": 0.0},
		"phase": Vector2(37.0, 61.0), "daylight": true, "sun_height": true},
	# ★ 햇살 얼룩 — **구름 그림자와 같은 타일**을 위상만 어긋나게 해서 밝게 더한다.
	#   구름 사이로 새는 빛이 땅에 지나가는 그림이라 그림자와 짝이고,
	#   맑을수록 세진다(invert). 새로 그리는 도트가 0 장이고 디더 규칙도 그대로다.
	#   맑은 날이 밝기만 하고 밋밋했던 것을 이것이 메운다.
	{"name": "sun", "file": "cloud_shadow.png", "axis": "cloud", "base": 0.0, "gain": 0.19,
		"drift": Vector2(7.0, 2.0), "wind": 26.0, "from": 0.0, "cover": 0.0,
		"invert": true, "blend": "add", "color": Color(1.0, 0.93, 0.7),
		"damp": {"rain": 1.0, "fog": 1.0, "snow": 0.8},
		"pulse": {"period": 17.0, "amount": 0.2, "phase": 1.3},
		"phase": Vector2(151.0, 97.0), "daylight": true},
	{"name": "cloud", "file": "cloud_shadow.png", "axis": "cloud", "base": 0.06, "gain": 0.34,
		"drift": Vector2(7.0, 2.0), "wind": 26.0, "from": 0.0, "cover": 0.53},
	{"name": "fog", "file": "fog.png", "axis": "fog", "base": 0.0, "gain": 0.72,
		"drift": Vector2(4.0, 1.0), "wind": 10.0, "from": 0.0, "cover": 0.58},
	{"name": "rain", "file": "rain.png", "axis": "rain", "base": 0.0, "gain": 0.85,
		"drift": Vector2(6.0, 260.0), "wind": 150.0, "from": 0.0, "cover": 0.06},
	# 폭우는 별개 날씨가 아니라 rain 이 센 것이다 — 센 겹은 늦게 들어온다
	{"name": "rain_heavy", "file": "rain_heavy.png", "axis": "rain", "base": 0.0, "gain": 0.8,
		"drift": Vector2(10.0, 380.0), "wind": 210.0, "from": 0.55, "cover": 0.20},
	# ★ 눈은 **앞뒤로 겹쳐야** 깊이가 산다. 한 겹이면 창문에 붙은 점으로 보인다.
	#   멀수록 느리고 옅다. 가장 앞 겹은 같은 도트를 2배로 키운 것이라 도트가 늘지 않는다.
	#   ⚠️ 비와 달리 눈은 **바람에 옆으로 밀린다.** 떨어지는 속도보다 바람이 더 크게 먹는다.
	# 눈은 여기 없다 — 낱개가 눈에 보이는 유일한 날씨라 SnowField 가 낱개로 그린다.
]

var _sprites: Array = []
var _elapsed := 0.0


## 이 겹이 지금 얼마나 짙은가. 화면을 덮어버리지 않는지 회귀로 재기 위해 따로 뺐다.
static func alpha_for(spec: Dictionary, axes: Dictionary) -> float:
	var raw: float = clampf(float(axes.get(String(spec["axis"]), 0.0)), 0.0, 1.0)
	# 맑을수록 세지는 겹이 있다 — 햇살은 구름의 반대다
	if bool(spec.get("invert", false)):
		raw = 1.0 - raw
	# 가운데에서 가장 센 겹이 있다 — 빛줄기는 구름이 아주 없어도, 꽉 차도 안 생긴다
	if spec.has("peak"):
		var peak := float(spec["peak"])
		var span: float = peak if raw < peak else maxf(1.0 - peak, 0.01)
		raw = clampf(1.0 - absf(raw - peak) / span, 0.0, 1.0)
	var from: float = float(spec["from"])
	# from 위에서만 들어오는 겹이 있다 (폭우는 비가 센 것이다)
	var strength: float = 0.0 if raw <= from else (raw - from) / maxf(1.0 - from, 0.01)
	var value: float = float(spec["base"]) + strength * float(spec["gain"])
	# ★ **다른 축이 끄는 겹이 있다.** 해가 드는 연출은 구름만 보고 정하면 안 된다 —
	#   비나 안개가 끼면 직사광이 없으므로 빛줄기도 햇살 얼룩도 사라져야 한다 (사용자 지적).
	#   축을 곱해서 끄므로 "비 오는 날씨" 라는 이름을 만들 필요가 없다 (원칙 4).
	#   ⚠️ 선형으로 깎으면 비가 꽤 와도 빛이 남는다. **제곱으로 떨어뜨린다** —
	#      이슬비에는 해가 남고 소나기에는 없다.
	for axis in spec.get("damp", {}):
		var wet: float = clampf(float(axes.get(axis, 0.0)), 0.0, 1.0)
		value *= pow(maxf(1.0 - wet * float(spec["damp"][axis]), 0.0), 2.0)
	return clampf(value, 0.0, 1.0)


## 이 축 묶음에서 겹들이 화면을 덮는 총량. 1 에 가까우면 아무것도 안 보인다.
##
## ⚠️ 알파가 곧 덮개가 아니다 — 타일이 **디더 마스크**라 절반쯤은 구멍이다.
##    cover 는 그 타일이 실제로 칠하는 픽셀 비율이다(재서 적었다).
static func total_cover(axes: Dictionary) -> float:
	var left := 1.0
	for spec in LAYERS:
		left *= 1.0 - alpha_for(spec, axes) * float(spec.get("cover", 1.0))
	return 1.0 - left


## only 에 이름을 주면 그 겹만 만든다. 집은 **맑고 구름이 흐르는 정도**만 하므로
## 구름 그림자와 햇살 얼룩만 쓴다 — 마당에 빛줄기가 쏟아지면 그게 날씨가 된다.
func build(only: Array = []) -> void:
	for spec in LAYERS:
		if not only.is_empty() and not (String(spec["name"]) in only):
			continue
		var path: String = ROOT + String(spec["file"])
		var texture: Texture2D = null
		if ResourceLoader.exists(path):
			texture = load(path)
		elif String(spec["name"]) == "rays":
			# 전용 도트가 아직 없다. 자리채움을 만들어 쓴다 — 파일이 들어오면 그쪽이 이긴다.
			texture = PlaceholderArt.light_shaft_texture()
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		if String(spec.get("blend", "")) == "add":
			var material := CanvasItemMaterial.new()
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			sprite.material = material
		sprite.centered = false
		sprite.scale = Vector2.ONE * float(spec.get("scale", 1))
		sprite.region_enabled = true
		# 타일을 이어 붙이려면 반복을 켜야 한다. 필터는 Nearest 그대로.
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(sprite)
		_sprites.append({"node": sprite, "spec": spec, "travel": Vector2.ZERO})


## view 는 지금 화면이 덮는 월드 사각형이다. 겹은 그 위에 딱 맞춰 놓인다.
## daylight 는 지금 햇빛의 양(0~1)이다. 밤에 햇살 얼룩이 비치면 안 된다.
func update(delta: float, axes: Dictionary, view: Rect2, daylight := 1.0,
		sun_height := 1.0) -> void:
	_elapsed += delta
	var wind := float(axes.get("wind", 0.3))
	for entry in _sprites:
		var spec: Dictionary = entry["spec"]
		var sprite: Sprite2D = entry["node"]
		# ⚠️ 흐른 양은 **더해서 쌓는다.** 예전엔 `속도 × 경과시간` 으로 매번 다시 셌는데,
		#    바람이 변하는 동안 속도가 **경과 시간만큼 뻥튀기**돼서 날씨가 바뀔 때마다
		#    화면이 확 쓸려 갔다 (사용자 지적). 지금 속도만 보고 한 걸음씩 더한다.
		#    보이지 않는 겹도 같이 쌓아야 다시 나타날 때 튀지 않는다.
		var drift: Vector2 = spec["drift"]
		entry["travel"] += (drift + Vector2(float(spec["wind"]) * wind, 0.0)) * delta

		var alpha := alpha_for(spec, axes)
		if bool(spec.get("daylight", false)):
			alpha *= clampf(daylight, 0.0, 1.0)
		# ★ 빛줄기는 **점심 무렵에만** 선다 (사용자 지적). 기둥이 수직에서 27° 라
		#   해가 높이 떠야 나오는 각도다 — 해가 낮게 걸린 시간에 그대로 쏟으면
		#   각도가 거짓말이 된다. 제곱해서 정오 쪽으로 더 몰아준다.
		if bool(spec.get("sun_height", false)):
			alpha *= pow(clampf(sun_height, 0.0, 1.0), 2.0)
		# ★ 빛은 가만히 있지 않는다. 아주 느리게 숨쉬면 판때기가 공기로 바뀐다.
		#   겹마다 주기가 어긋나 있어 서로 맞물렸다 풀리면서 산란처럼 보인다.
		#   ⚠️ 세기만 건드린다 — 무늬를 흔들면 디더가 자글거린다.
		#   ⚠️ alpha_for 는 날씨만 보게 둔다. 시간이 섞이면 회귀가 잴 수 없는 값이 된다.
		if spec.has("pulse"):
			var pulse: Dictionary = spec["pulse"]
			var wave: float = 0.5 - 0.5 * cos(TAU * _elapsed / float(pulse["period"])
				+ float(pulse.get("phase", 0.0)))
			alpha *= 1.0 - float(pulse["amount"]) * wave
		sprite.visible = alpha > 0.01
		if not sprite.visible:
			continue
		var color: Color = spec.get("color", Color.WHITE)
		sprite.modulate = Color(color.r, color.g, color.b, alpha)

		# 위상을 어긋나게 두면 같은 타일이라도 빛과 그림자가 겹치지 않는다
		var travel: Vector2 = entry["travel"] - Vector2(spec.get("phase", Vector2.ZERO))
		# ★ 흔들림은 **쌓지 않는다.** travel 에 더하면 눈이 옆으로 흘러가 버린다 —
		#   제자리에서 오가야 흔들림이다. 겹마다 주기가 어긋나 있어 통째로 안 움직인다.
		if spec.has("sway"):
			var sway: Dictionary = spec["sway"]
			travel.x += float(sway["amount"]) * sin(TAU * _elapsed / float(sway["period"])
				+ float(sway.get("phase", 0.0)))
		# ⚠️ region 을 **빼야** 무늬가 그 방향으로 흐른다.
		#    더하면 텍스처의 아래쪽을 화면 위에서 샘플링하게 되어 비가 위로 올라간다
		#    (실제로 그렇게 만들었다). drift 는 이제 **화면에서 보이는 방향**이다.
		# ⚠️ 정수 픽셀로만. 반픽셀이면 디더가 자글거린다.
		sprite.position = view.position.floor()
		# ⚠️ 키운 겹은 **키운 만큼 좁게 오려야** 같은 넓이를 덮는다.
		#    나눈 뒤에 floor 하므로 화면에서는 여전히 정수 픽셀에 떨어진다.
		var zoom := float(spec.get("scale", 1))
		sprite.region_rect = Rect2(((view.position - travel) / zoom).floor(),
			(view.size / zoom).ceil())
