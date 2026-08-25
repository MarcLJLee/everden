## 필드 튜닝 상수. 코드에 박지 않는다 — 실행 중 리모트 인스펙터로 만진다. (DEMO-SPEC §3.6)
class_name FieldTuning
extends Resource

@export_group("맵")
## 1타일 = 몇 픽셀인가. 몸통 캔버스가 24/32/48px 이므로 16px 이 기준이다.
@export var tile_size: int = 16
## 감지 반경을 넓히면 맵도 같이 커져야 한다. 안 그러면 서 있기만 해도 다 잡힌다.
@export var map_size := Vector2i(64, 48)

@export_subgroup("지형 덩어리 개수")
@export var forest_patches: int = 10
@export var water_patches: int = 4
@export var rock_patches: int = 4
## 타일 하나에 프롭이 놓일 확률. 0.06 이면 64×48 맵에 180개 남짓이다.
@export_range(0.0, 0.4, 0.005) var prop_density: float = 0.06

@export_group("개체 수")
## 대상 종 하나당 몇 마리를 뿌릴 것인가. 대상이 4종이므로 1이면 필드에 4마리다.
## DEMO-SPEC 의 제안값 3은 "필드 전체에 3마리"(§6.4 의 100타일 역산)를 전제한 숫자라,
## 종당으로 읽으면 12마리가 되어 첫 유도가 즉시 떠버린다. 측정해서 맞출 것.
@export var animal_count: int = 1
## 이 데모에서 데리고 나가는 동료. 종 분기를 코드가 아니라 여기에 둔다.
@export var companion_ids: Array[String] = ["dog", "cat"]
## 시작할 때 켜져 있는 동료. "개만 데려가면 못 찾는 애가 있다"가 첫 장면이어야 한다.
@export var companions_active_at_start: Array[String] = ["dog"]

@export_group("이동 (타일/초)")
@export var move_speed: float = 3.5
@export var wild_speed: float = 1.2
## 동료가 뒤처지지 않도록 하는 여유분
@export var companion_speed_scale: float = 1.25
## 동료가 플레이어 뒤로 유지하려는 거리 (타일)
@export var follow_distance: float = 1.4

@export_group("반경 (타일)")
## 감각 없이 그냥 눈으로 확인되는 거리. 이것보다 멀면 몸이 안 보인다 — 그래야
## 동료의 감각이 의미를 갖는다. (BRIEF §3.3)
@export var reveal_radius: float = 3.0

## 감각 반경의 기준값. 여기에 감각별 배율(tags.json)과 개체값이 곱해진다.
@export var guide_radius: float = 10.0
## 풀 AI 승격 거리. 가장 멀리 닿는 감각보다 좁으면 코가 헛돌기 때문에,
## Field 가 실제 감각 반경을 계산해 이 값이 모자라면 올려 쓰고 경고를 남긴다.
@export var activation_radius: float = 26.0
@export var interact_radius: float = 1.5

@export_group("교감 게이지")
@export var base_gauge_time: float = 3.0
## 상성이 어긋날 때 곱하는 계수 (먹이 유형 / 활동 시간 각각)
@export var mismatch_factor: float = 1.5

@export_group("연출")
## 카메라 배율. 7살이 볼 화면이라 크게 본다. (BRIEF §6.2 — 0.7~1.5배 제한은 런타임 줌 이야기)
@export var camera_zoom: float = 2.0
## 시간대 이름 → palettes.json 의 배경 팔레트 이름
@export var daypart_palette: Dictionary = {"낮": "day", "여명": "dusk", "밤": "night"}
## 시간대를 바꿨을 때 색이 넘어가는 시간(초). 0 이면 툭 튄다.
@export var daypart_fade: float = 1.2
## 어두울 때 눈이 되비추는 색. 빛을 내는 게 아니라 반사라서 노란빛이 돈다.
@export var eyeshine_color: Color = Color(0.98, 0.96, 0.55)
## 걷기 바운스 높이. 노드 Y로 처리하고 정수 픽셀로 스냅한다. (DEMO-SPEC §3.2)
@export var bounce_height_px: int = 1
## 걷기 2프레임의 교대 속도
@export var walk_cycle_hz: float = 6.0
