#!/usr/bin/env python3
"""
타이틀 화면 · 메뉴 · 확인 창 — 640×360 실제 픽셀

배경은 **켤 때마다 바뀐다.** 지형을 무작위로 고르고 **그 지형에 사는 동물**을 세운다 —
지형은 `habitat`, 시간대는 `activity` 에서 나온다. 정지 일러스트를 그리지 않는다.

**타이틀 화면 자체가 단서다.** 글로 "얘는 숲에 살아요" 라고 알려주는 대신 숲을 깔고
청설모를 세운다. 아이는 읽는 게 아니라 본다 — §3.6 "관찰로 풀린다" 를 게임에
들어가기 전에 한 번 하는 셈이고, 글을 못 읽어도 통한다.

메뉴 문구는 영문, **확인 창은 한글이다.** 되돌릴 수 없는 동작(세이브 덮어쓰기,
종료)만은 첫 플레이어가 읽을 수 있는 자리에 있어야 한다 — 7살은 EXIT 를 못 읽는다.

글자:
  · 로고(RUN II · EVERDEN)는 14×18 손도트. `build_logo.py` 와 같은 격자다.
  · 메뉴는 5×7 비트맵 폰트를 여기서 만든다. 필요한 글자가 14자뿐이라 폰트를
    끌어오는 것보다 싸고, 로고와 같은 손맛이 난다.
  · **한글은 갈무리 11 (OFL 1.1).** 11px 로 찍고 정수배로만 키운다 — `fonts/README.md`.
"""
import os, math, io
from PIL import Image, ImageDraw, ImageFont
import build_logo as L
import present_bg as P
import build_bg as G

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = L.W, L.H

INK      = (240, 236, 226)      # 선택된 항목
INK_DIM  = (150, 146, 138)      # 선택되지 않은 항목
INK_OFF  = (92, 90, 86)         # 고를 수 없는 항목
SHADOW   = (10, 12, 14)
ACCENT   = (233, 178, 96)       # 타이틀 · 커서
PANEL    = (26, 24, 30)
PANEL_ED = (108, 100, 92)


# ── 5×7 비트맵 폰트 ───────────────────────────────────────────────────
FONT5 = {
 "A":"01110/10001/10001/11111/10001/10001/10001",
 "B":"11110/10001/10001/11110/10001/10001/11110",
 "C":"01111/10000/10000/10000/10000/10000/01111",
 "D":"11110/10001/10001/10001/10001/10001/11110",
 "E":"11111/10000/10000/11110/10000/10000/11111",
 "F":"11111/10000/10000/11110/10000/10000/10000",
 "G":"01110/10001/10000/10111/10001/10001/01111",
 "H":"10001/10001/10001/11111/10001/10001/10001",
 "I":"11111/00100/00100/00100/00100/00100/11111",
 "J":"00111/00010/00010/00010/00010/10010/01100",
 "K":"10001/10010/10100/11000/10100/10010/10001",
 "L":"10000/10000/10000/10000/10000/10000/11111",
 "M":"10001/11011/10101/10101/10001/10001/10001",
 "N":"10001/11001/10101/10011/10001/10001/10001",
 "O":"01110/10001/10001/10001/10001/10001/01110",
 "P":"11110/10001/10001/11110/10000/10000/10000",
 "Q":"01110/10001/10001/10001/10101/10010/01101",
 "R":"11110/10001/10001/11110/10100/10010/10001",
 "S":"01111/10000/10000/01110/00001/00001/11110",
 "T":"11111/00100/00100/00100/00100/00100/00100",
 "U":"10001/10001/10001/10001/10001/10001/01110",
 "V":"10001/10001/10001/10001/10001/01010/00100",
 "W":"10001/10001/10001/10101/10101/11011/01010",
 "X":"10001/10001/01010/00100/01010/10001/10001",
 "Y":"10001/10001/01010/00100/00100/00100/00100",
 "Z":"11111/00010/00100/00100/01000/10000/11111",
 "0":"01110/10011/10101/10101/10101/11001/01110",
 "1":"00100/01100/00100/00100/00100/00100/01110",
 "2":"01110/10001/00001/00110/01000/10000/11111",
 "3":"11111/00010/00100/00010/00001/10001/01110",
 "4":"00010/00110/01010/10010/11111/00010/00010",
 "5":"11111/10000/11110/00001/00001/10001/01110",
 "6":"00110/01000/10000/11110/10001/10001/01110",
 "7":"11111/00001/00010/00100/01000/01000/01000",
 "8":"01110/10001/10001/01110/10001/10001/01110",
 "9":"01110/10001/10001/01111/00001/00010/01100",
 ".":"00000/00000/00000/00000/00000/01100/01100",
 "-":"00000/00000/00000/01110/00000/00000/00000",
 "/":"00001/00010/00010/00100/01000/01000/10000",
 "!":"00100/00100/00100/00100/00100/00000/00100",
 " ":"00000/00000/00000/00000/00000/00000/00000",
}
FW, FH, ADV = 5, 7, 6

def text_mask(s):
    s = s.upper()
    m = Image.new("L", (max(1, len(s)*ADV - 1), FH), 0); px = m.load()
    for i, ch in enumerate(s):
        rows = FONT5.get(ch, FONT5[" "]).split("/")
        for y, r in enumerate(rows):
            for x, v in enumerate(r):
                if v == "1": px[i*ADV + x, y] = 255
    return m

def draw_text(im, s, x, y, col, scale=2, shadow=True):
    """1px 그림자를 깐다 — 필드 위에 얹으면 그림자 없이는 글자가 배경에 먹힌다."""
    m = text_mask(s)
    for (dx, dy, c) in (((1, 1, SHADOW),) if shadow else ()) + ((0, 0, col),):
        layer = Image.new("RGBA", m.size, (0, 0, 0, 0))
        layer.paste(Image.new("RGBA", m.size, c + (255,)), (0, 0), m)
        layer = layer.resize((m.width*scale, m.height*scale), Image.NEAREST)
        im.alpha_composite(layer, (x + dx*scale, y + dy*scale))
    return m.width*scale

def text_w(s, scale=2):
    return (len(s)*ADV - 1) * scale


# ── EVERDEN — 게임 타이틀 ────────────────────────────────────────────
# ★ 처음엔 제작사 로고(`build_logo.py`)와 **같은 14×18 격자**로 찍었다. 그래서
#   심심했다 — 제작사 로고는 절제해야 하고 게임 타이틀은 정반대여야 하는데
#   둘을 같은 옷으로 입혔으니 타이틀이 로고처럼 보였다.
#
#   타이틀은 따로 간다:
#     · 16×20 격자, 획 4px    — 훨씬 두껍다
#     · 세로 그러데이션        — 위가 금색, 아래가 호박색
#     · 윗변 1px 하이라이트    — 도트 타이틀의 입체감은 여기서 나온다
#     · 오른쪽 아래로 돌출     — 판이 두꺼워 보인다
#     · 글자마다 1~2px 흔들림  — 반듯하면 회사 로고고, 흔들리면 놀이다
#     · 발밑에 풀·꽃, 글자 위에 고양이 — 화면에 심는다. 떠 있으면 스티커다
TW, TH, TS = 16, 20, 4          # 폭 · 높이 · 획

GRAD    = [(255, 232, 158), (250, 206, 96), (238, 168, 62), (206, 128, 48)]
T_HI    = (255, 248, 214)       # 윗변
T_EDGE  = (26, 18, 16)          # 외곽선
T_DROP  = (92, 52, 34)          # 돌출면

def _tm(): return L._mask(TW, TH)
def _r(d, x0, y0, x1, y1): d.rectangle([x0, y0, x1, y1], fill=255)

def _t_E():
    m = _tm(); d = ImageDraw.Draw(m)
    _r(d, 0, 0, TS-1, TH-1)
    _r(d, 0, 0, TW-1, TS-1)
    _r(d, 0, 8, TW-5, 11)
    _r(d, 0, TH-TS, TW-1, TH-1)
    return m

def _t_V():
    """양팔이 바닥에서 **만나야** V 다. 4px 만 좁히면 U 로 읽힌다 — 한 번 겪었다."""
    m = _tm(); px = m.load()
    for y in range(TH):
        o = (y*6)//(TH-1)                        # 0 → 6, 바닥에서 두 팔이 겹친다
        for k in range(TS):
            px[o+k, y] = 255
            px[TW-1-o-k, y] = 255
    return m

def _t_R():
    m = _tm(); d = ImageDraw.Draw(m)
    _r(d, 0, 0, TS-1, TH-1)
    _r(d, 0, 0, TW-TS-1, TS-1)
    _r(d, TW-TS, 0, TW-1, 11)
    _r(d, 0, 8, TW-1, 11)
    for i in range(TH-12):                       # 다리
        x = 7 + (i*5)//(TH-13)
        _r(d, x, 12+i, min(x+TS-1, TW-1), 12+i)
    return m

def _t_D():
    m = _tm(); d = ImageDraw.Draw(m)
    _r(d, 0, 0, TS-1, TH-1)
    _r(d, 0, 0, TW-TS-1, TS-1)
    _r(d, 0, TH-TS, TW-TS-1, TH-1)
    _r(d, TW-TS, 2, TW-1, TH-3)
    return m

def _t_N():
    m = _tm(); d = ImageDraw.Draw(m)
    _r(d, 0, 0, TS-1, TH-1)
    _r(d, TW-TS, 0, TW-1, TH-1)
    for y in range(TH):
        x = TS + (y*(TW-3*TS))//(TH-1)
        _r(d, x, y, x+TS-1, y)
    return m

T_GLYPH = {"E": _t_E, "V": _t_V, "R": _t_R, "D": _t_D, "N": _t_N}
# 무작위로 흔들면 실수처럼 보인다. 가운데가 살짝 뜨는 완만한 아치라야
# 의도한 것으로 읽힌다 — 현수막처럼.
BOB     = {0: 1, 1: -1, 2: -2, 3: -2, 4: -2, 5: -1, 6: 1}

def _edge(m, dx, dy):
    """마스크를 (dx,dy) 만큼 민 것을 빼서 한쪽 가장자리 1px 만 남긴다."""
    from PIL import ImageChops
    sh = L._mask(m.width, m.height); sh.paste(m, (dx, dy), m)
    return ImageChops.subtract(m, sh)

def title_mark(word="EVERDEN", scale=3):
    adv = TW + 5          # 돌출이 3px 나가므로 3px 간격이면 옆 글자와 붙는다
    dw = len(word)*adv - 5
    lift = 2                                     # 위로 뜨는 글자 여유
    dh = TH + lift + 1
    m = L._mask(dw, dh)
    for i, ch in enumerate(word):
        g = T_GLYPH[ch]()
        m.paste(g, (i*adv, lift + BOB[i]), g)

    pad = 4                                      # 외곽선 + 돌출
    size = (dw + pad, dh + pad)
    im = Image.new("RGBA", size, (0, 0, 0, 0))

    def stamp(mask, col, at):
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        layer.paste(Image.new("RGBA", mask.size, col + (255,)), at, mask)
        im.alpha_composite(layer)

    # 1) 오른쪽 아래 돌출 — 외곽선까지 함께 밀어야 두께로 읽힌다
    drop = L._mask(dw+2, dh+2)
    for dx in (0, 1, 2):
        for dy in (0, 1, 2): drop.paste(m, (dx, dy), m)
    stamp(drop, T_EDGE, (2, 2))
    stamp(m, T_DROP, (3, 3))

    # 2) 외곽선
    ol = L._mask(dw+2, dh+2)
    for dx in (0, 1, 2):
        for dy in (0, 1, 2): ol.paste(m, (dx, dy), m)
    stamp(ol, T_EDGE, (0, 0))

    # 3) 세로 그러데이션
    for i, col in enumerate(GRAD):
        band = m.copy()
        y0 = (dh*i)//len(GRAD); y1 = (dh*(i+1))//len(GRAD)
        bd = ImageDraw.Draw(band)
        if y0: bd.rectangle([0, 0, dw, y0-1], fill=0)
        bd.rectangle([0, y1, dw, dh], fill=0)
        stamp(band, col, (1, 1))

    # 4) 윗변 하이라이트 · 아랫변 그늘
    stamp(_edge(m, 0, -1), T_HI, (1, 1))
    stamp(_edge(m, 0, 1), (176, 106, 44), (1, 1))

    return im.resize((size[0]*scale, size[1]*scale), Image.NEAREST)


# ── 타이틀을 화면에 심는다 ───────────────────────────────────────────
# ── 타이틀 옆에 앉는 동무 — 켤 때마다 바뀐다 ─────────────────────────
# 풀은 **`data/animals.json` 의 모든 종 × 모든 성장 단계**다. 종을 여기 적지 않는다.
# `growth[]` 가 이미 baby/adult 와 `sprite_set` 이름을 들고 있으므로 데이터에서 뽑는다 —
# 종을 하나 추가하면 타이틀 풀도 저절로 늘어난다. §"종 이름으로 분기하지 않는다".
#
# ⚠️ 지금 실제로 그려진 것은 **개·고양이·청설모의 성체 셋뿐**이다. 아기 스프라이트는
#    아직 한 장도 없다(§4.5 는 종당 아기 6장을 잡아뒀다). 그래서 풀은 22칸인데
#    그릴 수 있는 것은 3칸이고, 나머지는 `available: false` 로 나간다.
import json as _json

def species_pool():
    path = os.path.join(os.path.dirname(OUT), "data", "animals.json")
    with io.open(path, encoding="utf-8") as fp:
        sp = _json.load(fp)["species"]
    out = []
    for a in sp:
        for g in a.get("growth", []):
            out.append({"species": a["id"], "name": a["name"],
                        "stage": g["stage"], "sprite_set": g.get("sprite_set")})
    return out

# 그려져 있는 것 — (종, 단계) → (프레임 키, 팔레트들)
RENDERABLE = {
    ("dog", "adult"):      ("dog_idle", ["dog_default", "dog_cream", "dog_black"]),
    ("cat", "adult"):      ("cat_sit",  ["cat_default", "cat_ginger", "cat_black"]),
    ("squirrel", "adult"): ("sq_idle",  ["squirrel_default", "squirrel_rare"]),
}

def _frame(key):
    import build as A
    return {"dog_idle": lambda: A.dog_side(0, "idle"),
            "cat_sit":  lambda: A.cat_special(0),
            "sq_idle":  lambda: A.squirrel_side(0, "idle")}[key]()

# 렌더 가능한 조합을 펼친 것 — 시안에서 `companion=n` 으로 고른다
VARIANTS = [(sp, st, pal, key)
            for (sp, st), (key, pals) in RENDERABLE.items() for pal in pals]
DEFAULT_COMPANION = 0          # 첫 실행 — 시작 동무는 개다 (VARIANTS[0])

def _companion_image(idx):
    import build as A
    sp, st, pal, key = VARIANTS[idx % len(VARIANTS)]
    im = _frame(key).to_image(A.PALETTES[pal])
    return im.resize((im.width*2, im.height*2), Image.NEAREST)


BLOCK_PAD = 40
TITLE_Y   = 46          # 화면에서 타이틀 워드마크의 윗변

def title_props(scale=3):
    """글자 발밑의 풀·꽃. 동무와 분리해 둬야 엔진이 동무만 갈아끼운다."""
    mark_w, mark_h = title_mark(scale=scale).size
    im = Image.new("RGBA", (mark_w + BLOCK_PAD*2, mark_h + 46), (0, 0, 0, 0))
    day = G.PALETTES["day"]
    base = mark_h - 8
    for (n, x) in (("tuft", 8), ("flowers", 84), ("tuft", 168),
                   ("mushroom", 246), ("tuft", 318), ("pebbles", 392),
                   ("flowers", 452)):
        c = G.OBJECTS[n].img(day)
        c = c.resize((c.width*2, c.height*2), Image.NEAREST)
        im.alpha_composite(c, (BLOCK_PAD + x, base + 26 - c.height))
    return im


# ── 동무 이름표 ──────────────────────────────────────────────────────
# **이름만 적는다.** 사는 곳은 배경이 이미 말하고 있다 — 숲을 깔고 청설모를 세웠으면
# 그 위에 "숲에 살아요" 를 또 쓰는 것은 그림으로 읽는 법을 뺏는 것이다.
# 못 만난 종도 이름은 보여준다. "???" 보다 "너구리" 가 훨씬 세게 당긴다 —
# 아이가 이름을 부를 수 있으니까.
#
# 마우스에서만 얻을 수 있는 정보를 만들지 않는다. 기본 조작은 WASD/패드다(§6.4).
# 이름표는 마우스를 올리면 즉시, 아무것도 안 하면 2초 뒤에 뜬다 — 마우스는 더 빠를 뿐이다.
LABEL_IDLE_MS = 2000

def _species_row(sp):
    with io.open(os.path.join(os.path.dirname(OUT), "data", "animals.json"),
                 encoding="utf-8") as fp:
        return next(x for x in _json.load(fp)["species"] if x["id"] == sp)

def companion_label(idx, scale=2):
    """**이름만 적는다.** 사는 곳은 배경이 이미 말하고 있다 —
    글로 또 쓰면 그림으로 읽는 법을 안 배운다."""
    sp, st, _, _ = VARIANTS[idx % len(VARIANTS)]
    info = next(c for c in species_pool() if c["species"] == sp and c["stage"] == st)
    name = info["name"] + (" 아기" if st == "baby" else "")

    pw, ph = 116, 30
    im = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, pw-1, ph-1], fill=(18, 18, 24, 205))
    d.rectangle([0, 0, pw-1, ph-1], outline=(96, 90, 84, 255), width=1)
    ktext(im, name, pw//2, 6, INK, scale=scale)
    return im


def title_block(scale=3, companion=DEFAULT_COMPANION):
    """워드마크만 얹으면 공중에 뜬 스티커로 보인다. 발밑에 풀·꽃을 겹치고
    옆에 동무를 앉힌다 — 전부 이미 있는 스프라이트다. 새로 그린 것 없다."""
    mark = title_mark(scale=scale)
    pad = 40
    im = Image.new("RGBA", (mark.width + pad*2, mark.height + 46), (0, 0, 0, 0))
    im.alpha_composite(mark, (pad, 0))

    day = G.PALETTES["day"]
    base = mark.height - 8                       # 글자 아랫변
    def prop(name, x, y, s=2):
        c = G.OBJECTS[name].img(day)
        c = c.resize((c.width*s, c.height*s), Image.NEAREST)
        im.alpha_composite(c, (x, y - c.height))

    for (n, x) in (("tuft", 8), ("flowers", 84), ("tuft", 168),
                   ("mushroom", 246), ("tuft", 318), ("pebbles", 392),
                   ("flowers", 452)):
        prop(n, pad + x, base + 26)

    # 글자 위에 올리면 잘려 보인다 — 마지막 글자 **옆**, 풀밭에 앉힌다.
    # 발이 풀선에 닿아야 하므로 아래를 기준으로 붙인다 (종마다 키가 다르다).
    c = _companion_image(companion)
    im.alpha_composite(c, (pad + mark.width - 24, base + 40 - c.height))
    return im


# ── 배경 — 지형을 무작위로 고르고, 거기 사는 동물을 세운다 ───────────
# **타이틀 화면 자체가 단서다.** 글로 "얘는 숲에 살아요" 라고 알려주는 대신,
# 숲을 깔고 그 위에 청설모를 세운다. 아이는 읽는 게 아니라 **본다** —
# §3.6 "관찰로 풀린다" 를 타이틀에서 먼저 한 번 하는 셈이다.
#
# 짝은 반드시 **지형 → 그 지형에 사는 종** 이어야 한다. 수달이 초원에 서 있으면
# 틀린 것을 가르친다. `habitat` 태그에서 뽑으므로 어긋날 수가 없다.
#
# 시간대도 `activity` 에서 나온다 — 야행성 너구리는 밤 배경에 선다.
# 어디에 있는지와 언제 나오는지가 둘 다 그림으로 들어간다. 새로 그릴 것은 없다.
DAYPART_BY_ACTIVITY = {"주행성": 0.30, "야행성": 0.86, "박명성": 0.62}
MAP_W, MAP_H = 40, 23           # 640 × 368 → 가운데를 360 으로 자른다

def _h(a, b, c=0):
    v = (a*73856093) ^ (b*19349663) ^ (c*83492791)
    return (v ^ (v >> 13)) & 0xffff

def terrain_field(terrain, u=0.30, seed=0):
    pal, tint = G.at_time(u)
    tiles = G.TERRAIN_TILES[terrain]
    full_h = MAP_H*G.T
    im = Image.new("RGBA", (W, full_h), (0, 0, 0, 255))

    water_top = None
    if terrain == "물가":                    # 물가는 물이 보여야 물가다
        water_top = 13 + _h(seed, 7) % 3
    for y in range(MAP_H):
        for x in range(MAP_W):
            if water_top is not None and y >= water_top:
                name = "shore_N" if y == water_top else f"water_{_h(x, y, seed) % 2}"
            else:
                name = tiles[_h(x, y, seed) % len(tiles)]
            im.paste(G.TILES[name].img(pal), (x*G.T, y*G.T))

    names = G.PROP_TERRAIN[terrain]
    # 지형마다 밀도가 다르다. 숲은 나무가 빽빽해야 숲으로 읽히고, 초원은 성겨야 초원이다.
    n_prop = {"초원": 44, "숲": 62, "물가": 46, "바위": 46}[terrain]
    draw = []
    for i in range(n_prop):
        v = _h(i*31 + 7, seed*13 + i, seed)
        tx, ty = v % MAP_W, (v >> 5) % MAP_H
        if water_top is not None and ty >= water_top - 1: continue
        c = G.OBJECTS[names[(v >> 9) % len(names)]]
        img = c.img(pal)
        sh = Image.new("RGBA", (img.width, img.height + 4), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse(
            [img.width//2 - img.width//3, img.height - 4,
             img.width//2 + img.width//3, img.height + 2], fill=(18, 24, 20, 100))
        sh.alpha_composite(img, (0, 0))
        draw.append((ty*G.T + G.T, sh, tx*G.T + (G.T - c.w)//2, (ty+1)*G.T - c.h))
    for _, img, x, y in sorted(draw, key=lambda d: d[0]):
        im.alpha_composite(img, (x, y))

    im = P.apply_tint(im, tint)
    top = (full_h - H)//2
    return im.crop((0, top, W, top + H))


def pairing(idx):
    """동무 → (지형, 시간대). 데이터에서 나온다 — 종 이름으로 분기하지 않는다."""
    sp, st, _, _ = VARIANTS[idx % len(VARIANTS)]
    row = _species_row(sp)
    hab = row.get("habitat") or ["초원"]
    return hab[idx % len(hab)], DAYPART_BY_ACTIVITY.get(row.get("activity"), 0.30)


_BG_CACHE = {}
def background(terrain="초원", u=0.30, dim=0.58, seed=0):
    """메뉴가 얹히므로 어둡게 깔고 스크림을 한 겹 더 얹는다.
    지형마다 밝기가 달라서(바위는 밝고 숲은 어둡다) 스크림이 없으면 어떤 지형에서는
    글자가 안 읽힌다 — 배경이 무작위가 되면서 이게 필수가 됐다."""
    key = (terrain, round(u, 3), round(dim, 3), seed)
    if key in _BG_CACHE: return _BG_CACHE[key].copy()
    field = terrain_field(terrain, u, seed).convert("RGBA")
    r, g, b, a = field.split()
    lut = [int(v*dim) for v in range(256)]
    out = Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))
    out.alpha_composite(_scrim())
    _BG_CACHE[key] = out
    return out.copy()

_SCRIM = None
def _scrim():
    global _SCRIM
    if _SCRIM is not None: return _SCRIM
    sc = Image.new("RGBA", (1, H)); px = sc.load()
    for y in range(H):
        t = max(0.0, min(1.0, (y - 150) / 120))
        px[0, y] = (6, 8, 12, int(170 * t*t))
    _SCRIM = sc.resize((W, H), Image.NEAREST)
    return _SCRIM


# ── 메뉴 ─────────────────────────────────────────────────────────────
ITEMS_SAVED = ["CONTINUE", "NEW GAME", "SETTING", "EXIT"]
ITEMS_FIRST = ["NEW GAME", "SETTING", "EXIT"]

MENU_X, CURSOR_X, MENU_TOP, MENU_GAP = 292, 250, 228, 29

def cursor():
    """커서는 삼각형이 아니라 발자국이다. 제작사 로고와 같은 물건이고,
    이 게임이 '흔적을 따라간다'는 게임이라는 걸 메뉴에서부터 말한다."""
    m = L.PAW_SMALL()
    im = Image.new("RGBA", m.size, (0, 0, 0, 0))
    im.paste(Image.new("RGBA", m.size, ACCENT + (255,)), (0, 0), m)
    return im.resize((m.width*2, m.height*2), Image.NEAREST)

def menu(im, items, sel, disabled=()):
    for i, label in enumerate(items):
        y = MENU_TOP + i*MENU_GAP
        on = (i == sel)
        col = INK_OFF if label in disabled else (INK if on else INK_DIM)
        draw_text(im, label, MENU_X + (6 if on else 0), y, col)
        if on:
            im.alpha_composite(cursor(), (CURSOR_X, y - 4))
    return im


def title_screen(sel=0, first_run=False, companion=DEFAULT_COMPANION,
                 label=False, terrain=None, u=None, seed=0):
    """배경 지형과 시간대는 동무에서 따라온다 — 짝이 어긋나면 틀린 것을 가르친다.
    label=False 는 막 켠 직후. 마우스를 올리거나 2초가 지나면 True 가 된다."""
    t, du = pairing(companion)
    im = background(terrain or t, du if u is None else u, seed=seed)
    mark = title_block(companion=companion)
    bx = (W - mark.width)//2
    im.alpha_composite(mark, (bx, TITLE_Y))
    if label:
        lb = companion_label(companion)
        im.alpha_composite(lb, (bx + mark.width - 104, TITLE_Y + mark.height + 4))
    items = ITEMS_FIRST if first_run else ITEMS_SAVED
    menu(im, items, sel)
    draw_text(im, "V0.1  DEMO 1", W - text_w("V0.1  DEMO 1", 1) - 10,
              H - 14, INK_OFF, scale=1)
    draw_text(im, "RUN II", 10, H - 14, INK_OFF, scale=1)
    return im


# ── 확인 창 — 한글 ───────────────────────────────────────────────────
FONT_DIR = os.path.join(os.path.dirname(OUT), "fonts")
GALMURI  = os.path.join(FONT_DIR, "Galmuri11.ttf")

_KF = {}
def kfont(px=11, bold=False):
    """갈무리는 11px 로 그린 폰트다. **11 로 찍고 정수배로 키운다.**
    22px 로 바로 찍으면 힌팅이 개입해 획이 흔들린다 — 도트 폰트를 쓰는 이유가 없어진다."""
    key = (px, bold)
    if key in _KF: return _KF[key]
    path = os.path.join(FONT_DIR, "Galmuri11-Bold.ttf" if bold else "Galmuri11.ttf")
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"{path} 가 없다. 갈무리(OFL 1.1)를 fonts/ 에 넣어야 한글이 나온다.")
    _KF[key] = ImageFont.truetype(path, px)
    return _KF[key]

def ktext(im, s, cx, y, col, scale=2, bold=False):
    """가운데 정렬. 안티에일리어싱을 끄고(`fontmode='1'`) 찍은 뒤 NEAREST 로 키운다."""
    f = kfont(bold=bold)
    tmp = Image.new("L", (W, 26), 0)
    d = ImageDraw.Draw(tmp); d.fontmode = "1"
    d.text((1, 1), s, font=f, fill=255)
    bb = tmp.getbbox()
    if not bb: return
    tmp = tmp.crop(bb)
    tmp = tmp.resize((tmp.width*scale, tmp.height*scale), Image.NEAREST)
    for (dx, dy, c) in ((1, 1, SHADOW), (0, 0, col)):
        layer = Image.new("RGBA", tmp.size, (0, 0, 0, 0))
        layer.paste(Image.new("RGBA", tmp.size, c + (255,)), (0, 0), tmp)
        im.alpha_composite(layer, (cx - tmp.width//2 + dx*scale, y + dy*scale))

# ── 설정 — 항목은 셋뿐이다 ───────────────────────────────────────────
SETTING_ROWS = [("SOUND", "bar", 8), ("MUSIC", "bar", 5), ("FULLSCREEN", "onoff", 1)]

def _bar(im, x, y, v, n=10):
    """숫자를 쓰지 않는다. 칸이 몇 개 찼는지가 곧 값이다 — 7살이 읽을 수 있어야 한다."""
    d = ImageDraw.Draw(im)
    for i in range(n):
        cx = x + i*14
        on = i < v
        d.rectangle([cx, y, cx+9, y+13],
                    fill=(ACCENT if on else (58, 56, 60)) + (255,))
        d.rectangle([cx, y, cx+9, y+13], outline=(16, 16, 18, 255), width=1)

def settings_screen(sel=0, companion=DEFAULT_COMPANION, seed=0):
    t, u = pairing(companion)
    im = background(t, u, seed=seed)
    # 하위 화면은 전체를 한 겹 더 눌러 깐다 — 필드 무늬 위에 얹힌 목록은 안 읽힌다.
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 8, 12, 120)))
    draw_text(im, "SETTING", 180, 92, ACCENT)
    for i, (label, kind, v) in enumerate(SETTING_ROWS):
        y = 138 + i*40
        on = (i == sel)
        draw_text(im, label, 180 + (6 if on else 0), y, INK if on else INK_DIM)
        if kind == "bar": _bar(im, 366, y - 1, v)
        else:
            draw_text(im, "ON" if v else "OFF", 366, y, INK if on else INK_DIM)
        if on: im.alpha_composite(cursor(), (140, y - 4))
    y = 138 + len(SETTING_ROWS)*40 + 22
    on = (sel == len(SETTING_ROWS))
    draw_text(im, "BACK", 180 + (6 if on else 0), y, INK if on else INK_DIM)
    if on: im.alpha_composite(cursor(), (140, y - 4))
    return im


def confirm(lines, yes="네", no="아니오", sel_yes=False, base=None):
    """되돌릴 수 없는 동작에만 뜬다. **기본 선택은 언제나 안전한 쪽이다.**"""
    im = base if base is not None else title_screen(1)
    im.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, 110)))
    bw, bh = 404, 140
    bx, by = (W - bw)//2, 172          # 가운데가 아니라 조금 아래 — 타이틀을 가리지 않는다
    d = ImageDraw.Draw(im)
    d.rectangle([bx, by, bx+bw, by+bh], fill=PANEL + (255,))
    d.rectangle([bx, by, bx+bw, by+bh], outline=PANEL_ED + (255,), width=2)
    for i, ln in enumerate(lines):
        ktext(im, ln, W//2, by + 24 + i*28, INK)
    for i, (lab, on) in enumerate(((no, not sel_yes), (yes, sel_yes))):
        cx = bx + int(bw*0.34) + i*int(bw*0.36)
        ktext(im, lab, cx, by + bh - 38, INK if on else INK_DIM)
        if on:
            c = cursor()
            im.alpha_composite(c, (cx - 60, by + bh - 38))
    return im


# ── 산출물 ───────────────────────────────────────────────────────────
NEW_GAME_CONFIRM = ["지금까지 만든 사파리가 사라져요.", "그래도 새로 시작할까요?"]
EXIT_CONFIRM     = ["게임을 끝낼까요?"]

def save_all():
    """조각 + 좌표를 함께 내보낸다. 엔진이 매 실행 동무를 골라 얹어야 하므로
    합성 스틸로는 안 된다 — 로고와 같은 방식이다."""
    d = os.path.join(OUT, "extracted", "ui")
    os.makedirs(d, exist_ok=True)
    mark = title_mark()
    mark.save(os.path.join(d, "title_mark.png"))
    cursor().save(os.path.join(d, "cursor_paw.png"))
    title_screen(0).save(os.path.join(d, "title_screen.png"))
    title_props().save(os.path.join(d, "title_grass.png"))

    block_w = mark.width + BLOCK_PAD*2
    bx = (W - block_w)//2
    pool = species_pool()
    for c in pool:
        key = (c["species"], c["stage"])
        c["available"] = key in RENDERABLE
        c["palettes"] = RENDERABLE.get(key, (None, []))[1]
        c["animation"] = "special" if c["species"] == "cat" and c["available"] else "idle"

    meta = {
        "_comment": "타이틀 화면. 배경은 필드를 그대로 그리고 이 조각들을 위에 얹는다.",
        "canvas": [W, H],
        "title_mark": "ui/title_mark.png",
        "title_mark_at": [bx + BLOCK_PAD, TITLE_Y],
        "title_grass": "ui/title_grass.png",
        "title_grass_at": [bx, TITLE_Y],
        "background": {
            "mode": "random_terrain",
            "rule": ("켤 때마다 지형을 무작위로 고르고 **그 지형에 사는 종**을 세운다. "
                     "타이틀 화면 자체가 단서다 — 글로 알려주지 않는다"),
            "terrain_from": "animals.json 의 habitat[] 중 하나",
            "daypart_from": "animals.json 의 activity",
            "daypart": DAYPART_BY_ACTIVITY,
            "tiles": "terrain/<지형>.png (변형은 palettes.json 의 terrain_variants)",
            "props": "palettes.json 의 prop_terrain",
            "prop_count": {"초원": 44, "숲": 62, "물가": 46, "바위": 46},
            "dim": 0.58,
            "scrim": "아래로 갈수록 어둡게. 지형마다 밝기가 달라서 없으면 어떤 지형에선 안 읽힌다",
            "warning": "지형과 종이 어긋나면 틀린 것을 가르친다. 반드시 habitat 에서 뽑을 것",
        },
        "companion": {
            "rule": "게임을 켤 때마다 하나를 무작위로 고른다. 배경 지형이 먼저다",
            "pool": "data/animals.json 의 모든 종 × 모든 growth 단계",
            "anchor": [bx + BLOCK_PAD + mark.width - 24, TITLE_Y + mark.height + 32],
            "anchor_origin": "왼쪽 아래 — 종마다 키가 달라서 발을 기준으로 붙인다",
            "scale": 2,
            "fallback": {"species": "dog", "stage": "adult"},
            "label": {
                "name": "이름만 적는다. 사는 곳은 배경이 말한다",
                "always": "도감에 없어도 이름은 보여준다 — 미끼는 이름이다",
                "reveal": {"on_hover": True, "idle_ms": LABEL_IDLE_MS},
                "input_parity": ("마우스에서만 얻는 정보를 만들지 않는다. "
                                 "기본 조작은 WASD/패드고 마우스는 더 빠를 뿐이다"),
                "anchor": [bx + block_w - 104, TITLE_Y + mark.height + 46 + 4],
                "anchor_origin": "왼쪽 위",
            },
            "candidates": pool,
        },
        "menu": {
            "text_x": MENU_X, "cursor_x": CURSOR_X,
            "top": MENU_TOP, "gap": MENU_GAP,
            "selected_offset_x": 6,
            "cursor": "ui/cursor_paw.png",
            "items_with_save": ITEMS_SAVED,
            "items_first_run": ITEMS_FIRST,
        },
        "font": {
            "latin": "5×7 자체 비트맵 (엔진 쪽에서 다시 만들 것)",
            "hangul": "fonts/Galmuri11.ttf — 11px 로 찍고 정수배로만 키운다",
            "hangul_note": "임포트에서 안티에일리어싱·힌팅·서브픽셀을 끄지 않으면 흐려진다",
        },
        "confirm": {
            "only_for": "되돌릴 수 없는 동작만",
            "default_choice": "safe",
            "new_game": NEW_GAME_CONFIRM,
            "exit": EXIT_CONFIRM,
        },
    }
    with io.open(os.path.join(d, "title.json"), "w", encoding="utf-8") as fp:
        _json.dump(meta, fp, ensure_ascii=False, indent=2)
    print("extracted/ui/title_mark.png · title_grass.png · cursor_paw.png · "
          "title_screen.png · title.json")


def _label_font(sz):
    try: return ImageFont.truetype(
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
    except Exception: return ImageFont.load_default()

def sheet():
    FH_, FL_, FS_ = _label_font(30), _label_font(20), _label_font(15)
    BGC, INKC, DIMC, ACCC = (26,31,38), (238,232,222), (150,158,168), (233,164,65)
    HW, HH = W//2, H//2
    PAD, GAP = 34, 20

    panels = [
        ("이어하기가 있을 때 — 첫 항목이 항상 CONTINUE", title_screen(0)),
        ("NEW GAME 선택", title_screen(1)),
        ("SETTING 선택", title_screen(2)),
        ("EXIT 선택", title_screen(3)),
        ("첫 실행 — 세이브가 없으니 CONTINUE 가 아예 없다",
         title_screen(0, first_run=True)),
        ("설정 — 항목은 셋뿐. 값은 숫자가 아니라 칸 수로 보인다", settings_screen(0)),
        ("새 게임 확인 — 기본 선택은 언제나 안전한 쪽(아니오)",
         confirm(NEW_GAME_CONFIRM, base=title_screen(1))),
        ("종료 확인", confirm(EXIT_CONFIRM, base=title_screen(3))),
    ]
    times = [(0.05, "새벽"), (0.30, "낮"), (0.60, "저녁"), (0.85, "밤")]

    cols = 2
    rows = (len(panels) + cols - 1)//cols
    tw = HW//2
    Hgt = 150 + rows*(HH + 46) + 220 + 300 + (HH//2 + 90)
    Wid = PAD*2 + cols*HW + (cols-1)*GAP
    out = Image.new("RGBA", (Wid, Hgt), BGC + (255,))
    d = ImageDraw.Draw(out)
    d.text((PAD, 26), "게임 시작 UI — 타이틀 · 메뉴 · 확인 창", font=FH_, fill=INKC)
    d.text((PAD, 68), "640×360 실제 픽셀. 켤 때마다 지형이 바뀌고 거기 사는 동물이 선다 — "
                      "타이틀 화면 자체가 단서다.", font=FS_, fill=DIMC)

    y = 118
    for i, (cap, im) in enumerate(panels):
        cx = PAD + (i % cols)*(HW + GAP)
        cy = y + (i//cols)*(HH + 46)
        out.alpha_composite(im.resize((HW, HH), Image.NEAREST), (cx, cy))
        d.rectangle([cx, cy, cx+HW-1, cy+HH-1], outline=(58,64,74), width=1)
        d.text((cx, cy + HH + 8), cap, font=FS_, fill=DIMC)
    y += rows*(HH + 46) + 16

    d.text((PAD, y), "동무는 켤 때마다 바뀐다 — 풀은 animals.json 의 모든 종 × 성장 단계",
           font=FL_, fill=ACCC)
    y += 30
    d.text((PAD, y), "22칸 중 지금 그려진 것은 성체 셋뿐이다. 아기 스프라이트는 아직 없다.",
           font=FS_, fill=DIMC)
    y += 26
    crop = (392, 56, 392 + 216, 56 + 124)
    KNAME = {c["species"]: c["name"] for c in species_pool()}
    for i, ci in enumerate((0, 3, 6, 5)):
        sp, st, pal, _ = VARIANTS[ci]
        c = title_screen(0, companion=ci).crop(crop)
        cw = (Wid - PAD*2 - GAP*3)//4
        ch = int(c.height * cw / c.width)
        cx = PAD + i*(cw + GAP)
        out.alpha_composite(c.resize((cw, ch), Image.NEAREST), (cx, y))
        d.text((cx, y + ch + 6), f"{KNAME[sp]} · {pal.split('_', 1)[1]}",
               font=FS_, fill=DIMC)
    y += 190

    d.text((PAD, y), "이름표 — 이름만 적는다", font=FL_, fill=ACCC)
    y += 30
    d.text((PAD, y), "마우스를 올리면 즉시, 아무것도 안 하면 2초 뒤에. 패드도 같은 정보를 본다.",
           font=FS_, fill=DIMC)
    y += 26
    lcrop = (352, 52, 352 + 272, 52 + 202)
    lstates = [
        (dict(companion=3, label=False), "막 켠 직후 — 그림만"),
        (dict(companion=3, label=True), "2초 뒤 — 이름만"),
        (dict(companion=6, label=True), "청설모는 숲에만 산다"),
    ]
    cw = (Wid - PAD*2 - GAP*2)//3
    for i, (kw, cap) in enumerate(lstates):
        c = title_screen(0, **kw).crop(lcrop)
        ch = int(c.height * cw / c.width)
        cx = PAD + i*(cw + GAP)
        out.alpha_composite(c.resize((cw, ch), Image.NEAREST), (cx, y))
        d.text((cx, y + ch + 6), cap, font=FS_, fill=DIMC)
    y += 236

    d.text((PAD, y), "지형도 시간대도 동물에서 따라온다", font=FL_, fill=ACCC)
    y += 30
    d.text((PAD, y), "habitat 에서 지형을, activity 에서 시간대를 뽑는다. "
                     "수달이 초원에 서 있으면 틀린 것을 가르친다.", font=FS_, fill=DIMC)
    y += 26
    tw2 = (Wid - PAD*2 - GAP*3)//4
    th2 = int(H * tw2 / W)
    for i, (ci, cap) in enumerate([
            (0, "개 · 초원 · 낮"), (6, "청설모 · 숲 · 낮"),
            (3, "고양이 · 초원 · 저녁"), (None, "수달 · 물가 (도트 없음)")]):
        if ci is None:
            im2 = background("물가", 0.62)
            mk = title_block(companion=0)
            bx2 = (W - mk.width)//2
            im2.alpha_composite(title_mark(), (bx2 + BLOCK_PAD, TITLE_Y))
            im2.alpha_composite(title_props(), (bx2, TITLE_Y))
            menu(im2, ITEMS_SAVED, 0)
        else:
            im2 = title_screen(0, companion=ci, label=True)
        cx = PAD + i*(tw2 + GAP)
        out.alpha_composite(im2.resize((tw2, th2), Image.NEAREST), (cx, y))
        d.text((cx, y + th2 + 6), cap, font=FS_, fill=DIMC)
    y += th2 + 34

    out.crop((0, 0, Wid, y + PAD)).convert("RGB").save(
        os.path.join(OUT, "title_sheet.png"))


def gif():
    """커서가 항목을 오르내리고 시간이 함께 흐른다."""
    seq = [0, 0, 1, 1, 2, 2, 3, 3, 2, 2, 1, 1]
    frames = [title_screen(s, u=0.55 + i*0.006) for i, s in enumerate(seq)]
    g = [f.convert("P", palette=Image.ADAPTIVE, colors=96) for f in frames]
    g[0].save(os.path.join(OUT, "title.gif"), save_all=True, append_images=g[1:],
              duration=260, loop=0, disposal=2)


if __name__ == "__main__":
    save_all(); sheet(); gif()
    title_screen(0).resize((W*2, H*2), Image.NEAREST).convert("RGB").save(
        os.path.join(OUT, "title_2x.png"))
    print("title_sheet.png · title.gif · title_2x.png")
