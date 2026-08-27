## 플레이스홀더 아트 — 전부 색 사각형을 코드로 생성한다. (DEMO-SPEC §3.8)
##
## 손으로 그린 스프라이트를 기다리지 않는다. 레이어 구조·앵커 정렬·북향 숨김·
## 바운스 동기화는 색 사각형으로 전부 검증된다. 재미가 확인된 뒤에 그린다.
##
## 종 id 로 분기하지 않는다. 색은 diet 에서, 크기는 size_class 에서 나온다.
class_name PlaceholderArt
extends RefCounted

const DIET_COLOR := {
	"초식": Color(0.42, 0.66, 0.34),
	"육식": Color(0.72, 0.36, 0.32),
	"잡식": Color(0.78, 0.58, 0.30),
}
const SENSE_COLOR := {
	"후각": Color(0.62, 0.44, 0.28),   # 코
	"청각": Color(0.60, 0.44, 0.78),   # 귀
	"시야": Color(0.36, 0.72, 0.80),   # 눈
}
const EYE_SIZE := {
	"big": Vector2i(3, 3), "round": Vector2i(2, 2), "narrow": Vector2i(2, 1), "dot": Vector2i(1, 1),
}
const MOUTH_SIZE := {
	"wide": Vector2i(3, 1), "small": Vector2i(2, 1), "beak": Vector2i(2, 2),
}
const EYE_COLOR := Color(0.10, 0.09, 0.12)
const MOUTH_COLOR := Color(0.35, 0.22, 0.22)

## 종 정의 하나로 몸통 SpriteFrames 를 만든다.
## 애니메이션: idle / move_side / move_north / move_south (좌우는 flip_h 로 낸다 — §4.5)
static func body_frames(species: Dictionary, canvas: Vector2i) -> SpriteFrames:
	var base := body_color(species)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	# 그려진 종과 같은 집합을 만든다. 하나라도 비면 그 동작에 들어간 순간 터진다.
	for anim in SpriteLibrary.ANIMATIONS:
		frames.add_animation(anim)
		frames.set_animation_loop(anim, true)
		frames.set_animation_speed(anim, 6.0)
	frames.add_frame("idle", _body_texture(canvas, base, 0, false))
	for step in 2:
		frames.add_frame("move_side", _body_texture(canvas, base, step, false))
		frames.add_frame("move_north", _body_texture(canvas, base.darkened(0.18), step, true))
		frames.add_frame("move_south", _body_texture(canvas, base, step, false))
		# 특징 동작 — 색 사각형이라도 유도 중에 뭔가 움직여야 읽힌다
		frames.add_frame("special", _body_texture(canvas, base.lightened(0.12 * step), step, false))
	return frames

## 색은 먹이 유형에서 나오고, 같은 먹이끼리는 id 해시로 색조만 흔든다.
## (종 이름으로 분기하는 것이 아니라 모든 종에 같은 함수를 먹인다)
static func body_color(species: Dictionary) -> Color:
	var base: Color = DIET_COLOR.get(String(species.get("diet", "")), Color(0.6, 0.6, 0.6))
	var jitter := float(String(species.get("id", "")).hash() % 1000) / 1000.0 - 0.5
	return Color.from_hsv(
		fposmod(base.h + jitter * 0.14, 1.0),
		clampf(base.s + jitter * 0.12, 0.2, 1.0),
		clampf(base.v + jitter * 0.10, 0.25, 1.0))

## 몸통 한 장. 걷기 2프레임은 **다리 모양만** 바꾼다 —
## 몸 전체의 오르내림은 Body 노드의 Y가 담당한다. (DEMO-SPEC §3.2)
static func _body_texture(canvas: Vector2i, color: Color, step: int, back_view: bool) -> ImageTexture:
	var img := Image.create_empty(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var torso_top := int(canvas.y * 0.34)
	var leg_top := canvas.y - 3
	img.fill_rect(Rect2i(2, torso_top, canvas.x - 4, leg_top - torso_top), color)
	# 귀 — 실루엣에 실마리를 준다
	var ear := maxi(2, canvas.x / 10)
	img.fill_rect(Rect2i(3, torso_top - ear, ear, ear), color.darkened(0.1))
	img.fill_rect(Rect2i(canvas.x - 3 - ear, torso_top - ear, ear, ear), color.darkened(0.1))
	if back_view:
		img.fill_rect(Rect2i(2, torso_top, canvas.x - 4, 2), color.darkened(0.35))
	# 다리 2프레임
	var leg_w := maxi(2, canvas.x / 8)
	var offset := 0 if step == 0 else leg_w
	var dark := color.darkened(0.28)
	img.fill_rect(Rect2i(3 + offset, leg_top, leg_w, 3), dark)
	img.fill_rect(Rect2i(canvas.x - 3 - leg_w - offset, leg_top, leg_w, 3), dark)
	return ImageTexture.create_from_image(img)

static func eye_texture(style: String) -> ImageTexture:
	return _rect_texture(EYE_SIZE.get(style, Vector2i(2, 2)), EYE_COLOR)

static func mouth_texture(style: String) -> ImageTexture:
	return _rect_texture(MOUTH_SIZE.get(style, Vector2i(2, 1)), MOUTH_COLOR)

## 머리 위 아이콘. 감각별로 색이 다르다 — 코/귀/눈 도트는 나중에 그린다. (tags.json emote_icons)
static func emote_texture(sense: String) -> ImageTexture:
	var color: Color = SENSE_COLOR.get(sense, Color(1, 1, 1))
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(0, 0, 8, 8), Color(1, 1, 1, 0.9))
	img.fill_rect(Rect2i(1, 1, 6, 6), color)
	return ImageTexture.create_from_image(img)

## 그림자는 바운스를 따라가지 않는다 — 발이 땅에서 떨어져 보이는 효과. (DEMO-SPEC §3.2)
static func shadow_texture(width: int) -> ImageTexture:
	var w := maxi(width, 4)
	var h := maxi(3, w / 5)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(w * 0.5, h * 0.5)
	for y in h:
		for x in w:
			var d := Vector2((x + 0.5 - center.x) / center.x, (y + 0.5 - center.y) / center.y)
			if d.length() <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.28))
	return ImageTexture.create_from_image(img)

## 빛줄기 타일 — 구름 사이로 쏟아지는 선형 빛(박명광선). (BRIEF §6.8 이펙트 레이어)
##
## 전용 도트가 아직 없어서 절차적으로 만든다. `weather/light_shaft.png` 가 들어오면
## 그쪽을 쓰고 이것은 안 쓰인다 (WeatherLayers 가 파일을 먼저 본다).
##
## ★ 이어 붙어야 한다 — 띠의 주기가 타일 크기를 나누어떨어져야 경계가 안 보인다.
## ★ 농담은 **4×4 Bayer 디더**로 낸다. 알파 그러데이션은 도트가 아니다 (§6.8 도트 규칙).
const BAYER4 := [
	[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5],
]

static func light_shaft_texture(tile := 512) -> ImageTexture:
	# ★ 두 번 틀렸다. 무엇이 틀렸는지 남겨둔다 —
	#   ① 일정한 사인 격자로 만들었더니 **줄무늬 필터**가 됐다. 박명광선은 규칙적이지 않다.
	#   ② 폭만 제각각으로 바꿨더니 이번엔 **화면 끝까지 이어지는 사선**이 됐고,
	#      각도도 누워서 빛이 쏟아지는 게 아니라 비스듬히 흐르는 무늬로 보였다.
	#
	#   구름 사이로 새는 빛은 **틈에서 시작해 아래로 갈수록 옅어지는, 길이가 있는 기둥**이다.
	#   그래서 폭(u)과 **길이(v)** 를 둘 다 준다. 끝이 있어야 기둥으로 읽힌다.
	#
	#   기울기는 (1,-2) — 수직에서 27° 다. 해가 높이 뜬 낮의 각도라 낮에만 켠다.
	var slope := 2
	# ⚠️ 기둥 길이는 타일보다 길 수 없다. 짧게 잡았더니 **뭉툭한 얼룩**이 됐다 —
	#    v 는 아래로 1px 갈 때 2 씩 줄므로, 세로 230px 을 덮으려면 460 이 필요하다.
	#    그래서 타일이 512 다. 굽는 데 한 번, 그 뒤로는 스크롤만 한다.
	var beams := [
		{"u": 40.0, "w": 26.0, "v": 500.0, "len": 430.0, "power": 1.0},
		{"u": 150.0, "w": 14.0, "v": 380.0, "len": 300.0, "power": 0.6},
		{"u": 250.0, "w": 38.0, "v": 470.0, "len": 460.0, "power": 0.9},
		{"u": 360.0, "w": 18.0, "v": 300.0, "len": 340.0, "power": 0.75},
		{"u": 440.0, "w": 22.0, "v": 200.0, "len": 260.0, "power": 0.5},
	]
	var image := Image.create_empty(tile, tile, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in tile:
		for x in tile:
			# u 는 기둥을 가로지르는 좌표, v 는 기둥을 따라가는 좌표. 둘 다 타일 안에서 이어진다.
			var u := float(posmod(slope * x + y, tile))
			var v := float(posmod(x - slope * y, tile))
			var best := 0.0
			for beam in beams:
				var across := 1e9
				# 타일 경계를 넘는 기둥도 이어지도록 좌우로 한 번씩 감아본다
				for wrap in [-tile, 0, tile]:
					across = minf(across, absf(u - (float(beam["u"]) + wrap)))
				if across > float(beam["w"]):
					continue
				var down := float(beam["v"]) - v
				if down < 0.0:
					down += float(tile)
				if down > float(beam["len"]):
					continue
				var t: float = down / float(beam["len"])
				# 위쪽 8% 는 틈에서 새어 나오는 참이라 부드럽게 밝아지고, 아래로는 길게 옅어진다
				var along: float = smoothstep(0.0, 0.08, t) * pow(1.0 - t, 1.6)
				var wide: float = pow(cos(across / float(beam["w"]) * PI * 0.5), 2.0)
				best = maxf(best, along * wide * float(beam["power"]))
			if best <= 0.02:
				continue
			var threshold: float = (float(BAYER4[y % 4][x % 4]) + 0.5) / 16.0
			if best < threshold:
				continue
			image.set_pixel(x, y, Color(1.0, 0.97 - (1.0 - best) * 0.10,
				0.80 - (1.0 - best) * 0.22, 1.0))
	return ImageTexture.create_from_image(image)


static func _rect_texture(size: Vector2i, color: Color) -> ImageTexture:
	var img := Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
