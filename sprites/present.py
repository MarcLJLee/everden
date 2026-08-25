#!/usr/bin/env python3
"""검수용 시트 · 걷기 GIF · 레이어 분해 · 팔레트 교체 데모를 만든다."""
import os, math
from PIL import Image, ImageDraw, ImageFont
import build as B

OUT = B.OUT
Z = 7  # 확대 배율

def font(sz):
    for p in ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
              "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"):
        if os.path.exists(p):
            try: return ImageFont.truetype(p, sz)
            except Exception: pass
    return ImageFont.load_default()

F_H, F_L, F_S = font(30), font(21), font(17)
BG, INK, DIM, LINE = (26,31,38), (238,232,222), (150,158,168), (52,60,70)

def up(c, pal, z=Z):
    im = c.to_image(pal)
    return im.resize((im.width*z, im.height*z), Image.NEAREST)

def checker(w, h, s=7):
    im = Image.new("RGBA", (w, h), (36,42,50,255)); d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if (x//s + y//s) % 2: d.rectangle([x, y, x+s-1, y+s-1], fill=(44,51,60,255))
    return im


def build_all():
    frames = {}
    for f in (0, 1):
        frames[f"dog/walk_east_{f}"]  = B.dog_side(f, "walk")
        frames[f"dog/walk_south_{f}"] = B.dog_south(f)
        frames[f"dog/walk_north_{f}"] = B.dog_north(f)
        frames[f"dog/idle_east_{f}"]  = B.dog_side(f, "idle")
        frames[f"dog/special_{f}"]    = B.dog_special(f)
        frames[f"cat/walk_east_{f}"]  = B.cat_side(f, "walk")
        frames[f"cat/walk_south_{f}"] = B.cat_south(f)
        frames[f"cat/walk_north_{f}"] = B.cat_north(f)
        frames[f"cat/special_{f}"]    = B.cat_special(f)
        frames[f"sq/walk_east_{f}"]   = B.squirrel_side(f, "walk")
        frames[f"sq/walk_south_{f}"]  = B.squirrel_south(f)
    for f in (0, 1):
        frames[f"dog/walk_west_{f}"] = frames[f"dog/walk_east_{f}"].mirrored()
    return frames


# ── 1. 검수 시트 ───────────────────────────────────────────────────────
def contact_sheet(fr):
    DP, SP = B.PALETTES["dog_default"], B.PALETTES["squirrel_default"]
    rows = [
        ("개 · 이동 4방향 (E/W는 미러)", DP, [
            ("남 ↓", [f"dog/walk_south_{i}" for i in (0,1)]),
            ("북 ↑", [f"dog/walk_north_{i}" for i in (0,1)]),
            ("동 →", [f"dog/walk_east_{i}"  for i in (0,1)]),
            ("서 ←", [f"dog/walk_west_{i}"  for i in (0,1)]),
        ]),
        ("개 · 대기 좌우 2방향 / 특징 동작 측면 1방향", DP, [
            ("대기 →", [f"dog/idle_east_{i}" for i in (0,1)]),
            ("꼬리 흔들기", [f"dog/special_{i}" for i in (0,1)]),
        ]),
        ("고양이 · 뾰족 귀 · 짧은 꼬리 · 보송한 윤곽", B.PALETTES["cat_default"], [
            ("남 ↓", [f"cat/walk_south_{i}" for i in (0,1)]),
            ("북 ↑", [f"cat/walk_north_{i}" for i in (0,1)]),
            ("동 →", [f"cat/walk_east_{i}"  for i in (0,1)]),
            ("앉기", [f"cat/special_{i}"    for i in (0,1)]),
        ]),
        ("청설모 · 24×24 (소형 캔버스)", SP, [
            ("남 ↓", [f"sq/walk_south_{i}" for i in (0,1)]),
            ("동 →", [f"sq/walk_east_{i}"  for i in (0,1)]),
        ]),
    ]
    CW, PAD, GAP = 32*Z, 34, 26
    H = 84 + sum(70 + CW + 64 for _ in rows)
    W = PAD*2 + 4*(CW*2 + GAP + 46)
    im = Image.new("RGBA", (W, H), BG + (255,)); d = ImageDraw.Draw(im)
    d.text((PAD, 26), "사파리 — 플레이스홀더 스프라이트", font=F_H, fill=INK)
    y = 96
    for title, pal, groups in rows:
        d.text((PAD, y), title, font=F_L, fill=(233,164,65)); y += 36
        d.line([PAD, y, W-PAD, y], fill=LINE, width=2); y += 20
        x = PAD
        for label, keys in groups:
            gw = CW*len(keys) + 10*(len(keys)-1)
            d.text((x, y), label, font=F_S, fill=DIM)
            for i, k in enumerate(keys):
                c = fr[k]
                sx = x + i*(CW+10)
                im.paste(checker(c.w*Z, c.h*Z), (sx, y+24))
                im.alpha_composite(up(c, pal), (sx, y+24))
                d.text((sx+4, y+24+c.h*Z+4), f"{i}", font=F_S, fill=DIM)
            x += gw + 46
        y += 24 + CW + 60
    im.convert("RGB").save(os.path.join(OUT, "preview.png"))


# ── 2. 걷기 GIF — 바운스는 스프라이트가 아니라 노드가 낸다 (§4.6) ──────
def walk_gif(fr):
    DP, SP = B.PALETTES["dog_default"], B.PALETTES["squirrel_default"]
    cells = [("남 ↓","dog/walk_south",DP,32), ("북 ↑","dog/walk_north",DP,32),
             ("동 →","dog/walk_east",DP,32),  ("서 ←","dog/walk_west",DP,32),
             ("청설모","sq/walk_east",SP,24)]
    CW, PAD, TOP = 32*Z, 26, 62
    W = PAD*2 + len(cells)*(CW+22) - 22
    H = TOP + CW + 46
    out = []
    for step in range(4):
        f = step % 2
        bounce = -Z if step in (1, 3) else 0     # 노드 Y 바운스 (정수 픽셀 스냅)
        im = Image.new("RGBA", (W, H), BG + (255,)); d = ImageDraw.Draw(im)
        d.text((PAD, 16), "걷기 — 바운스는 스프라이트가 아니라 노드 Y (§4.6)", font=F_L, fill=(233,164,65))
        for i, (label, key, pal, sz) in enumerate(cells):
            x = PAD + i*(CW+22)
            c = fr[f"{key}_{f}"]
            sw = c.w*Z
            gx = x + (CW-sw)//2
            # 그림자는 바운스를 따라가지 않는다
            d.ellipse([gx+sw*0.22, TOP+CW-18, gx+sw*0.78, TOP+CW-6], fill=(16,20,26,255))
            im.alpha_composite(up(c, pal), (gx, TOP + (CW - c.h*Z) + bounce))
            d.text((x+4, TOP+CW+16), label, font=F_S, fill=DIM)
        out.append(im.convert("P", palette=Image.ADAPTIVE, colors=64))
    out[0].save(os.path.join(OUT, "walk.gif"), save_all=True, append_images=out[1:],
                duration=190, loop=0, disposal=2)


# ── 3. 레이어 분해 + 앵커 ──────────────────────────────────────────────
def layer_demo(fr):
    DP = B.PALETTES["dog_default"]
    eye_front = B.eye_sprite("round", "기본", "front")
    eye_side  = B.eye_sprite("round", "기본", "side")
    eye_sad   = B.eye_sprite("round", "시무룩", "front")
    icon = B.icon_sprite("냄새"); ipal = list(B.ICON_PALETTE)
    ipal[B.MID] = B.ICON_ACCENT["냄새"] + (255,)

    # animals.json 앵커 (개 · 중형 32px). 아이콘은 방향과 무관하게 캔버스 중앙 위.
    EYE_FRONT_A, EYE_SIDE_A, HEAD_A = (16, 9), (24, 10), (16, 2)
    PAD_TOP = 18  # 아이콘이 들어갈 머리 위 여백 — 엔진에서는 형제 노드라 잘리지 않는다

    def compose(body, eye=None, eye_at=None, emote=False):
        base = Image.new("RGBA", (32*Z, (32+PAD_TOP)*Z), (0,0,0,0))
        base.alpha_composite(up(body, DP), (0, PAD_TOP*Z))
        if eye is not None:
            ex = (eye_at[0] - eye.w//2)*Z
            ey = (eye_at[1] - eye.h//2 + PAD_TOP)*Z
            base.alpha_composite(up(eye, DP), (ex, ey))   # 눈도 종 팔레트로 — 인덱스 7·8
        if emote:
            base.alpha_composite(up(icon, ipal, Z),
                                 ((HEAD_A[0]-8)*Z, (HEAD_A[1]-16+PAD_TOP)*Z))
        return base

    steps = [
        ("몸통만", compose(fr["dog/walk_south_0"]), "눈·입은 그리지 않는다"),
        ("+ 눈", compose(fr["dog/walk_south_0"], eye_front, EYE_FRONT_A), "eye_anchor front [16,9]"),
        ("+ 아이콘", compose(fr["dog/walk_south_0"], eye_front, EYE_FRONT_A, True), "head_anchor [16,2]"),
        ("측면 앵커", compose(fr["dog/walk_east_0"], eye_side, EYE_SIDE_A), "eye_anchor side [24,10]"),
        ("북향 — 눈 숨김", compose(fr["dog/walk_north_0"]), "뒷모습엔 얼굴이 없다"),
        ("표정 교체", compose(fr["dog/walk_south_0"], eye_sad, EYE_FRONT_A), "같은 몸통 · 눈만 시무룩"),
    ]
    CW, CH, PAD = 32*Z, (32+PAD_TOP)*Z, 34
    W = PAD*2 + len(steps)*(CW+26) - 26
    H = 190 + CH
    im = Image.new("RGBA", (W, H), BG + (255,)); d = ImageDraw.Draw(im)
    d.text((PAD, 26), "레이어 조합과 앵커 (§4.6)", font=F_H, fill=INK)
    d.text((PAD, 68), "종별로 그리는 것은 몸통뿐 — 눈·아이콘은 공용이고 앵커 좌표로 얹는다", font=F_S, fill=DIM)
    for i, (label, img, note) in enumerate(steps):
        x = PAD + i*(CW+26)
        im.paste(checker(CW, CH), (x, 108))
        im.alpha_composite(img, (x, 108))
        d.text((x, 108+CH+12), label, font=F_L, fill=(233,164,65))
        d.text((x, 108+CH+40), note, font=F_S, fill=DIM)
    im.convert("RGB").save(os.path.join(OUT, "layers.png"))


# ── 4. 팔레트 교체 (§4.3 색 유전 · 특수색) ─────────────────────────────
def palette_demo(fr):
    sets = [("개 · 기본", "dog/walk_east_0", "dog_default"),
            ("개 · 검정", "dog/walk_east_0", "dog_black"),
            ("개 · 크림", "dog/walk_east_0", "dog_cream"),
            ("청설모 · 기본", "sq/walk_east_0", "squirrel_default"),
            ("청설모 · 특수색", "sq/walk_east_0", "squirrel_rare")]
    CW, PAD = 32*Z, 34
    W = PAD*2 + len(sets)*(CW+26) - 26
    H = 200 + CW
    im = Image.new("RGBA", (W, H), BG + (255,)); d = ImageDraw.Draw(im)
    d.text((PAD, 26), "팔레트 교체 (§4.3)", font=F_H, fill=INK)
    d.text((PAD, 68), "그림은 한 장이다. 색 유전과 특수색은 팔레트만 갈아끼운 결과다", font=F_S, fill=DIM)
    for i, (label, key, pname) in enumerate(sets):
        x = PAD + i*(CW+26); pal = B.PALETTES[pname]; c = fr[key]
        im.paste(checker(CW, CW), (x, 108))
        im.alpha_composite(up(c, pal), (x + (CW-c.w*Z)//2, 108 + (CW-c.h*Z)))
        d.text((x, 108+CW+12), label, font=F_L, fill=(233,164,65))
        for j, col in enumerate(pal[1:7]):
            d.rectangle([x+j*22, 108+CW+44, x+j*22+18, 108+CW+62], fill=col[:3], outline=LINE)
    im.convert("RGB").save(os.path.join(OUT, "palettes.png"))


if __name__ == "__main__":
    fr = build_all()
    contact_sheet(fr); walk_gif(fr); layer_demo(fr); palette_demo(fr)
    print("preview.png · walk.gif · layers.png · palettes.png")
