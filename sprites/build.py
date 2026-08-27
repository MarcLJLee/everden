#!/usr/bin/env python3
"""
사파리 — 플레이스홀더 스프라이트 생성기

BRIEF 규칙을 코드로 강제한다:
  §4.4  외곽선은 검정이 아니라 해당 색의 어두운 톤
  §4.5  이동 4방향 / 대기 좌우 2방향 / 특징 동작 측면 1방향
  §4.6  몸통에는 눈·입을 그리지 않는다 (별도 레이어)
  §4.6  ★ 걷기 프레임에 상하 바운스를 넣지 않는다 — 다리만 바뀐다 (바운스는 노드 Y)
  §4.6  북향에서는 눈 레이어를 숨긴다
  §4.3  인덱스 컬러로 그리고 팔레트를 갈아끼운다
  tags.json  size_class → 캔버스 (소 24 / 중 32 / 대 48)

인덱스: 0 투명 · 1 외곽선 · 2 어두운털 · 3 중간털 · 4 밝은털 · 5 배/무늬 · 6 발·코 · 7 눈어둠 · 8 눈밝음
"""
import os, math, json
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))
TRANSPARENT, OUTLINE, DARK, MID, LIGHT, BELLY, PAW, EYED, EYEL = range(9)

# ── 팔레트 (§4.3 — 그림 한 장에 팔레트를 갈아끼운다) ────────────────────
PALETTES = {
    "dog_default":  [(0,0,0,0),(58,38,26),(122,84,50),(160,115,70),(196,148,95),(232,206,164),(70,48,34),(34,26,18),(244,236,224)],
    "dog_black":    [(0,0,0,0),(26,24,30),(56,52,62),(82,78,92),(112,108,124),(198,196,206),(38,36,44),(18,16,22),(236,232,240)],
    "dog_cream":    [(0,0,0,0),(120,88,52),(196,158,104),(224,190,134),(244,220,170),(255,246,224),(140,104,64),(34,26,18),(244,236,224)],
    "cat_default":  [(0,0,0,0),(48,40,38),(96,84,80),(134,120,114),(172,158,150),(238,230,220),(58,48,46),(28,22,18),(240,232,220)],
    "cat_ginger":   [(0,0,0,0),(92,50,26),(168,96,42),(206,132,62),(236,172,96),(252,232,196),(110,62,32),(28,22,18),(240,232,220)],
    "cat_black":    [(0,0,0,0),(24,22,28),(48,46,56),(70,68,80),(96,94,110),(150,148,162),(34,32,40),(18,16,22),(236,232,240)],
    "squirrel_default": [(0,0,0,0),(52,44,40),(104,92,84),(140,126,116),(176,162,150),(232,224,212),(64,54,48),(34,26,18),(244,236,224)],
    "squirrel_rare":    [(0,0,0,0),(96,58,26),(196,116,44),(226,150,64),(246,186,96),(255,238,196),(120,72,32),(34,26,18),(244,236,224)],
    "raccoon_dog_default": [(0,0,0,0),(46,40,38),(86,76,70),(124,112,102),(162,150,138),(226,216,200),(58,50,46),(30,24,20),(240,234,224)],
    "otter_default":    [(0,0,0,0),(44,32,24),(88,64,46),(120,90,64),(152,118,86),(212,192,164),(56,42,32),(30,24,18),(240,234,224)],
    "water_deer_default": [(0,0,0,0),(72,48,30),(134,96,58),(174,130,80),(208,164,108),(240,226,198),(86,60,38),(32,26,18),(244,236,224)],
    "leopard_cat_default": [(0,0,0,0),(70,50,32),(146,110,66),(186,146,88),(220,182,118),(244,232,206),(84,60,38),(30,24,18),(242,234,220)],
    "toad_default":     [(0,0,0,0),(44,46,30),(84,88,52),(114,120,70),(146,152,92),(206,200,150),(58,60,38),(28,26,16),(238,236,210)],
    "magpie_default":   [(0,0,0,0),(22,22,28),(40,40,50),(60,60,74),(88,88,106),(238,238,244),(46,44,40),(18,16,20),(236,232,240)],
    "sparrow_default":  [(0,0,0,0),(62,48,34),(112,88,60),(148,120,84),(184,154,112),(226,212,186),(78,60,42),(30,24,18),(242,234,220)],
    "snake_default":    [(0,0,0,0),(38,50,34),(74,94,58),(104,128,76),(138,166,98),(206,208,158),(52,64,40),(28,26,18),(238,236,210)],
}

# ── 캔버스 ────────────────────────────────────────────────────────────
class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[TRANSPARENT]*w for _ in range(h)]

    def set(self, x, y, v):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = v

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return TRANSPARENT

    def ellipse(self, cx, cy, rx, ry, v):
        for y in range(int(cy-ry)-1, int(cy+ry)+2):
            for x in range(int(cx-rx)-1, int(cx+rx)+2):
                if rx <= 0 or ry <= 0:
                    continue
                if ((x-cx)/rx)**2 + ((y-cy)/ry)**2 <= 1.0:
                    self.set(x, y, v)

    def rect(self, x0, y0, x1, y1, v):
        for y in range(int(y0), int(y1)+1):
            for x in range(int(x0), int(x1)+1):
                self.set(x, y, v)

    def blob(self, pts, v):
        for (x, y) in pts:
            self.set(x, y, v)

    def edge_lower(self, cx, cy, rx, ry, v=OUTLINE):
        """타원의 아래쪽 윤곽을 찍는다. 머리가 몸통에 파묻히는 것을 막는다."""
        for x in range(int(cx-rx), int(cx+rx)+1):
            t = 1.0 - ((x-cx)/rx)**2
            if t < 0: continue
            y = cy + ry*math.sqrt(t)
            self.set(x, int(round(y)), v)
            self.set(x, int(round(y))-1, v)

    def shade_top_light(self):
        """빛은 위에서. 위가 비면 밝게, 아래쪽 두 줄은 어둡게. (§4.4 바닥은 차분히)"""
        src = [row[:] for row in self.px]
        for y in range(self.h):
            for x in range(self.w):
                if src[y][x] != MID:
                    continue
                above_empty = (y-2 < 0) or src[y-2][x] in (TRANSPARENT,)
                below_empty = (y+2 >= self.h) or src[y+2][x] in (TRANSPARENT,)
                if above_empty:
                    self.px[y][x] = LIGHT
                elif below_empty:
                    self.px[y][x] = DARK

    def outline_pass(self):
        """§4.4 — 외곽선은 검정이 아니라 그 색의 어두운 톤(인덱스 1)"""
        solid = {DARK, MID, LIGHT, BELLY, PAW}
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] != TRANSPARENT:
                    continue
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    if self.get(x+dx, y+dy) in solid:
                        add.append((x, y)); break
        for (x, y) in add:
            self.set(x, y, OUTLINE)

    def to_image(self, palette):
        img = Image.new("RGBA", (self.w, self.h), (0,0,0,0))
        p = img.load()
        for y in range(self.h):
            for x in range(self.w):
                p[x, y] = palette[self.px[y][x]]
        return img

    def mirrored(self):
        c = Canvas(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                c.px[y][self.w-1-x] = self.px[y][x]
        return c


# ── 개 (중형 · 32×32) ──────────────────────────────────────────────────
# 발 접지선 y=27. 몸통 중심 Y는 프레임 간 고정 — 바운스는 노드가 한다(§4.6).
DOG_W = DOG_H = 32
DOG_BODY_Y = 17
DOG_FOOT_Y = 27

def dog_leg(c, x, top, bottom, near=True):
    w = 2 if near else 1
    c.rect(x, top, x+w, bottom, MID if near else DARK)
    c.rect(x, bottom-1, x+w, bottom, PAW)

def dog_side(frame, pose="walk", tail_deg=0):
    c = Canvas(DOG_W, DOG_H)
    # 꼬리 — 몸통 왼쪽 가장자리에서 시작해 위로 말린다. tail_deg 로 흔든다.
    for i in range(7):
        a = math.radians(200 + tail_deg + i*17)
        c.ellipse(7.6 + math.cos(a)*4.4, 13.6 + math.sin(a)*4.4, 1.8, 1.8, MID)
    if pose == "walk":
        back_x, front_x = (8, 19) if frame == 0 else (10, 17)
        far_off = 2 if frame == 0 else -2
    else:
        back_x, front_x = 9, 18
        far_off = 1 if frame == 1 else 0
    dog_leg(c, back_x + far_off + 4, DOG_BODY_Y+4, DOG_FOOT_Y, near=False)
    dog_leg(c, front_x + far_off - 4, DOG_BODY_Y+4, DOG_FOOT_Y, near=False)
    c.ellipse(14, DOG_BODY_Y, 8.4, 5.0, MID)          # 몸통
    c.ellipse(19.5, DOG_BODY_Y-2, 4.8, 5.2, MID)      # 가슴/목 — 머리까지 이어진다
    c.ellipse(14, DOG_BODY_Y+3.4, 6.4, 1.8, BELLY)    # 배
    dog_leg(c, back_x, DOG_BODY_Y+4, DOG_FOOT_Y, near=True)
    dog_leg(c, front_x, DOG_BODY_Y+4, DOG_FOOT_Y, near=True)
    c.ellipse(23.5, 11, 5.2, 5.0, MID)                # 머리 (목과 붙어 있다)
    c.ellipse(28, 12.8, 3.2, 2.2, BELLY)              # 주둥이
    c.ellipse(29.6, 12.2, 1.2, 1.0, PAW)              # 코
    c.ellipse(20.9, 12.4, 1.6, 2.9, DARK)             # 처진 귀 (머리 옆으로 늘어진다)
    c.shade_top_light(); c.outline_pass()
    return c

def dog_south(frame):
    c = Canvas(DOG_W, DOG_H)
    off = 1 if frame else -1
    for i, x in enumerate((10, 19)):                  # 뒷다리
        dog_leg(c, x, DOG_BODY_Y+4, DOG_FOOT_Y, near=False)
    c.ellipse(16, DOG_BODY_Y+1, 6.6, 5.2, MID)
    c.rect(12, DOG_BODY_Y+2, 20, DOG_BODY_Y+4, BELLY)
    dog_leg(c, 12+off, DOG_BODY_Y+4, DOG_FOOT_Y, near=True)
    dog_leg(c, 17-off, DOG_BODY_Y+4, DOG_FOOT_Y, near=True)
    c.ellipse(16, 10.5, 5.4, 5.0, MID)                # 머리 (정면)
    c.edge_lower(16, 10.5, 5.4, 5.0)                  # 머리 아래 윤곽 — 몸통과 분리
    c.ellipse(16, 12.6, 3.0, 1.6, BELLY)              # 주둥이 (납작하게)
    c.ellipse(16, 12.0, 1.2, 0.8, PAW)                # 코
    c.ellipse(10.6, 11, 2.1, 3.8, DARK)               # 귀 — 머리 바깥으로
    c.ellipse(21.4, 11, 2.1, 3.8, DARK)
    c.shade_top_light(); c.outline_pass()
    return c

def dog_north(frame):
    c = Canvas(DOG_W, DOG_H)
    off = 1 if frame else -1
    c.ellipse(16, 12, 1.8, 4.2, MID)                  # 꼬리 (뒤에서 보임)
    for x in (10, 19):
        dog_leg(c, x, DOG_BODY_Y+4, DOG_FOOT_Y, near=False)
    c.ellipse(16, DOG_BODY_Y+1, 6.6, 5.2, MID)
    dog_leg(c, 12+off, DOG_BODY_Y+4, DOG_FOOT_Y, near=True)
    dog_leg(c, 17-off, DOG_BODY_Y+4, DOG_FOOT_Y, near=True)
    c.ellipse(16, 10.8, 5.2, 4.8, MID)                # 뒤통수 — 주둥이·코 없음
    c.edge_lower(16, 10.8, 5.2, 4.8)
    c.ellipse(10.8, 11, 2.1, 3.6, DARK)               # 귀 (뒷면)
    c.ellipse(21.2, 11, 2.1, 3.6, DARK)
    c.shade_top_light(); c.outline_pass()
    return c

def dog_special(frame):
    """특징 동작: 꼬리 흔들기 — 측면 1방향 (§4.5). 몸통은 그대로, 꼬리 각도만 바뀐다."""
    return dog_side(0, pose="idle", tail_deg=-16 if frame == 0 else 16)


# ── 고양이 (중형 · 32×32) ────────────────────────────────────────────
# 개와 같은 캔버스이므로 실루엣으로 갈려야 한다 (§4.2):
#   개     = 처진 귀 · 말린 긴 꼬리 · 매끈한 윤곽
#   고양이 = 뾰족 선 귀 · **아주 짧은 꼬리(꼬부랑)** · 보송보송한 윤곽
#
# 꼬리가 짧으므로 실루엣 구분은 **귀와 털**이 떠맡는다. 한국 길고양이는
# 꼬리가 짧거나 꺾인 개체가 흔하다 — 지역 감각이면서 개와도 갈린다.
#
# ★ 귀엽게 만드는 것은 비례다 — 머리를 크게, 몸을 둥글게, 다리를 짧게.
#   날씬하게 그리면 고양이가 아니라 사슴이 된다.
CAT_BODY_Y = 18
CAT_FOOT_Y = 27

def _tri_up(c, cx, base_y, half_w, h, v):
    """위로 뾰족한 삼각형 — 고양이 귀"""
    for i in range(int(h)+1):
        w = half_w * (1 - i/float(h))
        c.rect(cx-w, base_y-i, cx+w, base_y-i, v)

def _fluff(c, pts, v=MID, r=1.5):
    """윤곽에 털 뭉치를 얹는다. 매끈한 타원은 고양이로 안 읽힌다."""
    for (x, y) in pts:
        c.ellipse(x, y, r, r, v)

def cat_leg(c, x, top, bottom, near=True):
    w = 1 if near else 0
    c.rect(x, top, x+w+1, bottom, MID if near else DARK)
    c.rect(x, bottom-1, x+w+1, bottom, PAW)

def cat_side(frame, pose="walk", tail_deg=0):
    c = Canvas(DOG_W, DOG_H)
    # 아주 짧은 꼬부랑 꼬리
    tw = math.radians(tail_deg)
    c.ellipse(6.6 - math.sin(tw)*0.8, 15.4, 2.1, 2.3, MID)
    c.ellipse(5.8 - math.sin(tw)*1.6, 13.0, 1.7, 1.7, MID)
    if pose == "walk":
        back_x, front_x = (9, 19) if frame == 0 else (11, 17)
        far_off = 2 if frame == 0 else -2
    else:
        back_x, front_x = 10, 18
        far_off = 1 if frame == 1 else 0
    cat_leg(c, back_x + far_off + 3, CAT_BODY_Y+4, CAT_FOOT_Y, near=False)
    cat_leg(c, front_x + far_off - 3, CAT_BODY_Y+4, CAT_FOOT_Y, near=False)
    c.ellipse(14.0, CAT_BODY_Y, 7.6, 5.0, MID)                   # 둥글고 통통한 몸
    c.ellipse(19.2, CAT_BODY_Y-0.6, 4.6, 4.8, MID)               # 가슴
    _fluff(c, [(8.5,13.2),(11.5,12.6),(15,12.6),(18,13.0)])      # 등 털
    _fluff(c, [(7.2,20.5),(10.5,22.2),(14,22.6)], r=1.4)         # 배 털
    c.ellipse(13.5, CAT_BODY_Y+3.2, 5.6, 1.6, BELLY)
    cat_leg(c, back_x, CAT_BODY_Y+4, CAT_FOOT_Y, near=True)
    cat_leg(c, front_x, CAT_BODY_Y+4, CAT_FOOT_Y, near=True)
    # 개(55-65cm)보다 작은 45-50cm 다. 같은 캔버스를 쓰되 실루엣이 개를 넘지 않아야 한다.
    c.ellipse(23.8, 14.0, 4.6, 4.4, MID)                         # 머리 — 개보다 한 뼘 작게
    _fluff(c, [(19.8,15.4),(27.4,15.6),(20.6,11.8)], r=1.3)      # 볼 털
    # ★ 고양이는 주둥이가 짧다. 머리 실루엣 밖으로 거의 안 나간다 (개는 2.5px 나간다)
    c.ellipse(26.6, 15.2, 1.7, 1.4, BELLY)                       # 짧은 주둥이
    c.ellipse(27.6, 14.8, 0.9, 0.7, PAW)                         # 코
    _tri_up(c, 21.0, 11.0, 2.0, 3.0, MID)                        # 뾰족 귀 (뒤)
    _tri_up(c, 25.4, 10.6, 2.0, 3.2, MID)                        # 뾰족 귀 (앞)
    c.shade_top_light(); c.outline_pass()
    return c

def cat_south(frame):
    c = Canvas(DOG_W, DOG_H)
    off = 1 if frame else -1
    c.ellipse(21.8, 16.6, 2.0, 2.2, MID)                         # 짧은 꼬리가 옆으로 삐죽
    c.ellipse(23.0, 14.6, 1.6, 1.6, MID)
    for x in (11, 19):
        cat_leg(c, x, CAT_BODY_Y+4, CAT_FOOT_Y, near=False)
    c.ellipse(16, CAT_BODY_Y+1, 6.2, 5.0, MID)                   # 통통한 몸
    _fluff(c, [(10.6,19.5),(21.4,19.5),(11.6,22.6),(20.4,22.6)], r=1.4)
    c.ellipse(16, CAT_BODY_Y+3, 4.2, 1.7, BELLY)
    cat_leg(c, 12+off, CAT_BODY_Y+4, CAT_FOOT_Y, near=True)
    cat_leg(c, 18-off, CAT_BODY_Y+4, CAT_FOOT_Y, near=True)
    c.ellipse(16, 12.6, 5.0, 4.6, MID)                           # 머리 — 개보다 작게
    _fluff(c, [(11.6,13.8),(20.4,13.8),(12.4,9.8),(19.6,9.8)], r=1.4)   # 볼 털
    c.edge_lower(16, 12.6, 5.0, 4.6)
    c.ellipse(16, 14.6, 2.2, 1.3, BELLY)                         # 짧은 주둥이 (개는 3.0×1.6)
    c.ellipse(16, 14.1, 0.9, 0.6, PAW)
    _tri_up(c, 12.6, 10.0, 2.1, 3.4, MID)                        # 뾰족 귀
    _tri_up(c, 19.4, 10.0, 2.1, 3.4, MID)
    c.shade_top_light(); c.outline_pass()
    return c

def cat_north(frame):
    c = Canvas(DOG_W, DOG_H)
    off = 1 if frame else -1
    for x in (11, 19):
        cat_leg(c, x, CAT_BODY_Y+4, CAT_FOOT_Y, near=False)
    c.ellipse(16, CAT_BODY_Y+1, 6.2, 5.0, MID)
    _fluff(c, [(10.6,19.5),(21.4,19.5),(11.6,22.6),(20.4,22.6)], r=1.4)
    cat_leg(c, 12+off, CAT_BODY_Y+4, CAT_FOOT_Y, near=True)
    cat_leg(c, 18-off, CAT_BODY_Y+4, CAT_FOOT_Y, near=True)
    c.ellipse(16, 12.8, 4.8, 4.4, MID)                           # 뒤통수 — 얼굴 없음
    _fluff(c, [(11.8,13.8),(20.2,13.8),(12.6,9.8),(19.4,9.8)], r=1.4)
    c.edge_lower(16, 12.8, 4.8, 4.4)
    # 짧은 꼬리 — 몸통 중앙에 두면 머리에 가리므로 옆으로 삐죽 내민다
    c.ellipse(21.4, 16.4, 2.1, 2.3, MID)
    c.ellipse(22.8, 14.4, 1.7, 1.7, MID)
    _tri_up(c, 12.8, 10.2, 2.1, 3.2, DARK)                       # 귀 뒷면은 어둡다
    _tri_up(c, 19.2, 10.2, 2.1, 3.2, DARK)
    c.shade_top_light(); c.outline_pass()
    return c

def cat_special(frame):
    """특징 동작: 앉아서 앞발 들기 — 측면 1방향 (§4.5).

    기지개는 32px 에서 뭉개진다. **앉은 고양이**는 실루엣이 완전히 달라서
    2프레임으로도 확실히 읽힌다 — 세로로 선 몸, 앞으로 감은 꼬리.
    """
    c = Canvas(DOG_W, DOG_H)
    # 앉으면 짧은 꼬리가 엉덩이 옆에 붙는다
    c.ellipse(8.0, 23.6, 2.2, 2.2, MID)
    c.ellipse(6.4, 21.8, 1.7, 1.7, MID)
    c.ellipse(13.0, 21.6, 5.4, 5.4, MID)                # 엉덩이
    _fluff(c, [(8.4,19.0),(9.6,25.4),(13,26.2)], r=1.5)
    c.ellipse(17.2, 17.4, 4.6, 5.8, MID)                # 세운 상체
    _fluff(c, [(13.6,14.6),(16.4,12.4),(20.6,16.0)])
    c.rect(19, 20, 20, 26, MID); c.rect(19, 25, 20, 26, PAW)     # 딛고 있는 앞발
    if frame == 0:
        c.rect(16, 20, 17, 26, MID); c.rect(16, 25, 17, 26, PAW) # 다른 앞발도 바닥
    c.ellipse(19.6, 11.4, 5.0, 4.8, MID)                # 머리
    _fluff(c, [(15.6,13.0),(23.6,13.0),(16.4,8.6)], r=1.4)
    c.ellipse(23.2, 12.8, 2.2, 1.6, BELLY)              # 주둥이
    c.ellipse(24.4, 12.4, 1.0, 0.8, PAW)                # 코
    _tri_up(c, 16.8, 8.2, 2.1, 3.6, MID)                # 뾰족 귀
    _tri_up(c, 21.6, 7.8, 2.1, 3.8, MID)
    if frame == 1:                                      # 앞발을 든다 — 실루엣 밖으로
        c.rect(20, 17, 23, 19, MID)
        c.ellipse(23.6, 17.4, 1.8, 1.8, MID)
        c.ellipse(24.2, 17.0, 1.0, 0.8, PAW)
    c.shade_top_light(); c.outline_pass()
    return c


# ── 청설모 (소형 · 24×24) ──────────────────────────────────────────────
SQ_W = SQ_H = 24
SQ_FOOT_Y = 20

def squirrel_side(frame, pose="walk"):
    c = Canvas(SQ_W, SQ_H)
    # 거대한 말린 꼬리 — 이 종의 실루엣 (§4.2)
    for t in range(0, 30):
        a = math.pi * (0.42 + t/30.0 * 1.05)
        r = 6.4 - t*0.045
        x = 8.2 + math.cos(a) * r * 1.05
        y = 12.0 - math.sin(a) * r
        c.ellipse(x, y, 2.1, 2.1, MID)
    if pose == "walk":
        legs = (10, 15) if frame == 0 else (11, 14)
    else:
        legs = (10, 15)
    for x in legs:
        c.rect(x, 16, x+1, SQ_FOOT_Y, DARK)
        c.rect(x, SQ_FOOT_Y-1, x+1, SQ_FOOT_Y, PAW)
    c.ellipse(13, 14.5, 4.6, 4.0, MID)                # 몸통
    c.ellipse(13, 16.6, 3.4, 1.3, BELLY)
    c.ellipse(17.5, 10.5, 3.6, 3.4, MID)              # 머리
    c.ellipse(20.2, 11.6, 1.6, 1.2, BELLY)            # 주둥이
    c.ellipse(21.2, 11.2, 0.9, 0.7, PAW)
    c.edge_lower(17.5, 10.5, 3.6, 3.4)
    c.ellipse(16.0, 7.0, 1.3, 1.9, DARK)              # 뾰족 귀
    c.ellipse(19.2, 6.8, 1.3, 1.9, DARK)
    c.shade_top_light(); c.outline_pass()
    return c

def squirrel_south(frame):
    c = Canvas(SQ_W, SQ_H)
    # 꼬리는 뒤가 아니라 한쪽으로 말아 올린다 — 뒤에 두면 머리와 뭉쳐 덩어리가 된다
    for i in range(8):
        a = math.radians(120 + i*22)
        c.ellipse(7.6 + math.cos(a)*4.6, 10.4 + math.sin(a)*4.6, 1.9, 1.9, MID)
    off = 1 if frame else -1
    for x in (10, 14):
        c.rect(x, 16, x+1, SQ_FOOT_Y, DARK)
    c.ellipse(13, 15, 4.4, 4.2, MID)                  # 몸통
    c.rect(11+off, 16, 12+off, SQ_FOOT_Y, MID)
    c.rect(15-off, 16, 16-off, SQ_FOOT_Y, MID)
    c.ellipse(13, 16.6, 3.0, 1.3, BELLY)
    c.ellipse(13, 10.6, 3.8, 3.6, MID)                # 머리
    c.edge_lower(13, 10.6, 3.8, 3.6)
    c.ellipse(13, 12.4, 1.5, 1.1, BELLY)
    c.ellipse(13, 11.9, 0.8, 0.6, PAW)
    c.ellipse(10.4, 7.6, 1.3, 1.9, DARK)              # 뾰족 귀
    c.ellipse(15.6, 7.6, 1.3, 1.9, DARK)
    c.shade_top_light(); c.outline_pass()
    return c



# ── 나머지 여덟 종 (1차 슬라이스 — 측면 대기만) ────────────────────────
# §4.5 는 종당 16장(성체 10 + 아기 6)을 잡아뒀다. 여기 있는 것은 **그 중 측면 대기뿐**이다.
# 도감·지도·팀 편성·타이틀이 전부 이 한 장에 물려 있어서 먼저 뚫는다 —
# 나머지 방향은 그 종이 실제로 필드에 나갈 때 그린다.
#
# **실루엣이 전부다.** 32px 에서 색은 팔레트로 갈리지만 형태는 안 갈린다.
# 종마다 "이것 하나로 알아본다" 를 정해두고 그 특징에 픽셀을 몰아준다:
#
#   너구리 = 눈가 마스크 + 통통한 몸 + 짧은 다리
#   수달   = 길고 낮은 몸 + 굵은 꼬리          (개와 겹치지 않게 다리를 더 짧게)
#   고라니 = 긴 다리 + 긴 목 + 큰 귀           (뿔이 없다 — 고라니의 특징이다)
#   삵     = 고양이 골격 + 점무늬 + 굵은 줄무늬 꼬리
#   두꺼비 = 넙적하고 낮다 + 옆으로 벌어진 뒷다리
#   까치   = 검흰 대비 + 몸보다 긴 꼬리
#   참새   = 작고 동글 + 짧은 꼬리
#   뱀     = S자 + 다리 없음
def _leg(c, x, top, bottom, w=2, v=MID, paw=True):
    c.rect(x, top, x+w-1, bottom, v)
    if paw: c.rect(x, bottom-1, x+w-1, bottom, PAW)

def _stripes(c, pts, v=DARK):
    for (x, y, w) in pts: c.rect(x, y, x+w-1, y, v)


# ★ 걷기 = **다리만 바뀐다.** 몸을 위아래로 흔들지 않는다 — 바운스는 노드 Y 다 (§4.6).
#   대기는 흔들림이 1px, 걷기는 4px. 같은 함수에 pose 만 다르게 준다.
def _gait(frame, pose, near=(10, 18), spread=4):
    """(뒷다리 x, 앞다리 x, 먼쪽 다리 오프셋)"""
    b, f = near
    if pose == "walk":
        return (b - spread//2, f + spread//2, 2) if frame == 0 else \
               (b + spread//2, f - spread//2, -2)
    return (b, f, 1 if frame else 0)


# 너구리 — 중형 32
def raccoon_side(frame=0, pose="idle"):
    c = Canvas(32, 32)
    BY, FY = 18, 27
    for i in range(6):                                   # 복슬 꼬리 (줄무늬)
        a = math.radians(196 + i*14)
        c.ellipse(7.4 + math.cos(a)*4.6, 15.4 + math.sin(a)*3.4, 2.4, 2.2,
                  DARK if i % 2 else MID)
    bx, fx, fo = _gait(frame, pose, (10, 18))
    _leg(c, bx + fo, BY+3, FY, 2, DARK, False)
    _leg(c, fx - fo, BY+3, FY, 2, DARK, False)
    c.ellipse(14.5, BY, 8.2, 5.4, MID)                   # 통통한 몸
    c.ellipse(14.5, BY+3.2, 6.6, 2.0, BELLY)
    _leg(c, bx, BY+3, FY, 3, MID)
    _leg(c, fx, BY+3, FY, 3, MID)
    c.ellipse(23.4, 13.6, 5.4, 4.6, MID)                 # 머리
    c.ellipse(27.4, 15.0, 2.6, 1.8, BELLY)               # 뾰족한 주둥이
    c.ellipse(29.0, 14.6, 1.0, 0.8, PAW)
    c.ellipse(22.2, 13.4, 2.6, 2.2, DARK)                # ★ 눈가 마스크
    c.ellipse(26.0, 13.0, 1.8, 1.6, DARK)
    c.ellipse(21.0, 10.0, 1.8, 1.6, DARK)                # 작고 둥근 귀
    c.ellipse(25.4, 9.8, 1.8, 1.6, DARK)
    c.shade_top_light(); c.outline_pass()
    return c


# 수달 — 중형 32
def otter_side(frame=0, pose="idle"):
    c = Canvas(32, 32)
    BY, FY = 20, 26
    for i in range(8):                                   # 굵고 긴 꼬리 — 뒤로 곧게
        c.ellipse(2.0 + i*1.5, 21.4 - i*0.28, 2.6 - i*0.18, 2.4 - i*0.16, MID)
    bx, fx, fo = _gait(frame, pose, (12, 20), spread=3)
    _leg(c, bx + fo, BY+2, FY, 2, DARK, False)
    _leg(c, fx - fo, BY+2, FY, 2, DARK, False)
    c.ellipse(16.5, BY, 9.6, 4.0, MID)                   # ★ 길고 낮은 몸
    c.ellipse(16.5, BY+2.2, 7.6, 1.4, BELLY)
    _leg(c, bx, BY+2, FY, 3, MID)                        # 아주 짧은 다리
    _leg(c, fx, BY+2, FY, 3, MID)
    c.ellipse(25.6, 17.0, 4.4, 3.8, MID)                 # 둥근 머리
    c.ellipse(29.0, 18.2, 2.2, 1.6, BELLY)               # 넓적한 주둥이
    c.ellipse(30.0, 17.8, 1.0, 0.9, PAW)
    c.ellipse(23.4, 14.4, 1.4, 1.2, DARK)                # 아주 작은 귀
    c.shade_top_light(); c.outline_pass()
    return c


# 고라니 — 대형 48
def deer_side(frame=0, pose="idle"):
    c = Canvas(48, 48)
    BY, FY = 27, 41
    bx, fx, fo = _gait(frame, pose, (14, 30), spread=6)
    _leg(c, bx + fo, BY+4, FY, 2, DARK, False)
    _leg(c, fx - fo, BY+4, FY, 2, DARK, False)
    for i in range(5):                                   # 짧은 꼬리
        c.ellipse(9.0 - i*0.7, 25.0 - i*0.9, 1.8, 1.6, MID)
    c.ellipse(22, BY, 10.6, 6.0, MID)                    # 몸
    c.ellipse(22, BY+3.6, 8.4, 2.2, BELLY)
    _leg(c, bx, BY+4, FY, 3, MID)                        # ★ 긴 다리
    _leg(c, fx, BY+4, FY, 3, MID)
    # ★ 목은 다섯 마디까지다. 여덟 마디를 쌓았더니 고라니가 아니라 기린이 됐다 —
    #   고라니는 **다리가 길지 목이 길지 않다.**
    for i in range(5):
        c.ellipse(31.0 + i*1.1, 22.4 - i*1.5, 3.2 - i*0.16, 3.2 - i*0.16, MID)
    c.ellipse(37.4, 15.4, 4.2, 3.6, MID)                 # 작은 머리
    c.ellipse(41.4, 16.8, 2.6, 1.9, BELLY)               # 긴 주둥이
    c.ellipse(43.0, 16.4, 1.0, 0.9, PAW)
    c.ellipse(34.6, 11.4, 1.7, 3.2, MID)                 # ★ 큰 귀 (뿔은 없다)
    c.ellipse(38.6, 10.8, 1.7, 3.2, MID)
    c.shade_top_light(); c.outline_pass()
    return c


# 삵 — 중형 32
def leopardcat_side(frame=0, pose="idle"):
    c = Canvas(32, 32)
    BY, FY = 18, 27
    # 꼬리는 **몸에서 확실히 떨어져** 나가야 보인다. 몸에 붙여 말면 사라진다
    for i in range(7):                                   # 굵은 꼬리 + 고리 무늬
        c.ellipse(7.6 - i*0.9, 16.4 - i*1.3, 2.4, 2.1, DARK if i % 2 else MID)
    bx, fx, fo = _gait(frame, pose, (11, 19))
    _leg(c, bx + fo, BY+3, FY, 2, DARK, False)
    _leg(c, fx - fo, BY+3, FY, 2, DARK, False)
    c.ellipse(15, BY, 8.6, 4.8, MID)                     # 고양이 골격, 조금 길게
    c.ellipse(15, BY+3.0, 6.8, 1.8, BELLY)
    _leg(c, bx, BY+3, FY, 3, MID)
    _leg(c, fx, BY+3, FY, 3, MID)
    for (x, y) in ((11,15),(15,14),(19,15),(13,18),(17,18),(21,17),(9,17)):
        c.ellipse(x, y, 1.2, 1.0, DARK)                  # ★ 점무늬
    c.ellipse(23.8, 13.6, 4.8, 4.4, MID)
    c.ellipse(27.4, 15.0, 1.8, 1.4, BELLY)               # 고양이처럼 짧은 주둥이
    c.ellipse(28.4, 14.6, 0.9, 0.7, PAW)
    # ★ 이마 줄무늬 + 뾰족 귀를 같이 그렸더니 모히칸이 됐다. 줄무늬는 뺀다 —
    #   32px 에서 머리 위에 두 가지를 겹칠 자리가 없다
    _tri_up(c, 20.8, 10.8, 2.0, 3.0, MID)                # 뾰족 귀
    _tri_up(c, 26.2, 10.6, 2.0, 3.0, MID)
    c.shade_top_light(); c.outline_pass()
    return c


# 두꺼비 — 소형 24
def toad_side(frame=0, pose="idle"):
    """★ 처음엔 낮은 타원 하나로 그렸더니 **덤불로 보였다.**
    두꺼비는 **앞을 든 자세**여야 두꺼비다 — 앞다리로 상체를 받치고,
    뒷다리는 뒤로 접혀 옆으로 벌어진다. 눈두덩이 머리 위로 솟아야 한다."""
    c = Canvas(24, 24)
    c.ellipse(9.6, 15.2, 6.2, 4.0, MID)                  # 엉덩이 쪽 몸통
    c.ellipse(5.2, 15.0, 3.4, 3.2, MID)                  # 접힌 뒷다리 덩어리
    if pose == "walk" and frame == 1:                    # 폴짝 — 뒷다리를 뻗는다
        c.rect(1, 16, 7, 17, MID); c.rect(0, 17, 6, 18, PAW)
    else:
        c.rect(2, 17, 7, 18, MID); c.rect(1, 18, 7, 19, PAW)   # 뒷발 — 옆으로 길게
    c.ellipse(15.0, 13.6, 4.6, 3.4, MID)                 # 들린 앞가슴
    c.ellipse(11.5, 17.0, 5.4, 1.6, BELLY)               # 배
    if pose == "walk" and frame == 1:
        c.rect(17, 14, 18, 17, MID); c.rect(16, 17, 20, 18, PAW)
    else:
        c.rect(16, 15, 17, 18, MID)                      # 앞다리 — 상체를 받친다
        c.rect(15, 18, 19, 19, PAW)
    c.ellipse(18.0, 11.6, 3.6, 3.0, MID)                 # 머리
    c.ellipse(20.6, 12.8, 1.8, 1.2, BELLY)               # 넓은 입
    c.ellipse(17.2, 8.8, 2.0, 1.8, MID)                  # ★ 솟은 눈두덩
    c.ellipse(20.0, 9.4, 1.6, 1.4, MID)
    for (x, y) in ((7,12),(10,11),(12,13),(8,15),(13,15),(5,13)):
        c.set(x, y, DARK)                                # 오돌토돌
    if frame:
        c.ellipse(11.5, 16.6, 5.2, 1.4, BELLY)           # 숨 쉬는 배
    c.shade_top_light(); c.outline_pass()
    return c


# 까치 — 소형 24
def magpie_side(frame=0, pose="idle"):
    c = Canvas(24, 24)
    for i in range(9):                                   # ★ 몸보다 긴 꼬리
        c.ellipse(2.0 + i*1.0, 18.4 - i*0.62, 1.8 - i*0.06, 1.5, DARK)
    c.ellipse(13.5, 13.6, 5.2, 4.6, DARK)                # 몸
    c.ellipse(13.0, 15.0, 3.6, 2.6, BELLY)               # ★ 흰 배
    c.ellipse(10.4, 12.4, 3.0, 2.2, BELLY)               # ★ 흰 어깨
    c.ellipse(17.4, 9.4, 3.4, 3.0, DARK)                 # 머리
    c.blob([(20,9),(21,9),(20,10),(21,10),(22,10)], PAW)  # 부리
    sp = 4 if (pose == "walk" and frame == 1) else 3     # 뛸 때 다리가 벌어진다
    _leg(c, 13 - sp//2, 17, 21, 1, PAW, False)           # 가는 다리 둘
    _leg(c, 13 + sp//2, 17, 21, 1, PAW, False)
    c.rect(12-sp//2, 20, 14-sp//2, 21, PAW)
    c.rect(12+sp//2, 20, 14+sp//2, 21, PAW)
    if frame: c.ellipse(11.4, 12.0, 2.6, 1.8, BELLY)
    c.shade_top_light(); c.outline_pass()
    return c


# 참새 — 소형 24
def sparrow_side(frame=0, pose="idle"):
    c = Canvas(24, 24)
    for i in range(4):                                   # ★ 짧은 꼬리
        c.ellipse(6.4 - i*0.9, 15.0 - i*0.5, 1.8, 1.4, DARK)
    c.ellipse(13.0, 14.0, 4.6, 4.2, MID)                 # ★ 작고 동글한 몸
    c.ellipse(12.6, 15.4, 3.2, 2.4, BELLY)
    c.ellipse(16.0, 10.4, 3.4, 3.0, MID)                 # 머리
    c.edge_lower(16.0, 10.4, 3.4, 3.0)                   # 머리 아래 윤곽 — 몸과 분리
    c.ellipse(14.4, 9.2, 2.0, 1.5, DARK)                 # 정수리 얼룩
    c.blob([(19,10),(20,10),(21,10),(19,11),(20,11)], PAW)   # 짧고 두툼한 부리
    sp = 4 if (pose == "walk" and frame == 1) else 2
    _leg(c, 13 - sp//2, 17, 20, 1, PAW, False)
    _leg(c, 13 + sp//2, 17, 20, 1, PAW, False)
    c.rect(12-sp//2, 19, 14-sp//2, 20, PAW)
    c.rect(12+sp//2, 19, 14+sp//2, 20, PAW)
    if frame: c.ellipse(9.6, 13.6, 2.2, 1.6, DARK)       # 날개 접었다 폈다
    c.shade_top_light(); c.outline_pass()
    return c


# 뱀 — 소형 24
def snake_side(frame=0, pose="idle"):
    c = Canvas(24, 24)
    wob = (0.0 if frame == 0 else 1.9) if pose == "walk" else (0.0 if frame == 0 else 0.5)
    for i in range(26):                                  # ★ S자 — 다리가 없다
        t = i / 25.0
        x = 2.5 + t*17.0
        y = 17.0 - math.sin(t*math.pi*1.9 + wob)*4.2
        r = 2.3 - abs(t-0.35)*1.1
        c.ellipse(x, y, max(1.1, r), max(1.0, r*0.92), MID)
    for i in range(6):                                   # 등 무늬
        t = 0.15 + i*0.13
        x = 2.5 + t*17.0
        y = 17.0 - math.sin(t*math.pi*1.9 + wob)*4.2
        c.ellipse(x, y - 0.6, 1.0, 0.8, DARK)
    # 머리가 몸통과 같은 굵기면 어디가 머리인지 모른다 — **확실히 굵게** 그린다
    hx = 2.5 + 1.0*17.0
    hy = 17.0 - math.sin(1.0*math.pi*1.9 + wob)*4.2
    c.ellipse(hx, hy, 3.4, 2.6, MID)                     # 삼각 머리
    c.ellipse(hx + 1.4, hy, 2.2, 1.8, LIGHT)             # 주둥이 밝게
    tx, ty = int(hx) + 4, int(hy)
    c.set(tx, ty, PAW); c.set(tx+1, ty, PAW)             # 갈라진 혀
    c.set(tx+2, ty-1, PAW); c.set(tx+2, ty+1, PAW)
    c.shade_top_light(); c.outline_pass()
    return c


SIDE_IDLE = {
    "raccoon_dog": raccoon_side, "otter": otter_side, "water_deer": deer_side,
    "leopard_cat": leopardcat_side, "toad": toad_side, "magpie": magpie_side,
    "sparrow": sparrow_side, "snake": snake_side,
}


# ── 이형(암수) 파츠 (§4.9) ─────────────────────────────────────────────
# ★ 암수를 **몸통 시트로 나누지 않는다.** 나누는 순간 종당 16장이 32장이 된다.
#   눈·입과 같은 **파츠 레이어**로 얹는다 — 북향에서 숨기는 규칙까지 그대로 재사용한다.
#   ★ 종 이름으로 분기하지 않는다(원칙 4). 엔진은 `DIMORPH` 에 그 종이 있는지만 본다.

def _px(rows, mapping, w=None, h=None):
    """ASCII 로 찍는다. 파츠는 작아서 타원보다 손으로 찍는 편이 정확하다."""
    h = h or len(rows); w = w or max(len(r) for r in rows)
    c = Canvas(w, h)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in mapping: c.set(x, y, mapping[ch])
    return c


def deer_tusk(angle):
    """고라니 수컷의 **엄니**(송곳니). 고라니는 뿔이 없고 수컷에게 긴 송곳니가 있다 —
    실존 생태 그대로다(§3.8). 32~48px 에서 실루엣으로 읽히는 몇 안 되는 이형이다.

    ★ 상아색은 **인덱스 8(눈밝음)** 으로 찍는다. 털색 팔레트가 뭐로 바뀌든
      엄니는 상아색으로 남아야 한다 — 검은 털 고라니를 만들어도 엄니는 희다."""
    I, O = EYEL, OUTLINE
    if angle == "side":
        # ★ 처음엔 2px 를 여섯 줄 세웠더니 **턱받이로 보였다.** 엄니는 가늘다 —
        #   위 2px, 아래 1px 로 가늘어지고 **뒤로 휘어야** 이빨로 읽힌다.
        #   뒤쪽 모서리에 외곽선을 붙여야 크림색 배(BELLY)에 안 묻는다.
        return _px([
            "..II",
            "..II",
            ".oII",
            ".oI.",
            ".oI.",
            "..o.",
        ], {"I": I, "o": O})
    # 정면 — 좌우 한 쌍. 주둥이가 좁으니 **가운데를 넓게** 비운다.
    return _px([
        "I...I",
        "I...I",
        "I...I",
        "o...o",
    ], {"I": I, "o": O})


DIMORPH = {
    # 종 id: (파츠 이름, 보이는 성별, 그리는 함수, 몸통 좌표 앵커)
    #   앵커는 파츠 캔버스의 **왼쪽 위**가 몸통 캔버스의 어디에 놓이는가다.
    #   측면 앵커는 동물이 오른쪽(E)을 볼 때 기준 — 미러하면 x 를 뒤집는다.
    "water_deer": {"part": "엄니", "sex": "male", "fn": deer_tusk,
                   "anchor": {"side": [41, 19], "front": [21, 20]}},
}
# 나머지 열 종은 **이형이 없다** — 실제로 암수가 같게 생겼다.
# 없는 종에 억지로 리본이나 색을 붙이지 않는다. 그건 동물이 아니라 클리셰다.


# ── 눈 레이어 (공용 · 종 수와 무관) ────────────────────────────────────
# §4.6 — 각도는 정면/측면 2개면 충분하다. 북향은 레이어를 숨긴다.
def eye_sprite(style, expr, angle):
    """32px 몸통 기준 눈은 2~3px. **밝은 외곽을 두르지 않는다.**

    예전에는 '어떤 몸통색에서도 살도록' 눈 둘레를 밝게 둘렀는데,
    그러면 눈이 두 배로 커져서 개구리가 된다.
    검은 개도 눈은 검다 — 색을 뒤집을 일이 아니다.
    어두운 털에서 눈이 읽히게 하는 것은 **동공 안의 반짝임 1픽셀**(catchlight)이다.
    """
    w, h = (9, 5) if angle == "front" else (5, 5)
    c = Canvas(w, h)

    def one(cx, outer):
        """outer: 바깥쪽이 어느 쪽인가 (-1 왼쪽, +1 오른쪽).
           표정은 **같은 눈이 변형되는 것**이어야 한다 —
           기본에 없던 눈썹 같은 것을 표정에서만 새로 그리면 다른 얼굴이 된다."""
        cx = int(cx)
        if expr == "기본":
            # 어두운 털에서도 눈이 읽히게 하는 것은 흰 테가 아니라
            # **동공 안의 반짝임 1픽셀**이다 (catchlight). 눈 자체는 어떤 털색에서도 검다.
            if style == "dot":        c.rect(cx, 2, cx, 3, EYED); c.set(cx, 2, EYEL)
            elif style == "narrow":   c.rect(cx, 2, cx+1, 2, EYED); c.set(cx, 2, EYEL)
            elif style == "big":      c.rect(cx, 1, cx+1, 3, EYED); c.set(cx, 1, EYEL)
            else:                     c.rect(cx, 2, cx+1, 3, EYED); c.set(cx, 2, EYEL)
        elif expr == "기쁨":                       # 눈이 위로 휜다
            c.set(cx, 3, EYED); c.set(cx+1, 2, EYED)
            if style in ("big", "round"): c.set(cx+2, 3, EYED)
        elif expr == "시무룩":                     # 눈꺼풀이 덮여 납작해지고 바깥이 처진다
            c.rect(cx, 3, cx+1, 3, EYED)
            c.set(cx if outer < 0 else cx+1, 4, EYED)

    if angle == "front": one(1, -1); one(6, +1)
    else:                one(1, -1)
    return c


EYE_PALETTE = [(0,0,0,0)]*7 + [(28,22,16,255), (250,246,238,255)]


# ── 방향 표시 (§4.5 v3.16 · v3.19) ─────────────────────────────────────
# ★ **발자국을 쓰지 않는다.** 지면 발자국은 이미 "여기 지나갔다"(시야 단서)라는 뜻으로
#   쓰이고 있다. 같은 그림에 두 뜻을 얹으면 아이가 헷갈린다 —
#   한 화면에 지면 발자국과 방향 발자국이 같이 뜨는 경우가 실제로 생긴다.
# ★ 감각 아이콘(무엇으로 찾았나) + 방향 화살표(어느 쪽인가) 로 **나눈다.**
#   나누면 2 감각 × 4 방향 = 8 이 아니라 **2 + 4 = 6** 이다 — 곱셈을 덧셈으로 바꾸는 자리.
DIRS = ("north", "south", "east", "west")

def dir_arrow(direction):
    """공용 4장. 강조색은 감각을 따라간다 — 코는 주황, 귀는 초록(ICON_ACCENT)."""
    c = Canvas(11, 11)
    A_ = MID                                    # 강조색 자리
    for r in range(4):                          # 삼각 머리
        if direction == "north":   c.rect(5-r, 1+r, 5+r, 1+r, A_)
        elif direction == "south": c.rect(5-r, 9-r, 5+r, 9-r, A_)
        elif direction == "east":  c.rect(9-r, 5-r, 9-r, 5+r, A_)
        else:                      c.rect(1+r, 5-r, 1+r, 5+r, A_)
    # 꼬리 — 없으면 화살표가 아니라 그냥 삼각형이다
    if direction == "north":   c.rect(4, 5, 6, 10, A_)
    elif direction == "south": c.rect(4, 0, 6, 5, A_)
    elif direction == "east":  c.rect(0, 4, 5, 6, A_)
    else:                      c.rect(5, 4, 10, 6, A_)
    return c


# ── 표현 아이콘 (공용 16×16) ───────────────────────────────────────────
ICON_PALETTE = [(0,0,0,0),(24,30,38,255),(0,0,0,0),(0,0,0,0),(0,0,0,0),(0,0,0,0),(0,0,0,0),(0,0,0,0),(244,236,224,255)]
ICON_ACCENT  = {"발견":(233,164,65),"잠":(140,166,200),"애정":(224,99,126),
                "냄새":(233,164,65),"소리":(134,171,85),"시야":(126,178,214)}

def icon_sprite(kind):
    c = Canvas(16, 16)
    A = MID  # 강조색 자리
    if kind == "발견":
        c.rect(7, 2, 8, 9, A); c.rect(7, 11, 8, 12, A)
    elif kind == "잠":
        for (x0,y0,s) in ((8,1,6),(2,8,5)):
            c.rect(x0, y0, x0+s, y0, A); c.rect(x0, y0+s, x0+s, y0+s, A)
            for i in range(s+1): c.set(x0+s-i, y0+i, A)
    elif kind == "애정":
        c.ellipse(5.5, 6, 3.2, 3.0, A); c.ellipse(10.5, 6, 3.2, 3.0, A)
        for i in range(7): c.rect(2+i, 8+i, 13-i, 8+i, A)
    elif kind == "냄새":                              # 코 (후각)
        # 16px 에서 코로 읽히려면 세 가지가 필요하다 —
        #   아래가 뾰족하면 하트로 보인다 → 밑을 평평하게
        #   콧구멍이 2픽셀이면 사라진다   → 3픽셀 쉼표로 키우고 아래쪽에 둔다
        #   인중(세로 홈)이 없으면 그냥 덩어리다
        c.ellipse(8, 8.6, 5.6, 4.4, A)                # 위가 넓은 콧등
        c.rect(3, 9, 12, 12, A)                       # 밑을 평평하게 자른다
        c.ellipse(8, 11.6, 4.6, 2.4, A)               # 아랫볼 — 모서리를 둥글린다
        for (x, y) in ((5,9),(5,10),(6,10),(10,9),(10,11),(9,10)):
            c.set(x, y, OUTLINE)                      # 콧구멍 (바깥 위 → 안쪽 아래로 기운 쉼표)
        c.set(6, 11, OUTLINE); c.set(10, 10, OUTLINE)
        c.rect(8, 11, 8, 13, OUTLINE)                 # 인중
    elif kind == "시야":                              # 눈 (시야)
        # 감각 셋 중 시야만 아이콘이 없었다. 후각(코)·청각(귀) 옆에 놓일 물건이라
        # 같은 무게로 보여야 한다 — 눈꺼풀 두 획 + 동공.
        c.ellipse(8, 8, 6.8, 4.2, A)                  # 렌즈
        c.ellipse(8, 8, 5.4, 2.8, TRANSPARENT)        # 속을 비워 테두리만 남긴다
        c.ellipse(8, 8, 2.4, 2.4, A)                  # 동공
    elif kind == "소리":                              # 귀 (청각)
        c.ellipse(8.4, 7.6, 5.0, 5.4, A)              # 귀 바깥
        c.ellipse(9.4, 8.2, 2.4, 3.2, TRANSPARENT)    # 안쪽 홈
        c.rect(9, 10, 15, 15, TRANSPARENT)            # 아래쪽을 터서 C자로
        c.ellipse(7.0, 11.8, 2.2, 2.6, A)             # 귓불
    add = []
    for y in range(16):
        for x in range(16):
            if c.px[y][x] != TRANSPARENT: continue
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                if c.get(x+dx, y+dy) == A: add.append((x,y)); break
    for (x,y) in add: c.set(x, y, OUTLINE)
    return c


# ── 빌드 ───────────────────────────────────────────────────────────────
def save(c, path, palette, scale=1):
    img = c.to_image(palette)
    if scale > 1:
        img = img.resize((img.width*scale, img.height*scale), Image.NEAREST)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return img

def main():
    frames = {}

    # 개 성체 — 이동 4방향(E/W 미러) + 대기 좌우 + 특징 측면
    for f in (0, 1):
        frames[f"dog_adult/walk_east_{f}"]  = dog_side(f, "walk")
        frames[f"dog_adult/walk_south_{f}"] = dog_south(f)
        frames[f"dog_adult/walk_north_{f}"] = dog_north(f)
        frames[f"dog_adult/idle_east_{f}"]  = dog_side(f, "idle")
        frames[f"dog_adult/special_{f}"]    = dog_special(f)
    for f in (0, 1):
        frames[f"dog_adult/walk_west_{f}"] = frames[f"dog_adult/walk_east_{f}"].mirrored()
        frames[f"dog_adult/idle_west_{f}"] = frames[f"dog_adult/idle_east_{f}"].mirrored()

    # 고양이 성체
    for f in (0, 1):
        frames[f"cat_adult/walk_east_{f}"]  = cat_side(f, "walk")
        frames[f"cat_adult/walk_south_{f}"] = cat_south(f)
        frames[f"cat_adult/walk_north_{f}"] = cat_north(f)
        frames[f"cat_adult/idle_east_{f}"]  = cat_side(f, "idle")
        frames[f"cat_adult/special_{f}"]    = cat_special(f)

    # 청설모 성체
    for f in (0, 1):
        frames[f"squirrel_adult/walk_east_{f}"]  = squirrel_side(f, "walk")
        frames[f"squirrel_adult/walk_south_{f}"] = squirrel_south(f)
        frames[f"squirrel_adult/idle_east_{f}"]  = squirrel_side(f, "idle")

    for name, c in frames.items():
        pal = (PALETTES["dog_default"] if name.startswith("dog")
               else PALETTES["cat_default"] if name.startswith("cat")
               else PALETTES["squirrel_default"])
        save(c, os.path.join(OUT, "png", name + ".png"), pal)

    eyes = {}
    for style in ("round", "big"):
        for expr in ("기본", "기쁨", "시무룩"):
            for angle in ("front", "side"):
                c = eye_sprite(style, expr, angle)
                eyes[f"{style}_{expr}_{angle}"] = c
                save(c, os.path.join(OUT, "png", "eyes", f"{style}_{expr}_{angle}.png"), EYE_PALETTE)

    icons = {}
    for kind in ("발견", "잠", "애정", "냄새", "소리"):
        c = icon_sprite(kind)
        pal = list(ICON_PALETTE); pal[MID] = ICON_ACCENT[kind] + (255,)
        icons[kind] = (c, pal)
        save(c, os.path.join(OUT, "png", "emote", f"{kind}.png"), pal)

    with open(os.path.join(OUT, "png", "palettes.json"), "w") as fp:
        json.dump({k: [list(x) for x in v] for k, v in PALETTES.items()}, fp, ensure_ascii=False, indent=2)

    print(f"몸통 {len(frames)}장 · 눈 {len(eyes)}장 · 아이콘 {len(icons)}장")
    return frames, eyes, icons

if __name__ == "__main__":
    main()
