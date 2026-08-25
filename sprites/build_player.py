#!/usr/bin/env python3
"""
플레이어 캐릭터 — 여자아이. 32×48 (2타일 폭 · 3타일 높이). 레이어 조합.

## 왜 옷과 머리를 나누는가, 그리고 어디서 멈추는가

눈은 각도 2개(정면·측면)면 끝났다. 북향에서는 숨기니까(§4.6).
**옷과 머리는 몸을 덮으므로 방향마다 필요하다** — 비용 구조가 다르다.

핵심은 이것이다:

    몸통 레이어가 프레임 애니메이션을 전담하고,
    나머지 레이어는 프레임과 무관한 오버레이가 된다.

걷기에서 실제로 움직이는 것은 **다리와 팔**뿐이다(몸의 상하 바운스는 노드가 낸다, §4.6).
그래서 다리를 덮는 신발은 몸통에 포함시키고, 그 위를 덮는 반바지·상의·머리는
방향당 한 장이면 된다.

| 레이어 | 장수 | 프레임 따라감? |
|---|---|---|
| `body`  피부·팔·다리·신발 | 10 (남2 북2 측2 대기2 특징2) | **예** |
| `bottom` 하의 | 4 (남 북 측 특징) | 아니오 |
| `top`    상의 | 4 | 아니오 |
| `gear`   배낭 | 4 | 아니오 |
| `hair`   머리 | 4 | 아니오 |
| `eye`    눈   | 6 (표정3 × 각도2) | 아니오 |

**새 의상 한 벌 = 상의 4 + 하의 4 = 8장.** 통짜였다면 10장을 다시 그려야 한다.
머리 한 종 = 4장. 머리 3 × 상의 3 × 하의 3 = **27 조합**이 나온다.

여기에 팔레트 교체(§4.3)가 곱해지므로 실질 가짓수는 훨씬 크다.
그리고 §4.7 — **아이가 옷을 디자인할 수 있다.** 종을 그리는 것보다 훨씬 쉬운 참여다.

### 신발을 나누지 않은 이유
신발은 다리 끝에 붙어 있어 **걷기 프레임을 따라간다.** 나누면 프레임 수만큼 그려야 해서
장수가 안 줄고 정렬만 어려워진다. 색은 팔레트(`AC`)로 바꾼다.

### 동물에는 이 구조를 적용하지 않는다
동물은 몸 자체가 정체성이라 덮을 것이 없다. 동물은 `몸통 + 눈` 2레이어 그대로다(§4.6).

인덱스 12개:
  0 투명 1 외곽선 2 피부 3 피부그늘 4 머리어둠 5 머리중간 6 머리밝음
  7 상의어둠 8 상의밝음 9 하의어둠 10 하의밝음 11 소품(신발·배낭·머리끈)
"""
import os, math
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))
(TR, OL, SK, SKD, HD, HM, HL, TD, TL, PD, PL, AC) = range(12)
W, H, FOOT_Y = 32, 48, 45

PALETTES = {
    "default": [(0,0,0,0),(44,32,30),(248,214,178),(214,166,132),
                (58,38,32),(92,60,44),(126,86,60),
                (176,62,58),(222,96,84),(46,62,96),(72,96,140),(198,168,96)],
    "mint":    [(0,0,0,0),(38,40,42),(248,214,178),(214,166,132),
                (40,34,44),(70,58,76),(102,88,110),
                (36,110,104),(72,166,152),(74,58,42),(112,88,64),(232,206,132)],
    "berry":   [(0,0,0,0),(46,30,40),(248,214,178),(214,166,132),
                (48,30,42),(84,50,70),(120,78,102),
                (128,52,104),(186,92,148),(56,52,84),(88,84,128),(226,196,120)],
}

class C:
    def __init__(s, w=W, h=H):
        s.w, s.h = w, h
        s.px = [[TR]*w for _ in range(h)]
    def set(s, x, y, v):
        if 0 <= int(x) < s.w and 0 <= int(y) < s.h: s.px[int(y)][int(x)] = v
    def get(s, x, y):
        return s.px[int(y)][int(x)] if 0 <= int(x) < s.w and 0 <= int(y) < s.h else TR
    def rect(s, x0, y0, x1, y1, v):
        for y in range(int(y0), int(y1)+1):
            for x in range(int(x0), int(x1)+1): s.set(x, y, v)
    def ellipse(s, cx, cy, rx, ry, v):
        for y in range(int(cy-ry)-1, int(cy+ry)+2):
            for x in range(int(cx-rx)-1, int(cx+rx)+2):
                if rx > 0 and ry > 0 and ((x-cx)/rx)**2 + ((y-cy)/ry)**2 <= 1.0: s.set(x, y, v)
    def edge_lower(s, cx, cy, rx, ry, v=OL):
        for x in range(int(cx-rx), int(cx+rx)+1):
            t = 1.0 - ((x-cx)/rx)**2
            if t < 0: continue
            s.set(x, round(cy + ry*math.sqrt(t)), v)
    def outline(s, v=OL):
        solid = {SK, SKD, HD, HM, HL, TD, TL, PD, PL, AC}
        add = []
        for y in range(s.h):
            for x in range(s.w):
                if s.px[y][x] != TR: continue
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    if s.get(x+dx, y+dy) in solid: add.append((x,y)); break
        for (x,y) in add: s.set(x, y, v)
    def img(s, pal, z=1):
        im = Image.new("RGBA", (s.w, s.h), (0,0,0,0)); p = im.load()
        for y in range(s.h):
            for x in range(s.w):
                col = pal[s.px[y][x]]
                p[x, y] = col if len(col) == 4 else col + (255,)
        return im.resize((s.w*z, s.h*z), Image.NEAREST) if z > 1 else im
    def mirrored(s):
        c = C(s.w, s.h)
        for y in range(s.h):
            for x in range(s.w): c.px[y][s.w-1-x] = s.px[y][x]
        return c


# ══ body — 프레임을 전담하는 유일한 레이어 ═══════════════════════════
def _legs_front(c, swing):
    for i, x in enumerate((12, 18)):
        off = swing if i == 0 else -swing
        c.rect(x, 33, x+2, 43+off, SK)
        c.rect(x, 43+off, x+2, FOOT_Y+off, AC)      # 신발 — 다리 끝이라 몸통에 포함

def body_south(frame):
    c = C(); sw = 1 if frame else -1
    _legs_front(c, sw)
    c.rect(11, 21, 20, 34, SK)                      # 몸통
    c.rect(8, 22, 10, 30, SK); c.rect(21, 22, 23, 30, SK)      # 팔
    c.ellipse(9, 30.5, 1.3, 1.3, SK); c.ellipse(22, 30.5, 1.3, 1.3, SK)
    c.rect(14, 19, 17, 22, SKD)                     # 목
    c.ellipse(16, 14, 5.8, 6.6, SK)                 # 머리 — 머리카락 구멍으로 비친다
    c.outline(); return c

def body_north(frame):
    c = C(); sw = 1 if frame else -1
    _legs_front(c, sw)
    c.rect(11, 21, 20, 34, SK)
    c.rect(8, 22, 10, 30, SK); c.rect(21, 22, 23, 30, SK)
    c.ellipse(9, 30.5, 1.3, 1.3, SK); c.ellipse(22, 30.5, 1.3, 1.3, SK)
    c.rect(13, 19, 18, 22, SKD)
    c.ellipse(16, 14, 5.8, 6.6, SK)                 # 머리 (북향은 머리카락이 다 덮는다)
    c.outline(); return c

def body_side(frame, pose="walk"):
    c = C()
    if pose == "walk": swing, arm = (2, 1) if frame == 0 else (-2, -1)
    else:              swing, arm = 0, (0 if frame == 0 else 1)
    for i, x in enumerate((13, 16)):
        off = swing if i == 0 else -swing
        c.rect(x, 33, x+2, 43, SK)
        c.rect(x+off, 43, x+2+off, FOOT_Y, AC)
    c.rect(12, 21, 19, 34, SK)
    c.rect(15, 19, 18, 22, SKD)
    c.rect(16, 22, 18, 28+arm, SK)                  # 팔
    c.ellipse(17, 29+arm, 1.3, 1.3, SK)
    c.ellipse(17, 13.6, 5.4, 6.6, SK)               # 머리
    c.outline(); return c

def body_special(frame):
    """발은 땅(FOOT_Y)에 그대로 두고 무릎을 접는다. 몸만 내려앉는다."""
    c = C(); d, reach = 8, (0 if frame == 0 else 2)
    c.rect(13, 43, 19, FOOT_Y, AC)                  # 발 — 땅에 그대로
    c.rect(15, 39, 17, 43, SK)                      # 정강이
    c.rect(11, 36, 18, 39, SK)                      # 허벅지 — 앞으로 튀어나온 무릎
    c.rect(13, 21+d, 19, 37, SK)                    # 몸통 (짧아진다)
    c.rect(15, 19+d, 18, 22+d, SKD)
    c.rect(18, 25+d, 23+reach, 27+d, SK)            # 내민 손
    c.ellipse(24+reach, 26+d, 1.7, 1.7, SK)
    c.ellipse(17, 13.6+d, 5.4, 6.6, SK)             # 머리
    c.outline(); return c


# ══ hair — 방향당 한 장. 프레임과 무관 ════════════════════════════════
def _tails(c, lx, rx, top, bot):
    """양갈래는 좌우 대칭이라 E/W 미러가 깨지지 않는다 (§4.5).
       포니테일 하나면 미러할 때 머리가 반대쪽으로 넘어간다."""
    for x in (lx, rx):
        c.ellipse(x, (top+bot)/2, 2.1, (bot-top)/2, HM)
        c.ellipse(x, bot-1.4, 1.8, 1.8, HD)
        c.ellipse(x, top+0.5, 2.0, 1.1, AC)         # 머리끈

def hair_south():
    c = C(); _tails(c, 7.5, 24.5, 12, 24)
    c.ellipse(16, 13, 6.4, 7.2, HM)
    c.ellipse(16, 15.6, 4.8, 5.2, TR)               # 얼굴 구멍 — 몸통의 머리가 비친다
    c.ellipse(16, 9.0, 6.0, 3.2, HM)                # 앞머리 (눈 자리를 비운다)
    c.rect(11, 11, 21, 11, HD)
    c.ellipse(16, 8.0, 5.0, 2.0, HL)
    c.outline(); return c

def hair_north():
    c = C(); _tails(c, 7.5, 24.5, 12, 24)
    c.ellipse(16, 13, 6.0, 7.0, HM)                 # 뒤통수 — 얼굴 구멍이 없다
    c.ellipse(16, 10.0, 5.6, 4.0, HL)
    c.rect(12, 16, 20, 19, HD)                      # 목덜미
    c.outline(); return c

def hair_side():
    c = C()
    c.ellipse(9.5, 18, 2.6, 5.4, HM); c.ellipse(9.5, 22, 2.0, 1.8, HD)
    c.ellipse(10.5, 13.2, 2.0, 1.1, AC)
    c.ellipse(16, 12.6, 6.0, 7.2, HM)
    c.ellipse(18.6, 15.4, 4.0, 4.8, TR)             # 얼굴 구멍
    c.ellipse(15.4, 8.8, 5.6, 3.0, HM)              # 앞머리
    c.ellipse(15, 7.6, 4.6, 2.0, HL)
    c.outline(); return c

def hair_special():
    c = C(); d = 8
    c.ellipse(9.5, 18+d, 2.6, 5.2, HM); c.ellipse(9.5, 22+d, 2.0, 1.8, HD)
    c.ellipse(10.5, 13.2+d, 2.0, 1.1, AC)
    c.ellipse(16, 12.6+d, 6.0, 7.2, HM)
    c.ellipse(18.6, 15.4+d, 4.0, 4.8, TR)
    c.ellipse(15.4, 8.8+d, 5.6, 3.0, HM)
    c.ellipse(15, 7.6+d, 4.6, 2.0, HL)
    c.outline(); return c


# ══ top / bottom — 의상. 방향당 한 장 ════════════════════════════════
def top_south():
    c = C()
    c.rect(10, 21, 21, 31, TL); c.rect(10, 28, 21, 31, TD)
    c.rect(8, 21, 10, 24, TL); c.rect(21, 21, 23, 24, TL)      # 소매
    c.outline(); return c

def top_north():
    c = C()
    c.rect(10, 21, 21, 31, TL); c.rect(10, 28, 21, 31, TD)
    c.rect(8, 21, 10, 24, TL); c.rect(21, 21, 23, 24, TL)
    c.outline(); return c

def top_side():
    c = C()
    c.rect(11, 21, 20, 31, TL); c.rect(11, 28, 20, 31, TD)
    c.rect(16, 21, 19, 24, TL)
    c.outline(); return c

def top_special():
    c = C(); d = 8
    c.rect(12, 21+d, 20, 29+d, TL); c.rect(12, 27+d, 20, 29+d, TD)
    c.rect(17, 22+d, 20, 25+d, TL)
    c.outline(); return c

def bottom_south():
    c = C(); c.rect(11, 31, 20, 36, PL); c.rect(11, 34, 20, 36, PD)
    c.rect(15, 33, 16, 36, PD)                      # 가랑이
    c.outline(); return c

def bottom_north():
    c = C(); c.rect(11, 31, 20, 36, PL); c.rect(11, 34, 20, 36, PD)
    c.outline(); return c

def bottom_side():
    c = C(); c.rect(12, 31, 19, 36, PL); c.rect(12, 34, 19, 36, PD)
    c.outline(); return c

def bottom_special():
    c = C(); d = 8
    c.rect(11, 34, 19, 39, PL); c.rect(11, 37, 19, 39, PD)
    c.outline(); return c


# ══ gear — 배낭. 북향에서 얼굴이 없으므로 뒷모습의 정체성 (§4.6) ══════
def gear_south():
    """정면에서는 어깨끈 두 줄만 보인다"""
    c = C()
    c.rect(12, 21, 12, 28, AC); c.rect(19, 21, 19, 28, AC)
    c.outline(); return c

def gear_north():
    """뒷모습의 정체성. 상의보다 좁아야 가방으로 읽힌다"""
    c = C()
    c.rect(12, 21, 12, 24, AC); c.rect(19, 21, 19, 24, AC)     # 어깨끈
    c.ellipse(16, 28.5, 3.8, 4.0, AC)                          # 가방 몸통 — 상의보다 좁게
    c.ellipse(16, 25.6, 3.8, 1.8, HD)                          # 덮개 (가죽)
    c.rect(15, 26, 16, 27, HD)                                 # 잠금
    c.ellipse(16, 31, 2.8, 1.2, HD)
    c.outline(); return c

def gear_side():
    c = C()
    c.ellipse(12.0, 26, 2.4, 3.8, AC)                          # 등 뒤 작은 가방
    c.ellipse(12.0, 23.6, 2.4, 1.4, HD)
    c.rect(15, 22, 15, 27, AC)                                 # 어깨끈
    c.outline(); return c

def gear_special():
    c = C(); d = 8
    c.ellipse(12.0, 26+d, 2.4, 3.8, AC)
    c.ellipse(12.0, 23.6+d, 2.4, 1.4, HD)
    c.rect(15, 22+d, 15, 27+d, AC)
    c.outline(); return c


# ══ eye ═══════════════════════════════════════════════════════════════
EYE_PAL = [(0,0,0,0)]*10 + [(28,22,20), (250,246,238)]
ED, ELi = 10, 11

def eye(expr="기본", angle="front"):
    """얼굴 폭이 9px 다. 눈은 **1픽셀 폭**이어야 얼굴이 남는다.

    §4.6 의 '밝은 1픽셀 외곽'은 어두운 털 위에서 필요한 규칙이라
    피부 위에 얹는 사람 눈에는 쓰지 않는다 — 쓰면 눈이 얼굴을 다 덮는다.

    표정은 굵기와 곡률로 낸다:
      기본 1×2 점 · 놀람 굵은 세로 · 기쁨 위로 휜 호
    """
    GAP = 3
    if expr == "기쁨":
        w = 3*2 + GAP
        c = C(w, 4)
        for cx in (0, 3 + GAP):
            c.set(cx, 2, ED); c.set(cx+1, 1, ED); c.set(cx+2, 2, ED)
    elif expr == "놀람":
        w = 2*2 + GAP
        c = C(w, 4)
        for cx in (0, 2 + GAP):
            c.rect(cx, 0, cx+1, 2, ED); c.set(cx, 0, ELi)
    else:  # 기본 — 1×2. 3픽셀로 길게 하면 눈이 째진다
        w = 1*2 + GAP
        c = C(w, 4)
        for cx in (0, 1 + GAP):
            c.rect(cx, 1, cx, 2, ED)
    if angle == "side":                          # 한쪽만 남긴다
        half = C((c.w + 1)//2 - GAP//2, c.h)
        for y in range(c.h):
            for x in range(half.w): half.px[y][x] = c.px[y][x]
        return half
    return c


# ══ 레이어 목록 ═══════════════════════════════════════════════════════
BODY = {"move_south_0": body_south(0), "move_south_1": body_south(1),
        "move_north_0": body_north(0), "move_north_1": body_north(1),
        "move_side_0":  body_side(0),   "move_side_1":  body_side(1),
        "idle_0": body_side(0, "idle"), "idle_1": body_side(1, "idle"),
        "special_0": body_special(0),   "special_1": body_special(1)}

def _dirset(fs): return {"south": fs[0](), "north": fs[1](), "side": fs[2](), "special": fs[3]()}
HAIR   = _dirset((hair_south, hair_north, hair_side, hair_special))
TOP    = _dirset((top_south, top_north, top_side, top_special))
BOTTOM = _dirset((bottom_south, bottom_north, bottom_side, bottom_special))
GEAR   = _dirset((gear_south, gear_north, gear_side, gear_special))

# 그리는 순서 — 뒤에서 앞으로
ORDER = ["gear_back", "body", "bottom", "top", "gear_front", "hair", "eye"]
ANCHORS = {"eye_front": [16, 17], "eye_side": [19, 17], "head": [16, 1]}
# 눈 스프라이트는 9×5 / 5×5 다. 앵커는 눈동자 쌍의 중심.

DIR_OF = {"move_south": "south", "move_north": "north", "move_side": "side",
          "idle": "side", "special": "special"}


def compose(anim_frame, pal, expr="기본", parts=("hair","top","bottom","gear","eye")):
    """레이어를 순서대로 얹는다. 엔진에서는 각 레이어가 자식 Sprite2D 다."""
    anim = anim_frame.rsplit("_", 1)[0]
    d = DIR_OF[anim]
    im = Image.new("RGBA", (W, H), (0,0,0,0))
    im.alpha_composite(BODY[anim_frame].img(pal))
    if "bottom" in parts: im.alpha_composite(BOTTOM[d].img(pal))
    if "top" in parts:    im.alpha_composite(TOP[d].img(pal))
    # 가방은 등에 있다 — 북향에서는 상의 위, 그 밖에서는 어깨끈만 보인다
    if "gear" in parts:   im.alpha_composite(GEAR[d].img(pal))
    if "hair" in parts:   im.alpha_composite(HAIR[d].img(pal))
    if "eye" in parts and d != "north":
        ang = "front" if d == "south" else "side"
        e = eye(expr, ang)
        a = ANCHORS["eye_front" if ang == "front" else "eye_side"]
        im.alpha_composite(e.img(EYE_PAL), (a[0]-e.w//2, a[1]-1))
    return im


if __name__ == "__main__":
    pal = PALETTES["default"]
    root = os.path.join(OUT, "png", "player")
    for group, items in (("body", BODY), ("hair", HAIR), ("top", TOP),
                         ("bottom", BOTTOM), ("gear", GEAR)):
        d = os.path.join(root, group); os.makedirs(d, exist_ok=True)
        for name, c in items.items(): c.img(pal).save(os.path.join(d, name + ".png"))
    d = os.path.join(root, "eye"); os.makedirs(d, exist_ok=True)
    for expr in ("기본", "기쁨", "놀람"):
        for ang in ("front", "side"):
            eye(expr, ang).img(EYE_PAL).save(os.path.join(d, f"{ang}_{expr}.png"))
    n = len(BODY) + len(HAIR) + len(TOP) + len(BOTTOM) + len(GEAR) + 6
    print(f"플레이어 레이어 {n}장 "
          f"(몸통 {len(BODY)} · 머리 {len(HAIR)} · 상의 {len(TOP)} · 하의 {len(BOTTOM)} · 가방 {len(GEAR)} · 눈 6)")
