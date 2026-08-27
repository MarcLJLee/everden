#!/usr/bin/env python3
"""
집 (사파리 층) — 게임을 켜면 처음 서는 곳

  타이틀에서 NEW GAME / CONTINUE 를 고르면 필드가 아니라 **집**으로 들어온다.
  나간다 → 만난다 → 데려온다 → **집이 달라진다** 가 이 게임의 고리인데,
  집이 없으면 "데려온다" 가 어디로 가는지가 화면에 없다.
  집은 §"진행은 누적으로 보이게" 를 눈으로 보여주는 화면이다.

⚠️ **집은 보는 곳이지 해야 하는 곳이 아니다.**
  사물은 고장나지 않고 유지비가 없다. 물을 갈아줄 필요도, 청소할 필요도 없다.
  동물이 늘고 사물이 늘수록 할 일이 늘어나면 §"수집이 벌이 되면 안 된다" 위반이다.
  사물의 값어치는 수치가 아니라 **동물이 그걸 갖고 노는 걸 보는 것**이다.

사물의 태그:
  **새 태그를 만들지 않는다.** 사물은 `tags.json` 에 이미 있는 값을 가리킨다
  (temperament · behavior_tags · likes · habitat). 그 태그를 가진 동물이 그 사물을 쓴다.
  종 이름으로 분기하지 않으므로 종을 추가해도, 사물을 추가해도 코드를 안 고친다.

애니메이션 비용:
  **사물이 새 동작을 요구하지 않는다.** 동물의 기존 특징 동작(`idle_animation`)이
  사물 옆에서 재생된다. 종×사물로 동작을 만들면 스프라이트가 곱셈으로 터진다 —
  이 규칙이 종당 장수를 사물 수와 무관하게 묶는다 (§4.5 종당 16장).
"""
import os, math, io, json
from PIL import Image, ImageDraw
import build_bg as G
import build as A
import build_player as PL
import build_title as T
from build_bg import (C, T as TS, TR, OL, GD, GM, GL, DD, DM, DL,
                      WD, WM, WL, KD, KM, SD, SM, AC)

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = 640, 360


# ── 집 ────────────────────────────────────────────────────────────────
def house():
    """96×80. 아이 키가 48px 이라 64px 집은 개집으로 보인다 — **문이 아이보다 커야 한다.**
    지붕은 강조색(빨강), 벽은 나무."""
    HW, HH, ROOF = 96, 80, 30
    c = C(HW, HH)
    c.rect(4, ROOF, HW-5, HH-3, KM)                  # 벽
    for y in range(ROOF+3, HH-3, 4):                 # 널빤지 결
        c.rect(6, y, HW-7, y, KD)
    for i in range(ROOF):                            # 지붕 — 사다리꼴
        c.rect(2 + i*3//2, ROOF - i, HW-3 - i*3//2, ROOF - i, AC)
    c.rect(HW//2-9, 0, HW//2+8, 1, KD)               # 용마루
    c.rect(2, ROOF-1, HW-3, ROOF, DD)                # 지붕 아랫단 그늘
    c.rect(0, ROOF, HW-1, ROOF+3, KD)                # 처마

    dx0, dx1 = HW//2 - 11, HW//2 + 10                # 문 — 아이(32px 폭)보다 넓다
    c.rect(dx0, HH-34, dx1, HH-3, DM)
    c.rect(dx0, HH-34, dx1, HH-32, DD)
    c.rect(dx0+1, HH-31, dx1-1, HH-3, DD)
    c.rect(dx0+4, HH-28, dx1-4, HH-8, DM)            # 문 안쪽 판
    c.set(dx1-4, HH-19, GL)                          # 손잡이
    c.rect(dx0-2, HH-3, dx1+2, HH-1, SM)             # 문지방 돌

    for (x0, x1) in ((11, 29), (HW-30, HW-12)):      # 창문
        c.rect(x0, ROOF+9, x1, ROOF+27, WM)
        c.rect(x0, ROOF+9, x1, ROOF+11, WL)
        c.rect(x0-1, ROOF+8, x1+1, ROOF+8, KD); c.rect(x0-1, ROOF+28, x1+1, ROOF+28, KD)
        c.rect(x0-1, ROOF+8, x0-1, ROOF+28, KD); c.rect(x1+1, ROOF+8, x1+1, ROOF+28, KD)
        c.rect((x0+x1)//2, ROOF+9, (x0+x1)//2, ROOF+27, KD)
    c.outline({KM, KD, AC, DM, DD, SM})
    return c


# ── 울타리 ────────────────────────────────────────────────────────────
def fence_h():
    """가로 울타리 한 칸 (16×20). 앵커는 바닥 중앙 — 다른 프롭과 같다."""
    c = C(16, 20)
    c.rect(2, 4, 3, 19, KM); c.rect(12, 4, 13, 19, KM)   # 기둥
    c.rect(0, 7, 15, 8, KM); c.rect(0, 13, 15, 14, KM)   # 가로대
    c.rect(0, 8, 15, 8, KD); c.rect(0, 14, 15, 14, KD)
    c.outline({KM, KD})
    return c

def fence_v():
    """세로 울타리 — 옆에서 보므로 기둥 하나에 가로대가 짧다."""
    c = C(16, 20)
    c.rect(6, 3, 9, 19, KM)
    c.rect(5, 7, 10, 8, KD); c.rect(5, 13, 10, 14, KD)
    c.outline({KM, KD})
    return c

def gate():
    """대문 — **열려 있다.** 닫힌 문은 '못 나간다' 로 읽힌다.
    나가는 곳이 어디인지가 화면에서 보여야 한다 (§규칙은 눈에 보여야 한다)."""
    c = C(32, 22)
    for x in (1, 28):
        c.rect(x, 0, x+2, 21, KM); c.rect(x, 0, x+2, 1, KD)
    # 열린 문짝 — 안쪽으로 비스듬히 젖혀져 있다
    for k in range(5):
        c.rect(4, 3 + k, 4 + k, 3 + k, KM)
        c.rect(27 - k, 3 + k, 27, 3 + k, KM)
    c.rect(4, 8, 8, 13, KD); c.rect(23, 8, 27, 13, KD)
    c.outline({KM, KD})
    return c


# ── 사물 — 사서 놓는다 ────────────────────────────────────────────────
def ball():
    c = C(14, 14)
    c.ellipse(7, 8, 5.4, 5.2, AC)
    c.ellipse(5.4, 6, 2.2, 2.0, GL)                  # 무늬
    c.ellipse(9.4, 10, 1.6, 1.4, GL)
    c.set(5, 5, WL)                                  # 반짝임 1픽셀
    c.outline({AC, GL})
    return c

def bowl(water=False):
    c = C(18, 12)
    c.ellipse(9, 8, 7.6, 3.4, SM)
    c.ellipse(9, 7, 6.2, 2.4, SD)
    c.ellipse(9, 7, 5.4, 1.9, WM if water else DM)
    if water: c.ellipse(7, 6.4, 2.2, 0.9, WL)
    c.outline({SM, SD})
    return c

def scratcher():
    """긁는 기둥 — 나무선호 태그를 가진 동물이 쓴다."""
    c = C(18, 34)
    c.ellipse(9, 31, 8.0, 3.0, KD)                   # 받침
    c.rect(6, 6, 11, 30, DM)                         # 기둥 (새끼줄)
    for y in range(7, 30, 2): c.rect(6, y, 11, y, DL)
    c.rect(3, 2, 14, 7, KM); c.rect(3, 2, 14, 2, KD) # 위 판
    c.outline({KM, KD, DM, DL})
    return c

def shade():
    """그늘막 — 겁많음 태그를 가진 동물이 숨는 곳이자 누구나 쉬는 곳."""
    c = C(40, 30)
    c.rect(2, 26, 4, 29, KD); c.rect(35, 26, 37, 29, KD)
    for i in range(7):                               # 천
        c.rect(1 + i, 6 + i, 38 - i, 6 + i, AC if i < 5 else DD)
    c.rect(0, 12, 39, 15, AC); c.rect(0, 15, 39, 15, DD)
    for x in range(0, 40, 6): c.rect(x, 16, x+2, 18, AC)   # 술
    c.rect(3, 15, 3, 27, KD); c.rect(36, 15, 36, 27, KD)
    c.outline({AC, KD, DD})
    return c

def puddle():
    """웅덩이 — 물가선호 태그를 가진 동물이 논다."""
    c = C(30, 16)
    c.ellipse(15, 9, 13.0, 5.6, DD)
    c.ellipse(15, 9, 11.4, 4.4, WD)
    c.ellipse(15, 9, 10.0, 3.4, WM)
    c.ellipse(11, 7.6, 3.4, 1.2, WL)
    c.outline({DD})
    return c

def cushion():
    c = C(20, 12)
    c.ellipse(10, 8, 9.0, 3.6, AC)
    c.ellipse(10, 7, 7.6, 2.6, DL)
    c.outline({AC})
    return c


HOUSE  = house()
FENCE  = {"h": fence_h(), "v": fence_v(), "gate": gate()}

# 사물이 가리키는 태그는 **전부 tags.json 에 이미 있는 값**이다. 새 열거형을 만들지 않는다.
OBJECTS = {
    "공":       (ball(),        ["호기심", "대담함"],   40),
    "밥그릇":   (bowl(False),   ["잡식", "육식", "초식"], 20),
    "물그릇":   (bowl(True),    [],                     20),
    "긁는기둥": (scratcher(),   ["나무선호"],           60),
    "그늘막":   (shade(),       ["겁많음"],             80),
    "웅덩이":   (puddle(),      ["물가선호"],           50),
    "방석":     (cushion(),     [],                     30),
}


# ── 화면 ─────────────────────────────────────────────────────────────
MAP_W, MAP_H = 40, 23
YARD = (2, 2, 37, 19)          # 울타리 안쪽 (타일 좌표)
GATE_TX = 18                   # 대문이 뚫린 자리
HOUSE_AT = (256, 60)          # 문 한가운데가 대문과 같은 x 여야 한다

def _h(a, b, c=0):
    v = (a*73856093) ^ (b*19349663) ^ (c*83492791)
    return (v ^ (v >> 13)) & 0xffff

# 사물 배치 — 나중에 아이가 직접 놓는다. 지금은 기본 배치 한 벌.
PLACED = [("웅덩이", 96, 250), ("그늘막", 396, 216), ("긁는기둥", 168, 214),
          ("밥그릇", 214, 300), ("물그릇", 250, 300), ("공", 140, 306),
          ("방석", 470, 300)]
ANIMALS = [("dog", "dog_default", "idle", 200, 262),
           ("cat", "cat_default", "special", 420, 268),
           ("squirrel", "squirrel_default", "idle", 92, 202)]
# 마당 안 자잘한 것 — 빈 잔디만 있으면 마당이 아니라 운동장이다
YARD_PROPS = [("tuft", 60, 300), ("flowers", 508, 262), ("tuft", 336, 306),
              ("pebbles", 452, 224), ("flowers", 78, 322), ("tuft", 520, 316),
              ("bush", 40, 210), ("bush", 552, 200)]
# 울타리 밖 — 뒷산이 붙어 있다
OUTSIDE = [("tree", 8, 40), ("conifer", 600, 52), ("tree", 592, 340),
           ("conifer", 16, 348), ("bush", 610, 150), ("tree", 4, 150)]
PLAYER_AT = (288, 200)

def ground(pal):
    im = Image.new("RGBA", (W, MAP_H*TS), (0, 0, 0, 255))
    x0, y0, x1, y1 = YARD
    for ty in range(MAP_H):
        for tx in range(MAP_W):
            inside = x0 <= tx <= x1 and y0 <= ty <= y1
            if not inside:
                name = f"grass_{_h(tx, ty, 5) % G.GRASS_N}"
            elif tx in (GATE_TX, GATE_TX+1) and ty >= 9:
                name = "dirt"                       # 문에서 대문까지 곧게 난 길
            else:
                name = f"grass_{_h(tx, ty, 5) % G.GRASS_N}"
            im.paste(G.TILES[name].img(pal), (tx*TS, ty*TS))
    return im

def _shadow(img, w):
    out = Image.new("RGBA", (img.width, img.height + 4), (0, 0, 0, 0))
    sh = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([img.width//2 - w//2, img.height - 4,
                                img.width//2 + w//2, img.height + 2],
                               fill=(18, 24, 20, 105))
    out.alpha_composite(sh); out.alpha_composite(img, (0, 0))
    return out

def home_field(u=0.30, bare=False):
    """집 마당. 지형·프롭과 같은 규약 — 앵커는 바닥 중앙이고 Y-sort 대상이다.

    bare=True 는 **첫 만남**용이다 — 산 사물도, 사는 동물도, 플레이어도 없다.
    첫 만남은 아무것도 없는 데서 시작해야 첫 친구가 사건이 된다 (§2.9)."""
    pal, tint = G.at_time(u)
    im = ground(pal)
    draw = []

    def put(img, x, y_base, shadow=0):
        if shadow: img = _shadow(img, shadow)
        draw.append((y_base, img, x, y_base - img.height + (4 if shadow else 0)))

    x0, y0, x1, y1 = YARD
    fh, fv, gt = FENCE["h"].img(pal), FENCE["v"].img(pal), FENCE["gate"].img(pal)
    hx0, hx1 = HOUSE_AT[0]//TS, (HOUSE_AT[0] + HOUSE.w)//TS - 1
    for tx in range(x0, x1+1):                                  # 위 울타리
        if hx0 <= tx <= hx1: continue                           # 집이 담장을 대신한다
        put(fh, tx*TS, (y0)*TS + 6)
    for ty in range(y0+1, y1+1):                                # 좌우 울타리
        put(fv, x0*TS, ty*TS + TS)
        put(fv, x1*TS, ty*TS + TS)
    for tx in range(x0, x1+1):                                  # 아래 울타리 + 대문
        if tx in (GATE_TX, GATE_TX+1): continue
        put(fh, tx*TS, (y1+1)*TS)
    put(gt, GATE_TX*TS, (y1+1)*TS)

    hs = HOUSE.img(pal)
    put(hs, HOUSE_AT[0], HOUSE_AT[1] + hs.height)

    for name, x, yb in OUTSIDE:
        c = G.OBJECTS[name]
        put(c.img(pal), x, yb, shadow=max(8, c.w - 8))
    for name, x, yb in YARD_PROPS:
        c = G.OBJECTS[name]
        put(c.img(pal), x, yb, shadow=max(6, c.w - 8))
    for name, x, yb in ([] if bare else PLACED):
        c = OBJECTS[name][0]
        put(c.img(pal), x, yb, shadow=max(8, c.w - 6))

    for sp, palname, anim, x, yb in ([] if bare else ANIMALS):
        fn = {("dog", "idle"): lambda: A.dog_side(0, "idle"),
              ("cat", "special"): lambda: A.cat_special(0),
              ("squirrel", "idle"): lambda: A.squirrel_side(0, "idle")}[(sp, anim)]
        put(fn().to_image(A.PALETTES[palname]), x, yb, shadow=16)

    if not bare:
        put(PL.compose("idle_0", PL.PALETTES["default"]), PLAYER_AT[0], PLAYER_AT[1] + 48,
            shadow=14)

    for _, img, x, y in sorted(draw, key=lambda d: d[0]):
        im.alpha_composite(img, (x, y))

    im = T.P.apply_tint(im, tint)
    top = (MAP_H*TS - H)//2
    return im.crop((0, top, W, top + H))


# ── HUD — 두 개뿐이다 ─────────────────────────────────────────────────
# 화면에 상시로 띄우는 것은 **재화와 자리**뿐이다. 둘 다 §2 에서 이미 규칙이 있고
# 숫자가 아니라 상태로 읽힌다. 배고픔·청결·기분 게이지 같은 것은 두지 않는다 —
# 그것들이 생기는 순간 집이 '해야 하는 곳'이 된다.
def hud(im, coin=120, seats_used=3, seats=5):
    day = G.PALETTES["day"]
    d = ImageDraw.Draw(im)
    def plate(x, y, w, h):
        d.rectangle([x, y, x+w, y+h], fill=(18, 18, 24, 190))
        d.rectangle([x, y, x+w, y+h], outline=(96, 90, 84, 255), width=1)

    plate(8, 8, 92, 24)
    nut = G.FOODS["견과"].img(day)
    im.alpha_composite(nut.resize((16, 16), Image.NEAREST), (12, 12))
    T.draw_text(im, str(coin), 34, 15, T.INK, scale=2)

    plate(W-116, 8, 108, 24)
    paw = T.cursor()
    im.alpha_composite(paw, (W-110, 13))
    T.draw_text(im, f"{seats_used} / {seats}", W-80, 15, T.INK, scale=2)
    return im

def home_screen(u=0.30, hint=True):
    im = home_field(u)
    hud(im)
    if hint:
        T.ktext(im, "문으로 나가면 밖이야", W//2, H-30, T.INK_DIM, scale=1)
    return im


# ── 산출물 ───────────────────────────────────────────────────────────
def save_all():
    d = os.path.join(OUT, "extracted", "home")
    os.makedirs(d, exist_ok=True)
    day = G.PALETTES["day"]
    HOUSE.img(day).save(os.path.join(d, "house.png"))
    for k, c in FENCE.items(): c.img(day).save(os.path.join(d, f"fence_{k}.png"))
    for n, (c, tags, price) in OBJECTS.items():
        c.img(day).save(os.path.join(d, f"obj_{n}.png"))

    meta = {
        "_comment": ("집(사파리 층)의 조각. 사물은 **새 태그를 만들지 않는다** — "
                     "tags.json 에 이미 있는 값을 가리키고, 그 태그를 가진 동물이 쓴다."),
        "tile_size": TS,
        "house": {"file": "home/house.png", "size": [HOUSE.w, HOUSE.h],
                  "door_x": HOUSE.w//2, "anchor": "바닥 중앙"},
        "fence": {k: f"home/fence_{k}.png" for k in FENCE},
        "objects": {n: {"file": f"home/obj_{n}.png",
                        "size": [c.w, c.h],
                        "for_tags": tags,
                        "price": price,
                        "anchor": "바닥 중앙"}
                    for n, (c, tags, price) in OBJECTS.items()},
        "rules": {
            "no_upkeep": "사물은 고장나지 않고 유지비가 없다. 한 번 사면 끝이다",
            "no_new_enum": "for_tags 의 값은 전부 tags.json 에 이미 있다",
            "no_new_animation": ("사물이 새 동작을 요구하지 않는다. 동물의 기존 "
                                 "idle_animation 이 사물 옆에서 재생된다 — "
                                 "종×사물로 동작을 만들면 스프라이트가 곱셈으로 터진다"),
            "match": "for_tags 가 비어 있으면 누구나 쓴다. 아니면 하나라도 겹치는 동물이 쓴다",
        },
        "hud": {"items": ["재화", "자리"],
                "note": "배고픔·청결·기분 게이지를 두지 않는다. 집은 해야 하는 곳이 아니다"},
    }
    with io.open(os.path.join(d, "home.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=2)
    print(f"extracted/home/ 에 {2 + len(FENCE) + len(OBJECTS)}개 파일 + home.json")


def sheet():
    from PIL import ImageFont
    def font(sz):
        try: return ImageFont.truetype(
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
        except Exception: return ImageFont.load_default()
    FH_, FL_, FS_ = font(30), font(20), font(15)
    BGC, INKC, DIMC, ACCC = (26,31,38), (238,232,222), (150,158,168), (233,164,65)
    PAD, GAP = 34, 20
    day = G.PALETTES["day"]

    Wid = W + PAD*2
    out = Image.new("RGBA", (Wid, 1700), BGC + (255,))
    d = ImageDraw.Draw(out)
    d.text((PAD, 26), "집 — 게임을 켜면 처음 서는 곳", font=FH_, fill=INKC)
    d.text((PAD, 68), "640×360 실제 픽셀. 집은 보는 곳이지 해야 하는 곳이 아니다 — "
                      "게이지도 유지비도 없다.", font=FS_, fill=DIMC)

    y = 116
    d.text((PAD, y), "낮", font=FL_, fill=ACCC); y += 28
    out.alpha_composite(home_screen(0.30), (PAD, y)); y += H + 22
    d.text((PAD, y), "밤 — 같은 화면, 팔레트만 바뀐다 (§6.3)", font=FL_, fill=ACCC); y += 28
    out.alpha_composite(home_screen(0.86), (PAD, y)); y += H + 26

    d.text((PAD, y), "조각 — 새로 그린 것은 이 12장뿐이다", font=FL_, fill=ACCC); y += 30
    row = [("집", HOUSE, 1)] + [(f"울타리·{k}", c, 2) for k, c in FENCE.items()] + \
          [(n, c, 2) for n, (c, _, _) in OBJECTS.items()]
    CW, CH = 104, 96
    cols = (Wid - PAD*2) // CW
    for i, (name, c, z) in enumerate(row):
        cx = PAD + (i % cols)*CW
        cy = y + (i // cols)*(CH + 26)
        im = c.img(day, z)
        if im.height > CH: im = c.img(day, 1)
        out.alpha_composite(im, (cx + (CW - im.width)//2, cy + CH - im.height))
        d.text((cx, cy + CH + 6), name, font=FS_, fill=DIMC)
    y += ((len(row) + cols - 1)//cols)*(CH + 26) + 24

    d.text((PAD, y), "사물은 새 태그를 만들지 않는다", font=FL_, fill=ACCC); y += 28
    d.text((PAD, y), "tags.json 에 이미 있는 값을 가리키고, 그 태그를 가진 동물이 쓴다. "
                     "빈 칸은 누구나.", font=FS_, fill=DIMC); y += 26
    for n, (c, tags, price) in OBJECTS.items():
        d.text((PAD, y), n, font=FS_, fill=INKC)
        d.text((PAD + 90, y), " · ".join(tags) if tags else "누구나", font=FS_, fill=ACCC)
        d.text((Wid - PAD - 60, y), f"{price}", font=FS_, fill=DIMC)
        y += 22
    y += 20
    out.crop((0, 0, Wid, y)).convert("RGB").save(os.path.join(OUT, "home_sheet.png"))


if __name__ == "__main__":
    save_all(); sheet()
    home_screen().resize((W*2, H*2), Image.NEAREST).convert("RGB").save(
        os.path.join(OUT, "home_2x.png"))
    print("home_sheet.png · home_2x.png")
