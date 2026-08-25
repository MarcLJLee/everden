#!/usr/bin/env python3
"""플레이어 검수 시트 · 레이어 분해 · 조합 데모 · Godot 내보내기."""
import os, json
from PIL import Image, ImageDraw, ImageFont
import build_player as P
import build as A
import build_bg as G

OUT = P.OUT
def font(sz):
    try: return ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", sz)
    except Exception: return ImageFont.load_default()
F_H, F_L, F_S = font(30), font(21), font(17)
BG, INK, DIM, ACC = (26,31,38), (238,232,222), (150,158,168), (233,164,65)

def checker(w, h, s=7):
    im = Image.new("RGBA", (w,h), (36,42,50,255)); d = ImageDraw.Draw(im)
    for y in range(0,h,s):
        for x in range(0,w,s):
            if (x//s + y//s) % 2: d.rectangle([x,y,x+s-1,y+s-1], fill=(44,51,60,255))
    return im


def sheet():
    Z = 6
    pal = P.PALETTES["default"]
    rows = [("이동 4방향 (E/W는 미러)",
             [("남 ↓","move_south_0"),("","move_south_1"),
              ("북 ↑","move_north_0"),("","move_north_1"),
              ("동 →","move_side_0"),("","move_side_1")]),
            ("대기 / 교감 모션",
             [("대기","idle_0"),("","idle_1"),
              ("교감 — 쪼그려 손 내밀기","special_0"),("","special_1")])]
    CW, CH, PAD, GAP = P.W*Z, P.H*Z, 34, 12
    H = 96 + sum(64 + CH + 54 for _ in rows)
    W = PAD*2 + 6*(CW+GAP)
    im = Image.new("RGBA",(W,H),BG+(255,)); d = ImageDraw.Draw(im)
    d.text((PAD,26),"플레이어 — 여자아이 32×48",font=F_H,fill=INK)
    y = 96
    for title, items in rows:
        d.text((PAD,y),title,font=F_L,fill=ACC); y += 34
        d.line([PAD,y,W-PAD,y],fill=(52,60,70),width=2); y += 16
        for i,(lab,key) in enumerate(items):
            x = PAD + i*(CW+GAP)
            im.paste(checker(CW,CH),(x,y))
            im.alpha_composite(P.compose(key,pal).resize((CW,CH),Image.NEAREST),(x,y))
            if lab: d.text((x,y+CH+8),lab,font=F_S,fill=DIM)
        y += CH + 54
    im.convert("RGB").save(os.path.join(OUT,"player.png"))


def layers():
    Z = 9
    pal = P.PALETTES["default"]
    steps = [("몸통",("",),"피부·팔·다리·신발. 프레임을 전담한다"),
             ("+하의",("bottom",),"방향당 1장"),
             ("+상의",("bottom","top"),"방향당 1장"),
             ("+가방",("bottom","top","gear"),"등에 멘다"),
             ("+머리",("bottom","top","gear","hair"),"얼굴 자리가 뚫려 있다"),
             ("+눈",("bottom","top","gear","hair","eye"),"1px 폭. 북향에선 숨긴다")]
    CW, CH, PAD, GAP = P.W*Z, P.H*Z, 34, 20
    W = PAD*2 + len(steps)*(CW+GAP)
    H = 180 + CH
    im = Image.new("RGBA",(W,H),BG+(255,)); d = ImageDraw.Draw(im)
    d.text((PAD,26),"플레이어 레이어 — 몸통만 프레임을 따라간다",font=F_H,fill=INK)
    d.text((PAD,68),"옷·머리·가방은 방향당 한 장이면 된다. 그래서 새 의상 한 벌이 8장이다.",font=F_S,fill=DIM)
    for i,(lab,parts,note) in enumerate(steps):
        x = PAD + i*(CW+GAP)
        im.paste(checker(CW,CH),(x,108))
        im.alpha_composite(P.compose("move_south_0",pal,parts=parts).resize((CW,CH),Image.NEAREST),(x,108))
        d.text((x,108+CH+10),lab,font=F_L,fill=ACC)
        d.text((x,108+CH+38),note,font=F_S,fill=DIM)
    im.convert("RGB").save(os.path.join(OUT,"player_layers.png"))


def outfits():
    Z = 7
    sets = [("기본","default"),("민트","mint"),("베리","berry")]
    views = ["move_south_0","move_side_0","move_north_0"]
    CW, CH, PAD, GAP = P.W*Z, P.H*Z, 34, 14
    W = PAD*2 + len(views)*len(sets)*(CW+GAP)
    H = 168 + CH
    im = Image.new("RGBA",(W,H),BG+(255,)); d = ImageDraw.Draw(im)
    d.text((PAD,26),"팔레트 교체 — 그림은 한 벌이다 (§4.3)",font=F_H,fill=INK)
    d.text((PAD,68),"머리·상의·하의가 각각 다른 인덱스라 팔레트만 바꿔도 다른 아이가 된다.",font=F_S,fill=DIM)
    x = PAD
    for lab, pname in sets:
        for v in views:
            im.paste(checker(CW,CH),(x,106))
            im.alpha_composite(P.compose(v,P.PALETTES[pname]).resize((CW,CH),Image.NEAREST),(x,106))
            x += CW + GAP
        d.text((x-3*(CW+GAP), 106+CH+10), lab, font=F_L, fill=ACC)
        x += 18
    im.convert("RGB").save(os.path.join(OUT,"player_outfits.png"))


def with_animals():
    """동물 옆에 세워 크기를 확인한다"""
    Z = 7
    pal = G.PALETTES["day"]
    items = [("플레이어 32×48", P.compose("move_side_0", P.PALETTES["default"])),
             ("개 32×32", A.dog_side(0,"walk").to_image(A.PALETTES["dog_default"])),
             ("청설모 24×24", A.squirrel_side(0,"walk").to_image(A.PALETTES["squirrel_default"])),
             ("나무 32×48", G.OBJECTS["tree"].img(pal))]
    CW, CH, PAD, GAP = 32*Z, 48*Z, 34, 22
    W = PAD*2 + len(items)*(CW+GAP)
    H = 150 + CH + 40
    im = Image.new("RGBA",(W,H),(38,52,40,255)); d = ImageDraw.Draw(im)
    d.text((PAD,26),"크기 비교 — 타일 16px 기준",font=F_H,fill=INK)
    d.text((PAD,68),"플레이어는 3타일 높이, 개는 2타일, 청설모는 1.5타일.",font=F_S,fill=DIM)
    base = 108 + CH
    for i,(lab,img) in enumerate(items):
        x = PAD + i*(CW+GAP)
        big = img.resize((img.width*Z, img.height*Z), Image.NEAREST)
        for t in range(0, CH+1, 16*Z):
            d.line([x, base-t, x+CW, base-t], fill=(52,72,54), width=1)
        im.alpha_composite(big,(x + (CW-big.width)//2, base-big.height))
        d.text((x,base+12),lab,font=F_S,fill=DIM)
    im.convert("RGB").save(os.path.join(OUT,"player_scale.png"))


def export():
    """Godot 규약: 합성 스트립(바로 쓸 수 있게) + 레이어 원본(나중에 물릴 수 있게)"""
    root = os.path.join(OUT, "extracted", "player")
    os.makedirs(root, exist_ok=True)
    pal = P.PALETTES["default"]
    anims = {"idle": ["idle_0","idle_1"],
             "move_side": ["move_side_0","move_side_1"],
             "move_north": ["move_north_0","move_north_1"],
             "move_south": ["move_south_0","move_south_1"],
             "special": ["special_0","special_1"]}
    for anim, keys in anims.items():
        strip = Image.new("RGBA",(P.W*len(keys), P.H),(0,0,0,0))
        for i,k in enumerate(keys):
            # 합성본에는 눈을 넣지 않는다 — 눈은 엔진이 표정에 따라 얹는다
            strip.alpha_composite(P.compose(k,pal,parts=("hair","top","bottom","gear")),(i*P.W,0))
        strip.save(os.path.join(root, anim + ".png"))
    for expr in ("기본","기쁨","놀람"):
        for ang in ("front","side"):
            P.eye(expr,ang).img(P.EYE_PAL).save(os.path.join(root, f"eye_{ang}_{expr}.png"))
    ld = os.path.join(root,"layers"); os.makedirs(ld, exist_ok=True)
    for name, items in (("body",P.BODY),("hair",P.HAIR),("top",P.TOP),
                        ("bottom",P.BOTTOM),("gear",P.GEAR)):
        for key, c in items.items():
            c.img(pal).save(os.path.join(ld, f"{name}_{key}.png"))
    meta = {"canvas":[P.W,P.H], "anchors":P.ANCHORS, "layer_order":P.ORDER,
            "dir_of":P.DIR_OF,
            "palettes":{k:[list(x) for x in v] for k,v in P.PALETTES.items()},
            "palette_index":["투명","외곽선","피부","피부그늘","머리어둠","머리중간","머리밝음",
                             "상의어둠","상의밝음","하의어둠","하의밝음","소품"],
            "note":"<anim>.png 는 기본 의상 합성본(눈 없음). layers/ 는 레이어 원본."}
    with open(os.path.join(root,"player.json"),"w") as f:
        json.dump(meta,f,ensure_ascii=False,indent=2)
    print("extracted/player/ 내보냄")


if __name__ == "__main__":
    sheet(); layers(); outfits(); with_animals(); export()
    print("player.png · player_layers.png · player_outfits.png · player_scale.png")
