#!/usr/bin/env python3
"""
넓은 필드 + 앰비언트 생물 — 뒷산 냇가

## 왜 앰비언트를 먼저 넣는가

"생태가 얇다" 는 느낌은 **수집종이 적어서가 아니라 잡을 수 없는 생명이 없어서** 온다.
숲이 살아 있어 보이는 것은 나비가 지나가고 물고기가 튀고 개미가 줄지어 가기 때문이지,
잡을 수 있는 동물이 많아서가 아니다.

> **잡을 수 없는 생명이 있어야 세계가 세계다.**
> 보이는 것이 전부 수집 대상이면 숲이 아니라 쇼핑 목록이다.

앰비언트 생물은 **도감에 없고 자리를 안 먹고 데이터도 없다.** 종당 도트 한두 장이라
수집종(§4.5 종당 16장) 대비 **10분의 1도 안 되는 값으로 생태를 열 배로 만든다.**

## 넓은 필드

96×54 타일 (1536×864) — 한 화면의 약 2.4 × 2.4 배. 지형 구역이 여럿 들어가야
"어디로 갈까" 가 생기고, §3.3 의 동료 유도가 의미를 갖는다. 한 화면짜리 필드에서는
유도할 거리가 없다.
"""
import os, math, json
from PIL import Image, ImageDraw
import build_bg as G
import build as A
from build_bg import (C, T, TR, OL, GD, GM, GL, DD, DM, DL,
                      WD, WM, WL, KD, KM, SD, SM, AC)

OUT = os.path.dirname(os.path.abspath(__file__))
MAP_W, MAP_H = 96, 54


# ── 앰비언트 생물 — 잡을 수 없는 것들 ─────────────────────────────────
def butterfly(frame):
    """나비. 날개를 접었다 폈다 두 프레임이면 난다."""
    c = C(10, 8)
    if frame == 0:
        c.ellipse(3.4, 3.4, 2.6, 2.8, AC); c.ellipse(6.6, 3.4, 2.6, 2.8, AC)
        c.ellipse(3.6, 3.2, 1.2, 1.2, GL); c.ellipse(6.4, 3.2, 1.2, 1.2, GL)
    else:
        c.ellipse(4.2, 3.6, 1.4, 3.0, AC); c.ellipse(5.8, 3.6, 1.4, 3.0, AC)
    c.rect(5, 2, 5, 6, KD)
    c.set(4, 1, KD); c.set(6, 1, KD)
    c.outline({AC, GL, KD})
    return c

def dragonfly(frame):
    """잠자리 — 물가에 붙는다. 가로로 긴 날개가 실루엣을 만든다."""
    c = C(14, 8)
    y = 3 if frame == 0 else 4
    c.rect(1, y, 5, y, WL); c.rect(8, y, 12, y, WL)
    c.rect(2, y-1, 5, y-1, WM); c.rect(8, y-1, 11, y-1, WM)
    c.rect(6, 2, 7, 6, WD)
    c.ellipse(6.5, 2, 1.6, 1.4, WM)
    c.outline({WL, WM, WD})
    return c

def fish_jump(frame):
    """물고기가 튀어오른다 — 세 프레임. 물가 타일 위에만 뜬다."""
    c = C(14, 10)
    if frame == 0:
        c.rect(4, 7, 9, 7, WL); c.set(3, 6, WM); c.set(10, 6, WM)
    elif frame == 1:
        c.ellipse(7, 4, 3.0, 1.6, SM); c.blob([(10,3),(11,2),(11,5),(10,4)], SD)
        c.rect(3, 7, 10, 7, WM); c.set(2, 6, WL); c.set(11, 6, WL)
    else:
        c.rect(2, 7, 11, 7, WD); c.set(1, 6, WM); c.set(12, 6, WM)
        c.set(4, 5, WL); c.set(9, 5, WL)
    c.outline({WL, WM, WD, SM, SD})
    return c

def bird_shadow(frame):
    """땅 위를 지나가는 새 그림자. **새를 그리지 않는다** — 하늘은 화면 밖이다.
    그림자만으로 위에 무언가 날고 있다는 게 성립한다.
    색은 외곽선(가장 어두운 칸)으로 찍고 **엔진에서 반투명으로** 얹는다."""
    c = C(22, 12)
    d = 0 if frame == 0 else 2
    for k in range(7):                                   # 벌린 날개
        c.rect(10-k, 4+d+k//3, 11-k+1, 5+d+k//3, OL)
        c.rect(11+k, 4+d+k//3, 12+k, 5+d+k//3, OL)
    c.rect(10, 3+d, 12, 8+d, OL)                         # 몸통
    c.rect(11, 8+d, 12, 9+d, OL)                         # 꼬리
    return c

def ants(frame):
    """개미 행렬. 한 마리가 아니라 **줄**이라야 개미로 보인다."""
    c = C(16, 6)
    for i in range(5):
        x = (i*3 + frame) % 15
        c.set(x, 3, KD); c.set(x, 2, KD)
    return c

def bee(frame):
    """★ 처음엔 나비와 같은 강조색(빨강)으로 찍었더니 **작은 나비**로 보였다.
    벌은 **줄무늬**로 갈린다 — 8px 에서도 가로 줄 두 개면 벌이다."""
    c = C(9, 7)
    c.ellipse(4.5, 4, 2.6, 1.9, DL)
    c.rect(3, 2, 3, 6, KD); c.rect(5, 2, 5, 6, KD)       # 줄무늬 둘
    if frame == 0: c.rect(2, 1, 5, 1, WL)                # 날개
    else: c.rect(3, 0, 7, 0, WL)
    c.outline({DL, KD})
    return c


# 앰비언트는 **어느 지형에 붙는지**만 데이터로 둔다. 종 이름으로 분기하지 않는다.
AMBIENT = {
    "나비":     (butterfly,   2, ["초원", "숲"],        "공중"),
    "잠자리":   (dragonfly,   2, ["물가"],              "공중"),
    "물고기":   (fish_jump,   3, ["물가"],              "수면"),
    "새그림자": (bird_shadow, 2, ["초원", "숲", "바위"], "지면"),
    "개미":     (ants,        3, ["초원", "숲"],        "지면"),
    "벌":       (bee,         2, ["초원"],              "공중"),
}


# ── 넓은 필드 ─────────────────────────────────────────────────────────
def _h(x, y, s=0):
    v = (x*73856093) ^ (y*19349663) ^ (s*83492791)
    return (v ^ (v >> 13)) & 0xffff

def stream_y(x):
    """구불구불한 냇물. 주기 함수라 어디서 잘라도 이어진다."""
    return 30 + math.sin(x*0.075)*7.0 + math.sin(x*0.031 + 1.7)*4.0

def terrain_at(tx, ty):
    """지형 구역 — **한 필드 안에 넷이 다 들어가야** '어디로 갈까' 가 생긴다."""
    sy = stream_y(tx)
    if abs(ty - sy) <= 1.6:  return "물"
    if abs(ty - sy) <= 2.6:  return "물가"
    if ((tx-22)/30.0)**2 + ((ty-12)/13.0)**2 <= 1.0: return "숲"
    if ((tx-74)/24.0)**2 + ((ty-44)/12.0)**2 <= 1.0: return "바위"
    if ((tx-84)/16.0)**2 + ((ty-12)/10.0)**2 <= 1.0: return "숲"
    return "초원"

def build_map():
    m = {}
    for ty in range(MAP_H):
        for tx in range(MAP_W):
            t = terrain_at(tx, ty)
            if t == "물":
                up = terrain_at(tx, ty-1) != "물"
                dn = terrain_at(tx, ty+1) != "물"
                m[(tx, ty)] = ("물", "shore_N" if up else "shore_S" if dn
                               else f"water_{_h(tx,ty,2) % 2}")
            else:
                keys = G.TERRAIN_TILES[t]
                m[(tx, ty)] = (t, keys[_h(tx, ty, 5) % len(keys)])
    return m

def scatter(m, seed=1):
    """프롭·단서·앰비언트를 지형에 맞춰 뿌린다. `PROP_TERRAIN` 을 그대로 읽는다."""
    props, clues, life = [], [], []
    dens = {"숲": 0.20, "초원": 0.055, "물가": 0.10, "바위": 0.13}
    for (tx, ty), (t, _) in m.items():
        if t == "물": continue
        v = _h(tx, ty, seed)
        if (v % 1000)/1000.0 < dens[t]:
            names = G.PROP_TERRAIN[t]
            props.append((names[(v >> 6) % len(names)], tx, ty))
        elif (v % 1000) == 777:
            names = list(G.CLUES)[:6]
            clues.append((names[(v >> 8) % len(names)], tx, ty))
    for name, (fn, nfr, terrs, _) in AMBIENT.items():
        for k in range(46):
            v = _h(k*37 + 11, seed*13 + k, seed + 3)
            tx, ty = v % MAP_W, (v >> 7) % MAP_H
            t = terrain_at(tx, ty)
            if name == "물고기":
                if t != "물": continue
            elif t == "물" or t not in terrs:
                continue
            life.append((name, tx, ty, (v >> 3) % nfr))
    return props, clues, life


def render(u=0.30, weather=None, zoom=1, seed=1, ambient=True):
    pal, tint = G.at_time(u)
    m = build_map()
    im = Image.new("RGBA", (MAP_W*T, MAP_H*T), (0, 0, 0, 255))
    for (tx, ty), (_, key) in m.items():
        im.paste(G.TILES[key].img(pal), (tx*T, ty*T))

    props, clues, life = scatter(m, seed)
    for name, tx, ty in clues:
        im.alpha_composite(G.CLUES[name].img(pal), (tx*T, ty*T))

    draw = []
    def put(img, x, yb, shadow=0):
        if shadow:
            sh = Image.new("RGBA", (img.width, img.height + 4), (0, 0, 0, 0))
            ImageDraw.Draw(sh).ellipse(
                [img.width//2 - shadow//2, img.height - 4,
                 img.width//2 + shadow//2, img.height + 2], fill=(18, 24, 20, 100))
            sh.alpha_composite(img, (0, 0)); img = sh
        draw.append((yb, img, x, yb - img.height))
    for name, tx, ty in props:
        c = G.OBJECTS[name]
        put(c.img(pal), tx*T + (T - c.w)//2, (ty+1)*T, max(6, c.w - 8))
    if ambient:
        for name, tx, ty, fr in life:
            fn, nfr, _, layer = AMBIENT[name]
            c = fn(fr)
            y = (ty+1)*T - (10 if layer == "공중" else 0)
            put(c.img(pal), tx*T, y)
    for _, img, x, y in sorted(draw, key=lambda d: d[0]):
        im.alpha_composite(img, (x, y))

    import present_bg as P
    im = P.apply_tint(im, tint)
    if weather:
        import build_weather as WX
        im = WX.apply_weather(im, weather, t=1.4)
    if zoom != 1:
        im = im.resize((im.width//zoom, im.height//zoom), Image.NEAREST)
    return im


# ── 희귀는 확률이 아니라 조건이다 ─────────────────────────────────────
# "가끔 발견되는 동물" 을 **낮은 확률**로 만들면 두 가지가 깨진다.
#   · 원칙 3 — 확률을 노출하지 않는다. 노출 안 하면 아이는 왜 못 만나는지 모른다
#   · 원칙 6 — 못 만나는 것이 벌이 된다. 백 번 나가도 못 보면 그게 벌이다
#
# 그래서 희귀함을 **조건**으로 만든다. 조건은 아이가 알아낼 수 있는 것이어야 하고,
# **조건을 채우면 반드시 나온다.** 확률이 아니라 **열쇠**다.
#
#   비 온 다음 날 + 물가        → 수달이 나온다
#   짙은 안개 + 새벽 + 숲        → 고라니가 나온다
#   맑은 밤 + 바위              → 삵이 나온다
#
# 이러면 **새 종을 하나도 안 그리고** "가끔 발견되는 동물" 이 생긴다. 도트 0장이다.
# 그리고 §3.6 "관찰로 풀린다" 가 한 겹 더 깊어진다 — 아이가 날씨를 보고 나갈 날을 고른다.
# ★ v3.10 — `when` 은 **배치**가 아니라 **출현** 조건이다 (브리프 §3.11).
#   개체가 거기 있느냐는 필드 진입 시 한 번 정해지고(개체수 0 가능),
#   `when` 은 놓인 개체가 **지금 나와 있는가**를 정한다. 날씨가 바뀌면 다시 본다.
RARE_RULES = [
    {"species": "otter",       "when": {"terrain": "물가", "after_rain": True},
     "hint": "비 온 다음 날 물가에서 봤어요"},
    {"species": "water_deer",  "when": {"terrain": "숲", "daypart": "새벽", "fog": ">0.3"},
     "hint": "안개 낀 새벽 숲에서 봤어요"},
    {"species": "leopard_cat", "when": {"terrain": "바위", "daypart": "밤", "cloud": "<0.2"},
     "hint": "맑은 밤 돌밭에서 봤어요"},
    {"species": "toad",        "when": {"terrain": "물가", "rain": ">0.2"},
     "hint": "비 오는 날 물가에서 봤어요"},
]


def save_all():
    d = os.path.join(OUT, "extracted", "ambient")
    os.makedirs(d, exist_ok=True)
    day = G.PALETTES["day"]
    n = 0
    for name, (fn, nfr, terrs, layer) in AMBIENT.items():
        frames = [fn(i) for i in range(nfr)]
        cw = max(c.w for c in frames); ch = max(c.h for c in frames)
        strip = Image.new("RGBA", (cw*nfr, ch), (0, 0, 0, 0))
        for i, c in enumerate(frames):
            strip.alpha_composite(c.img(day), (i*cw + (cw-c.w)//2, ch-c.h))
        strip.save(os.path.join(d, f"{name}.png")); n += nfr

    meta = {
        "_comment": ("앰비언트 생물 — **수집 대상이 아니다.** 도감에 없고 자리를 안 먹고 "
                     "상호작용도 없다. 보이는 것이 전부 수집 대상이면 숲이 아니라 쇼핑 목록이다."),
        "creatures": {name: {"file": f"ambient/{name}.png", "frames": nfr,
                             "frame_w": max(fn(i).w for i in range(nfr)),
                             "terrain": terrs, "layer": layer}
                      for name, (fn, nfr, terrs, layer) in AMBIENT.items()},
        "layers": {"공중": "Y-sort 밖. 지면보다 10px 위에 그린다",
                   "수면": "물 타일 위에만",
                   "지면": "Y-sort 대상"},
        "bird_shadow_note": ("새를 그리지 않는다 — 하늘은 화면 밖이다. 그림자는 "
                             "외곽선 색으로 찍혀 있으니 **반투명으로 얹을 것**"),
        "field": {"tiles": [MAP_W, MAP_H], "px": [MAP_W*T, MAP_H*T],
                  "screens": round(MAP_W*T/640, 1),
                  "note": "지형 넷이 한 필드 안에 들어가야 동료 유도(§3.3)가 의미를 갖는다"},
        "rare": {
            "model": "정의 · 출현 · 발견은 다른 시점이다 (브리프 §3.11, v3.10)",
            "stages": {
                "정의": ("필드 진입 시 **한 번**. 이번 원정의 개체 수 분포가 여기서 끝난다. "
                        "**개체수 0 은 정상** — 오늘 이 필드에 없다는 뜻이고 다음 원정에 다시 굴린다"),
                "출현": ("**날씨가 바뀔 때마다** 다시 정한다. 놓인 개체 중 지금 누가 나와 있는가. "
                        "개체를 빼앗지 않는다 — 안 보이는 것은 지금 안 나와 있을 뿐이다(원칙 2)"),
                "발견": "플레이의 몫 — 동료 감각(§3.3) · 단서(§5.4) · 관찰(§3.6)",
            },
            "rules_are": "출현 조건이다. 배치 조건이 아니다",
            "rules": RARE_RULES,
            "no_zero_gate": ("어떤 날씨에도 나와 있는 종이 늘 있어야 한다 — 기다림을 강요하지 않는다. "
                             "개체수 0 은 이 규칙과 다른 층이다"),
            "transition": ("깜빡이면 안 된다. 축 값이 서서히 움직이고 하늘·소리·구름 그림자가 먼저 알린다. "
                           "이미 교감 중인 개체는 날씨가 바뀌어도 사라지지 않는다"),
            "why": "새 종을 그리지 않고 '가끔 발견되는 동물' 을 만든다 — 도트 0장"},
    }
    with open(os.path.join(d, "ambient.json"), "w") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=2)
    print(f"extracted/ambient/ 에 {len(AMBIENT)}개 스트립({n}프레임) + ambient.json")


def sheet():
    from PIL import ImageFont
    def font(sz):
        try: return ImageFont.truetype(
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
        except Exception: return ImageFont.load_default()
    FH, FL, FS = font(30), font(20), font(15)
    BG, INK, DIM, ACC = (26, 31, 38), (238, 232, 222), (150, 158, 168), (233, 164, 65)
    day = G.PALETTES["day"]
    PAD = 34
    W_ = 800
    out = Image.new("RGBA", (W_, 1500), BG + (255,))
    d = ImageDraw.Draw(out)
    d.text((PAD, 26), "넓은 필드 + 앰비언트 생물", font=FH, fill=INK)
    d.text((PAD, 68), "잡을 수 없는 생명이 있어야 세계가 세계다 — 보이는 것이 전부 수집 대상이면 쇼핑 목록이다.",
           font=FS, fill=DIM)

    y = 112
    d.text((PAD, y), f"필드 {MAP_W}×{MAP_H} 타일 = {MAP_W*T}×{MAP_H*T}px · 한 화면의 2.4 × 2.4 배",
           font=FL, fill=ACC); y += 30
    ov = render(0.30, zoom=2)
    ov = ov.resize((W_ - PAD*2, int((W_ - PAD*2) * ov.height / ov.width)), Image.NEAREST)
    out.alpha_composite(ov, (PAD, y))
    d.rectangle([PAD, y, PAD+ov.width-1, y+ov.height-1], outline=(58, 64, 74), width=1)
    y += ov.height + 8
    d.text((PAD, y), "지형 넷이 한 필드 안에 있다 — 숲 · 냇물 · 초원 · 돌밭. 한 화면짜리 필드에서는 유도할 거리가 없다.",
           font=FS, fill=DIM); y += 34

    d.text((PAD, y), "실제 화면 (1:1)", font=FL, fill=ACC); y += 30
    cw2 = (W_ - PAD*2 - 16)//2
    for i, (box, wx) in enumerate((((300, 180, 940, 540), None),
                                   ((520, 300, 1160, 660), "가랑비"))):
        cimg = render(0.30, weather=wx).crop(box)
        cimg = cimg.resize((cw2, int(cw2*360/640)), Image.NEAREST)
        out.alpha_composite(cimg, (PAD + i*(cw2+16), y))
    y += int(cw2*360/640) + 30

    d.text((PAD, y), "앰비언트 — 도감에 없고 자리를 안 먹는다", font=FL, fill=ACC); y += 30
    CW3 = (W_ - PAD*2)//3
    for i, (name, (fn, nfr, terrs, layer)) in enumerate(AMBIENT.items()):
        cx = PAD + (i % 3)*CW3
        cy = y + (i // 3)*70
        x = cx
        for k in range(nfr):
            im2 = fn(k).img(day, 3)
            out.alpha_composite(im2, (x, cy + 40 - im2.height)); x += im2.width + 6
        d.text((cx, cy + 46), f"{name} · {'·'.join(terrs)}", font=FS, fill=DIM)
    y += 70*((len(AMBIENT)+2)//3) + 16

    d.text((PAD, y), "희귀는 확률이 아니라 조건이다", font=FL, fill=ACC); y += 28
    d.text((PAD, y), "조건을 채우면 반드시 나온다. 새 종을 하나도 안 그리고 '가끔 발견되는 동물' 이 생긴다 — 도트 0장.",
           font=FS, fill=DIM); y += 26
    NAME = {"otter": "수달", "water_deer": "고라니", "leopard_cat": "삵", "toad": "두꺼비"}
    for r in RARE_RULES:
        d.text((PAD + 10, y), NAME[r["species"]], font=FS, fill=INK)
        d.text((PAD + 90, y), r["hint"], font=FS, fill=ACC); y += 22
    y += 24

    d.text((PAD, y), "수집종을 더 늘리기 전에 — 장수 계산", font=FL, fill=ACC); y += 28
    for line, col in (
        ("지금 11종. 완전한 것은 개·고양이·청설모 셋뿐 (48장).", DIM),
        ("나머지 여덟 종은 측면 대기 한 장씩 — 남은 빚이 8 × 15 = 120장이다.", DIM),
        ("새 수집종 하나 = 16장 ≈ 일주일. 세 종을 더하면 48장이 더 쌓인다.", INK),
        ("앰비언트 여섯 종은 전부 합쳐 14장이었다 — 생태 체감의 대부분이 여기서 온다.", ACC)):
        d.text((PAD + 10, y), line, font=FS, fill=col); y += 24
    out.crop((0, 0, W_, y + 20)).convert("RGB").save(
        os.path.join(OUT, "field_sheet.png"))


if __name__ == "__main__":
    save_all(); sheet()
    print("field_sheet.png")
