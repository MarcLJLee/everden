#!/usr/bin/env python3
"""
남은 화면들 — 사물 상점 · 배치 모드 · 필드 HUD · 팀 편성

전부 640×360 실제 픽셀이고, 앞선 화면들과 같은 규약을 따른다:

  · 선택 표시는 **밝기 + 오른쪽으로 6px**. 커서는 발자국이다 (§6.7)
  · 라틴·숫자는 5×7 자체 비트맵, 한글은 갈무리 11
  · **마우스 전용 정보를 만들지 않는다.** 패드로도 같은 것을 본다
  · **글로 설명하지 않고 보여준다** — 상점에서 "누가 쓰나"는 태그 이름이 아니라
    내 동물의 얼굴로 보여준다. 7살은 태그를 못 읽는다
"""
import os, io, json, math
from PIL import Image, ImageDraw
import build_bg as G
import build as A
import build_player as PL
import build_title as T
import build_home as Hm
import present_bg as P

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = 640, 360
TS = G.T

INK, DIM, OFF, ACC = T.INK, T.INK_DIM, T.INK_OFF, T.ACCENT
PANEL_BG, PANEL_ED = (18, 18, 24, 214), (96, 90, 84, 255)


def panel(im, x, y, w, h, fill=PANEL_BG):
    d = ImageDraw.Draw(im)
    d.rectangle([x, y, x+w, y+h], fill=fill)
    d.rectangle([x, y, x+w, y+h], outline=PANEL_ED, width=1)

def dimmed(img, k=0.42):
    r, g, b, a = img.split()
    lut = [int(v*k) for v in range(256)]
    return Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))

def coin(im, x, y, n):
    day = G.PALETTES["day"]
    im.alpha_composite(G.FOODS["견과"].img(day).resize((16, 16), Image.NEAREST), (x, y))
    T.draw_text(im, str(n), x + 22, y + 3, INK, scale=2)

def sprite_of(sp, pal=None):
    fn = {"dog": lambda: A.dog_side(0, "idle"),
          "cat": lambda: A.cat_side(0, "idle"),
          "squirrel": lambda: A.squirrel_side(0, "idle")}.get(
              sp, (lambda sp=sp: A.SIDE_IDLE[sp](0)) if sp in A.SIDE_IDLE else None)
    return fn().to_image(A.PALETTES[pal or f"{sp}_default"])

def sense_icon(kind, scale=1):
    c = A.icon_sprite(kind)
    pal = list(A.ICON_PALETTE); pal[A.MID] = A.ICON_ACCENT[kind] + (255,)
    im = c.to_image(pal)
    return im.resize((im.width*scale, im.height*scale), Image.NEAREST) if scale > 1 else im


# ── 우리 동물 (시안용) ────────────────────────────────────────────────
MINE = [("dog", "dog_default", "탄이", ["후각"]),
        ("cat", "cat_default", "나비", ["청각", "시야"]),
        ("squirrel", "squirrel_default", "밤톨", ["시야"])]

def _species_row(sp):
    with io.open(os.path.join(os.path.dirname(OUT), "data", "animals.json"),
                 encoding="utf-8") as fp:
        return next(x for x in json.load(fp)["species"] if x["id"] == sp)

def users_of(obj_name):
    """이 사물을 **내 동물 중 누가 쓰는가.** 태그를 화면에 쓰지 않는다 —
    태그가 겹치는 동물의 얼굴을 보여준다. 그게 사는 이유가 된다."""
    tags = Hm.OBJECTS[obj_name][1]
    out = []
    for sp, pal, name, _ in MINE:
        row = _species_row(sp)
        own = set(row.get("habitat", [])) | {row.get("diet"), row.get("temperament")} \
              | set(row.get("behavior_tags", [])) \
              | set(sum((g.get("behavior_tags", []) for g in row.get("growth", [])), []))
        if not tags or (own & set(tags)): out.append((sp, pal, name))
    return out


# ── 1. 사물 상점 ──────────────────────────────────────────────────────
SHOP_ITEMS = list(Hm.OBJECTS.keys())

def shop_screen(sel=0, coins=120, owned=("밥그릇", "물그릇")):
    im = Hm.home_screen(0.30, hint=False)
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 8, 12, 150)))
    day = G.PALETTES["day"]

    panel(im, 8, 8, W-17, 30)
    T.ktext(im, "무엇을 놓아볼까?", 108, 15, INK, scale=1)
    coin(im, W-96, 15, coins)

    # 왼쪽 — 사물 격자 4×2
    gx, gy, cw, ch = 14, 50, 78, 74
    for i, name in enumerate(SHOP_ITEMS):
        c, tags, price = Hm.OBJECTS[name]
        x, y = gx + (i % 4)*cw, gy + (i // 4)*ch
        on = (i == sel)
        have = name in owned
        can = coins >= price
        panel(im, x, y, cw-8, ch-10,
              fill=(40, 38, 46, 235) if on else PANEL_BG)
        if on:
            # 격자에서는 발자국 커서가 옆 칸을 침범한다. 테두리로 고른 것을 표시한다 —
            # 목록에서만 발자국을 쓴다.
            ImageDraw.Draw(im).rectangle([x-1, y-1, x+cw-7, y+ch-9],
                                         outline=ACC + (255,), width=2)
        art = c.img(day)
        if not can and not have: art = dimmed(art)
        im.alpha_composite(art, (x + (cw-8-art.width)//2, y + 40 - art.height))
        if have:
            T.ktext(im, "있음", x + (cw-8)//2, y + 46, OFF, scale=1)
        else:
            im.alpha_composite(G.FOODS["견과"].img(day).resize((12, 12), Image.NEAREST),
                               (x + 12, y + 46))
            T.draw_text(im, str(price), x + 28, y + 48, INK if can else OFF, scale=1)

    # 오른쪽 — 고른 것 하나만 크게
    name = SHOP_ITEMS[sel]
    c, tags, price = Hm.OBJECTS[name]
    px_, py_, pw, ph = 336, 50, W-336-14, 232
    panel(im, px_, py_, pw, ph)
    T.ktext(im, name, px_ + pw//2, py_ + 10, INK, scale=2)
    big = c.img(day, 2)
    im.alpha_composite(big, (px_ + (pw-big.width)//2, py_ + 100 - big.height))

    T.ktext(im, "이걸 좋아할 아이", px_ + pw//2, py_ + 112, DIM, scale=1)
    us = users_of(name)
    if us:
        tot = sum(sprite_of(s, p).width for s, p, _ in us) + 8*(len(us)-1)
        x = px_ + (pw - tot)//2
        for s, p, nm in us:
            a = sprite_of(s, p)
            im.alpha_composite(a, (x, py_ + 168 - a.height))
            T.ktext(im, nm, x + a.width//2, py_ + 170, ACC, scale=1)
            x += a.width + 8
    else:
        T.ktext(im, "아직 아무도 없어요", px_ + pw//2, py_ + 150, OFF, scale=1)

    can = coins >= price and name not in owned
    panel(im, px_ + 20, py_ + ph - 42, pw - 40, 30,
          fill=(52, 44, 30, 240) if can else (30, 30, 34, 220))
    T.ktext(im, "있어요" if name in owned else ("사기" if can else "돈이 모자라요"),
            px_ + pw//2, py_ + ph - 34, INK if can else OFF, scale=2 if can else 1)

    T.ktext(im, "산 것은 언제든 도로 팔 수 있어요 · 값은 그대로 돌려줘요",
            W//2, H - 26, DIM, scale=1)
    return im


# ── 2. 배치 모드 ──────────────────────────────────────────────────────
def place_screen(name="긁는기둥", tx=22, ty=14, ok=True):
    """**격자에 스냅한다.** 자유 배치는 7살한테 어렵고 겹침 판정이 지저분해진다.
    그리고 **되돌릴 수 없는 실패를 만들지 않는다** — 배치는 언제든 옮기고,
    판 값은 그대로 돌려준다. 잘못 사도 손해가 없어야 한다 (원칙 2)."""
    im = Hm.home_screen(0.30, hint=False)
    day = G.PALETTES["day"]
    d = ImageDraw.Draw(im)

    top = (Hm.MAP_H*TS - H)//2
    x0, y0, x1, y1 = Hm.YARD
    # 격자는 **점으로** 찍는다. 선으로 그으면 화면을 통째로 잡아먹어서
    # 어디에 놓는지가 아니라 격자가 주인공이 된다 — 한 번 그렇게 그려봤다.
    for gy in range(y0+1, y1+2):
        for gx in range(x0+1, x1+1):
            sx, sy = gx*TS, gy*TS - top
            if 0 <= sy < H: d.point((sx, sy), fill=(255, 255, 255, 46))

    c = Hm.OBJECTS[name][0]
    art = c.img(day)
    ghost = art.copy(); ghost.putalpha(art.getchannel("A").point(lambda v: v*3//5))
    # 강조는 **사물이 차지하는 만큼** 그린다. 한 칸만 그리면 큰 사물이 어디까지
    # 먹는지가 안 보인다
    fw = max(1, (art.width + TS - 1)//TS); fh = max(1, (art.height + TS - 1)//TS)
    cx, cy = (tx - fw//2)*TS, (ty - fh + 1)*TS - top
    col = (120, 230, 130, 255) if ok else (230, 110, 100, 255)
    d.rectangle([cx, cy, cx+fw*TS-1, cy+fh*TS-1], outline=col, width=2)
    im.alpha_composite(ghost, (cx + (fw*TS - art.width)//2, cy + fh*TS - art.height))

    panel(im, 8, 8, 260, 30)
    T.ktext(im, f"{name} 놓는 중", 138, 15, INK, scale=1)
    panel(im, W-236, H-38, 228, 30)
    T.ktext(im, "여기 놓기        그만두기", W-122, H-31, DIM, scale=1)
    im.alpha_composite(T.cursor(), (W-228, H-33))
    return im


# ── 3. 필드 HUD ───────────────────────────────────────────────────────
def _field(u=0.30):
    return P.render_field(u).crop((0, 16, W, 16+H)).convert("RGBA")

def field_hud(mode="seek", seats=(3, 5), u=0.30, progress=0.62, paused=False):
    """탐색 중 / 교감 중. **게이지는 시작하면 반드시 완료된다** —
    방해 요소도 실패 조건도 없다 (원칙 2).

    ★ v3.19 — 유도 방향을 **발자국으로 그리지 않는다.** 지면 발자국은 "여기 지나갔다"
      (시야 단서)로 이미 쓰이고 있어서 한 화면에 두 뜻이 겹친다. 화살표로 나눈다.
    """
    im = _field(u)
    day = G.PALETTES["day"]

    # 동료 — 개가 냄새를 맡고 방향을 가리킨다 (§3.3)
    dog = A.dog_side(0, "walk").to_image(A.PALETTES["dog_default"])
    im.alpha_composite(dog, (188, 236))

    def head_mark(cx, base_y, sense, direction=None):
        """머리 위 표시. **패널을 두르지 않는다.**

        ★ 검은 판을 깔았더니 필드 위에 얹힌 **UI 위젯**으로 보였다 — 세계 밖의 물건이다.
          아이콘에 이미 어두운 외곽선이 있어서(ICON_PALETTE 인덱스 1) 배경 위에서 읽힌다.
        ★ **1배로 쓴다.** 동물이 32px 인데 아이콘이 32px 이면 아이콘이 동물만 해진다.
        ★ 대신 아래에 **꼬리 3px** 를 붙인다 — 누가 말하는지가 판 없이도 분명해진다.
        """
        ic = sense_icon(sense)
        arrow = None
        if direction:
            pal = list(A.ICON_PALETTE); pal[A.MID] = A.ICON_ACCENT[sense] + (255,)
            arrow = A.dir_arrow(direction).to_image(pal)
        w_ = ic.width + (arrow.width + 1 if arrow else 0)
        x = cx - w_//2
        y = base_y - ic.height - 4
        # 1px 그림자 — 판을 두르는 대신 이걸로 풀 위에서 떠오르게 한다
        sh = Image.new("RGBA", ic.size, (0, 0, 0, 0))
        sh.paste(Image.new("RGBA", ic.size, (14, 16, 20, 170)), (0, 0), ic)
        im.alpha_composite(sh, (x + 1, y + 1))
        im.alpha_composite(ic, (x, y))
        if arrow:
            ay = y + (ic.height - arrow.height)//2
            ash = Image.new("RGBA", arrow.size, (0, 0, 0, 0))
            ash.paste(Image.new("RGBA", arrow.size, (14, 16, 20, 170)), (0, 0), arrow)
            im.alpha_composite(ash, (x + ic.width + 2, ay + 1))
            im.alpha_composite(arrow, (x + ic.width + 1, ay))
        d = ImageDraw.Draw(im)                       # 꼬리 — 말하는 주인을 가리킨다
        for r in range(3):
            d.line([(cx - (2 - r), y + ic.height + r), (cx + (2 - r), y + ic.height + r)],
                   fill=(24, 30, 38, 235))

    if mode == "seek":
        # 지면 단서 — 동료가 없어도 플레이어가 직접 본다.
        # ★ v3.19 — 시야 동료가 하는 일이 **이것**이다. 몸을 멀리서 그려주는 게 아니라
        #   "여기 지나갔다"는 **자리**를 더 멀리서 알아본다.
        for (n, x, y) in (("발자국", 300, 244), ("발자국", 336, 232), ("털", 372, 220)):
            im.alpha_composite(G.CLUES[n].img(day), (x, y))
        head_mark(188 + dog.width//2, 236, "냄새", "east")
        # ★ 아래 안내 바를 뺐다. 머리 위 표시가 이미 같은 말을 하고 있고,
        #   검은 바가 하나 더 깔리면 필드가 UI 로 덮인다.
    else:
        # 교감 — 점유 시간 게이지 (§3.4). **동물 머리 위**에 뜬다
        cat = A.cat_side(0, "idle").to_image(A.PALETTES["cat_ginger"])
        cx_, base = 352, 224
        im.alpha_composite(cat, (cx_, base))
        gw, gh = 34, 5
        gx, gy = cx_ + cat.width//2 - gw//2, base - 10
        d = ImageDraw.Draw(im)
        d.rectangle([gx-1, gy-1, gx+gw, gy+gh], fill=(24, 22, 28, 230),
                    outline=(96, 90, 84, 255))
        fill = (150, 140, 110, 255) if paused else (255, 219, 115, 255)
        d.rectangle([gx, gy, gx+int(gw*progress), gy+gh-1], fill=fill)
        head_mark(cx_ + cat.width//2, gy - 7, "애정")
        if paused:   # 멈춘 것은 보이지 않으니 이때만 한 줄
            T.ktext(im, "멀어졌어요 · 다시 오면 이어서", W//2, H-34, DIM, scale=1)
        # 쏟다 만 개체 — 그 자리에 남은 게이지가 계속 보인다 (§3.4)
        other = A.squirrel_side(0, "idle").to_image(A.PALETTES["squirrel_default"])
        im.alpha_composite(other, (170, 150))
        ox, oy = 170 + other.width//2 - gw//2, 150 - 10
        d.rectangle([ox-1, oy-1, ox+gw, oy+gh], fill=(24, 22, 28, 200),
                    outline=(80, 76, 72, 255))
        d.rectangle([ox, oy, ox+int(gw*0.3), oy+gh-1], fill=(150, 140, 110, 255))

    # 상시 HUD — **지명과 자리 둘뿐이다** (§3.4)
    # ★ HUD 판도 가볍게 — 필드가 주인공이다. 글자에 그림자가 있어서 판이 옅어도 읽힌다
    HUD_BG = (16, 16, 22, 130)
    panel(im, W-104, 6, 96, 22, fill=HUD_BG)
    im.alpha_composite(T.cursor(), (W-99, 10))
    T.draw_text(im, f"{seats[0]} / {seats[1]}", W-72, 12, INK, scale=2)
    panel(im, 6, 6, 88, 22, fill=HUD_BG)
    T.ktext(im, "뒷산 냇가", 50, 11, INK, scale=1)
    return im


# ── 4. 팀 편성 · 원정 출발 ────────────────────────────────────────────
DEST = [("뒷산 냇가", ["물가", "숲"], ["dog", "cat", "squirrel"]),
        ("돌밭 너머", ["바위", "초원"], ["dog", "cat"])]

def team_screen(sel=0, picked=(0, 1), dest=0):
    """§3.1 — 목적지 미리보기는 **도감에 기록된 종만** 보여준다.
    아직 못 만난 종을 여기 띄우면 '무엇을 만날지 모른다'가 사라진다."""
    im = Hm.home_screen(0.30, hint=False)
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 8, 12, 170)))
    day = G.PALETTES["day"]

    panel(im, 8, 8, W-17, 30)
    T.ktext(im, "누구랑 갈까?", 92, 15, INK, scale=1)

    # 왼쪽 — 우리 동물
    for i, (sp, pal, name, senses) in enumerate(MINE):
        y = 52 + i*62
        on = (i == sel)
        panel(im, 26, y, 268, 54, fill=(40, 38, 46, 230) if on else PANEL_BG)
        a = sprite_of(sp, pal)
        im.alpha_composite(a, (36 + (6 if on else 0), y + 48 - a.height))
        T.ktext(im, name, 116, y + 10, INK if on else DIM, scale=2)
        x = 168
        for s in senses:
            im.alpha_composite(sense_icon({"후각": "냄새", "청각": "소리",
                                           "시야": "시야"}[s]), (x, y + 18))
            x += 20
        if i in picked:
            T.ktext(im, "같이 감", 258, y + 20, ACC, scale=1)
        if on: im.alpha_composite(T.cursor(), (4, y + 16))

    # 오른쪽 — 목적지와 미리보기
    name, terrains, seen = DEST[dest]
    px_, pw = 306, W - 306 - 14
    panel(im, px_, 52, pw, 176)
    T.ktext(im, name, px_ + pw//2, 60, INK, scale=2)
    # 지형 타일만 놓으면 색 사각형으로 보인다. 이름을 붙여야 "물가" 로 읽힌다 —
    # 타이틀에서는 배경 전체가 맥락이라 이름이 필요 없었지만 여기는 32px 조각이다
    tw = len(terrains)*44 - 8
    x = px_ + (pw - tw)//2
    for t in terrains:
        key = {"초원": "grass_0", "숲": "forest_0", "물가": "wet_0", "바위": "rock"}[t]
        im.alpha_composite(G.TILES[key].img(day, 2), (x, 84))
        T.ktext(im, t, x + 16, 118, DIM, scale=1)
        x += 44
    T.ktext(im, "만난 적 있는 아이들", px_ + pw//2, 136, DIM, scale=1)
    tot = sum(sprite_of(s).width for s in seen) + 6*(len(seen)-1)
    x = px_ + (pw - tot)//2
    for s in seen:
        a = sprite_of(s)
        im.alpha_composite(a, (x, 194 - a.height)); x += a.width + 6
    T.ktext(im, "여기 없는 아이도 있어요", px_ + pw//2, 200, OFF, scale=1)

    panel(im, px_ + 20, 244, pw - 40, 32, fill=(52, 44, 30, 240))
    T.ktext(im, "출발!", px_ + pw//2, 252, INK, scale=2)
    T.ktext(im, "데려간 아이는 다치지 않아요 · 언제든 돌아올 수 있어요",
            W//2, H - 26, DIM, scale=1)
    return im


# ── 6. 쉼터 ───────────────────────────────────────────────────────────
# §2.4 — 정원을 넘은 동물이 대기하는 곳. 규칙이 셋이고 셋 다 화면에서 보여야 한다.
#
#   1. **방출은 없다.** 그래서 "내보내기" 버튼이 없다. 집 ↔ 쉼터 둘뿐이다
#   2. **쉼터의 동물도 원정에 나갈 수 있다.** 안 보여주면 아이가 쉼터를
#      '못 쓰는 곳'으로 배운다 — 배지로 화면에 못박는다
#   3. **되돌릴 수 있다.** 자리가 꽉 찼으면 교체를 묻고, 교체도 언제든 되돌린다
#
# 그리고 쉼터가 **창고나 우리처럼 보이면 안 된다.** 동물이 실제로 잘 지내는 그림이어야
# 한다 — 그늘막 아래 방석에 누워 있고 자는 표시가 떠 있다. §"수집이 벌이 되면 안 된다".
SHELTER = [("cat", "cat_black", "까망", 150, 210),
           ("squirrel", "squirrel_rare", "도토리", 330, 244)]

def _plain_ground(terrain="초원", seed=9):
    """쉼터는 **집 마당이 아니다.** 집 바닥을 그대로 쓰면 같은 곳으로 읽힌다 —
    길도 울타리도 없는 다른 마당이어야 한다."""
    day = G.PALETTES["day"]
    keys = G.TERRAIN_TILES[terrain]
    im = Image.new("RGBA", (W, Hm.MAP_H*TS), (0, 0, 0, 255))
    for ty in range(Hm.MAP_H):
        for tx in range(W//TS + 1):
            im.paste(G.TILES[keys[Hm._h(tx, ty, seed) % len(keys)]].img(day),
                     (tx*TS, ty*TS))
    return im

def shelter_screen(sel=0, seats=(3, 5)):
    day = G.PALETTES["day"]
    im = _plain_ground()
    draw = []
    def put(img, x, yb, shadow=0):
        if shadow: img = Hm._shadow(img, shadow)
        draw.append((yb, img, x, yb - img.height + (4 if shadow else 0)))

    # 그늘막을 먼저, 동물을 그 **앞**(yb 가 더 큰 자리)에 눕힌다 — 뒤에 두면 가려진다
    for n, x, yb in (("그늘막", 116, 194), ("그늘막", 296, 228),
                     ("방석", 146, 206), ("방석", 326, 240),
                     ("물그릇", 232, 276), ("공", 420, 268),
                     ("방석", 460, 300), ("긁는기둥", 502, 218)):
        c = Hm.OBJECTS[n][0]
        put(c.img(day), x, yb, shadow=max(8, c.w - 6))
    for n, x, yb in (("tree", 24, 176), ("conifer", 120, 132), ("tree", 250, 120),
                     ("bush", 190, 156), ("tree", 420, 140), ("conifer", 556, 160),
                     ("bush", 356, 168), ("tuft", 300, 300), ("flowers", 90, 296),
                     ("tuft", 540, 292), ("bush", 610, 220), ("pebbles", 380, 316),
                     ("flowers", 168, 330), ("tuft", 470, 340)):
        c = G.OBJECTS[n]
        put(c.img(day), x, yb, shadow=max(6, c.w - 8))
    for sp, pal, nm, x, yb in SHELTER:
        put(sprite_of(sp, pal), x, yb, shadow=16)
    for _, img, x, y in sorted(draw, key=lambda d: d[0]):
        im.alpha_composite(img, (x, y))
    top = (Hm.MAP_H*TS - H)//2
    im = im.crop((0, top, W, top + H))
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 8, 12, 86)))

    for sp, pal, nm, x, yb in SHELTER:          # 자는 표시 — 잘 지낸다는 것을 그림으로
        im.alpha_composite(sense_icon("잠"), (x + 24, yb - top - 48))

    panel(im, 8, 8, W-17, 26)
    T.ktext(im, "쉼터", 44, 12, INK, scale=1)
    T.ktext(im, "집 자리", 300, 12, DIM, scale=1)
    T.draw_text(im, f"{seats[0]} / {seats[1]}", 356, 13,
                ACC if seats[0] < seats[1] else OFF, scale=2)
    T.ktext(im, "여기서 쉬는 아이", 500, 12, DIM, scale=1)
    T.draw_text(im, str(len(SHELTER)), 600, 13, INK, scale=2)

    sp, pal, nm, x, yb = SHELTER[sel]
    sy = yb - top
    im.alpha_composite(T.cursor(), (x + 6, sy - 50))
    lw, lh = 130, 44
    # 이름표를 동물 **아래**에 두면 정작 고른 아이를 가린다. 옆으로 뺀다
    lx = x + 44 if x < W//2 else x - lw - 12
    lx = min(W - lw - 10, max(10, lx))
    ly = min(H - 80 - lh, max(40, sy - 30))
    panel(im, lx, ly, lw, lh)
    T.ktext(im, nm, lx + lw//2, ly + 5, INK, scale=2)
    T.ktext(im, "원정 갈 수 있어요", lx + lw//2, ly + 27, ACC, scale=1)

    full = seats[0] >= seats[1]
    panel(im, 14, H-62, W-28, 50, fill=(30, 30, 36, 230))
    if full:
        # 자리가 없다고 **막지 않는다.** 바꿀지 묻고, 바꿔도 되돌릴 수 있다 (원칙 2)
        T.ktext(im, "집에 자리가 없어요 — 누구랑 바꿀까요?", W//2, H-57, INK, scale=1)
        x2 = 128
        for who, sp2, pal2 in (("탄이", "dog", "dog_default"),
                               ("나비", "cat", "cat_default")):
            a = sprite_of(sp2, pal2)
            im.alpha_composite(a, (x2, H-38))
            T.ktext(im, who, x2 + a.width//2, H-22, DIM, scale=1)
            x2 += 96
        T.ktext(im, "바꿔도 언제든 되돌릴 수 있어요", W-158, H-32, DIM, scale=1)
    else:
        T.ktext(im, f"{nm}를 집으로 데려갈까요?", W//2, H-54, INK, scale=1)
        im.alpha_composite(T.cursor(), (176, H-34))
        T.ktext(im, "데려가기", 240, H-32, INK, scale=1)
        T.ktext(im, "여기서 더 쉬기", 400, H-32, DIM, scale=1)
    return im


# ── 6.4 키캡 — 조작을 **글이 아니라 그림**으로 (§6.9) ──────────────────
# ★ "◀ ▶ 로 고르고 [스페이스] 로 정해요" 는 7살에게 **읽기 과제**다.
#   키 모양을 그려주면 읽지 않고 알아본다. 전부 공용이라 **종 수·화면 수와 무관**하다.
KEY_FACE, KEY_EDGE, KEY_INK = (58, 54, 66, 255), (110, 104, 96, 255), (238, 232, 222)

def _keycap(w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w-1, h-1], fill=KEY_FACE, outline=KEY_EDGE)
    for (x, y) in ((0, 0), (w-1, 0), (0, h-1), (w-1, h-1)):
        d.point((x, y), fill=(0, 0, 0, 0))          # 모서리를 깎아 둥글게 읽히게
    d.line([(1, h-2), (w-2, h-2)], fill=(34, 32, 40, 255))   # 아래 그림자 = 눌리는 물건
    return im

def key_text(label, pad=5):
    w = T.text_w(label, 1) + pad*2
    im = _keycap(w, 13)
    T.draw_text(im, label, pad, 3, KEY_INK, scale=1, shadow=False)
    return im

def key_arrows():
    """◀ ▶ — 글자가 아니라 삼각형으로 찍는다. 폰트에 없는 모양이다."""
    im = Image.new("RGBA", (27, 13), (0, 0, 0, 0))
    for i, left in enumerate((True, False)):
        cap = _keycap(12, 13)
        d = ImageDraw.Draw(cap)
        for r in range(4):
            x = 4 + r if left else 7 - r
            d.line([(x, 6-r), (x, 6+r)], fill=KEY_INK + (255,))
        im.alpha_composite(cap, (i*15, 0))
    return im

def key_wasd():
    """W 위, ASD 아래. 묶음 하나로 그려야 '이 네 개' 로 읽힌다."""
    im = Image.new("RGBA", (35, 24), (0, 0, 0, 0))
    im.alpha_composite(key_text("W", 3), (11, 0))
    for i, c in enumerate("ASD"):
        im.alpha_composite(key_text(c, 3), (i*12, 11))
    return im

KEYS = {"space": lambda: key_text("SPACE"), "start": lambda: key_text("START"),
        "esc": lambda: key_text("ESC"), "arrows": key_arrows, "wasd": key_wasd}


# ── 패드 글리프 (§2.10) ────────────────────────────────────────────────
# ★ **글은 그대로, 그림만 바뀐다.** 문장에 "[스페이스]" 를 안 넣기로 한 규칙이
#   여기서 값을 한다 — 넣었다면 장치마다 문장을 다시 써야 했다.
# ★ 7살에게는 A·B 글자보다 **색과 자리**가 먼저 읽힌다. 그래서 색을 쓴다.
# ⚠️ 엑스박스 배치 기준이다. 닌텐도 패드는 A/B 자리가 반대라 글리프를 갈아야 한다.
PAD_A, PAD_B = (72, 172, 84, 255), (206, 72, 66, 255)
PAD_GREY, PAD_EDGE = (86, 82, 92, 255), (140, 134, 126, 255)

def _disc(im, cx, cy, r, fill, edge=None):
    d = ImageDraw.Draw(im)
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=fill, outline=edge)
    return d

def pad_face(letter, color):
    """A · B — 원 하나에 글자 하나. 지름 13 으로 키캡과 높이를 맞춘다."""
    im = Image.new("RGBA", (13, 13), (0, 0, 0, 0))
    _disc(im, 6, 6, 6, color, (24, 22, 28, 255))
    T.draw_text(im, letter, 4, 3, (250, 246, 238), scale=1, shadow=False)
    return im

def pad_stick():
    """왼쪽 스틱 — **기울이는** 물건이라 화살표를 원 **밖에** 둘러야 방향이 읽힌다.
    ★ 처음엔 화살표를 원 안에 넣었더니 그냥 도넛으로 보였다."""
    im = Image.new("RGBA", (19, 19), (0, 0, 0, 0))
    _disc(im, 9, 9, 6, PAD_GREY, (24, 22, 28, 255))
    _disc(im, 9, 9, 3, (198, 192, 184, 255), (24, 22, 28, 255))
    d = ImageDraw.Draw(im)
    W_ = (238, 232, 222, 255)
    for r in range(3):                                    # 위 · 아래
        d.line([(9-r, 2+r), (9+r, 2+r)], fill=W_)
        d.line([(9-r, 16-r), (9+r, 16-r)], fill=W_)
    for r in range(3):                                    # 왼 · 오른
        d.line([(2+r, 9-r), (2+r, 9+r)], fill=W_)
        d.line([(16-r, 9-r), (16-r, 9+r)], fill=W_)
    return im

def pad_dpad():
    """십자 방향키 — **좌우 끝을 밝게** 해서 '옆으로 고르는 것' 을 말한다."""
    im = Image.new("RGBA", (17, 15), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([6, 0, 10, 14], fill=PAD_GREY, outline=(24, 22, 28, 255))
    d.rectangle([0, 5, 16, 9], fill=PAD_GREY, outline=(24, 22, 28, 255))
    d.rectangle([7, 6, 9, 8], fill=PAD_GREY)              # 가운데 이음매를 지운다
    W_ = (238, 232, 222, 255)
    for r in range(3):                                    # 좌우 끝 삼각형
        d.line([(1+r, 7-r), (1+r, 7+r)], fill=W_)
        d.line([(15-r, 7-r), (15-r, 7+r)], fill=W_)
    return im

def pad_menu():
    """☰ — 엑스박스 로고를 그리지 않는다. 세 줄이면 '메뉴' 로 읽힌다."""
    im = _keycap(17, 13)
    d = ImageDraw.Draw(im)
    for i in range(3):
        d.line([(5, 4 + i*2), (11, 4 + i*2)], fill=KEY_INK + (255,))
    return im

PADS = {"a": lambda: pad_face("A", PAD_A), "b": lambda: pad_face("B", PAD_B),
        "stick": pad_stick, "dpad": pad_dpad, "menu": pad_menu}

# 같은 행동에 두 글리프. **자리와 크기가 같아서 그림만 갈아 끼우면 된다.**
GLYPH = {"이동": ("wasd", "stick"), "고르기": ("arrows", "dpad"),
         "인사·정하기": ("space", "a"), "그만두기": ("esc", "b"),
         "메뉴": ("start", "menu")}


# ── 6.5 초대 카드 — 게이지가 끝나는 순간 (§3.12) ──────────────────────
# ★ **축하지 평가가 아니다.** 능력치 숫자를 여기 띄우면 "좋은 개체/나쁜 개체" 가 생기고
#   7살이 리셋 노가다를 배운다. 숫자는 하나도 안 쓴다 — 나이만 예외다.
# ★ 새로 그리는 도트 **0장**. 몸통 · 성별 뱃지(§4.9) · 감각 아이콘 전부 이미 있다.

# 종 설명 — **개체가 아니라 종**이다. 두 줄, 한 줄 15자 안쪽.
# 글을 이제 배우는 7살이 읽거나, 옆에서 읽어준다. 길면 벽이 된다.
# ★ 값의 주인은 구현 세션(data/animals.json)이다. 아래는 **제안**이다.
BLURB = {
    "dog":         ("코가 아주 밝아요.", "냄새로 친구를 찾아요."),
    "cat":         ("발소리가 안 나요.", "높은 데를 좋아해요."),
    "squirrel":    ("도토리를 모아요.", "볼주머니에 넣고 다녀요."),
    "raccoon_dog": ("밤에 돌아다녀요.", "아무거나 잘 먹어요."),
    "otter":       ("물속을 잘 헤엄쳐요.", "물가 굴에서 잠자요."),
    "water_deer":  ("뿔이 없는 사슴이에요.", "물가 풀밭을 좋아해요."),
    "leopard_cat": ("고양이를 닮았어요.", "밤에 혼자 다녀요."),
    "toad":        ("비 오는 날 나와요.", "뛰지 않고 걸어요."),
    "magpie":      ("반짝이는 걸 좋아해요.", "나무 위에 둥지를 지어요."),
    "sparrow":     ("무리 지어 다녀요.", "씨앗을 콕콕 먹어요."),
    "snake":       ("허물을 벗고 자라요.", "따뜻한 돌 위를 좋아해요."),
}
KO_NAME = {"dog": "개", "cat": "고양이", "squirrel": "다람쥐", "raccoon_dog": "너구리",
           "otter": "수달", "water_deer": "고라니", "leopard_cat": "삵",
           "toad": "두꺼비", "magpie": "까치", "sparrow": "참새", "snake": "뱀"}

def invite_card(sp="water_deer", male=True, stage="어른", age=3, is_new=True, pal=None):
    im = _field(0.30)
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 8, 12, 176)))
    day = G.PALETTES["day"]

    pw, ph = 400, 278
    px_, py_ = (W - pw)//2, 26
    panel(im, px_, py_, pw, ph, fill=(22, 22, 30, 240))
    cx = px_ + pw//2

    T.ktext(im, "우리 사파리에 왔어요!", cx, py_ + 12, ACC, scale=2)

    # 동물 — 2배. 이형이 있는 종이면 파츠를 얹는다 (§4.9)
    body = sprite_of(sp, pal)
    d = A.DIMORPH.get(sp)
    if d and male:
        base = A.PALETTES[pal or f"{sp}_default"]
        t = d["fn"]("side").to_image(base)
        ax, ay = d["anchor"]["side"]
        body = body.copy(); body.alpha_composite(t, (ax, ay))
    # 작은 종이 카드에서 초라해 보이면 안 된다 — 실루엣 높이를 맞춰 정수배로만 키운다
    k = max(2, min(4, 96 // max(1, body.height)))
    big = body.resize((body.width*k, body.height*k), Image.NEAREST)
    im.alpha_composite(big, (cx - big.width//2, py_ + 132 - big.height))

    T.ktext(im, KO_NAME[sp], cx, py_ + 140, INK, scale=3)

    # 뱃지 줄 — 성별 · 단계 · 나이. **능력치 숫자는 없다.**
    row = py_ + 180
    badge = (SEX_M if male else SEX_F).img(day)
    b2 = badge.resize((badge.width*2, badge.height*2), Image.NEAREST)
    im.alpha_composite(b2, (px_ + 74, row - 4))
    # ★ 아기는 나이를 숫자로 안 쓴다. "0살" 은 아무 뜻도 없다
    age_txt = "아기" if stage == "아기" else f"{stage} · {age}살"
    T.ktext(im, age_txt, px_ + 168, row + 2, INK, scale=2)

    x = px_ + 250
    for s in _species_row(sp).get("senses", []):
        im.alpha_composite(sense_icon({"후각": "냄새", "청각": "소리",
                                       "시야": "시야"}[s], 2), (x, row - 4))
        x += 38

    # 개략적인 설명 — 두 줄
    a, b = BLURB[sp]
    T.ktext(im, a, cx, py_ + 214, DIM, scale=1)
    T.ktext(im, b, cx, py_ + 232, DIM, scale=1)

    if is_new:
        T.ktext(im, "도감에 새로 들어왔어요", cx, py_ + 254, ACC, scale=1)
    panel(im, cx - 74, H - 46, 148, 28, fill=(52, 44, 30, 240))
    T.ktext(im, "반가워!", cx + 8, H - 40, INK, scale=2)
    im.alpha_composite(T.cursor(), (cx - 64, H - 40))
    return im


# ── 6.6 첫 만남 — **튜토리얼이 아니라 첫 번째 초대다** (§2.9) ──────────
# ★ 여기서 배우는 조작이 **본편과 같아야** 한다. 다른 코드로 다른 규칙을 만들면
#   아이가 여기서 배운 것이 필드에서 안 통한다. 게이지도 카드도 같은 것을 쓴다.
# ★ 글로 가르치지 않는다 — **한 줄 + 키캡**. 7살은 글을 다 안 읽는다.

def _player_side():
    return PL.compose("move_side_0", PL.PALETTES[list(PL.PALETTES)[0]])

def _glyph(action, device="key"):
    """같은 행동, 두 그림. **자리와 크기가 같아서 그림만 갈아 끼우면 된다.**"""
    k, p = GLYPH[action]
    return (PADS[p] if device == "pad" else KEYS[k])()


def first_meeting(step="invite", progress=0.62, device="key"):
    """step: walk(걸어보기) · notice(강아지가 왔다) · greet · invite(게이지)
    device: key | pad — **글은 그대로고 그림만 바뀐다.**"""
    im = Hm.home_field(0.30, bare=True)   # 아무것도 없는 마당에서 시작한다
    day = G.PALETTES["day"]

    ply = _player_side()
    px_, py_ = 250, 210
    im.alpha_composite(ply, (px_, py_ - ply.height))

    if step != "walk":
        pup = sprite_of("dog")
        pup = pup.transpose(Image.FLIP_LEFT_RIGHT)          # 아이 쪽을 본다
        im.alpha_composite(pup, (px_ + 52, py_ - pup.height))

    # 한 줄만. 아래에 키캡을 놓는다 — 읽지 않아도 알아본다
    # ★ 마지막 칸에 키캡이 **없는** 것이 중요하다 — 초대는 누르고 있는 게 아니라
    #   **곁에 있어 주는** 것이다(§3.4). 키캡을 두면 아이가 손가락을 누르고 기다린다.
    line, keys = {
        "walk":   ("걸어 볼까요?",           ["이동"]),
        "notice": ("어? 누가 왔어요.",        []),
        "greet":  ("가까이 가서 인사해요.",   ["인사·정하기"]),
        "invite": ("곁에 있어 주면 돼요.",    []),
    }[step]

    panel(im, 8, H - 62, W - 17, 54)
    T.ktext(im, line, W//2, H - 56, INK, scale=2)
    if keys:
        kx = W//2
        arts = [_glyph(k, device) for k in keys]
        tot = sum(a.width for a in arts) + 8*(len(arts)-1)
        kx -= tot//2
        for a in arts:
            im.alpha_composite(a, (kx, H - 32 + (24 - a.height)//2)); kx += a.width + 8

    if step == "invite":
        # ★ 게이지는 **동물 머리 위**에 뜬다 — 화면 아래 바가 아니라 그 자리에서 찬다.
        #   본편(§3.4)과 같은 물건이어야 아이가 여기서 배운 것을 필드에서 쓴다.
        gx, gy, gw = px_ + 48, py_ - 42, 40
        d = ImageDraw.Draw(im)
        d.rectangle([gx, gy, gx+gw, gy+4], fill=(24, 22, 28, 220), outline=(96, 90, 84, 255))
        d.rectangle([gx+1, gy+1, gx+1+int((gw-2)*progress), gy+3], fill=(255, 219, 115, 255))
    return im


# ── 6.7 필드에서 집으로 — **나가는 문이 있어야 한다** (§3.13) ───────────
# ★ 지금 구현에는 필드를 나오는 길이 없다. 원정을 나가면 못 돌아온다.
#   되돌릴 수 없는 상태를 만들지 않는다(원칙 2)는 여기에도 걸린다.
def field_home(sel=0, carrying=2, device="key"):
    im = _field(0.30)
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 8, 12, 150)))
    day = G.PALETTES["day"]

    pw, ph = 320, 226
    px_, py_ = (W-pw)//2, 62
    panel(im, px_, py_, pw, ph, fill=(22, 22, 30, 242))
    cx = px_ + pw//2

    home = SC_HOME.img(day)
    big = home.resize((home.width*2, home.height*2), Image.NEAREST)
    im.alpha_composite(big, (cx - big.width//2, py_ + 14))

    T.ktext(im, "집에 갈까요?", cx, py_ + 54, INK, scale=3)
    # ★ 데려가는 아이를 **얼굴로** 보여준다 — 숫자로 적으면 안 읽힌다
    if carrying:
        T.ktext(im, "같이 가는 아이", cx, py_ + 96, DIM, scale=1)
        arts = [sprite_of(sp, pal) for sp, pal, _, _ in MINE[:carrying]]
        tot = sum(a.width for a in arts) + 8*(len(arts)-1)
        x = cx - tot//2
        for a in arts:
            im.alpha_composite(a, (x, py_ + 146 - a.height)); x += a.width + 8

    for i, (label, bw) in enumerate((("갈래요", 130), ("더 놀래요", 130))):
        bx = cx - 136 + i*142
        on = (i == sel)
        by = py_ + ph - 46
        panel(im, bx, by, bw, 32, fill=(52, 44, 30, 240) if on else (30, 30, 34, 220))
        T.ktext(im, label, bx + bw//2 + 8, by + 7, INK if on else DIM, scale=2)
        if on: im.alpha_composite(T.cursor(), (bx + 8, by + 8))

    k = _glyph("메뉴", device)
    im.alpha_composite(k, (W - k.width - 12, 12))
    T.ktext(im, "로 열고 닫아요", W - k.width - 62, 14, DIM, scale=1)
    return im


# ── 7. 세계 지도 ──────────────────────────────────────────────────────
# §3.7 — 원정은 목표 사냥이 아니라 **여행**이다. 지도가 그 프레이밍을 짊어진다.
#
# 지도 배경은 **새로 그리지 않는다.** 지형 타일을 넓게 깔아 지역 덩어리를 만들고,
# 길은 **발자국**으로 잇는다 — 로고·메뉴 커서와 같은 물건이다.
# 새로 그리는 도트는 **핀 하나와 집 아이콘 하나**뿐이다.
def map_pin(dark=False):
    c = G.C(11, 15)
    c.ellipse(5, 5, 4.6, 4.6, G.SD if dark else G.AC)
    c.ellipse(5, 5, 2.0, 2.0, G.TR)
    for y in range(9, 15): c.rect(4, y, 6, y, G.KD)
    c.outline({G.AC, G.SD, G.KD})
    return c

def map_home():
    c = G.C(16, 14)
    c.rect(2, 6, 13, 12, G.KM)
    for i in range(6): c.rect(2 + i, 6 - i, 13 - i, 6 - i, G.AC)
    c.rect(6, 8, 9, 12, G.DD)
    c.outline({G.KM, G.AC, G.DD})
    return c

PIN, HOME_ICON = map_pin(), map_home()
SC_HOME = HOME_ICON

# ── 암수·짝 표식 (§4.9 · §2.4) ────────────────────────────────────────
# 종 수와 무관한 **다섯 장**이다. 동물마다 그리지 않는다.
#
# ★ 규칙을 짊어지는 것은 기호가 아니라 **하트**다 (원칙 3).
#   아이는 ♂♀ 를 읽어서 아기가 왜 안 생기는지 아는 게 아니라,
#   "얘는 혼자예요" 라는 **반쪽 하트**를 보고 안다. ♂♀ 는 그 다음에 붙는 이름표다.
#   ⚠️ 리본·분홍/파랑 같은 클리셰는 쓰지 않는다 — 동물이 아니라 사람 옷이다.

TR, OL, KD, SD, SM, AC = G.TR, G.OL, G.KD, G.SD, G.SM, G.AC

def _ring(c, cx, cy, r, v):
    c.ellipse(cx, cy, r, r, v); c.ellipse(cx, cy, r-1.6, r-1.6, TR)

def _rows(rows, mapping, w, h):
    c = G.C(w, h)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in mapping: c.set(x, y, mapping[ch])
    return c

def sex_badge(male):
    """★ 암수를 **색으로 나누지 않는다.** 둘 다 같은 회색이고 모양만 다르다 —
    분홍/파랑은 클리셰고, 색은 이미 §4.3 유전이 쓰고 있다."""
    M = {"#": SM}
    if male:                                      # ♂ — 고리 + 오른위 화살
        rows = ["......#####",
                "..........#",
                ".......#..#",
                "......#...#",
                ".###.#.....",
                "#...#......",
                "#...#......",
                "#...#......",
                ".###.......",
                "...........",
                "..........."]
    else:                                         # ♀ — 고리 + 아래 십자
        rows = ["..###......",
                ".#...#.....",
                ".#...#.....",
                ".#...#.....",
                "..###......",
                "...#.......",
                "...#.......",
                ".#####.....",
                "...#.......",
                "...#.......",
                "..........."]
    c = _rows(rows, M, 11, 11); c.outline({SM}); return c

def heart(half=False):
    """온전한 하트 = 짝이 있다 · 반쪽 하트 = **혼자예요**.
    ★ 규칙을 짊어지는 것은 이 하트지 ♂♀ 가 아니다 (원칙 3)."""
    full = ["..##.##..",
            ".#######.",
            ".#######.",
            ".#######.",
            "..#####..",
            "...###...",
            "....#....",
            "........."]
    c = _rows(full, {"#": AC}, 9, 8)
    if half:
        for y in range(8):                        # 오른쪽 절반을 비운다
            for x in range(5, 9):
                if c.px[y][x] == AC: c.set(x, y, TR)
        for (x, y) in ((5,0),(7,1),(7,3),(6,4),(5,5)):
            c.set(x, y, SM)                       # 빈자리를 점선으로 남긴다
    c.outline({AC})
    return c

def map_pin_pair():
    """짝이 있는 곳 — 지도 핀 **속**을 하트로 바꾼다. 핀을 새로 그리지 않는다."""
    c = map_pin()
    mini = ["#.#", "###", ".#."]
    for y, r in enumerate(mini):
        for x, ch in enumerate(r):
            if ch == "#": c.set(3 + x, 3 + y, OL)
    return c

SEX_M, SEX_F, HEART, HEART_HALF, PIN_PAIR = (
    sex_badge(True), sex_badge(False), heart(), heart(True), map_pin_pair())



MAP_REGIONS = [                     # (지형, 중심x, 중심y, 반지름x, 반지름y)
    ("숲",   140, 90, 170, 110),
    ("물가", 330, 170, 150, 46),
    ("바위", 520, 268, 130, 90),
]
# 판이 가운데 아래에 뜨므로 표는 그 바깥으로 흩어 놓는다 —
# 고른 곳을 설명하는 판이 다른 곳을 가리면 지도가 아니다
SPOTS = [
    ("home",  "우리집",      96, 292, None, None),
    ("open",  "뒷산 냇가",  292, 150, ["물가", "숲"], ["dog", "cat", "squirrel"]),
    ("open",  "돌밭 너머",  492, 206, ["바위", "초원"], ["dog", "cat"]),
    ("unseen", "???",       548, 80,  None, None),
]

def map_screen(sel=1):
    day = G.PALETTES["day"]
    im = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    for ty in range(H//TS + 1):
        for tx in range(W//TS + 1):
            cx, cy = tx*TS + 8, ty*TS + 8
            name = None
            for terr, ex, ey, rx, ry in MAP_REGIONS:
                dd = ((cx-ex)/rx)**2 + ((cy-ey)/ry)**2
                if dd <= 1.0:
                    # 지도에서 "물가" 를 젖은 흙 타일로만 깔면 그냥 갈색 땅이다.
                    # 가운데는 **물**이어야 물가로 읽힌다 — 축척이 다르면 표현도 달라진다
                    if terr == "물가" and dd <= 0.55:
                        name = f"water_{Hm._h(tx, ty, 3) % 2}"
                    else:
                        keys = G.TERRAIN_TILES[terr]
                        name = keys[Hm._h(tx, ty, 3) % len(keys)]
            if name is None:
                name = f"grass_{Hm._h(tx, ty, 3) % G.GRASS_N}"
            im.paste(G.TILES[name].img(day), (tx*TS, ty*TS))
    r, g, b, a = im.split()
    lut = [int(v*0.62) for v in range(256)]
    im = Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))

    import build_logo as LG
    def trail(a, b, n=6, alpha=190):
        for k in range(1, n):
            t = k/n
            paw = LG.paw(False, scale=1)
            ch = paw.getchannel("A").point(lambda v: v*alpha//255)
            paw.putalpha(ch)
            im.alpha_composite(paw, (int(a[0] + (b[0]-a[0])*t),
                                     int(a[1] + (b[1]-a[1])*t)))
    pts = [(s[2], s[3]) for s in SPOTS]
    trail(pts[0], pts[1]); trail(pts[1], pts[2])
    trail(pts[1], pts[3], alpha=70)          # 아직 안 가본 길은 흐리게

    for i, (kind, name, x, y, terr, seen) in enumerate(SPOTS):
        art = HOME_ICON.img(day) if kind == "home" else PIN.img(day, )
        if kind == "unseen": art = _silhouette(art, (70, 68, 78))
        im.alpha_composite(art, (x - art.width//2, y - art.height))
        on = (i == sel)
        T.ktext(im, name, x, y + 4, INK if on else DIM, scale=1)
        if on: im.alpha_composite(T.cursor(), (x - 11, y - art.height - 20))

    panel(im, 8, 8, W-17, 26)
    T.ktext(im, "어디로 갈까?", 74, 12, INK, scale=1)

    kind, name, x, y, terr, seen = SPOTS[sel]
    pw, ph = 216, 156
    px_, py_ = (W - pw)//2, H - ph - 30
    panel(im, px_, py_, pw, ph)
    T.ktext(im, name, px_ + pw//2, py_ + 8, INK, scale=2)
    if kind == "unseen":
        T.ktext(im, "아직 가 본 적 없어요", px_ + pw//2, py_ + 54, OFF, scale=1)
        T.ktext(im, "냇가에서 더 놀다 보면", px_ + pw//2, py_ + 88, OFF, scale=1)
        T.ktext(im, "길이 보일 거예요", px_ + pw//2, py_ + 110, OFF, scale=1)
    elif kind == "home":
        T.ktext(im, "여기가 우리집이에요", px_ + pw//2, py_ + 70, DIM, scale=1)
    else:
        tw = len(terr)*40 - 8
        tx2 = px_ + (pw - tw)//2
        for t in terr:
            key = {"초원": "grass_0", "숲": "forest_0", "물가": "wet_0",
                   "바위": "rock"}[t]
            im.alpha_composite(G.TILES[key].img(day, 2), (tx2, py_ + 34))
            T.ktext(im, t, tx2 + 16, py_ + 68, DIM, scale=1)
            tx2 += 40
        # §3.7 — 여행은 동료에게도 놀이다. 지형이 겹치는 동료를 이름으로 부른다
        like = [nm for (sp2, pal2, nm, _) in MINE
                if set(_species_row(sp2).get("habitat", [])) & set(terr)]
        if like:
            T.ktext(im, f"{' · '.join(like[:2])}가 좋아할 거예요",
                    px_ + pw//2, py_ + 88, ACC, scale=1)
        T.ktext(im, "만난 적 있는 아이", px_ + pw//2, py_ + 108, DIM, scale=1)
        tot = sum(sprite_of(s).width for s in seen) + 4*(len(seen)-1)
        sx = px_ + (pw - tot)//2
        for s2 in seen:
            aa = sprite_of(s2)
            im.alpha_composite(aa, (sx, py_ + ph - 4 - aa.height)); sx += aa.width + 4

    T.ktext(im, "걸어서 다녀오는 거예요 · 다치는 아이는 없어요",
            W//2, H - 26, DIM, scale=1)
    return im


def save_ui():
    """지도 아이콘 둘 — 이 화면에서 새로 그린 도트 전부다."""
    d = os.path.join(OUT, "extracted", "ui")
    os.makedirs(d, exist_ok=True)
    day = G.PALETTES["day"]
    PIN.img(day).save(os.path.join(d, "map_pin.png"))
    HOME_ICON.img(day).save(os.path.join(d, "map_home.png"))
    # 암수·짝 표식 — 종 수와 무관 (§4.9)
    for name, c in (("sex_male", SEX_M), ("sex_female", SEX_F),
                    ("pair_ok", HEART), ("pair_alone", HEART_HALF),
                    ("map_pin_pair", PIN_PAIR)):
        c.img(day).save(os.path.join(d, f"{name}.png"))
    # 키캡 — 조작을 글이 아니라 그림으로 (§6.9). 화면 수·종 수와 무관
    for name, fn in KEYS.items():
        fn().save(os.path.join(d, f"key_{name}.png"))
    for name, fn in PADS.items():
        fn().save(os.path.join(d, f"pad_{name}.png"))
    _save_screens(d)
    print(f"extracted/ui/ 지도 아이콘 2 + 암수·짝 표식 5 + 키캡 {len(KEYS)} + 패드 {len(PADS)} + screens.json")


# ── 화면 인계 규약 (§6.9) ────────────────────────────────────────────
# ★ 시안 PNG 는 참고용이지 **사양이 아니다.** 그림을 보고 좌표를 재는 것보다
#   `Label.text = "지형: ..."` 한 줄이 빠르니, 넘기는 형식이 글이면 화면도 글이 된다.
#   로고·타이틀은 json 으로 넘겨서 안 갈라졌다 — 나머지 화면에도 같은 방식을 쓴다.
#
#   kind:  art    그림이다. **글로 바꾸면 안 된다**
#          text   글. 짧게
#          count  숫자를 써도 되는 자리
#          keycap 조작 안내. 문장에 [스페이스] 를 쓰지 않는다
def _save_screens(d):
    meta = {
        "_comment": ("화면 인계 규약 (BRIEF §6.9). `art` 로 표시된 자리에 라벨이 들어가 있으면 "
                     "구현 실수가 아니라 **인계가 실패한 것**이다. 검수는 시안 PNG 와 실행 화면을 "
                     "나란히 놓고 글의 개수를 센다."),
        "kinds": {"art": "그림. 글로 바꾸지 않는다", "text": "글. 짧게",
                  "count": "숫자를 써도 되는 자리", "keycap": "아래 glyphs 표를 볼 것"},
        "glyphs": {
            "_comment": ("행동 하나에 그림 둘. **마지막으로 쓴 입력 장치**를 따라 갈아 끼운다 "
                         "(BRIEF §2.10). 자리와 크기가 같으므로 배치는 안 흔들린다. "
                         "★ 문장에는 키 이름을 넣지 않는다 — 넣었다면 장치마다 문장을 다시 써야 한다."),
            "switch_on": "마지막 입력 이벤트가 조이패드면 pad, 키보드·마우스면 key",
            "layout": "엑스박스 기준. 닌텐도 패드는 A/B 자리가 반대라 글리프를 갈아야 한다",
            "map": {action: {"key": f"ui/key_{k}.png", "pad": f"ui/pad_{p}.png"}
                    for action, (k, p) in GLYPH.items()},
        },
        "screens": {
            "world_map": {
                "decides": ["어디로"],
                "_note": "동료는 여기서 안 고른다 — 팀 편성 화면으로 (§3.9)",
                "elements": [
                    {"id": "지역_덩어리", "kind": "art", "what": "지형 타일을 원반으로 깔아 지역을 만든다"},
                    {"id": "길", "kind": "art", "what": "ui/logo_paw_small 을 0.45 배로 잇는다"},
                    {"id": "핀", "kind": "art", "what": "ui/map_pin · 짝이 필요하면 ui/map_pin_pair"},
                    {"id": "곳_이름", "kind": "text", "what": "지역 이름 하나"},
                    {"id": "지형", "kind": "art",
                     "what": "★ 지형 타일 그림 + 아래 이름. **'지형: 물가 · 숲' 처럼 글로 쓰지 않는다**"},
                    {"id": "동료_기분", "kind": "art",
                     "what": "★ 동료 얼굴 + 기쁨 눈(shared/eye_side_기쁨). 유불리를 말하지 않는다"},
                    {"id": "만난_아이", "kind": "art",
                     "what": "★ 얼굴 스프라이트 줄. **이름을 나열하지 않는다**. 못 만난 게 있으면 실루엣 하나"},
                    {"id": "조작", "kind": "keycap", "what": "arrows · space · esc"},
                ]},
            "team": {
                "decides": ["누구랑"],
                "elements": [
                    {"id": "우리_아이", "kind": "art", "what": "얼굴 + 이름 + 감각 아이콘(shared/emote_냄새·소리·시야)"},
                    {"id": "같이_감", "kind": "text", "what": "고른 아이 표시"},
                    {"id": "자리", "kind": "count", "what": "n / PARTY_MAX"},
                    {"id": "목적지", "kind": "art", "what": "지형 타일 + 만난 아이 얼굴"},
                    {"id": "출발", "kind": "text", "what": "출발!"},
                    {"id": "조작", "kind": "keycap", "what": "arrows · space"},
                ]},
            "first_meeting": {
                "_note": ("튜토리얼이 아니라 **첫 번째 초대**다 (§2.9). "
                          "본편 Gauge 를 그대로 쓴다 — 별도 코드로 다시 짜면 규칙이 갈라진다."),
                "yard": "bare — 산 사물도, 사는 동물도 없다",
                "steps": [
                    {"say": "걸어 볼까요?", "keycap": "wasd", "advance": "실제로 걸으면"},
                    {"say": "어? 누가 왔어요.", "keycap": None, "advance": "강아지가 다가온다"},
                    {"say": "가까이 가서 인사해요.", "keycap": "space", "advance": "interact 한 번"},
                    {"say": "곁에 있어 주면 돼요.", "keycap": None,
                     "advance": "★ 키캡 없음 — 누르고 있는 게 아니라 머무는 것이다"},
                ],
                "gauge": {"where": "동물 머리 위", "code": "본편 Gauge.gd 그대로",
                          "hold": False, "on_done": "초대 카드(§3.12)"},
            },
            "invite_card": {
                "_note": "축하지 평가가 아니다 (§3.12). 능력치 숫자를 넣지 않는다",
                "elements": [
                    {"id": "몸", "kind": "art", "what": "2~4배. 실루엣 높이를 맞춰 정수배로만"},
                    {"id": "종_이름", "kind": "text", "what": "가장 크게"},
                    {"id": "성별", "kind": "art", "what": "ui/sex_male · ui/sex_female"},
                    {"id": "나이", "kind": "text", "what": "'어른 · 3살' / 아기는 '아기'만"},
                    {"id": "감각", "kind": "art", "what": "shared/emote_*"},
                    {"id": "설명", "kind": "text", "what": "종 blurb 두 줄, 한 줄 15자 안쪽"},
                    {"id": "도감", "kind": "text", "what": "새 종일 때만"},
                ]},
            "field": {
                "_note": ("원정 필드 (BRIEF §3.3 · §3.4 · §5.4). "
                          "★ 상시 HUD 는 **지명과 자리 둘뿐**이다 — 늘리지 않는다. "
                          "판도 옅게(알파 130) 깐다. 글자에 그림자가 있어서 읽히고, **필드가 주인공**이다."),
                "elements": [
                    {"id": "지명", "kind": "text", "what": "왼쪽 위. 지역 이름 하나"},
                    {"id": "자리", "kind": "count", "what": "오른쪽 위. 발자국 아이콘 + n / max"},
                    {"id": "지면_단서", "kind": "art",
                     "what": ("clues/{발자국,큰발자국,나무흔적,물자국,허물,털}.png 를 **땅에** 놓는다. "
                              "동료가 없어도 플레이어가 직접 본다. 시야 동료는 **더 멀리서 알아볼 뿐**")},
                    {"id": "감각_표시", "kind": "art",
                     "what": ("**동료 머리 위.** shared/emote_{냄새,소리} + shared/dir_{방향}.png. "
                              "★ 아이콘이 '무엇으로', 화살표가 '어느 쪽'. 둘을 나눠야 2×4=8 이 아니라 2+4=6"),
                     "style": ("★ **판을 두르지 않는다.** 검은 판을 깔면 필드 위에 얹힌 UI 위젯으로 보인다 — "
                               "세계 밖의 물건이 된다. **1배**로 쓰고(동물이 32px 인데 아이콘이 32px 이면 "
                               "아이콘이 동물만 해진다), 대신 **1px 그림자**로 풀 위에서 띄우고 "
                               "아래에 **꼬리 3px** 를 붙여 주인을 가리킨다")},
                    {"id": "게이지", "kind": "art",
                     "what": "**동물 머리 위.** 아래 gauge 항목 참조"},
                    {"id": "상황_한줄", "kind": "text",
                     "what": ("★ **평소에는 없다.** 머리 위 표시가 이미 같은 말을 하고 있고, "
                              "검은 바가 하나 더 깔리면 필드가 UI 로 덮인다. "
                              "**안 보이는 것을 알려야 할 때만** 뜬다 — 게이지가 멈췄을 때 "
                              "'멀어졌어요 · 다시 오면 이어서' 정도")},
                ],
                "gauge": {
                    "_comment": ("점유 시간 게이지 (§3.4). **도트 0장** — ColorRect 로 그린다. "
                                 "시작하면 반드시 완료된다. 방해도 실패도 없다."),
                    "where": "동물 머리 위, 가로 가운데. 첫 만남과 **같은 자리·같은 크기**여야 한다",
                    "size": [34, 5],
                    "back": [24, 22, 28, 230], "edge": [96, 90, 84, 255],
                    "fill": [255, 219, 115, 255],
                    "fill_paused": [150, 140, 110, 255],
                    "paused": "멀어지면 **색만 죽는다.** 줄지 않는다 — 되돌릴 수 없는 실패를 만들지 않는다",
                    "partial": ("★ 쏟다 만 개체는 **그 자리에 남은 게이지가 계속 보인다.** "
                                "'아까 하다 만 애'를 알아봐야 다시 갈 마음이 생긴다. "
                                "Field.gd 의 `_partial_invites()` 가 이미 그 값을 준다"),
                    "on_done": "초대 카드(§3.12)",
                }},
            "field_home": {
                "_note": "필드를 나오는 문 (§3.13). START 로 열고 닫는다",
                "elements": [
                    {"id": "집", "kind": "art", "what": "ui/map_home 2배"},
                    {"id": "물음", "kind": "text", "what": "집에 갈까요?"},
                    {"id": "같이_가는_아이", "kind": "art",
                     "what": "★ 얼굴 줄. **'동료 2 / 초대 1' 처럼 숫자로 적지 않는다**"},
                    {"id": "선택", "kind": "text", "what": "갈래요 / 더 놀래요 — 둘뿐"},
                    {"id": "조작", "kind": "keycap", "what": "start"},
                ]},
        },
    }
    with open(os.path.join(d, "screens.json"), "w") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=2)


# ── 검수 시트 ────────────────────────────────────────────────────────
def sheet():
    from PIL import ImageFont
    def font(sz):
        try: return ImageFont.truetype(
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
        except Exception: return ImageFont.load_default()
    FH_, FL_, FS_ = font(30), font(20), font(15)
    BGC, INKC, DIMC, ACCC = (26,31,38), (238,232,222), (150,158,168), (233,164,65)
    PAD = 34

    panels = [
        ("사물 상점", shop_screen(3),
         "값 옆에 붙는 것은 태그 이름이 아니라 우리 아이 얼굴이다 — 사는 이유가 그림으로 보인다"),
        ("배치 모드", place_screen(),
         "16px 격자에 스냅. 격자는 점으로만 찍는다 — 선으로 그으면 격자가 주인공이 된다"),
        ("필드 · 찾는 중", field_hud("seek"),
         "동료가 냄새를 맡고 발자국으로 방향을 가리킨다. 지면 단서는 동료 없이도 보인다"),
        ("필드 · 친해지는 중", field_hud("bond"),
         "점유 시간 게이지. 시작하면 반드시 완료된다 — 방해도 실패도 없다 (원칙 2)"),
        ("초대 카드", invite_card("water_deer", True, "어른", 3, True),
         "축하지 평가가 아니다 — 능력치 숫자를 띄우면 '다시 뽑을까'가 생긴다. 새 도트 0장"),
        ("팀 편성 · 출발", team_screen(1),
         "감각은 코·귀·눈 아이콘으로. 목적지 미리보기는 도감에 있는 종만 (§3.1)"),
        ("도감 · 만난 아이", dex_screen(1),
         "크기는 아이 키(120cm)와 나란히 놓는다. 사는 곳은 여기서 푼다 — 이미 겪은 것이라 정답이 아니다"),
        ("도감 · 아직 못 만난 아이", dex_screen(4),
         "빈 칸이 아니라 채워질 자리. 이름은 보여주고 모습은 감춘다 — 이름은 미끼, 모습이 보상"),
        ("쉼터", shelter_screen(0),
         "창고가 아니라 잘 지내는 곳. 방출 버튼이 없고, 쉼터의 아이도 원정에 나간다 (§2.4)"),
        ("쉼터 · 자리가 꽉 찼을 때", shelter_screen(1, seats=(5, 5)),
         "누구랑 바꿀지 묻는다. 바꿔도 언제든 되돌린다 — 되돌릴 수 없는 선택을 만들지 않는다"),
        ("세계 지도", map_screen(1),
         "길은 발자국으로 잇는다. 새로 그린 도트는 핀과 집 아이콘 둘뿐"),
        ("세계 지도 · 아직 못 가 본 곳", map_screen(3),
         "확률을 노출하지 않는다. '냇가에서 더 놀다 보면 길이 보일 거예요' — 조건이 아니라 약속"),
    ]
    Wid = W + PAD*2
    out = Image.new("RGBA", (Wid, 200 + len(panels)*(H + 76)), BGC + (255,))
    d = ImageDraw.Draw(out)
    d.text((PAD, 26), "남은 화면 — 상점 · 배치 · 필드 · 팀 편성 · 도감", font=FH_, fill=INKC)
    d.text((PAD, 68), "640×360 실제 픽셀. 선택은 밝기 + 6px, 커서는 발자국, "
                      "한글은 갈무리 11.", font=FS_, fill=DIMC)
    y = 116
    for title, im, cap in panels:
        d.text((PAD, y), title, font=FL_, fill=ACCC); y += 28
        out.alpha_composite(im, (PAD, y)); y += H + 8
        d.text((PAD, y), cap, font=FS_, fill=DIMC); y += 40
    out.crop((0, 0, Wid, y)).convert("RGB").save(os.path.join(OUT, "screens_sheet.png"))




# ── 5. 도감 ───────────────────────────────────────────────────────────
# 도감은 데이터베이스가 아니라 **보물 상자**여야 한다.
#
#   못 만난 종은 **실루엣 + 이름**이다. 빈 칸으로 두면 "너 아직 못 했어" 가 되고,
#   다 보여주면 만날 이유가 없어진다. 이름은 미끼고 **모습이 보상이다** —
#   타이틀에서 이름을 감추지 않기로 한 것과 같은 선이다.
#
#   여기서는 **사는 곳을 보여준다.** 타이틀에서 감췄던 것을 도감에서는 푼다.
#   한 번 만난 동물의 서식지는 이미 아이가 겪은 것이라 정답을 주는 게 아니다.
DEX_ORDER = ["dog", "cat", "squirrel", "raccoon_dog", "otter", "water_deer",
             "leopard_cat", "toad", "magpie", "sparrow", "snake"]
MET = {"dog", "cat", "squirrel", "raccoon_dog", "toad"}   # 시안용 — 실제로는 세이브에서 온다
HAS_ART = {"dog", "cat", "squirrel"} | set(A.SIDE_IDLE)

CHILD_CM = 120                            # 7살 키. 크기 비교의 기준자
FOOD_ICON = {"견과": "견과", "열매": "열매", "씨앗": "씨앗",
             "물고기": "물고기", "풀": "풀"}
ACTIVITY_KO = {"주행성": "낮에 나와요", "야행성": "밤에 나와요",
               "박명성": "해뜰 때 해질 때"}

def _silhouette(img, col=(58, 56, 64)):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", img.size, col + (255,)), (0, 0), img)
    return out

def _size_cm(row):
    """'55-65cm' → 대표값 하나. 범위의 가운데를 쓴다."""
    t = (row.get("size") or {}).get("adult", "")
    nums = [int(n) for n in "".join(c if c.isdigit() else " " for c in t).split()]
    return sum(nums)//len(nums) if nums else 0

def dex_screen(sel=1):
    im = Hm.home_screen(0.30, hint=False)
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 8, 12, 186)))
    day = G.PALETTES["day"]
    d = ImageDraw.Draw(im)

    panel(im, 8, 8, W-17, 26)
    T.ktext(im, "도감", 44, 12, INK, scale=1)
    T.draw_text(im, f"{len(MET)} / {len(DEX_ORDER)}", W-84, 13, ACC, scale=2)

    # 왼쪽 — 종 격자
    gx, gy, cw, ch, cols = 14, 42, 73, 84, 4
    for i, sp in enumerate(DEX_ORDER):
        row = _species_row(sp)
        x, y = gx + (i % cols)*cw, gy + (i // cols)*ch
        on = (i == sel)
        panel(im, x, y, cw-9, ch-12, fill=(40, 38, 46, 235) if on else PANEL_BG)
        if on:
            d.rectangle([x-1, y-1, x+cw-8, y+ch-11], outline=ACC + (255,), width=2)
        if sp in HAS_ART:
            art = sprite_of(sp)
            if sp not in MET: art = _silhouette(art)
        else:
            art = Image.new("RGBA", (28, 24), (0, 0, 0, 0))
            ImageDraw.Draw(art).rectangle([0, 0, 27, 23], fill=(46, 44, 52, 255))
            T.draw_text(art, "?", 11, 8, (86, 84, 92), scale=1, shadow=False)
        im.alpha_composite(art, (x + (cw-9-art.width)//2, y + 46 - art.height))
        T.ktext(im, row["name"], x + (cw-9)//2, y + 50,
                INK if sp in MET else OFF, scale=1)

    # 오른쪽 — 고른 종
    sp = DEX_ORDER[sel]
    row = _species_row(sp)
    px_, py_, pw, ph = 312, 42, W - 312 - 14, 258
    panel(im, px_, py_, pw, ph)
    met = sp in MET
    T.ktext(im, row["name"], px_ + pw//2, py_ + 8, INK if met else OFF, scale=2)

    if met:
        big = sprite_of(sp)
        big = big.resize((big.width*2, big.height*2), Image.NEAREST)
        im.alpha_composite(big, (px_ + 20, py_ + 112 - big.height))
    else:
        # 빈 칸으로 두면 "너 아직 못 했어" 가 된다. **채워질 자리**로 보여야 한다.
        bw_, bh_ = 88, 72
        bx_, by_ = px_ + (pw - bw_)//2, py_ + 46
        d.rectangle([bx_, by_, bx_+bw_, by_+bh_], fill=(30, 29, 35, 255))
        for k in range(0, bw_, 6):                       # 점선 테두리
            d.rectangle([bx_+k, by_, bx_+k+2, by_], fill=(86, 82, 92, 255))
            d.rectangle([bx_+k, by_+bh_, bx_+k+2, by_+bh_], fill=(86, 82, 92, 255))
        for k in range(0, bh_, 6):
            d.rectangle([bx_, by_+k, bx_, by_+k+2], fill=(86, 82, 92, 255))
            d.rectangle([bx_+bw_, by_+k, bx_+bw_, by_+k+2], fill=(86, 82, 92, 255))
        if sp in HAS_ART:
            sil = _silhouette(sprite_of(sp))             # 도트가 있으면 실루엣까지는 보여준다
            sil = sil.resize((sil.width*2, sil.height*2), Image.NEAREST)
            im.alpha_composite(sil, (bx_ + (bw_-sil.width)//2, by_ + (bh_-sil.height)//2))
        else:
            T.draw_text(im, "?", bx_ + bw_//2 - 9, by_ + bh_//2 - 14, (92, 88, 98), scale=4)

    if not met:
        T.ktext(im, "아직 만난 적 없어요", px_ + pw//2, py_ + 132, OFF, scale=1)
        T.ktext(im, "만나면 여기가 채워져요", px_ + pw//2, py_ + 154, OFF, scale=1)
        T.ktext(im, "새로운 아이를 만나면 자리가 하나 늘어요",
                W//2, H - 26, DIM, scale=1)
        return im

    # 크기 — 실측을 아이 키와 나란히 (§측정은 스케일 정의지 지표가 아니다)
    # 이름·막대·숫자를 **세 칸으로 갈라 놓는다.** 겹치면 막대가 글자에 먹힌다
    cm = _size_cm(row)
    lab_r, bx, bw = px_ + 150, px_ + 158, 96
    for k, (lab, val, col) in enumerate((("나", CHILD_CM, (120, 128, 140)),
                                         (row["name"], cm, ACC))):
        y = py_ + 40 + k*24
        w_ = max(4, int(bw * min(1.0, val / max(CHILD_CM, cm))))
        d.rectangle([bx, y, bx+bw, y+10], fill=(34, 32, 38, 255))
        d.rectangle([bx, y, bx+w_, y+10], fill=col + (255,))
        d.rectangle([bx, y, bx+bw, y+10], outline=(70, 68, 76, 255), width=1)
        T.ktext(im, lab, lab_r - 32, y - 2, DIM, scale=1)
        T.draw_text(im, f"{val}CM", bx + bw + 8, y + 1, DIM, scale=1)

    def label(y, text): T.ktext(im, text, px_ + 44, y, DIM, scale=1)

    y = py_ + 116                                   # 사는 곳
    label(y, "사는 곳")
    x = px_ + 92
    for t in row.get("habitat", []):
        key = {"초원": "grass_0", "숲": "forest_0", "물가": "wet_0", "바위": "rock"}[t]
        im.alpha_composite(G.TILES[key].img(day), (x, y - 2))
        T.ktext(im, t, x + 8, y + 16, DIM, scale=1)
        x += 26

    y += 42                                          # 언제
    label(y, "언제")
    T.ktext(im, ACTIVITY_KO.get(row.get("activity"), ""), px_ + 148, y, INK, scale=1)

    y += 28                                          # 좋아하는 것
    label(y, "좋아해")
    x = px_ + 92
    for lk in row.get("likes", []):
        if lk in FOOD_ICON:
            im.alpha_composite(G.FOODS[FOOD_ICON[lk]].img(day), (x, y - 4)); x += 20
    if x == px_ + 92:
        T.ktext(im, "·".join(row.get("likes", [])), px_ + 148, y, DIM, scale=1)

    y += 30                                          # 감각
    label(y, "잘하는 것")
    x = px_ + 92
    for s in row.get("senses", []):
        im.alpha_composite(sense_icon({"후각": "냄새", "청각": "소리",
                                       "시야": "시야"}[s]), (x, y - 4))
        x += 20

    T.ktext(im, "새로운 아이를 만나면 자리가 하나 늘어요", W//2, H - 26, DIM, scale=1)
    return im


if __name__ == "__main__":
    save_ui(); sheet()
    print("screens_sheet.png")
