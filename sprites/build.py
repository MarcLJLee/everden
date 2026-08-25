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


# ── 표현 아이콘 (공용 16×16) ───────────────────────────────────────────
ICON_PALETTE = [(0,0,0,0),(24,30,38,255),(0,0,0,0),(0,0,0,0),(0,0,0,0),(0,0,0,0),(0,0,0,0),(0,0,0,0),(244,236,224,255)]
ICON_ACCENT  = {"발견":(233,164,65),"잠":(140,166,200),"애정":(224,99,126),"냄새":(233,164,65),"소리":(134,171,85)}

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
