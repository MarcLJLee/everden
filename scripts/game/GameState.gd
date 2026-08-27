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

## 회귀가 진짜 저장 파일을 건드리면 안 된다 — 사람이 모아온 아이들이 거기 있다.
var autosave := true

var _next_uid := 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if not load_game():
		start_new()


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


func note_seen(species_id: String) -> void:
	if species_id in seen:
		return
	seen.append(species_id)


func of_uid(uid: int) -> Dictionary:
	for one in collection:
		if int(one["uid"]) == uid:
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
		"tutorial_done": tutorial_done,
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
	party = parsed.get("party", [])
	_next_uid = int(parsed.get("next_uid", collection.size() + 1))
	tutorial_done = bool(parsed.get("tutorial_done", false))
	return true
