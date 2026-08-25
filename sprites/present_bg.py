#!/usr/bin/env python3
"""필드 목업 · 하루 주기(팔레트 보간 + 오버레이 틴트 + 이펙트) · 검수 시트."""
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageChops
import build_bg as G
import build as A

OUT, T = G.OUT, G.T

def font(sz):
    try: return ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
    except Exception: return ImageFont.load_default()
F_H, F_L, F_S = font(30), font(21), font(17)
BG, INK, DIM, ACC = (26,31,38), (238,232,222), (150,158,168), (233,164,65)

MAP_W, MAP_H = 40, 24
STREAM_TOP, STREAM_BOT = 11, 14

def is_water(x, y):
    wob = math.sin(x*0.32)*1.5 + math.sin(x*0.11+2)*0.9
    return STREAM_TOP + wob <= y <= STREAM_BOT + wob

def _hash(x, y):
    h = (x*73856093) ^ (y*19349663)
    return (h ^ (h >> 13)) & 0xffff

def build_map():
    """물 타일의 이웃을 보고 물가 타일을 고른다 — 모서리에 코너가 들어가야 계단이 안 진다."""
    m = {}
    for y in range(MAP_H):
        for x in range(MAP_W):
            if is_water(x, y):
                n = not is_water(x, y-1); s = not is_water(x, y+1)
                w = not is_water(x-1, y); e = not is_water(x+1, y)
                side = ("N" if n else "") + ("S" if s else "") + \
                       ("W" if w else "") + ("E" if e else "")
                key = {"": "water_0", "N": "shore_N", "S": "shore_S",
                       "W": "shore_W", "E": "shore_E",
                       "NW": "shore_NW", "NE": "shore_NE",
                       "SW": "shore_SW", "SE": "shore_SE"}.get(side, "shore_N")
                m[(x, y)] = key
            elif 25 <= x <= 27 and y > STREAM_BOT + 2:   m[(x,y)] = "dirt"
            elif 20 <= x <= 32 and is_water(x, y-1):     m[(x,y)] = "sand"
            elif y >= MAP_H-3 and x < 8:                 m[(x,y)] = "rock"
            else:  m[(x,y)] = f"grass_{_hash(x,y) % G.GRASS_N}"
    return m

PROPS = [("tree",3,8),("conifer",8,6),("tree",33,7),("conifer",36,9),
         ("deadtree",19,5),("bigrock",13,9),("stump",29,8),
         ("bush",6,10),("bush",24,6),("flowers",11,7),("mushroom",16,9),
         ("tuft",21,9),("tuft",30,10),("pebbles",26,10),
         ("reed",10,17),("reed",12,18),("reed",31,17),
         ("log",15,20),("rock",34,19),("bush",5,19),("tuft",8,21),
         ("flowers",20,22),("conifer",2,21),("tree",37,22),
         ("thornbush",22,19),("mud",27,21),("branch",17,17),
         ("mushroom",36,17),("pebbles",13,22),("tuft",24,23)]

CLUE_SPOTS = [("발자국",25,17),("발자국",26,19),("큰발자국",32,20),
              ("나무흔적",12,8),("물자국",18,16),("허물",35,21),("털",7,18)]

ACTOR_POS = [("dog_e",22,21,"dog"),("sq_e",14,8,"squirrel"),("cat_s",5,16,"cat")]

FRAMES = {"dog_e": A.dog_side(0,"walk"), "dog_s": A.dog_south(0),
          "cat_s": A.cat_south(0), "sq_e": A.squirrel_side(0,"walk")}
APAL = {"dog": A.PALETTES["dog_default"], "cat": A.PALETTES["cat_default"],
        "squirrel": A.PALETTES["squirrel_default"]}


def apply_tint(im, tint):
    """오버레이 틴트 — 전역 곱연산. 팔레트가 색조를, 이게 밝기·채도를 담당한다."""
    if tint == (1.0, 1.0, 1.0): return im
    r, g, b, a = im.split()
    lut = lambda k: [min(255, int(i*k)) for i in range(256)]
    return Image.merge("RGBA", (r.point(lut(tint[0])), g.point(lut(tint[1])),
                                b.point(lut(tint[2])), a))

def night_effects(im, strength):
    """이펙트 레이어 — 반딧불. Linear 필터·자유 좌표 (§6.2)"""
    if strength <= 0.02: return im
    fx = Image.new("RGBA", im.size, (0,0,0,0)); d = ImageDraw.Draw(fx)
    r = random.Random(9)
    for _ in range(26):
        x, y = r.randrange(im.width), r.randrange(int(im.height*0.85))
        a = int(200*strength*(0.4 + 0.6*r.random()))
        d.ellipse([x-1, y-1, x+2, y+2], fill=(226, 240, 150, a))
        d.ellipse([x-3, y-3, x+4, y+4], fill=(180, 220, 120, a//5))
    return Image.alpha_composite(im, fx)


def render_field(u, water_frame=0):
    """u ∈ [0,1) 하루 위치. 팔레트 보간 → 틴트 → 이펙트 순으로 얹는다."""
    pal, tint = G.at_time(u)
    im = Image.new("RGBA", (MAP_W*T, MAP_H*T), (0,0,0,255))
    m = build_map()
    for (x, y), name in m.items():
        if name == "water_0": name = f"water_{water_frame}"
        im.paste(G.TILES[name].img(pal), (x*T, y*T))
    for name, tx, ty in CLUE_SPOTS:
        im.alpha_composite(G.CLUES[name].img(pal), (tx*T, ty*T))

    def with_shadow(img, w):
        """§4.4 — 발밑 타원 그림자는 필수"""
        out = Image.new("RGBA", (img.width, img.height + 4), (0,0,0,0))
        sh = Image.new("RGBA", out.size, (0,0,0,0))
        ImageDraw.Draw(sh).ellipse(
            [img.width//2 - w//2, img.height - 4, img.width//2 + w//2, img.height + 2],
            fill=(18, 24, 20, 105))
        out.alpha_composite(sh); out.alpha_composite(img, (0, 0))
        return out

    draw = []
    for name, tx, ty in PROPS:
        c = G.OBJECTS[name]
        sw = {"tree": 15, "conifer": 15, "deadtree": 9, "stump": 15,
              "bigrock": 22, "rock": 17, "log": 24, "bush": 17,
              "thornbush": 16, "reed": 8}.get(name, 10)
        img = with_shadow(c.img(pal), sw)
        draw.append((ty*T+T, img, tx*T + (T-c.w)//2, (ty+1)*T - c.h))
    for key, tx, ty, sp in ACTOR_POS:
        c = FRAMES[key]
        draw.append((ty*T+T, c.to_image(APAL[sp]), tx*T + (T-c.w)//2, (ty+1)*T - c.h))
    for _, img, x, y in sorted(draw, key=lambda d: d[0]):
        im.alpha_composite(img, (x, y))

    im = apply_tint(im, tint)
    night = max(0.0, math.cos((u - 0.875) * 2*math.pi) * 0.5 + 0.5) ** 3
    return night_effects(im, night)


# ── 산출물 ─────────────────────────────────────────────────────────────
def field_big():
    im = render_field(0.25)
    im.resize((im.width*2, im.height*2), Image.NEAREST).convert("RGB").save(
        os.path.join(OUT, "field.png"))

def daynight_sheet():
    Z, crop = 2, (0, 4*T, MAP_W*T, 21*T)
    stops = [(0.02,"새벽"), (0.28,"낮"), (0.56,"저녁"), (0.80,"밤")]
    panels = [(lab, render_field(u).crop(crop).resize(
                  ((crop[2]-crop[0])*Z, (crop[3]-crop[1])*Z), Image.NEAREST))
              for u, lab in stops]
    pw, ph = panels[0][1].size
    PAD = 30
    out = Image.new("RGBA", (pw+PAD*2, 150 + len(panels)*(ph+52)), BG+(255,))
    d = ImageDraw.Draw(out)
    d.text((PAD, 26), "하루 — 팔레트 보간 + 오버레이 틴트 + 이펙트", font=F_H, fill=INK)
    d.text((PAD, 68), "인덱스 아트는 한 벌. 시간은 팔레트를 섞어서 만들고, 틴트가 밝기를, 이펙트가 반딧불을 얹는다.",
           font=F_S, fill=DIM)
    y = 122
    for lab, im in panels:
        d.text((PAD, y), lab, font=F_L, fill=ACC); y += 32
        out.alpha_composite(im, (PAD, y)); y += ph + 20
    out.convert("RGB").save(os.path.join(OUT, "field_daynight.png"))

def daycycle_gif():
    Z, crop = 1, (4*T, 5*T, 30*T, 20*T)
    N = 24
    frames = []
    for i in range(N):
        u = i / N
        im = render_field(u, water_frame=i % 2).crop(crop)
        im = im.resize((im.width*2, im.height*2), Image.NEAREST)
        frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=128))
    frames[0].save(os.path.join(OUT, "field_daycycle.gif"), save_all=True,
                   append_images=frames[1:], duration=140, loop=0, disposal=2)

def parts_sheet():
    pal = G.PALETTES["day"]; Z = 5
    groups = [
        ("타일 16×16 — 32px 캐릭터는 2타일 높이", [(n, G.TILES[n]) for n in
            [f"grass_{i}" for i in range(G.GRASS_N)] +
            ["dirt","sand","rock","water_0","water_1",
             "shore_N","shore_S","shore_E","shore_W","shore_NE","shore_NW","shore_SE","shore_SW"]]),
        ("오브젝트 — 앵커는 바닥 중앙, Y-sort 대상 (§6.2)", [(n, G.OBJECTS[n]) for n in
            ("tree","conifer","deadtree","stump","bigrock","rock","pebbles","log",
             "bush","tuft","flowers","mushroom","reed")]),
        ("도움·치료 상황 — 사고 쪽으로만 (§2.6)", [(n, G.OBJECTS[n]) for n in
            ("thornbush","mud","branch")]),
        ("단서 — tags.json 의 trait_to_sense 를 그대로 (§5.4)", [(n, G.CLUES[n]) for n in
            ("발자국","큰발자국","나무흔적","물자국","허물","털","냄새표시","소리표시")]),
        ("먹이 — likes 태그", [(n, G.FOODS[n]) for n in ("견과","열매","씨앗","물고기","풀")]),
    ]
    PAD, cols, GAP = 34, 8, 18
    cellw = 32*Z + 12
    plan = []          # (제목, 항목, 셀높이, 행수)
    for title, items in groups:
        ch = max(c.h for _, c in items)*Z + 12
        rows = math.ceil(len(items)/cols)
        plan.append((title, items, ch, rows))
    H = 96 + sum(64 + r*(ch + 44) for _, _, ch, r in plan)
    W = PAD*2 + cols*(cellw + GAP)
    out = Image.new("RGBA", (W, H), BG+(255,)); d = ImageDraw.Draw(out)
    d.text((PAD, 26), "배경 · 오브젝트 · 아이템", font=F_H, fill=INK)
    y = 96
    for title, items, ch, rows in plan:
        d.text((PAD, y), title, font=F_L, fill=ACC); y += 34
        d.line([PAD, y, W-PAD, y], fill=(52,60,70), width=2); y += 16
        for i, (name, c) in enumerate(items):
            cx = PAD + (i % cols)*(cellw + GAP); cy = y + (i//cols)*(ch + 44)
            im = c.img(pal, Z)
            out.paste(Image.new("RGBA", (cellw, ch), (36,42,50,255)), (cx, cy))
            out.alpha_composite(im, (cx + (cellw-im.width)//2, cy + ch - im.height - 6))
            d.text((cx, cy + ch + 6), name, font=F_S, fill=DIM)
        y += rows*(ch + 44) + 14
    out.convert("RGB").save(os.path.join(OUT, "bg_parts.png"))


if __name__ == "__main__":
    G.save_all()
    parts_sheet(); field_big(); daynight_sheet(); daycycle_gif()
    print("bg_parts.png · field.png · field_daynight.png · field_daycycle.gif")
