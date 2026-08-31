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
INK     = (246, 232, 202)            # 종이·나무의 따뜻한 밝은 면
INK_LO  = (202, 148, 82)             # 아랫변 1px — 타이틀과 같은 호박빛 그림자
INK_OL  = (36, 26, 20)
PAW     = (120, 101, 76)             # 어른 발자국
PAW_SHA = (56, 45, 36)               # 1px 아래 그림자 — 검은 배경에서도 패드가 뭉개지지 않는다
PAW_LIT = (211, 171, 96)             # 아이 발자국 — 따뜻한 금빛
PAW_LIT_SHA = (106, 76, 47)


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


# 본문보다 한 단계 작고 얇은 보조 글자. `RUN II`가 게임 메뉴처럼 보이지 않게
# 스튜디오 표기를 붙인다. 폰트를 불러오지 않고도 로고의 픽셀 밀도를 유지한다.
MICRO = {
    "S": ("111", "100", "111", "001", "111"),
    "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "111"),
    "D": ("110", "101", "101", "101", "110"),
    "I": ("111", "010", "010", "010", "111"),
    "O": ("111", "101", "101", "101", "111"),
}

def micro_word(text):
    """1px 획의 `STUDIO`. ×2 뒤에도 주 워드마크보다 조용해야 한다."""
    chars = [MICRO[ch] for ch in text]
    w = len(chars) * 4 - 1
    m = _mask(w, 5); px = m.load()
    for n, glyph in enumerate(chars):
        for y, row in enumerate(glyph):
            for x, bit in enumerate(row):
                if bit == "1": px[n * 4 + x, y] = 255
    im = Image.new("RGBA", (w, 5), (0, 0, 0, 0))
    im.paste(Image.new("RGBA", im.size, INK_LO + (255,)), (0, 0), m)
    return im


def _main_wordmark():
    """RUN II 본문. mark·보조 글자를 조합하기 전의 원래 워드마크다."""
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
    return im


def wordmark(scale=2):
    """`RUN II STUDIO` — 발자국 마크·본문·보조 글자를 하나의 로고로 묶는다."""
    main = _main_wordmark()
    mark = brand_mark()
    sub = micro_word("STUDIO")
    gap = 5
    w = mark.width + gap + main.width
    h = max(mark.height, main.height + 2 + sub.height)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im.alpha_composite(mark, (0, (h - mark.height) // 2))
    im.alpha_composite(main, (mark.width + gap, 0))
    im.alpha_composite(sub, (mark.width + gap + (main.width - sub.width) // 2, main.height + 2))
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

PAW_BIG_LEFT = lambda: _ascii([
    "......##.##.....",      # 안쪽 두 발가락은 한 걸음 앞에 있다
    "...##......##...",      # 바깥 발가락은 반 박자 뒤 — comb 모양을 피한다
    "...##.......##..",
    "................",
    "......######....",
    "....##########..",
    "...############.",
    "....##########..",
    "......######....",
])

PAW_SMALL_LEFT = lambda: _ascii([
    "....##.##...",
    ".##.....##..",
    ".##......##.",
    "............",
    "....#####...",
    "..#########.",
    ".##########.",
    "..#########.",
    "....#####...",
])

def _mirror(mask):
    """왼·오른발은 대칭이지만 파일은 따로 내보낸다 — 변형 없이 픽셀 정렬이 유지된다."""
    from PIL import ImageOps
    return ImageOps.mirror(mask)

def paw_mask(big, side="left"):
    left = (PAW_BIG_LEFT if big else PAW_SMALL_LEFT)()
    return left if side == "left" else _mirror(left)

def paw(big, scale=2, side="left"):
    """발가락·패드 사이를 보존한 1px 아래 그림자. 발자국이 아닌 열매처럼 보이지 않게 한다."""
    m = paw_mask(big, side)
    fill = PAW if big else PAW_LIT
    shade = PAW_SHA if big else PAW_LIT_SHA
    im = Image.new("RGBA", (m.width + 1, m.height + 1), (0, 0, 0, 0))
    im.paste(Image.new("RGBA", m.size, shade + (255,)), (1, 1), m)
    im.paste(Image.new("RGBA", m.size, fill + (255,)), (0, 0), m)
    return im.resize((im.width*scale, im.height*scale), Image.NEAREST)

def brand_mark():
    """워드마크 왼쪽의 한 짝. 화면 아래의 궤적과 같은 물건이라 이름 없이도 동물 게임을 말한다."""
    m = paw_mask(True, "left")
    im = Image.new("RGBA", (m.width + 2, m.height + 2), (0, 0, 0, 0))
    # 1px 테두리는 검은 배경에서만 쓰고, 발가락 틈은 건드리지 않는다.
    for dx, dy in ((0, 1), (1, 0), (2, 1), (1, 2)):
        im.paste(Image.new("RGBA", m.size, INK_OL + (255,)), (dx, dy), m)
    im.paste(Image.new("RGBA", m.size, PAW_LIT + (255,)), (1, 1), m)
    return im

N_BIG, N_SMALL = 7, 5

def _big_at(i):
    """큰 발은 왼쪽 아래에서 완만히 올라간다. 좌우 발 모양도 번갈아 진짜 걸음이 된다."""
    return 32 + i*69, 252 - i*8 + (-2 if i % 2 else 6)

def _small_at(i):
    """작은 발은 어른 발 아래를 더 짧게 따라간다. 두 궤적이 가까워지는 끝이 로고를 가리킨다."""
    return 185 + i*53, 302 - i*7 + (-2 if i % 2 else 5)

def _paw_entry(big, i):
    side = "left" if i % 2 == 0 else "right"
    stem = "logo_paw_big" if big else "logo_paw_small"
    return {
        "at": list(_big_at(i) if big else _small_at(i)),
        "file": "ui/%s%s.png" % (stem, "" if side == "left" else "_right"),
    }

def footprints(n_big, n_small):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for i in range(min(n_big, N_BIG)):
        im.alpha_composite(paw(True, side="left" if i % 2 == 0 else "right"), _big_at(i))
    for i in range(min(n_small, N_SMALL)):
        im.alpha_composite(paw(False, side="left" if i % 2 == 0 else "right"), _small_at(i))
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
        im.alpha_composite(wm, ((W - wm.width)//2, MARK_AT))
    return im


# 타이밍은 여기 한 곳에만 있다. `logo.json` 으로 그대로 나가서 엔진이 같은 값을 읽는다 —
# 좌표와 타이밍이 데이터로 나오면 로고를 다시 그려도 엔진 코드를 안 고친다.
FRAMES      = 32
FRAME_MS    = 80        # 32 × 80ms = 2.56초
BIG_FROM    = 3
BIG_EVERY   = 2
SMALL_FROM  = 11
SMALL_EVERY = 2
MARK_FROM   = 17
MARK_OVER   = 7
MARK_AT     = 128       # 워드마크 윗변 y (x 는 가운데 정렬)

def sequence():
    """2.5초. 아무 키나 누르면 건너뛴다 — 아이는 이 화면을 수백 번 본다."""
    out = []
    for f in range(FRAMES):
        nb = max(0, min(N_BIG, (f - BIG_FROM) // BIG_EVERY))
        ns = max(0, min(N_SMALL, (f - SMALL_FROM) // SMALL_EVERY))
        a  = 0.0 if f < MARK_FROM else min(1.0, (f - MARK_FROM) / MARK_OVER)
        out.append(screen(nb, ns, a))
    return out


def save_all():
    """조각 + 좌표/타이밍을 함께 내보낸다.
    합성 스틸 한 장만 주면 엔진이 발자국을 따로 못 움직인다 — 32프레임을 통째로
    굽는 것은 640×360 × 32장이라 낭비고, 조각과 좌표를 주면 엔진이 그린다.
    지형·프롭·단서를 `palettes.json` 으로 넘긴 것과 같은 방식이다."""
    import json
    d = os.path.join(OUT, "extracted", "ui")
    os.makedirs(d, exist_ok=True)
    wm = wordmark()
    wm.save(os.path.join(d, "logo_wordmark.png"))
    screen().save(os.path.join(d, "logo_screen.png"))
    paw(True, side="left").save(os.path.join(d, "logo_paw_big.png"))
    paw(True, side="right").save(os.path.join(d, "logo_paw_big_right.png"))
    paw(False, side="left").save(os.path.join(d, "logo_paw_small.png"))
    paw(False, side="right").save(os.path.join(d, "logo_paw_small_right.png"))

    meta = {
        "_comment": "제작사 로고 부팅 화면. 좌표는 스프라이트의 좌상단 기준, 캔버스 640×360.",
        "canvas": [W, H],
        "background": list(BG),
        "wordmark": "ui/logo_wordmark.png",
        "wordmark_at": [(W - wm.width)//2, MARK_AT],
        "paw_big": "ui/logo_paw_big.png",
        "paw_small": "ui/logo_paw_small.png",
        "big":   [_paw_entry(True, i)  for i in range(N_BIG)],
        "small": [_paw_entry(False, i) for i in range(N_SMALL)],
        "timing": {
            "frames": FRAMES, "frame_ms": FRAME_MS,
            "big_from": BIG_FROM, "big_every": BIG_EVERY,
            "small_from": SMALL_FROM, "small_every": SMALL_EVERY,
            "mark_from": MARK_FROM, "mark_fade_frames": MARK_OVER,
        },
        "skippable": True,
    }
    with open(os.path.join(d, "logo.json"), "w") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=2)
    print("extracted/ui/logo_wordmark.png · logo_screen.png · "
          "logo_paw_big{,_right}.png · logo_paw_small{,_right}.png · logo.json")


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
