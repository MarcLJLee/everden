#!/usr/bin/env python3
"""
날씨 레이어 — 맑음 · 흐림 · 비 · 폭우 · 안개 · 눈

§6.8. **팔레트를 건드리지 않는다.** 시간대는 팔레트가, 날씨는 틴트와 오버레이가
담당한다 — 그래야 시간대 × 날씨가 곱셈(4×6=24벌)이 아니라 덧셈이 된다.

    1) 인덱스 아트        한 벌
    2) 팔레트 보간        시간대
    3) 오버레이 틴트      시간대 틴트 × 날씨 틴트
  ★ 3.5) 구름 그림자      곱연산으로 흐른다 — **맑은 날에도 항상 있다**
    4) 이펙트 레이어      빗줄기 · 눈 · 안개 판
    5) 국소 광원          Light2D

★ 구름 그림자가 이 파일의 핵심이다. 날씨가 "없는" 상태를 만들지 않는 장치라,
  맑은 날 화면이 정지 화면처럼 보이는 것을 막는다. 비용은 **타일 한 장**이다.

전부 **이어 붙는(tileable) 타일**로 낸다. 엔진은 스크롤만 하면 된다 —
화면 크기 텍스처를 굽지 않으므로 해상도가 바뀌어도 그대로 쓴다.

⚠️ **디더 마스크는 정수 픽셀로만 스크롤한다.** 반픽셀로 움직이면 디더 무늬가
   자글거려서 도트가 아니라 노이즈로 보인다. (§6.2 Nearest 규칙의 연장)
"""
import os, math, json
from PIL import Image, ImageDraw
import build_bg as G

OUT = os.path.dirname(os.path.abspath(__file__))

# 4×4 Bayer — 도트에서 부드러운 농담을 내는 정석. 알파 그러데이션은 도트가 아니다.
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

def _noise(n, freqs, seed=0):
    """주기 함수의 합 — 타일 경계에서 반드시 이어진다."""
    f = [[0.0]*n for _ in range(n)]
    for k, (fx, fy, amp) in enumerate(freqs):
        px = (seed*7 + k*13) % 17 / 17.0 * 2*math.pi
        py = (seed*11 + k*5) % 19 / 19.0 * 2*math.pi
        for y in range(n):
            sy = math.sin(2*math.pi*fy*y/n + py)
            for x in range(n):
                f[y][x] += amp * math.sin(2*math.pi*fx*x/n + px) * sy
    lo = min(min(r) for r in f); hi = max(max(r) for r in f)
    rng = (hi - lo) or 1.0
    return [[(v - lo)/rng for v in r] for r in f]

def _dither(field, n, gain=1.0, bias=0.0):
    """농담 → 1비트 디더 마스크."""
    m = Image.new("L", (n, n), 0); px = m.load()
    for y in range(n):
        for x in range(n):
            v = min(1.0, max(0.0, field[y][x]*gain + bias))
            if v*16 > BAYER[y % 4][x % 4]: px[x, y] = 255
    return m


# ── 구름 그림자 ───────────────────────────────────────────────────────
CLOUD_N = 320
def cloud_mask(n=CLOUD_N, coverage=0.34, seed=3):
    """하늘의 구름이 땅에 떨어뜨리는 그림자. **가장자리가 디더로 풀려야** 한다 —
    단단한 테두리면 그림자가 아니라 얼룩이다."""
    f = _noise(n, [(1, 1, 1.0), (2, 1, 0.55), (1, 2, 0.5),
                   (3, 2, 0.3), (2, 3, 0.28), (4, 4, 0.16)], seed)
    return _dither(f, n, gain=1.9, bias=coverage - 0.95)


# ── 비 ────────────────────────────────────────────────────────────────
def rain_tile(n=64, count=26, length=9, wind=0.34, seed=1, col=(196, 214, 236)):
    """빗줄기. 타일 밖으로 나간 획은 반대편으로 돌아 들어와 **경계가 안 보인다.**"""
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); px = im.load()
    r = 1103515245*seed + 12345
    for _ in range(count):
        r = (r*1103515245 + 12345) & 0x7fffffff; sx = r % n
        r = (r*1103515245 + 12345) & 0x7fffffff; sy = r % n
        r = (r*1103515245 + 12345) & 0x7fffffff; ln = length + r % 4
        for i in range(ln):
            x = int(sx + i*wind) % n
            y = (sy + i) % n
            a = 160 if i < ln-2 else 90
            px[x, y] = col + (a,)
    return im

def splash(frame):
    """빗방울이 땅에 닿은 자국. 세 프레임이면 튄다."""
    c = G.C(10, 6)
    if frame == 0:
        c.rect(4, 3, 5, 3, G.WL)
    elif frame == 1:
        c.rect(3, 3, 6, 3, G.WM); c.set(2, 2, G.WL); c.set(7, 2, G.WL)
    else:
        c.rect(2, 3, 7, 3, G.WD); c.set(1, 2, G.WM); c.set(8, 2, G.WM)
    return c


# ── 눈 ────────────────────────────────────────────────────────────────
def snow_tile(n=96, count=30, size=1, seed=2, wind=0.5):
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    r = 1103515245*seed + 7
    for _ in range(count):
        r = (r*1103515245 + 12345) & 0x7fffffff; x = r % n
        r = (r*1103515245 + 12345) & 0x7fffffff; y = r % n
        a = 200 if size > 1 else 150
        d.rectangle([x, y, x+size-1, y+size-1], fill=(238, 244, 252, a))
    return im


# ── 빛줄기 (박명광선) ─────────────────────────────────────────────────
# 구름 사이로 쏟아지는 선형 빛. 구현 세션이 `PlaceholderArt.light_shaft_texture()` 로
# 절차적으로 만들어 쓰고 있고, 이 파일이 그 자리를 대신한다.
#
# ★ **이어 붙어야 한다.** 띠의 주기가 타일 크기를 나누어떨어져야 경계가 안 보인다.
#   `tile % period == 0` 이고 `(slope*tile) % period == 0` 이어야 한다.
#   128 / 32 / 2 는 그 조건을 만족한다.
#
# ★ **띠 굵기를 고르게 두면 발이 아니라 창살이 된다.** 실제 박명광선은 굵은 줄기 하나에
#   가는 줄기가 몇 개 붙는다 — 주기 함수의 합으로 굵기를 흐트러뜨리되 주기는 지킨다.
#
# ★ **더하는 빛이다.** 알파로 세기를 주고, 곱연산으로 깔지 않는다.
#   심지는 희고 가장자리는 노랗다 — 햇빛은 가장자리에서 따뜻해진다.
SHAFT_N, SHAFT_PERIOD, SHAFT_SLOPE = 128, 64, 2

def light_shaft(n=SHAFT_N, period=SHAFT_PERIOD, slope=SHAFT_SLOPE):
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); px = im.load()
    for y in range(n):
        for x in range(n):
            ph = ((x + slope*y) % period) / period          # 0~1, 띠 하나
            # 굵기를 흐트러뜨린다 — 주기 1·2·3 의 합이라 경계는 그대로 이어진다
            # ★ 띠가 촘촘하면 박명광선이 아니라 **창살**이다. 주기를 크게 잡고
            #   심지를 좁혀서 **넓은 어둠 사이로 몇 줄기만** 지나가게 한다.
            core = (max(0.0, math.sin(ph*math.pi))**7.0 * 0.95
                    + max(0.0, math.sin(ph*math.pi*2 + 0.9))**14.0 * 0.45
                    + max(0.0, math.sin(ph*math.pi*3 + 2.4))**18.0 * 0.30)
            # 세로로도 아주 느리게 강약을 준다 — 균일한 줄은 창살로 보인다
            core *= 0.70 + 0.30*math.sin(2*math.pi*y/n + 1.1)
            if core <= 0.06: continue
            if core*16 <= BAYER[y % 4][x % 4]: continue     # 4×4 Bayer 디더
            wsp = min(1.0, core)
            px[x, y] = (255, int(248 - (1-wsp)*30), int(204 - (1-wsp)*56), 255)
    return im


# ── 안개 ──────────────────────────────────────────────────────────────
FOG_N = 256
def fog_mask(n=FOG_N, seed=5):
    f = _noise(n, [(1, 1, 1.0), (2, 2, 0.6), (1, 3, 0.4), (3, 1, 0.35)], seed)
    return _dither(f, n, gain=1.5, bias=-0.18)


# ── 날씨는 이름이 아니라 축이다 ───────────────────────────────────────
# 처음엔 맑음·흐림·비·폭우·안개·눈 여섯 **이름**으로 짰다. 그러면 "조금 오는 비" 를
# 표현할 자리가 없다. 이름을 버리고 **축 네 개**로 바꾼다:
#
#   cloud 0~1   구름 그림자의 짙기 — 맑음↔흐림이 이 축이다
#   fog   0~1   안개
#   rain  0~1   비        (폭우는 별개 날씨가 아니라 rain 이 센 것이다)
#   snow  0~1   눈
#   wind  0~1   ★ 하나로 구름 방향 · 빗줄기 기울기 · 눈의 흐름을 **동시에** 정한다.
#               따로 놀면 화면이 어긋나 보인다
#
# 이름(맑음·폭우…)은 이 공간의 **한 점에 붙인 별명**일 뿐이다. 데이터는 축을 들고 있고
# 화면은 축을 읽는다 — 새 날씨를 추가할 때 코드를 안 고친다. 감각 배율(§3.3
# `weather_scale`)도 이름이 아니라 축에 걸어야 "옅은 안개는 조금만 깎인다" 가 된다.
#
# ⚠️ **강도에 상한을 둔다.** 짙은 안개에서 화면이 안 보이면 7살은 그냥 못 논다.
#    아무리 세도 캐릭터 실루엣과 길은 읽혀야 한다 — 날씨는 연출이지 장애물이 아니다.
FOG_MAX, RAIN_MAX, CLOUD_MAX = 0.52, 1.0, 0.46

PRESETS = {
    "맑음":       dict(cloud=0.15, wind=0.30),
    "구름조금":   dict(cloud=0.28, wind=0.38),
    "흐림":       dict(cloud=0.44, fog=0.06, wind=0.46),
    "옅은안개":   dict(cloud=0.12, fog=0.22, wind=0.10),
    "짙은안개":   dict(cloud=0.14, fog=0.52, wind=0.14),
    "가랑비":     dict(cloud=0.26, fog=0.04, rain=0.30, wind=0.26),
    "비":         dict(cloud=0.32, fog=0.06, rain=0.62, wind=0.38),
    "폭우":       dict(cloud=0.46, fog=0.10, rain=1.00, wind=0.66),
    "진눈깨비":   dict(cloud=0.34, fog=0.08, rain=0.22, snow=0.35, wind=0.44),
    "눈":         dict(cloud=0.30, fog=0.10, snow=0.60, wind=0.36),
    "함박눈":     dict(cloud=0.40, fog=0.18, snow=1.00, wind=0.24),
}

def axes(name=None, **kw):
    a = dict(cloud=0.15, fog=0.0, rain=0.0, snow=0.0, wind=0.3)
    if name: a.update(PRESETS[name])
    a.update(kw)
    a["cloud"] = min(CLOUD_MAX, a["cloud"])
    a["fog"] = min(FOG_MAX, a["fog"])
    a["rain"] = min(RAIN_MAX, a["rain"])
    return a

def tint_of(a):
    """틴트를 표로 적지 않고 **축에서 뽑는다.** 그래야 강도가 저절로 따라온다."""
    k = min(1.0, a["cloud"]*0.9 + a["rain"]*0.55 + a["snow"]*0.18 + a["fog"]*0.2)
    return tuple(1.0 + (c - 1.0)*k for c in (0.66, 0.73, 0.88))

_CACHE = {}
def _cached(key, fn):
    if key not in _CACHE: _CACHE[key] = fn()
    return _CACHE[key]

def _scroll(tile, ox, oy, w, h):
    """정수 픽셀로만 민다 — 반픽셀이면 디더가 자글거린다."""
    n = tile.width
    ox, oy = int(ox) % n, int(oy) % n
    out = Image.new(tile.mode, (w + n, h + n), 0 if tile.mode == "L" else (0, 0, 0, 0))
    for y in range(0, h + n, n):
        for x in range(0, w + n, n):
            out.paste(tile, (x, y))
    return out.crop((ox, oy, ox + w, oy + h))

def _alpha(mask, k):
    return mask.point(lambda v: int(v*k))


def apply_weather(im, name=None, t=0.0, **kw):
    """필드 위에 날씨를 얹는다. t 는 흐르는 시간(초).
    구름 그림자는 **캐릭터 위에도 떨어진다** — 땅에만 깔면 필터처럼 보인다."""
    a = axes(name, **kw)
    w, h = im.size
    im = im.convert("RGBA")
    wind = a["wind"]

    tint = tint_of(a)                            # 3) 틴트 — 축에서 나온다
    if tint != (1.0, 1.0, 1.0):
        r, g, b, al = im.split()
        lut = lambda k: [min(255, int(i*k)) for i in range(256)]
        im = Image.merge("RGBA", (r.point(lut(tint[0])), g.point(lut(tint[1])),
                                  b.point(lut(tint[2])), al))

    if a["cloud"] > 0.01:                        # 3.5) 구름 그림자 — 늘 흐른다
        m = _cached("cloud", cloud_mask)
        sh = _scroll(m, t*22*wind + 40, t*7 + 20, w, h)
        layer = Image.new("RGBA", (w, h), (10, 14, 26, 255))
        layer.putalpha(_alpha(sh, a["cloud"]))
        im.alpha_composite(layer)

    if a["fog"] > 0.01:                          # 4) 안개
        m = _cached("fog", fog_mask)
        sh = _scroll(m, t*8*(0.4 + wind) + 10, t*3, w, h)
        layer = Image.new("RGBA", (w, h), (206, 214, 224, 255))
        layer.putalpha(_alpha(sh, a["fog"]))
        im.alpha_composite(layer)
        if a["fog"] > 0.3:                       # 짙어지면 두 겹 — 속도가 다르면 깊어 보인다
            sh2 = _scroll(m, -t*5 + 90, t*2 + 130, w, h)
            l2 = Image.new("RGBA", (w, h), (214, 220, 228, 255))
            l2.putalpha(_alpha(sh2, (a["fog"] - 0.3)*0.7))
            im.alpha_composite(l2)

    if a["rain"] > 0.01:                         # 4) 비 — 강도가 겹 수를 정한다
        r0 = a["rain"]
        layers = [(0.0, 26 + int(r0*30), 8 + int(r0*7), 300 + r0*260,
                   (196, 214, 236))]
        if r0 > 0.5:
            layers.append((0.5, int(r0*44), 10 + int(r0*6), 380 + r0*200,
                           (168, 190, 216)))
        for i, (ph, cnt, ln, spd, col) in enumerate(layers):
            tile = _cached(f"rain{i}{cnt}{ln}",
                           lambda cnt=cnt, ln=ln, i=i, col=col:
                           rain_tile(64, cnt, ln, wind, 1 + i*3, col))
            im.alpha_composite(_scroll(tile, -t*spd*wind - ph*90, t*spd + ph*40, w, h))

    if a["snow"] > 0.01:                         # 4) 눈 — 앞뒤 두 겹
        s0 = a["snow"]
        far = _cached(f"snow_far{int(s0*100)}",
                      lambda: snow_tile(160, int(30 + s0*90), 1, 2))
        near = _cached(f"snow_near{int(s0*100)}",
                       lambda: snow_tile(160, int(10 + s0*34), 2, 6))
        im.alpha_composite(_scroll(far, -t*30*wind, t*(36 + s0*40), w, h))
        im.alpha_composite(_scroll(near, -t*52*wind, t*(64 + s0*60), w, h))
    return im


def save_all():
    d = os.path.join(OUT, "extracted", "weather")
    os.makedirs(d, exist_ok=True)
    day = G.PALETTES["day"]

    def mask_png(m, path, col):
        im = Image.new("RGBA", m.size, col + (255,)); im.putalpha(m)
        im.save(path)

    mask_png(cloud_mask(), os.path.join(d, "cloud_shadow.png"), (10, 14, 26))
    mask_png(fog_mask(), os.path.join(d, "fog.png"), (206, 214, 224))
    rain_tile(64, 26, 9, 0.34, 1).save(os.path.join(d, "rain.png"))
    rain_tile(64, 54, 14, 0.62, 4).save(os.path.join(d, "rain_heavy.png"))
    light_shaft().save(os.path.join(d, "light_shaft.png"))
    snow_tile(96, 26, 1, 2).save(os.path.join(d, "snow_far.png"))
    snow_tile(96, 14, 2, 6).save(os.path.join(d, "snow_near.png"))
    sp = [splash(i) for i in range(3)]
    strip = Image.new("RGBA", (10*3, 6), (0, 0, 0, 0))
    for i, c in enumerate(sp): strip.alpha_composite(c.img(day), (i*10, 0))
    strip.save(os.path.join(d, "splash.png"))

    meta = {
        "_comment": ("날씨는 팔레트를 건드리지 않는다. 시간대 틴트에 **곱해지는** "
                     "틴트 한 겹 + 이어 붙는 오버레이 타일이다 (§6.8)."),
        "layer_order": ["팔레트 보간(시간대)", "오버레이 틴트(시간대×날씨)",
                        "구름 그림자(곱연산)", "이펙트(비·눈·안개)", "국소 광원"],
        "integer_scroll_only": ("디더 마스크는 정수 픽셀로만 스크롤할 것. "
                                "반픽셀이면 디더 무늬가 자글거린다"),
        "cloud_shadow": {"file": "weather/cloud_shadow.png", "tile": CLOUD_N,
                         "blend": "multiply/alpha", "always_on": True,
                         "note": "맑은 날에도 흐른다. 날씨가 '없는' 상태를 만들지 않는다"},
        "fog": {"file": "weather/fog.png", "tile": FOG_N},
        "light_shaft": {
            "file": "weather/light_shaft.png", "tile": SHAFT_N,
            "period": SHAFT_PERIOD, "slope": SHAFT_SLOPE,
            "blend": "add", "when": "낮에만 · 구름이 중간일 때 가장 세다",
            "note": ("구름이 아주 없으면 새어 나올 틈이 없고, 꽉 차면 빛이 못 뚫는다. "
                     "**더하는 빛이라 알파로 세기를 준다** — 곱연산으로 깔지 말 것"),
        },
        "sun_dapple": {
            "reuse": "weather/cloud_shadow.png",
            "note": ("햇살 얼룩은 **구름 그림자와 같은 타일**을 위상만 어긋나게 해 "
                     "밝게 더한 것이다. 구름 사이로 새는 빛이라 그림자와 짝이고 "
                     "새로 그리는 도트가 0장이다 — 구현 세션이 발명했다"),
            "when": "맑을수록 세다 · 낮에만",
        },
        "rain": {"file": "weather/rain.png", "heavy": "weather/rain_heavy.png",
                 "tile": 64, "splash": "weather/splash.png", "splash_frames": 3},
        "snow": {"far": "weather/snow_far.png", "near": "weather/snow_near.png",
                 "tile": 96, "note": "앞뒤 두 겹을 다른 속도로 흘린다"},
        "model": ("날씨는 이름이 아니라 **축**이다. cloud · fog · rain · snow · wind "
                  "각각 0~1. 이름(맑음·폭우…)은 한 점에 붙인 별명일 뿐이다"),
        "axes": ["cloud", "fog", "rain", "snow", "wind"],
        "caps": {"fog": FOG_MAX, "rain": RAIN_MAX, "cloud": CLOUD_MAX,
                 "why": ("강도에 상한을 둔다. 짙은 안개에서 화면이 안 보이면 "
                         "7살은 그냥 못 논다 — 날씨는 연출이지 장애물이 아니다")},
        "tint_from_axes": ("틴트를 표로 적지 않는다. cloud*0.9 + rain*0.55 + "
                           "snow*0.18 + fog*0.2 로 (0.66,0.73,0.88) 쪽으로 당긴다. "
                           "그래야 강도가 저절로 따라온다"),
        "presets": {k: axes(k) for k in PRESETS},
        "wind_note": ("`wind` 하나가 구름 방향 · 빗줄기 기울기 · 눈의 흐름을 "
                      "동시에 정한다. 값이 따로 놀면 화면이 어긋나 보인다"),
        "sense_note": ("§3.3 `weather_scale` 은 이름이 아니라 **축**에 걸 것. "
                       "그래야 '옅은 안개는 시야가 조금만 깎인다' 가 된다"),
        "season_note": "눈은 계절이 생긴 뒤에만 뽑을 것 (§7)",
    }
    with open(os.path.join(d, "weather.json"), "w") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=2)
    print("extracted/weather/ 에 7개 파일 + weather.json")


# ── 검수 산출물 ──────────────────────────────────────────────────────
def _field(u=0.30):
    import present_bg as P
    return P.render_field(u).crop((0, 16, 640, 376)).convert("RGBA")

def gifs():
    """맑은 날 구름 그림자가 흐르는 것 — 이 파일에서 제일 보여주고 싶은 것이다.
    정지 화면으로는 '아무것도 없는 날' 인데, 흐르면 살아 있는 날이 된다."""
    f = _field(0.30)
    for name, fname, span, n in (("맑음", "weather_clouds.gif", 26.0, 28),
                                 ("비", "weather_rain.gif", 1.2, 16),
                                 ("함박눈", "weather_snow.gif", 3.0, 16)):
        frames = [apply_weather(f.copy(), name, t=span*i/n) for i in range(n)]
        g = [x.convert("P", palette=Image.ADAPTIVE, colors=128) for x in frames]
        g[0].save(os.path.join(OUT, fname), save_all=True, append_images=g[1:],
                  duration=110, loop=0, disposal=2)

def sheet():
    from PIL import ImageFont
    def font(sz):
        try: return ImageFont.truetype(
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
        except Exception: return ImageFont.load_default()
    FH, FL, FS = font(30), font(20), font(15)
    BG, INK, DIM, ACC = (26, 31, 38), (238, 232, 222), (150, 158, 168), (233, 164, 65)
    f = _field(0.30)
    PAD, GAP = 34, 16
    cw, ch = 320, 180

    rows = [
        ("구름은 늘 흐른다 — 맑은 날에도", ["맑음", "구름조금", "흐림"],
         "날씨가 '없는' 상태를 만들지 않는다. 구름 그림자 타일 한 장이면 정지 화면이 살아난다"),
        ("비 — 같은 축, 다른 강도", ["가랑비", "비", "폭우"],
         "폭우는 별개 날씨가 아니라 rain 이 센 것이다. 강도가 겹 수·속도·기울기를 함께 올린다"),
        ("안개 · 눈", ["옅은안개", "짙은안개", "함박눈"],
         "짙어져도 길과 실루엣은 읽힌다 — 상한을 둔다. 날씨는 연출이지 장애물이 아니다"),
    ]
    W_ = PAD*2 + cw*3 + GAP*2
    out = Image.new("RGBA", (W_, 160 + len(rows)*(ch + 76)), BG + (255,))
    d = ImageDraw.Draw(out)
    d.text((PAD, 26), "날씨 레이어 — 축 다섯 개", font=FH, fill=INK)
    d.text((PAD, 68), "cloud · fog · rain · snow · wind. 이름은 이 공간의 한 점에 붙인 별명일 뿐이다.",
           font=FS, fill=DIM)
    y = 116
    for title, names, cap in rows:
        d.text((PAD, y), title, font=FL, fill=ACC); y += 28
        for i, nm in enumerate(names):
            im = apply_weather(f.copy(), nm, t=1.4).resize((cw, ch), Image.NEAREST)
            x = PAD + i*(cw + GAP)
            out.alpha_composite(im, (x, y))
            d.rectangle([x, y, x+cw-1, y+ch-1], outline=(58, 64, 74), width=1)
            d.text((x, y + ch + 6), nm, font=FS, fill=DIM)
        y += ch + 26
        d.text((PAD, y), cap, font=FS, fill=DIM); y += 30
    out.crop((0, 0, W_, y + 10)).convert("RGB").save(
        os.path.join(OUT, "weather_sheet.png"))


if __name__ == "__main__":
    save_all(); sheet(); gifs()
    print("weather_sheet.png · weather_clouds.gif · weather_rain.gif · weather_snow.gif")
