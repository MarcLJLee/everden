#!/usr/bin/env python3
"""
Godot 프로젝트가 읽는 형식으로 내보낸다.

경로·이름은 `scripts/art/SpriteLibrary.gd` 의 규약을 그대로 따른다:
  sprites/extracted/<종 id>/<애니메이션>.png   가로 스트립, 프레임 폭 = 캔버스 폭
  sprites/extracted/shared/eye_<각도>_<표정>.png
배경은 TerrainMap 의 지형 이름을 파일명으로 쓴다 (초원·숲·물가·바위).
"""
import os, json
from PIL import Image
import build as A
import build_bg as G
import build_logo as L
import build_title as TI
import build_home as HM

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extracted")

def strip(frames, pal, canvas_w):
    """가로로 이어붙인 스트립. 프레임 폭 = 캔버스 폭."""
    ims = [c.to_image(pal) if hasattr(c, "to_image") else c.img(pal) for c in frames]
    h = max(i.height for i in ims)
    out = Image.new("RGBA", (canvas_w*len(ims), h), (0,0,0,0))
    for i, im in enumerate(ims):
        out.alpha_composite(im, (i*canvas_w + (canvas_w-im.width)//2, h-im.height))
    return out

def w(path, im):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)


# 이 스크립트가 소유한 폴더만 비운다.
# ★ 예전에 `shutil.rmtree(OUT)` 였다. 그러면 이 스크립트가 만들지 않는 것 —
#   구현 세션이 내보낸 `extracted/player/` 37장 — 이 통째로 사라진다.
#   생성기는 자기가 쓰는 자리만 지운다.
OWNED = ("dog", "cat", "squirrel", "shared", "terrain", "props", "clues",
         "food", "ui", "home")

def clear_owned():
    """소유 폴더의 png·json 만 지운다.
    ★ `.import` · `.uid` 는 건드리지 않는다 — 지우면 Godot 이 UID 를 새로 발급해서
      `.tscn` 의 참조가 끊긴다. 파일을 덮어쓰는 것만으로 재임포트는 일어난다."""
    for name in OWNED:
        for root, _, files in os.walk(os.path.join(OUT, name)):
            for f in files:
                if not f.endswith((".png", ".json")): continue
                try: os.remove(os.path.join(root, f))
                except PermissionError: pass   # 삭제 못 하는 마운트 — 어차피 덮어쓴다
    j = os.path.join(OUT, "palettes.json")
    if os.path.isfile(j):
        try: os.remove(j)
        except PermissionError: pass


def main():
    clear_owned()

    # ── 몸통 스트립 ───────────────────────────────────────────────────
    dog_pal, sq_pal = A.PALETTES["dog_default"], A.PALETTES["squirrel_default"]
    cat_pal = A.PALETTES["cat_default"]
    dog = {
        "idle":        [A.dog_side(0, "idle"), A.dog_side(1, "idle")],
        "move_side":   [A.dog_side(0, "walk"), A.dog_side(1, "walk")],
        "move_north":  [A.dog_north(0), A.dog_north(1)],
        "move_south":  [A.dog_south(0), A.dog_south(1)],
        "special":     [A.dog_special(0), A.dog_special(1)],
    }
    for anim, fr in dog.items():
        w(f"{OUT}/dog/{anim}.png", strip(fr, dog_pal, 32))

    cat = {
        "idle":        [A.cat_side(0, "idle"), A.cat_side(1, "idle")],
        "move_side":   [A.cat_side(0, "walk"), A.cat_side(1, "walk")],
        "move_north":  [A.cat_north(0), A.cat_north(1)],
        "move_south":  [A.cat_south(0), A.cat_south(1)],
        "special":     [A.cat_special(0), A.cat_special(1)],
    }
    for anim, fr in cat.items():
        w(f"{OUT}/cat/{anim}.png", strip(fr, cat_pal, 32))

    sq = {
        "idle":       [A.squirrel_side(0, "idle"), A.squirrel_side(1, "idle")],
        "move_side":  [A.squirrel_side(0, "walk"), A.squirrel_side(1, "walk")],
        "move_south": [A.squirrel_south(0), A.squirrel_south(1)],
    }
    for anim, fr in sq.items():
        w(f"{OUT}/squirrel/{anim}.png", strip(fr, sq_pal, 24))

    # ── 눈 — 공용이 원칙이므로 shared/ 에 둔다 (§4.6) ─────────────────
    # ★ 눈 색(인덱스 7·8)은 종 팔레트에 있다. 엔진에서 눈 레이어도 몸통과 같은
    #   팔레트 셰이더를 통과시켜야 검은 털에서 눈이 저절로 밝아진다 (§4.3).
    #   아래 파일은 기본 팔레트로 구운 것이라 밝은 털 종에는 그대로 쓸 수 있다.
    for expr in ("기본", "기쁨", "시무룩"):
        for angle in ("front", "side"):
            c = A.eye_sprite("round", expr, angle)
            w(f"{OUT}/shared/eye_{angle}_{expr}.png", c.to_image(dog_pal))
    # 스타일이 다른 종은 종 폴더에 (SpriteLibrary 가 종 폴더를 먼저 본다)
    for sp, style, pal in (("squirrel", "big", sq_pal), ("cat", "big", cat_pal)):
        for expr in ("기본", "기쁨", "시무룩"):
            for angle in ("front", "side"):
                c = A.eye_sprite(style, expr, angle)
                w(f"{OUT}/{sp}/eye_{angle}_{expr}.png", c.to_image(pal))

    # ── 표현 아이콘 ──────────────────────────────────────────────────
    for kind in ("발견", "잠", "애정", "냄새", "소리"):
        c = A.icon_sprite(kind)
        pal = list(A.ICON_PALETTE); pal[A.MID] = A.ICON_ACCENT[kind] + (255,)
        im = c.to_image(pal)
        w(f"{OUT}/shared/emote_{kind}.png", im)
        if kind == "냄새":
            w(f"{OUT}/shared/emote_icon.png", im)   # 현재 emote_texture() 호환

    # ── 지형 타일 — 파일명이 TerrainMap 의 지형 이름 ─────────────────
    day = G.PALETTES["day"]
    terrain = {
        "초원": [G.TILES[f"grass_{i}"]  for i in range(G.GRASS_N)],
        "숲":   [G.TILES[f"forest_{i}"] for i in range(G.FOREST_N)],
        "물가": [G.TILES[f"wet_{i}"]    for i in range(G.WET_N)],
        "바위": [G.TILES["rock"]],
    }
    for name, tiles in terrain.items():
        w(f"{OUT}/terrain/{name}.png", strip(tiles, day, G.T))

    # 물·물가 전이 (열린 물을 그릴 때)
    for name in ("water_0", "water_1", "dirt", "sand",
                 "shore_N","shore_S","shore_E","shore_W",
                 "shore_NE","shore_NW","shore_SE","shore_SW"):
        w(f"{OUT}/terrain/extra/{name}.png", G.TILES[name].img(day))

    # ── 프롭 · 단서 · 먹이 ───────────────────────────────────────────
    for name, c in G.OBJECTS.items(): w(f"{OUT}/props/{name}.png", c.img(day))
    for name, c in G.CLUES.items():   w(f"{OUT}/clues/{name}.png", c.img(day))
    for name, c in G.FOODS.items():   w(f"{OUT}/food/{name}.png", c.img(day))

    # ── UI — 제작사 로고 · 타이틀 · 커서 ─────────────────────────────
    L.save_all()
    TI.save_all()

    # ── 집 — 건물 · 울타리 · 사물 ─────────────────────────────────────
    HM.save_all()

    # ── 팔레트 — 밤낮은 이 값들을 보간해서 만든다 ────────────────────
    def rgba(p): return [list(G._rgba(x)) for x in p]
    meta = {
        "_comment": "밤낮 = 배경 팔레트 보간 → 오버레이 틴트 → 이펙트. 국소 광원만 Light2D.",
        "tile_size": G.T,
        "cycle": G.CYCLE,
        "background": {k: rgba(v) for k, v in G.PALETTES.items()},
        "background_index": ["투명","외곽선","풀어둠","풀중간","풀밝음",
                             "흙어둠","흙중간","흙밝음","물어둠","물중간","물밝음",
                             "나무어둠","나무중간","돌어둠","돌중간","강조"],
        "overlay_tint": {k: list(v) for k, v in G.TINTS.items()},
        "actors": {k: rgba(v) for k, v in A.PALETTES.items()},
        "actor_index": ["투명","외곽선","털어둠","털중간","털밝음","배","발·코","눈어둠","눈밝음"],
        "eye_uses_actor_palette": True,
        "eye_note": ("눈 색은 종 팔레트의 인덱스 7(눈어둠)·8(눈밝음)이다. "
                     "눈 레이어를 몸통과 같은 팔레트 셰이더에 통과시키면 "
                     "검은 털 팔레트에서 눈이 저절로 밝아진다 — 흰 테를 두르지 않는다."),
        "terrain_variants": {k: len(v) for k, v in terrain.items()},
        "prop_terrain": G.PROP_TERRAIN,
        "clue_by_trait": {k: f"clues/{k}.png" for k in
                          ("발자국","큰발자국","나무흔적","물자국","허물","털")},
        "clue_airborne": {"후각": "clues/냄새표시.png", "청각": "clues/소리표시.png"},
    }
    with open(f"{OUT}/palettes.json", "w") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=2)

    n = sum(len([f for f in files if f.endswith((".png", ".json"))])
            for _, _, files in os.walk(OUT))
    print(f"extracted/ 에 {n}개 파일 (png·json)")

if __name__ == "__main__":
    main()
