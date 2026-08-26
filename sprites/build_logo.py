#!/usr/bin/env python3
"""
부팅 화면 — 제작사 로고 `RUN II`

  이름의 뜻은 "2회차". 부모가 된 두 번째 삶.
  회차 = playthrough/run 이라 RUN II 가 직역에 가장 가깝다.

큰 발자국이 먼저 찍히다가 어느 지점부터 작은 발자국이 나란히 붙는다.
이름의 뜻이 한 컷에 들어가고, **새로 그리는 도트는 글자와 발자국 둘뿐이다.**
(처음엔 `clues/발자국.png` 를 재활용하려 했는데 안 됐다 — 이유는 아래 §발자국 참조)

글자는 폰트로 찍지 않는다 — 로고는 손으로 찍은 도트여야 한다.
설계 해상도 14×18(획 3px)에서 그리고 **정수배로만** 키운다. 중간 크기는 없다.
"""
import os, math
from PIL import Image, ImageDraw
import build_bg as G

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = 640, 360                      # project.godot 의 뷰포트와 같아야 한다

BG      = (14, 15, 19)               # 순검정이 아니다 — 외곽선이 살아야 한다
INK     = (236, 230, 216)
INK_LO  = (170, 160, 142)            # 아랫변 1px — 위가 밝다 (§4.4 를 글자에도)
INK_OL  = (8, 8, 10)
PAW     = (92, 84, 74)               # 어른 발자국
PAW_LIT = (128, 118, 102)            # 아이 발자국 — 조금 더 밝게 해야 눈이 따라간다


# ── 글자 — 14×18 격자, 획 3px ────────────────────────────────────────
GW, GH, STEM = 14, 18, 3

def _mask(w, h):
    return Image.new("L", (w, h), 0)

def _rect(d, x0, y0, x1, y1):
    d.rectangle([x0, y0, x1, y1], fill=255)

WAIST = 7                                            # 허리 시작 줄

def glyph_R():
    m = _mask(GW, GH); d = ImageDraw.Draw(m)
    _rect(d, 0, 0, STEM-1, GH-1)                     # 세로 기둥
    _rect(d, 0, 0, GW-STEM-1, STEM-1)                # 윗변
    _rect(d, GW-STEM, 0, GW-1, WAIST+STEM-1)         # 볼 오른쪽
    _rect(d, 0, WAIST, GW-1, WAIST+STEM-1)           # 허리
    n = GH - (WAIST+STEM)                            # 다리
    for i in range(n):
        x = (GW-STEM-5) + (i*5)//(n-1)
        _rect(d, x, WAIST+STEM+i, x+STEM-1, WAIST+STEM+i)
    return m

def glyph_U():
    m = _mask(GW, GH); d = ImageDraw.Draw(m)
    _rect(d, 0, 0, STEM-1, GH-STEM-1)
    _rect(d, GW-STEM, 0, GW-1, GH-STEM-1)
    _rect(d, 0, GH-STEM, GW-1, GH-1)
    return m

NW = 16          # N 은 두 기둥 사이에 대각선이 들어가야 해서 조금 넓다
def glyph_N():
    m = _mask(NW, GH); d = ImageDraw.Draw(m)
    _rect(d, 0, 0, STEM-1, GH-1)
    _rect(d, NW-STEM, 0, NW-1, GH-1)
    span = NW - 3*STEM                               # 대각선이 움직일 수 있는 폭
    for i in range(GH):
        x = STEM + (i*span)//(GH-1)
        _rect(d, x, i, x+STEM-1, i)
    return m

IW = 10
def glyph_I():
    """로마 숫자. 세리프가 없으면 알파벳 I 로 읽힌다 — 여기서는 숫자여야 한다."""
    m = _mask(IW, GH); d = ImageDraw.Draw(m)
    _rect(d, (IW-STEM)//2, 0, (IW-STEM)//2+STEM-1, GH-1)
    _rect(d, 0, 0, IW-1, STEM-1)
    _rect(d, 0, GH-STEM, IW-1, GH-1)
    return m


def wordmark(scale=2):
    """RUN II — 정수배로만 키운다. 글자 사이 간격도 설계 격자에서 잡는다.
    RUN 과 II 사이는 한 글자 폭만큼 벌린다. 붙이면 'RUNII' 한 단어로 읽힌다."""
    parts, x = [], 0
    for g, adv in ((glyph_R(), GW+4), (glyph_U(), GW+4), (glyph_N(), NW+13),
                   (glyph_I(), IW+4), (glyph_I(), IW)):
        parts.append((x, g)); x += adv
    dw, dh = x, GH

    m = _mask(dw, dh)
    for ox, g in parts: m.paste(g, (ox, 0), g)

    # 아랫변 1px 만 어둡게 — 획 한가운데를 자르면 실수처럼 보인다
    up = _mask(dw, dh); up.paste(m, (0, -1), m)
    from PIL import ImageChops
    bottom = ImageChops.subtract(m, up)

    # 외곽선 — 1px 확장한 마스크에서 원본을 뺀다
    ol = _mask(dw+2, dh+2)
    for dx in (0, 1, 2):
        for dy in (0, 1, 2):
            ol.paste(m, (dx, dy), m)

    im = Image.new("RGBA", (dw+2, dh+2), (0, 0, 0, 0))
    im.paste(Image.new("RGBA", im.size, INK_OL + (255,)), (0, 0), ol)
    for col, msk in ((INK, m), (INK_LO, bottom)):
        layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
        layer.paste(Image.new("RGBA", (dw, dh), col + (255,)), (1, 1), msk)
        im.alpha_composite(layer)

    return im.resize((im.width*scale, im.height*scale), Image.NEAREST)


# ── 발자국 ────────────────────────────────────────────────────────────
# `clues/발자국.png` 를 그대로 키워 봤는데 안 됐다. 그 스프라이트는 16px 필드 위,
# 풀·흙이라는 맥락 안에서 읽히도록 그린 것이라 검은 배경에 혼자 두고 3배로 키우면
# 발가락이 뭉쳐서 열매처럼 보인다. **맥락이 사라지면 실루엣이 대신 일해야 한다.**
# 그래서 로고용으로 한 짝짜리 발자국을 따로 찍는다 — 이 화면에서 새로 그리는 도트는
# 글자와 이것 둘뿐이다.
# 발가락은 발바닥에서도, 서로에게서도 떨어져 있어야 한다. 붙으면 발자국이 아니라
# 버섯이 된다 — 두 번 겪었다.
# 타원 함수로는 이 크기가 안 나온다. r=1.2 짜리 원은 십자가로 찍히고 r=1.5 는 옆
# 발가락과 붙는다. **16px 안에 발가락 넷이면 한 개가 2px, 사이가 2px 다.**
# 이 크기에서는 도트를 직접 놓는 편이 빠르고 정확하다.
def _ascii(rows):
    m = _mask(len(rows[0]), len(rows)); px = m.load()
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == "#": px[x, y] = 255
    return m

PAW_BIG = lambda: _ascii([
    ".....##..##.....",      # 가운데 발가락 둘이 앞으로 나온다
    ".##..##..##..##.",
    ".##..##..##..##.",
    ".##..........##.",
    "................",
    "....########....",
    "..############..",
    ".##############.",
    ".##############.",
    "..############..",
    "....########....",
])

PAW_SMALL = lambda: _ascii([
    "...##.##...",
    "##.##.##.##",
    "##.##.##.##",
    "##.......##",
    "...........",
    "..#######..",
    ".#########.",
    ".#########.",
    "..#######..",
])

def paw(big, scale=2):
    m = (PAW_BIG if big else PAW_SMALL)()
    im = Image.new("RGBA", m.size, (0, 0, 0, 0))
    im.paste(Image.new("RGBA", m.size, ((PAW if big else PAW_LIT)) + (255,)), (0, 0), m)
    return im.resize((m.width*scale, m.height*scale), Image.NEAREST)

N_BIG, N_SMALL = 7, 5
SMALL_FROM = 2              # 어른이 두 걸음 혼자 걷다가 이 걸음부터 아이가 붙는다

def _big_at(i):
    """왼쪽 아래에서 오른쪽으로 올라가며 — 화면 밖에서 걸어 들어온다.
    좌우로 번갈아 흔들려야 '걸어간 자국'으로 읽힌다. 일직선은 자국이 아니라 점선이다.
    다만 흔들림이 보폭만큼 커지면 두 줄로 보인다 — 8px 면 충분하다."""
    return 40 + i*78, 244 - i*6 + (0 if i % 2 else 8)

def _small_at(i):
    """아이 줄은 어른 줄 **아래**에 따로 흐른다. 보폭이 짧아 걸음 수가 더 잦다.
    사이에 끼워 넣으면 두 줄이 한 줄로 뭉개져서 '나란히 걷는다'가 사라진다."""
    return 196 + i*62, 300 - i*5 + (0 if i % 2 else 7)

def footprints(n_big, n_small):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for i in range(min(n_big, N_BIG)):
        im.alpha_composite(paw(True), _big_at(i))
    for i in range(min(n_small, N_SMALL)):
        im.alpha_composite(paw(False), _small_at(i))
    return im


# ── 화면 ─────────────────────────────────────────────────────────────
def screen(n_big=N_BIG, n_small=N_SMALL, mark_alpha=1.0, tag=None):
    im = Image.new("RGBA", (W, H), BG + (255,))
    im.alpha_composite(footprints(n_big, n_small))
    if mark_alpha > 0:
        wm = wordmark()
        if mark_alpha < 1.0:
            a = wm.getchannel("A").point(lambda v: int(v*mark_alpha))
            wm.putalpha(a)
        im.alpha_composite(wm, ((W - wm.width)//2, 128))
    return im


FRAMES = 32
def sequence():
    """2.5초. 아무 키나 누르면 건너뛴다 — 아이는 이 화면을 수백 번 본다."""
    out = []
    for f in range(FRAMES):
        nb = max(0, min(N_BIG, (f - 3) // 2))
        ns = max(0, min(N_SMALL, (f - 11) // 2))
        a  = 0.0 if f < 17 else min(1.0, (f - 17) / 7)
        out.append(screen(nb, ns, a))
    return out


def save_all():
    d = os.path.join(OUT, "extracted", "ui")
    os.makedirs(d, exist_ok=True)
    wordmark().save(os.path.join(d, "logo_wordmark.png"))
    screen().save(os.path.join(d, "logo_screen.png"))
    print("extracted/ui/logo_wordmark.png · logo_screen.png")


def sheet():
    """검수 시트 — 실제 픽셀 그대로. 확대는 정수배만 쓴다."""
    from PIL import ImageFont
    def font(sz):
        try: return ImageFont.truetype(
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
        except Exception: return ImageFont.load_default()
    FH, FL, FS = font(30), font(20), font(16)
    INKC, DIM, ACC = (238,232,222), (150,158,168), (233,164,65)

    wm = wordmark()
    keys = [(6, "발자국이 찍히기 시작"), (14, "아이 발자국이 붙는다"),
            (22, "이름이 떠오른다"), (31, "완성 — 2.5초, 아무 키나 누르면 건너뛴다")]
    frames = sequence()

    PAD, GAP = 34, 22
    body_w = W + PAD*2
    out = Image.new("RGBA", (body_w, 150 + 96 + len(keys)*(H//2 + 46) + 60),
                    (26,31,38,255))
    d = ImageDraw.Draw(out)
    d.text((PAD, 26), "제작사 로고 — RUN II", font=FH, fill=INKC)
    d.text((PAD, 68), "\"2회차\". 회차 = playthrough/run. 640×360 실제 픽셀이다 — 목업이 아니다.",
           font=FS, fill=DIM)

    y = 112
    d.text((PAD, y), "워드마크 — 설계 14×18(획 3px), 화면에는 ×2", font=FL, fill=ACC)
    y += 30
    out.alpha_composite(wm, (PAD, y))
    d.text((PAD + wm.width + GAP, y + 6), f"{wm.width}×{wm.height}px", font=FS, fill=DIM)
    y += wm.height + 34

    d.text((PAD, y), "부팅 시퀀스", font=FL, fill=ACC); y += 30
    for f, cap in keys:
        half = frames[f].resize((W//2, H//2), Image.NEAREST)
        out.alpha_composite(half, (PAD, y))
        d.text((PAD + W//2 + GAP, y + H//4 - 10), cap, font=FS, fill=DIM)
        y += H//2 + 16
    out.crop((0, 0, body_w, y + PAD - 16)).convert("RGB").save(
        os.path.join(OUT, "logo_sheet.png"))


if __name__ == "__main__":
    save_all()
    sheet()
    frames = sequence()
    frames[-1].convert("RGB").save(os.path.join(OUT, "logo.png"))
    gif = [f.convert("P", palette=Image.ADAPTIVE, colors=64) for f in frames]
    gif[0].save(os.path.join(OUT, "logo.gif"), save_all=True,
                append_images=gif[1:], duration=80, loop=0, disposal=2)
    # 2배 확대본 — 실제 창 크기(1280×720)에서 어떻게 보이는지
    z = frames[-1].resize((W*2, H*2), Image.NEAREST)
    z.convert("RGB").save(os.path.join(OUT, "logo_2x.png"))
    print("logo.png · logo.gif · logo_2x.png")
