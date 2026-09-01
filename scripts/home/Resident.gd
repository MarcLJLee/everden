## 집에 사는 동물 하나. (BRIEF §2.7)
##
## ★ **사물이 새 동작을 요구하지 않는다.** 종 × 사물로 놀이 동작을 만들면
##   7종 × 7사물 = 49벌이 된다. 사물은 **자리와 태그만 제공하고 동작은 동물이 들고 온다** —
##   공 옆에서는 개가 꼬리를 흔들고, 긁는기둥 옆에서는 고양이가 몸을 턴다.
##   그래서 여기서 재생하는 것은 그 동물의 기존 특징 동작뿐이다.
class_name Resident
extends RefCounted

## 사물 옆에 머무는 시간. 아이가 "쟤가 공 갖고 논다"를 알아볼 만큼은 길어야 한다.
const PLAY_MIN := 3.0
const PLAY_MAX := 7.0
const WANDER_MIN := 1.5
const WANDER_MAX := 4.0

## 이 아이의 개체 번호. **짝은 종이 아니라 개체에 붙는다** — 하트를 누구 머리 위에
## 띄울지가 여기서 갈린다.
var uid := -1
var actor: Actor = null
var tags: Array = []          ## 이 동물이 가진 태그 전부 (temperament · diet · behavior_tags)
var target = null             ## 지금 향하는 사물 (Dictionary) 또는 null
var _timer := 0.0
var _playing := false
var _goal := Vector2.ZERO


static func tags_of(species: Dictionary) -> Array:
	var out: Array = [species.get("temperament", ""), species.get("diet", "")]
	for stage in species.get("growth", []):
		for tag in stage.get("behavior_tags", []):
			out.append(String(tag))
	return out


## 이 동물이 이 사물을 쓰는가. for_tags 가 비어 있으면 누구나 쓴다.
func uses(object_tags: Array) -> bool:
	if object_tags.is_empty():
		return true
	for tag in object_tags:
		if String(tag) in tags:
			return true
	return false


func update(delta: float, objects: Array, yard: Rect2, rng: RandomNumberGenerator) -> void:
	_timer -= delta
	if _playing:
		# 사물 옆에서 자기 특징 동작을 재생한다. 사물은 동작을 갖고 있지 않다.
		actor.move_vector = Vector2.ZERO
		actor.play_special = true
		if _timer <= 0.0:
			_playing = false
			actor.play_special = false
			_choose(objects, yard, rng)
		return

	var to_goal := _goal - actor.position
	if to_goal.length() <= 6.0:
		if target != null:
			_playing = true
			_timer = rng.randf_range(PLAY_MIN, PLAY_MAX)
			actor.look_direction = (target["position"] as Vector2) - actor.position
		else:
			_choose(objects, yard, rng)
		return
	actor.move_vector = to_goal.normalized()
	if _timer <= 0.0:
		_choose(objects, yard, rng)


## 반은 사물로, 반은 아무 데나. 늘 사물만 찾아가면 마당이 기계처럼 보인다.
func _choose(objects: Array, yard: Rect2, rng: RandomNumberGenerator) -> void:
	actor.play_special = false
	actor.look_direction = Vector2.ZERO
	var mine: Array = []
	for entry in objects:
		if uses(entry["for_tags"]):
			mine.append(entry)
	if not mine.is_empty() and rng.randf() < 0.65:
		target = mine[rng.randi_range(0, mine.size() - 1)]
		# 사물 옆에 선다 — 위에 겹쳐 서면 사물이 가려진다
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		_goal = (target["position"] as Vector2) + Vector2(side * 16.0, 2.0)
		_timer = rng.randf_range(6.0, 12.0)
	else:
		target = null
		_goal = Vector2(rng.randf_range(yard.position.x + 16, yard.end.x - 16),
			rng.randf_range(yard.position.y + 8, yard.end.y - 8))
		_timer = rng.randf_range(WANDER_MIN, WANDER_MAX)
	_goal = _goal.clamp(yard.position + Vector2(12, 6), yard.end - Vector2(12, 6))
