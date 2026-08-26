# 폰트

**갈무리 (Galmuri) v2.40.4** — SIL Open Font License 1.1.
저작자 Lee Minseo (quiple). 라이선스 전문은 `LICENSE-Galmuri.txt` 에 있고,
**배포물에 함께 넣어야 한다.** exe 로 굽든 pck 로 굽든 마찬가지다.

| 파일 | 쓰는 곳 |
|---|---|
| `Galmuri11.ttf` | 기본. 확인 창·대사·라벨 전부 |
| `Galmuri11-Bold.ttf` | 강조 |
| `Galmuri9.ttf` | 아주 작은 라벨이 필요해질 때 |
| `Galmuri14.ttf` | 큰 글씨가 필요해질 때 |

원본 zip 에는 Mono·Condensed·woff2·bdf·Bitmap 변형이 더 있다. 필요해지면
`_to_delete/` 의 `Galmuri-v2.40.4.zip` 에서 꺼내 쓰면 된다.
**woff2 와 bdf 는 Godot 이 못 읽는다** — ttf 만 가져왔다.

## 반드시 지킬 것 — 11px 로 찍고 정수배로만 키운다

갈무리11 은 **11px 격자에서 그린 폰트**다. 22px 로 바로 찍으면 힌팅이 개입해
획 두께가 자리마다 달라진다 — 도트 폰트를 쓰는 이유가 사라진다.
크게 쓰려면 11 로 찍어서 ×2, ×3 으로 키운다.

`sprites/build_title.py` 의 `ktext()` 가 이 규칙대로 되어 있다
(PIL 은 `ImageDraw.fontmode = "1"` 로 안티에일리어싱을 끈다).

## Godot 임포트 설정 (구현 세션 확인 필요)

에디터에서 폰트를 고르고 **Import** 탭에서 아래를 끈 뒤 Reimport 해야 한다.
하나라도 켜져 있으면 640×360 을 정수배로 늘렸을 때 글자만 흐려진다.

- Antialiasing → **Disabled**
- Hinting → **None**
- Subpixel Positioning → **Disabled**
- Generate Mipmaps → **끔**
- Multichannel Signed Distance Field → **끔**

폰트 크기는 **11 또는 22·33** 만 쓴다. 13, 16 같은 값은 쓰지 않는다.
