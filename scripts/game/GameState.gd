## 한 판의 상태 — **무엇을 데리고 있고, 어디를 가봤고, 지금 누구와 나가는가.**
##
## ★ 이게 없어서 집이 "그림이 있는 모든 종" 을 매번 새로 뿌리고 있었다.
##   아트가 들어올 때마다 집 식구가 늘어난 것이 그 증상이다 (사용자 지적).
##   집에 있는 것은 **모아온 아이들**이지 데이터에 있는 종이 아니다.
##
## ★ 개체는 종이 아니다. 같은 청설모라도 성별이 다르고 이름이 다르다 —
##   그래서 `uid` 로 센다. 종 id 는 **문자열로 저장한다** (BRIEF §6.5 세이브 안전장치):
##   나중에 콘텐츠 팩이 바뀌어도 저장이 깨지지 않는다.
##
## ⚠️ 원칙 1 — 동물은 죽지 않는다. 여기에는 **빼는 길이 없다.**
class_name GameState
extends Node

const SAVE_PATH := "user://everden.json"
const VERSION := 1
## 원정에 데려갈 수 있는 동료 수. 브리프는 "3마리 내외"(§3.2)고 지금은 둘로 시작한다.
const PARTY_MAX := 2
## 원정에서 돌아올 때 짝이 될 확률. **행운이어야 하므로 낮게** 잡는다 (사용자 지적) —
## 두세 번 만에 되면 그건 절차지 행운이 아니다.
##
## 재보고 고른 값이다. 귀가할 때마다 **되풀이해서 굴리므로** 낮아도 막히지 않는다:
##   0.35 → 평균 2.9번 (두 번 안에 58%)   ← 너무 흔하다
##   0.15 → 평균 6.4번
##   0.10 → 평균 9.6번 (두 번 안에 20%)   ← 이것
## 문이 닫히지 않는 한(원칙 2) 낮은 값이 오히려 그 순간을 사건으로 만든다.
##
## ⚠️ **되돌릴 수 없는 실패를 만들지 않는다**(원칙 2). 안 된 날은 "아직" 일 뿐이고
##    다음 귀가에 다시 굴린다 — 문이 닫히지 않으므로 기다림이 벌이 되지 않는다.
## ⚠️ **숫자를 화면에 내지 않는다**(원칙 3). 아이가 보는 것은 하트가 떴다는 사건뿐이다.
## ★ 브리프 §2.4 는 이 대목을 "확률로 풀지 않는다" 로 적어두었다.
##   플레이어가 확률 쪽을 골랐으므로 그렇게 두고, 설계 세션에 그 절을 넘겼다.
const PAIR_CHANCE := 0.10
## 재보기용 덮어쓰기. 0 이하면 위 상수를 쓴다.
var PAIR_CHANCE_OVERRIDE := 0.0

## 모아온 개체들. [{uid, species_id, sex}]
var collection: Array = []
## 한 번이라도 만난 종. 도감과 지도의 "만난 적 있는 아이" 가 여기서 나온다.
var seen: Array = []
## 지금 고른 목적지
var region_id := "home_hills"
## 이번 원정에 데려갈 개체들 (uid)
var party: Array = []
## 첫 만남을 지났는가. 새 판은 **아무도 없이** 시작하고 강아지 하나를 초대하며 시작한다.
var tutorial_done := false
## 짝이 된 종들. 암수를 다 데려왔다고 바로 되는 게 아니다 (사용자 지적) —
## 원정에서 돌아올 때마다 한 번씩 굴린다.
var paired: Array = []
## 이번 귀가에 새로 짝이 된 종들. 집이 한 번 보여주고 비운다.
var rolled_pairs: Array = []

## 회귀가 진짜 저장 파일을 건드리면 안 된다 — 사람이 모아온 아이들이 거기 있다.
var autosave := true

## 마지막으로 쓴 입력 장치 — "key" 또는 "pad". (BRIEF §2.10)
## ★ 설정 항목을 만들지 않는다. **패드를 집어 드는 것 자체가 이미 선택이다.**
##   바뀌는 것은 키캡 **그림 하나뿐**이라 문장도 배치도 안 흔들린다.
var last_device := "key"

var _next_uid := 1
## 불러오면서 낡은 자료를 고쳤는가. 고쳤으면 파일도 다시 쓴다.
var _repaired := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# 오토로드라 화면이 바뀌어도 계속 듣는다
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not load_game():
		start_new()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		last_device = "pad"
	elif event is InputEventKey or event is InputEventMouseButton:
		last_device = "key"


## 첫 판 — **아무도 없다.**
##
## ★ 처음부터 개와 고양이를 들려주면 "친구가 생긴다" 는 이 게임의 첫 사건이 사라진다.
##   첫 강아지는 **초대해서 얻는 것**이고, 그게 곧 초대 규칙을 배우는 자리다.
##   그 아이가 자라서 같이 여행을 다니고, 코로 다른 동물을 찾아준다 (§3.3).
func start_new() -> void:
	collection.clear()
	seen.clear()
	party.clear()
	_next_uid = 1
	tutorial_done = false
	paired.clear()
	region_id = "home_hills"
	save_game()


## 첫 만남이 끝났다 — 강아지가 식구가 되고, 그대로 첫 동료가 된다.
func finish_tutorial() -> Dictionary:
	var puppy := add("dog", Actor.roll_sex(_rng))
	party = [int(puppy["uid"])]
	tutorial_done = true
	save_game()
	return puppy


## 새 식구. 종 id 는 문자열로 남긴다.
## ⚠️ **여기서 바로 저장한다.** 동료를 영입하는 순간마다 남아야 한다 (사용자 지적) —
##    원정 중에 창을 닫아도 만난 아이가 사라지면 그건 되돌릴 수 없는 손실이다 (원칙 2).
func add(species_id: String, sex := "") -> Dictionary:
	var one := {
		"uid": _next_uid,
		"species_id": species_id,
		"sex": sex if not sex.is_empty() else Actor.roll_sex(_rng),
	}
	_next_uid += 1
	collection.append(one)
	note_seen(species_id)
	save_game()
	return one


## 이 종이 짝을 이뤘는가.
func is_paired(species_id: String) -> bool:
	return species_id in paired


## 원정에서 돌아왔다. 암수가 다 있는 종마다 한 번씩 굴린다.
## 새로 짝이 된 종 이름들을 돌려준다 — 화면이 그 사건을 보여줘야 하기 때문이다.
func roll_pairs() -> Array:
	# ⚠️ **종마다 한 번**이다. 개체를 돌면 암수 두 마리가 각각 굴려서 확률이 두 배가 된다
	#    — 재보니 0.35 가 0.58 로 뛰었다.
	var kinds: Array = []
	for one in collection:
		var id := String(one["species_id"])
		if not (id in kinds):
			kinds.append(id)
	var made: Array = []
	for id in kinds:
		if id in paired:
			continue
		if sexes_of(id).size() < 2:
			continue
		if _rng.randf() < (PAIR_CHANCE_OVERRIDE if PAIR_CHANCE_OVERRIDE > 0.0 else PAIR_CHANCE):
			made.append(id)
	for id in made:
		paired.append(id)
	if not made.is_empty():
		save_game()
	return made


func note_seen(species_id: String) -> void:
	if species_id in seen:
		return
	seen.append(species_id)


## 이 아이가 지금 같이 가는가. uid 는 언제나 정수로 견준다.
func going(uid: int) -> bool:
	return int(uid) in party


## 데려가거나 두고 간다. 꽉 찼으면 가장 먼저 고른 아이가 나간다 —
## 막고 끝내면 왜 안 되는지가 안 보인다.
func toggle_party(uid: int) -> void:
	var id := int(uid)
	if going(id):
		party.erase(id)
	elif party.size() < PARTY_MAX:
		party.append(id)
	else:
		party.pop_front()
		party.append(id)
	save_game()


func of_uid(uid: int) -> Dictionary:
	for one in collection:
		if int(one["uid"]) == int(uid):
			return one
	return {}


## 지금 데려가는 개체들. 저장에 없는 uid 는 조용히 버린다 —
## 팩이 빠졌거나 저장이 낡았을 때 여기서 멈추면 안 된다.
func party_members() -> Array:
	var out: Array = []
	for uid in party:
		var one := of_uid(int(uid))
		if not one.is_empty():
			out.append(one)
	return out


## 그 종을 몇 마리 데리고 있는가 — 짝이 있는지 보는 데 쓴다.
func sexes_of(species_id: String) -> Dictionary:
	var kinds := {}
	for one in collection:
		if String(one["species_id"]) == species_id:
			kinds[String(one["sex"])] = int(kinds.get(String(one["sex"]), 0)) + 1
	return kinds


## 짝 없이 혼자인 종 → 필드에 반드시 있어야 하는 성별. (BRIEF §2.4 확정 배치)
## 성별 때문에 생기는 영구 벽을 구조적으로 막는 장치다.
func lonely_species() -> Dictionary:
	var needed := {}
	for one in collection:
		var id := String(one["species_id"])
		if needed.has(id):
			continue
		var kinds := sexes_of(id)
		if kinds.size() >= 2:
			continue
		needed[id] = "female" if kinds.has("male") else "male"
	return needed


func save_game() -> void:
	if not autosave:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("저장하지 못했습니다: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"version": VERSION, "next_uid": _next_uid, "collection": collection,
		"seen": seen, "region_id": region_id, "party": party,
		"tutorial_done": tutorial_done, "paired": paired,
	}, "  "))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != VERSION:
		return false
	collection = parsed.get("collection", [])
	seen = parsed.get("seen", [])
	region_id = String(parsed.get("region_id", "home_hills"))
	# ⚠️ JSON 에서 온 숫자는 **실수**다. uid 를 그대로 두면 불러온 1.0 과 새로 고른 1 이
	#    서로 다른 것으로 보여서, 같은 아이가 동료에 두 번 들어간다 (실제로 그랬다).
	# 겹친 것도 여기서 걷어낸다 — 이미 저장된 판이 있으므로 고치는 김에 고쳐 준다.
	# 같은 아이가 둘이면 필드에 **개가 두 마리** 나온다 (사용자 지적).
	var raw_party: Array = parsed.get("party", [])
	party = []
	for uid in raw_party:
		if not (int(uid) in party):
			party.append(int(uid))
	while party.size() > PARTY_MAX:
		party.pop_back()
	# ⚠️ 고쳤으면 **파일도 고쳐 준다.** 메모리만 고치면 저장을 부르는 일이 없는 판에서는
	#    파일이 계속 낡은 채로 남는다 — 다음에 열 때마다 같은 것을 또 고치게 된다.
	if party.size() != raw_party.size():
		_repaired = true
	for one in collection:
		one["uid"] = int(one["uid"])
	_next_uid = int(parsed.get("next_uid", collection.size() + 1))
	tutorial_done = bool(parsed.get("tutorial_done", false))
	paired = parsed.get("paired", [])
	if _repaired:
		_repaired = false
		save_game()
	return true
