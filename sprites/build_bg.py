#!/usr/bin/env python3
"""
사파리 — 배경 타일 · 필드 오브젝트 · 단서 아이템 생성기

  타일 16×16 (32px 캐릭터 = 2타일 높이)
  오브젝트는 앵커가 바닥 중앙 — Y-sort 대상 (§6.2)
  단서 아이템은 tags.json 의 trait_to_sense 를 그대로 옮긴 것 (§5.4)
  전부 인덱스 컬러 — 밤낮은 팔레트 교체로 시험한다 (§7 조명 미결)
"""
import os, math, random
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))
T = 16  # 타일 크기

# 인덱스
(TR, OL, GD, GM, GL, DD, DM, DL, WD, WM, WL,
 KD, KM, SD, SM, AC) = range(16)

PALETTES = {
    "day": [(0,0,0,0),(38,46,36),
            (58,88,52),(84,120,64),(120,158,84),           # 풀
            (92,68,44),(126,96,62),(158,126,84),           # 흙
            (36,86,110),(58,124,150),(104,170,190),        # 물
            (72,52,34),(104,78,50),                        # 나무
            (78,82,86),(116,120,124),                      # 돌
            (214,96,84)],                                  # 강조 (열매·꽃)
    "dusk": [(0,0,0,0),(34,34,40),
            (58,70,56),(82,96,66),(116,124,80),
            (86,62,46),(116,86,60),(146,112,78),
            (40,72,96),(62,102,128),(104,142,166),
            (66,48,36),(96,70,50),
            (70,70,78),(104,104,112),
            (206,110,76)],
    "dawn": [(0,0,0,0),(30,34,44),
            (52,72,62),(76,102,74),(112,138,92),
            (86,66,54),(118,92,72),(150,122,96),
            (34,74,102),(58,110,140),(112,158,184),
            (66,50,40),(96,74,56),
            (72,74,86),(110,112,124),
            (222,124,110)],
    "night": [(0,0,0,0),(20,24,34),
            (32,48,48),(44,64,64),(64,88,86),
            (48,44,48),(66,60,62),(88,80,80),
            (22,44,68),(32,64,92),(58,96,124),
            (38,34,38),(56,50,52),
            (44,46,58),(68,70,84),
            (140,84,84)],
}

# 시간대 키프레임 — 이 사이를 보간하면 하루가 연속으로 흐른다
CYCLE = ["dawn", "day", "dusk", "night"]

# 오버레이 틴트 (곱연산). 팔레트가 색조를, 틴트가 밝기·채도를 담당한다.
TINTS = {"dawn": (0.92, 0.90, 1.00), "day": (1.00, 1.00, 1.00),
         "dusk": (1.00, 0.86, 0.78), "night": (0.62, 0.68, 0.92)}

def _rgba(c):
    return c if len(c) == 4 else (c[0], c[1], c[2], 255)

def lerp_pal(a, b, t):
    out = []
    for (ca, cb) in zip(a, b):
        ca, cb = _rgba(ca), _rgba(cb)
        if ca[3] == 0 and cb[3] == 0: out.append((0,0,0,0)); continue
        out.append(tuple(int(ca[i] + (cb[i]-ca[i])*t) for i in range(4)))
    return out

def lerp_tint(a, b, t):
    return tuple(a[i] + (b[i]-a[i])*t for i in range(3))

def at_time(u):
    """u ∈ [0,1) — 하루 한 바퀴. (팔레트, 틴트) 를 돌려준다."""
    n = len(CYCLE)
    f = (u % 1.0) * n
    i = int(f) % n; j = (i+1) % n; t = f - int(f)
    return (lerp_pal(PALETTES[CYCLE[i]], PALETTES[CYCLE[j]], t),
            lerp_tint(TINTS[CYCLE[i]], TINTS[CYCLE[j]], t))


class C:
    def __init__(s, w, h=None):
        s.w, s.h = w, h or w
        s.px = [[TR]*s.w for _ in range(s.h)]
    def set(s, x, y, v):
        if 0 <= x < s.w and 0 <= y < s.h: s.px[int(y)][int(x)] = v
    def get(s, x, y):
        return s.px[int(y)][int(x)] if 0 <= x < s.w and 0 <= y < s.h else TR
    def fill(s, v):
        for y in range(s.h):
            for x in range(s.w): s.px[y][x] = v
    def rect(s, x0, y0, x1, y1, v):
        for y in range(int(y0), int(y1)+1):
            for x in range(int(x0), int(x1)+1): s.set(x, y, v)
    def ellipse(s, cx, cy, rx, ry, v):
        for y in range(int(cy-ry)-1, int(cy+ry)+2):
            for x in range(int(cx-rx)-1, int(cx+rx)+2):
                if rx > 0 and ry > 0 and ((x-cx)/rx)**2 + ((y-cy)/ry)**2 <= 1.0: s.set(x, y, v)
    def blob(s, pts, v):
        for (x, y) in pts: s.set(x, y, v)
    def outline(s, solids, v=OL):
        add = []
        for y in range(s.h):
            for x in range(s.w):
                if s.px[y][x] != TR: continue
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    if s.get(x+dx, y+dy) in solids: add.append((x,y)); break
        for (x, y) in add: s.set(x, y, v)
    def img(s, pal, z=1):
        im = Image.new("RGBA", (s.w, s.h), (0,0,0,0)); p = im.load()
        pal = [_rgba(c) for c in pal]
        for y in range(s.h):
            for x in range(s.w): p[x, y] = pal[s.px[y][x]]
        return im.resize((s.w*z, s.h*z), Image.NEAREST) if z > 1 else im


# ── 타일 ──────────────────────────────────────────────────────────────
def grass(v=0):
    r = random.Random(1000 + v*37); c = C(T); c.fill(GM)
    for _ in range(r.randint(4, 7)):
        c.set(r.randrange(T), r.randrange(T), GD)
    for _ in range(r.randint(2, 4)):                  # 풀날 — 세로 2px 이하로 짧게
        x, y = r.randrange(T), r.randrange(1, T)
        c.set(x, y, GL)
        if r.random() < 0.5: c.set(x, y-1, GL)
    if r.random() < 0.35:                             # 가끔 작은 돌
        x, y = r.randrange(1, T-2), r.randrange(1, T-1)
        c.set(x, y, SD); c.set(x+1, y, SM)
    return c

def forest(v=0):
    """숲 바닥 — 어두운 풀 + 낙엽. TerrainMap 의 '숲' (감각 반경이 깎이는 곳)"""
    r = random.Random(3000 + v*41); c = C(T); c.fill(GD)
    for _ in range(r.randint(5, 8)): c.set(r.randrange(T), r.randrange(T), GM)
    for _ in range(r.randint(2, 4)):                      # 낙엽
        x, y = r.randrange(T-1), r.randrange(T)
        c.set(x, y, DM); c.set(x+1, y, DD)
    if r.random() < 0.4:
        x, y = r.randrange(T-2), r.randrange(T-1)
        c.set(x, y, KD); c.set(x+1, y, KD)                # 잔가지
    return c

def wetground(v=0):
    """물가 지면 — 동물이 서는 젖은 땅. TerrainMap 의 '물가'"""
    r = random.Random(4000 + v*29); c = C(T); c.fill(DL)
    for _ in range(r.randint(4, 7)): c.set(r.randrange(T), r.randrange(T), DM)
    for _ in range(r.randint(1, 2)):                      # 물 고인 자리 — 납작하게
        x, y = r.randrange(2, T-3), r.randrange(1, T-1)
        c.ellipse(x, y, 2.6, 0.9, WD)
        c.set(int(x), int(y), WM)
    for _ in range(r.randint(1, 3)): c.set(r.randrange(T), r.randrange(T), GD)
    return c

def dirt(v=0):
    r = random.Random(200+v); c = C(T); c.fill(DM)
    for _ in range(12): c.set(r.randrange(T), r.randrange(T), DD)
    for _ in range(7): c.set(r.randrange(T), r.randrange(T), DL)
    return c

def sand():
    r = random.Random(300); c = C(T); c.fill(DL)
    for _ in range(10): c.set(r.randrange(T), r.randrange(T), DM)
    return c

def rockground():
    r = random.Random(400); c = C(T); c.fill(SM)
    for _ in range(14): c.set(r.randrange(T), r.randrange(T), SD)
    for _ in range(4):
        x, y = r.randrange(T-4), r.randrange(T)
        c.rect(x, y, x+3, y, SD)
    return c

def water(frame=0):
    c = C(T); c.fill(WM)
    for i in range(3):
        y = (i*5 + frame*2) % T
        x = (i*6 + frame*3) % T
        c.rect(x, y, min(T-1, x+4), y, WL)
        c.rect((x+8) % T, (y+3) % T, min(T-1, (x+8) % T + 2), (y+3) % T, WD)
    return c

def shore(side):
    """물 위에 풀이 얹힌 가장자리. side: N E S W NE NW SE SW"""
    c = water(0)
    r = random.Random(500 + hash(side) % 97)
    def land(x, y):
        c.set(x, y, GM)
        if r.random() < 0.35: c.set(x, y, GD)
    for y in range(T):
        for x in range(T):
            n = r.randint(0, 2)
            if side == "N" and y < 7 + (1 if (x % 4 == 0) else 0): land(x, y)
            elif side == "S" and y > 8 - (1 if (x % 5 == 0) else 0): land(x, y)
            elif side == "W" and x < 7 + (1 if (y % 4 == 0) else 0): land(x, y)
            elif side == "E" and x > 8 - (1 if (y % 5 == 0) else 0): land(x, y)
            elif side == "NW" and (x < 7 or y < 7): land(x, y)
            elif side == "NE" and (x > 8 or y < 7): land(x, y)
            elif side == "SW" and (x < 7 or y > 8): land(x, y)
            elif side == "SE" and (x > 8 or y > 8): land(x, y)
    # 물가 밝은 선
    for y in range(T):
        for x in range(T):
            if c.px[y][x] in (WM, WD, WL):
                if any(c.get(x+dx, y+dy) in (GM, GD) for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))):
                    c.set(x, y, WL)
    return c


# ── 오브젝트 (앵커 = 바닥 중앙, Y-sort 대상) ──────────────────────────
def tree():
    c = C(32, 48)
    c.rect(14, 30, 18, 45, KM); c.rect(14, 30, 15, 45, KD)   # 줄기
    c.ellipse(16, 20, 13, 11, GM)                             # 수관
    c.ellipse(11, 15, 7, 6, GL); c.ellipse(22, 17, 6, 5, GL)
    c.ellipse(16, 27, 11, 5, GD)
    r = random.Random(11)
    for _ in range(9): c.set(r.randrange(6, 27), r.randrange(10, 28), GD)
    c.outline({GM, GL, GD, KM, KD})
    return c

def bush():
    c = C(24, 24)
    c.ellipse(12, 16, 10, 7, GM); c.ellipse(8, 12, 6, 5, GL); c.ellipse(16, 13, 5, 4, GL)
    c.ellipse(12, 20, 9, 3, GD)
    for (x, y) in ((6,13),(17,16),(11,10)): c.ellipse(x, y, 1.2, 1.2, AC)   # 열매
    c.outline({GM, GL, GD, AC})
    return c

def tuft():
    c = C(16, 16)
    for x, h, lean in ((3,6,-1),(6,9,0),(9,7,1),(12,5,1)):
        for i in range(h):
            c.set(x + (i*lean)//3, 15-i, GL if i > h//2 else GM)
            c.set(x + (i*lean)//3 + 1, 15-i, GM)
    c.outline({GM, GL})
    return c

def conifer():
    """침엽수 — 활엽수와 실루엣이 완전히 달라야 화면이 안 지루하다 (§4.2)"""
    c = C(32, 48)
    c.rect(15, 36, 17, 46, KM); c.rect(15, 36, 15, 46, KD)
    for i, (cy, w) in enumerate(((14, 6), (22, 9), (30, 12))):
        for dy in range(9):
            hw = int(w * dy / 9.0)
            c.rect(16-hw, cy+dy-4, 16+hw, cy+dy-4, GM if dy < 6 else GD)
        c.rect(16-w//3, cy-4, 16+w//3, cy-3, GL)
    c.ellipse(16, 8, 3, 4, GM)
    c.outline({GM, GL, GD, KM, KD})
    return c

def deadtree():
    """마른 나무 — 잎이 없어 실루엣이 완전히 다르다"""
    c = C(32, 48)
    c.rect(14, 16, 17, 46, KM); c.rect(14, 16, 14, 46, KD)
    for (x0, y0, x1, y1) in ((14,26,6,18),(17,22,25,14),(15,18,10,10),(17,30,24,26)):
        steps = max(abs(x1-x0), abs(y1-y0))
        for i in range(steps+1):
            c.set(x0 + (x1-x0)*i//steps, y0 + (y1-y0)*i//steps, KM)
            c.set(x0 + (x1-x0)*i//steps, y0 + (y1-y0)*i//steps + 1, KD)
    c.outline({KM, KD})
    return c

def stump():
    c = C(24, 16)
    c.rect(7, 6, 17, 14, KM); c.rect(7, 11, 17, 14, KD)
    c.ellipse(12, 6, 5.4, 2.6, KD)
    c.ellipse(12, 6, 3.4, 1.6, KM)
    c.ellipse(12, 6, 1.4, 0.8, KD)
    for (x, y) in ((6,12),(18,11)): c.ellipse(x, y, 1.8, 1.4, KD)   # 뿌리
    c.outline({KM, KD})
    return c

def bigrock():
    c = C(32, 24)
    c.ellipse(16, 16, 13, 7.5, SM)
    c.ellipse(12, 10, 7.5, 5, SM)
    c.ellipse(21, 12, 5.5, 3.6, SD)
    for (x, y) in ((9,13),(19,17),(14,19),(24,15)): c.set(x, y, SD)
    c.ellipse(16, 21, 12, 2.6, SD)
    c.outline({SM, SD})
    return c

def pebbles():
    c = C(16, 12)
    c.ellipse(4.5, 8, 3.2, 2.2, SM); c.ellipse(11, 9, 2.6, 1.8, SM)
    c.ellipse(8, 6, 1.8, 1.3, SD)
    c.ellipse(4.5, 9.4, 3.0, 1.0, SD); c.ellipse(11, 10.2, 2.4, 0.8, SD)
    c.outline({SM, SD})
    return c

def flowers():
    c = C(16, 16)
    for x, h in ((3,7),(7,9),(11,6)):
        for i in range(h): c.set(x, 14-i, GM)
        c.ellipse(x, 14-h, 1.6, 1.4, AC)
        c.set(x, 14-h, GL)
    c.outline({GM, GL, AC})
    return c

def mushroom():
    c = C(16, 12)
    c.rect(7, 6, 8, 11, DL)
    c.ellipse(7.5, 6, 4.4, 2.8, AC)
    for (x, y) in ((5,5),(9,6),(7,4)): c.set(x, y, DL)
    c.rect(11, 9, 12, 11, DL); c.ellipse(11.5, 9, 2.4, 1.6, AC)
    c.outline({AC, DL})
    return c

def rock():
    c = C(24, 16)
    c.ellipse(12, 11, 9, 5, SM); c.ellipse(9, 8, 5, 3.5, SM)
    c.ellipse(9, 7, 4, 2, (SD if False else SM))
    for (x, y) in ((7,9),(14,10),(11,12)): c.set(x, y, SD)
    c.ellipse(12, 14, 8, 2, SD)
    c.outline({SM, SD})
    return c

def log():
    c = C(32, 16)
    c.ellipse(17, 9, 13, 3.6, KM)                     # 누운 몸통
    c.rect(5, 9, 29, 12, KM)
    c.rect(5, 11, 29, 12, KD)                         # 아래 그늘
    c.ellipse(5.5, 9.5, 2.8, 3.8, KD)                 # 잘린 단면
    c.ellipse(5.5, 9.5, 1.6, 2.2, KM)
    c.ellipse(5.5, 9.5, 0.6, 0.9, KD)                 # 나이테
    r = random.Random(31)
    for _ in range(7):                                # 결
        x = r.randrange(10, 27); c.rect(x, 8, x, 9, KD)
    c.outline({KM, KD})
    return c

def reed():
    c = C(16, 24)
    for x, top in ((5,6),(8,3),(11,8)):
        c.rect(x, top, x, 23, GM); c.set(x, top, GL)
        c.ellipse(x, top+1, 1.2, 2.2, DM)
    c.outline({GM, GL, DM})
    return c


# ── 도움·치료 상황 (§2.6 — 사고 쪽으로만) ─────────────────────────────
def thornbush():
    c = C(24, 24)
    c.ellipse(12, 16, 9, 6, GD); c.ellipse(12, 20, 8, 3, GD)
    r = random.Random(7)
    for _ in range(14):
        x, y = r.randrange(4, 20), r.randrange(9, 20)
        c.set(x, y, SM); c.set(x, y-1, SM)
    c.outline({GD, SM})
    return c

def mud():
    c = C(24, 16)
    c.ellipse(12, 11, 10, 4.4, DD); c.ellipse(9, 10, 4, 2, DM)
    c.ellipse(15, 12, 3, 1.6, DM)
    c.outline({DD, DM})
    return c

def brokenbranch():
    c = C(24, 16)
    c.rect(2, 9, 21, 11, KM); c.rect(2, 11, 21, 11, KD)
    c.blob([(9,8),(10,7),(11,7),(15,12),(16,13)], KD)
    c.rect(12, 6, 13, 9, KM); c.rect(17, 11, 18, 14, KM)
    c.outline({KM, KD})
    return c


# ── 단서 아이템 (§5.4 trait_to_sense) ─────────────────────────────────
def clue_pawprint(big=False):
    c = C(T)
    s = 1.35 if big else 1.0
    for (dx, dy) in ((0, 0), (5, 4)):
        cx, cy = 5 + dx, 6 + dy
        c.ellipse(cx, cy+1.6*s, 2.2*s, 1.7*s, DD)
        for i, ox in enumerate((-2.2, -0.7, 0.8, 2.3)):
            c.ellipse(cx + ox*s, cy - 1.2*s, 0.8*s, 0.9*s, DD)
    return c

def clue_pinecone():
    c = C(T)
    c.ellipse(8, 9, 3.4, 4.6, KM)
    for y in range(5, 14, 2):
        for x in range(5, 12, 3): c.set(x + (y//2 % 2), y, KD)
    c.blob([(11,5),(12,6),(12,10),(11,12)], TR)   # 갉아먹힌 자리
    c.outline({KM, KD})
    return c

def clue_wetsoil():
    c = C(T)
    c.ellipse(8, 10, 6, 3.4, DD)
    c.ellipse(6, 9, 2.4, 1.4, WD); c.ellipse(10, 11, 1.8, 1.0, WD)
    c.outline({DD, WD})
    return c

def clue_slough():
    c = C(T)
    for i in range(11):
        a = math.radians(i*30)
        c.ellipse(8 + math.cos(a)*4.6, 8 + math.sin(a)*3.2, 1.5, 1.5, DL)
    for i in range(11):
        a = math.radians(i*30)
        c.set(int(8 + math.cos(a)*4.6), int(8 + math.sin(a)*3.2), DM)
    c.outline({DL, DM})
    return c

def clue_fur():
    c = C(T)
    for x, h in ((4,5),(6,7),(8,6),(10,8),(12,5)):
        for i in range(h): c.set(x, 12-i, DL if i % 2 else DM)
    c.ellipse(8, 12, 4.4, 1.6, DM)
    c.outline({DM, DL})
    return c

def mark_scent():
    """후각 표시 — 지면 흔적이 아니라 공중에 뜨는 표시"""
    c = C(T)
    for i in range(3):
        for y in range(2, 14):
            x = 4 + i*4 + int(math.sin(y*0.9)*1.4)
            if y % 2 == 0: c.set(x, y, AC)
    return c

def mark_sound():
    """청각 표시 — 지면 흔적이 아니라 공중에 뜨는 표시"""
    c = C(T)
    for r_ in (3, 5, 7):
        for i in range(14):
            a = math.radians(-55 + i*8)
            c.set(3 + math.cos(a)*r_, 8 + math.sin(a)*r_, AC)
    return c


# ── 먹이 아이템 (likes 태그) ──────────────────────────────────────────
def food_acorn():
    c = C(T); c.ellipse(8, 10, 3.2, 3.8, DM); c.ellipse(8, 6, 3.6, 2.0, KD)
    c.set(8, 3, KD); c.outline({DM, KD}); return c

def food_berry():
    c = C(T)
    c.ellipse(6, 10, 2.6, 2.6, AC); c.ellipse(10, 9, 2.4, 2.4, AC)
    c.rect(8, 4, 8, 7, GD); c.ellipse(10, 5, 2.0, 1.2, GM)
    c.outline({AC, GD, GM}); return c

def food_seed():
    c = C(T)
    for (x, y) in ((5,9),(9,7),(7,12),(11,11)): c.ellipse(x, y, 1.6, 1.2, DL)
    c.outline({DL}); return c

def food_fish():
    c = C(T)
    c.ellipse(8, 8, 5.2, 2.8, WL); c.blob([(13,6),(14,5),(14,11),(13,10),(13,8)], WM)
    c.set(4, 7, WD); c.ellipse(8, 8, 2.4, 1.2, WM)
    c.outline({WL, WM, WD}); return c

def food_grass():
    c = C(T)
    for x, h in ((4,7),(7,9),(10,6)):
        for i in range(h): c.set(x + i//4, 13-i, GL if i > h//2 else GM)
    c.outline({GM, GL}); return c


GRASS_N = 6
FOREST_N = 3
WET_N = 3
TILES = {f"grass_{i}": grass(i) for i in range(GRASS_N)}
TILES.update({f"forest_{i}": forest(i) for i in range(FOREST_N)})
TILES.update({f"wet_{i}": wetground(i) for i in range(WET_N)})
TILES.update({
         "dirt": dirt(), "sand": sand(), "rock": rockground(),
         "water_0": water(0), "water_1": water(1)})
for s in ("N","E","S","W","NE","NW","SE","SW"):
    TILES[f"shore_{s}"] = shore(s)

OBJECTS = {
    # 나무
    "tree": tree(), "conifer": conifer(), "deadtree": deadtree(), "stump": stump(),
    # 돌
    "bigrock": bigrock(), "rock": rock(), "pebbles": pebbles(),
    # 풀·식생
    "bush": bush(), "tuft": tuft(), "flowers": flowers(),
    "mushroom": mushroom(), "reed": reed(), "log": log(),
    # 도움·치료 상황 (§2.6 — 사고 쪽으로만)
    "thornbush": thornbush(), "mud": mud(), "branch": brokenbranch(),
}

CLUES = {"발자국": clue_pawprint(False), "큰발자국": clue_pawprint(True),
         "나무흔적": clue_pinecone(), "물자국": clue_wetsoil(),
         "허물": clue_slough(), "털": clue_fur(),
         "냄새표시": mark_scent(), "소리표시": mark_sound()}


# ── 먹이 4장 추가 — `likes` 에 있는데 그림이 없던 것들 ────────────────
# 도감의 "좋아해" 칸이 초식·육식 종에서 통째로 비어 있었다. 다섯 장으로는 부족하다.
#
# ★ 처음엔 타원으로 그렸다가 넷 다 실패했다 — 16px 에서 타원을 겹치면 잎도 뿌리도
#   벌레도 전부 "갈색 덩어리" 가 된다. **이 크기에서는 실루엣이 전부**라
#   행을 직접 찍는 편이 빠르고 정확하다. (발자국에서 이미 한 번 겪은 것)
def _art(rows, mapping):
    c = C(T)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in mapping: c.set(x, y, mapping[ch])
    return c

def food_leaf():
    c = _art([
        "................",
        "............##..",
        "..........####..",
        ".........#####..",
        "........######..",
        "...#..#######...",
        "..#####v#####...",
        ".######v#####...",
        "..#####v####....",
        "...####v###.....",
        "....######......",
        "....s##.........",
        "...s............",
        "..s.............",
        "................",
        "................",
    ], {"#": GM, "v": GD, "s": KD})
    for (x, y) in ((6,5),(7,4),(8,4),(9,3),(10,3)): c.set(x, y, GL)
    c.outline({GM, GL, GD, KD}); return c

def food_root():
    """당근 꼴 — 위가 넓고 아래로 뾰족해야 '뿌리' 로 읽힌다."""
    c = _art([
        "................",
        "....g..g..g.....",
        "....g.ggg.g.....",
        ".....gg#gg......",
        "....#######.....",
        "....#######.....",
        ".....#####......",
        ".....#####......",
        "......###.......",
        "......###.......",
        ".......#........",
        ".......#........",
        "................",
        "................",
        "................",
        "................",
    ], {"#": DL, "g": GM})
    for (x, y) in ((5,5),(6,4),(6,6),(7,7),(6,8)): c.set(x, y, DM)
    c.outline({DL, DM, GM}); return c

def food_insect():
    """딱정벌레. **다리가 몸 밖으로 나와야** 벌레로 읽힌다 —
    몸에 붙여 그리면 그냥 씨앗이다."""
    c = _art([
        "................",
        "....L......R....",
        ".....L....R.....",
        "......####......",
        "......####......",
        "..L..######..R..",
        ".....######.....",
        "..L..######..R..",
        ".....######.....",
        "..L..######..R..",
        ".....######.....",
        "......####......",
        "................",
        "................",
        "................",
        "................",
    ], {"#": KM, "L": KD, "R": KD})
    for y in (5, 7, 9):                       # 다리를 몸까지 이어 붙인다
        c.rect(2, y, 4, y, KD); c.rect(11, y, 13, y, KD)
    c.set(6, 2, KD); c.set(9, 2, KD)          # 더듬이 뿌리
    c.rect(7, 3, 8, 11, KD)                   # 등 가운데 갈라진 선
    c.outline({KM, KD}); return c

def food_meat():
    """뼈다귀 붙은 고기. 아이가 보는 화면이라 **만화 같은 형태**로 — 덩어리는 안 된다."""
    c = _art([
        "................",
        "................",
        "........####....",
        "......########..",
        ".....##########.",
        ".....##########.",
        "......########..",
        "....b..######...",
        "...bbb..####....",
        "....bbbb........",
        "...bb..bb.......",
        "..bbb...........",
        "...b............",
        "................",
        "................",
        "................",
    ], {"#": AC, "b": SM})
    for (x, y) in ((7,3),(8,3),(6,4),(7,4),(8,4)): c.set(x, y, DL)
    c.outline({AC, SM, DL}); return c

FOODS = {"견과": food_acorn(), "열매": food_berry(), "씨앗": food_seed(),
         "물고기": food_fish(), "풀": food_grass(),
         "나뭇잎": food_leaf(), "뿌리": food_root(),
         "곤충": food_insect(), "고기": food_meat()}


def save_all():
    pal = PALETTES["day"]
    for group, items in (("tiles", TILES), ("objects", OBJECTS),
                         ("clues", CLUES), ("food", FOODS)):
        d = os.path.join(OUT, "png", "bg", group); os.makedirs(d, exist_ok=True)
        for name, c in items.items():
            c.img(pal).save(os.path.join(d, f"{name}.png"))
    n = sum(len(x) for x in (TILES, OBJECTS, CLUES, FOODS))
    print(f"배경 {n}장 (타일 {len(TILES)} · 오브젝트 {len(OBJECTS)} · 단서 {len(CLUES)} · 먹이 {len(FOODS)})")

if __name__ == "__main__":
    save_all()


# 지형별로 어울리는 프롭. `palettes.json` 으로 나가고 타이틀 배경도 이걸 읽는다 —
# 출처가 둘이 되면 어긋난다.
PROP_TERRAIN = {
    "초원": ["tuft", "flowers", "rock", "pebbles", "bigrock", "bush"],
    "숲":   ["tree", "conifer", "deadtree", "stump", "mushroom", "log", "bush",
             "thornbush", "branch"],
    "물가": ["reed", "pebbles", "mud", "tuft"],
    "바위": ["bigrock", "rock", "pebbles", "deadtree"],
}

# 지형 이름 → 그 지형을 채우는 타일 키들
TERRAIN_TILES = {
    "초원": [f"grass_{i}"  for i in range(GRASS_N)],
    "숲":   [f"forest_{i}" for i in range(FOREST_N)],
    "물가": [f"wet_{i}"    for i in range(WET_N)],
    "바위": ["rock"],
}
