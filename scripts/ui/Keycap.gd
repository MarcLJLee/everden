## 키캡 — **어떻게 누르는지는 그림이 말한다.** (BRIEF §2.10 · §6.9)
##
## ★ 문장에 `[스페이스]` 를 넣지 않는다. 넣으면 장치마다 문장을 다시 써야 한다 —
##   패드를 들었을 때 바뀌는 것이 **그림 하나뿐**이어야 값을 한다.
##   문장은 **무엇을 하는지**만 말하고, 어떻게 누르는지는 그림이 말한다.
##
## ★ 마지막으로 쓴 입력 장치를 따라 갈아 끼운다. 설정 항목을 만들지 않는다 —
##   패드를 집어 드는 것 자체가 이미 선택이다.
##
## ⚠️ 엑스박스 배치 기준이다. 닌텐도 패드는 A/B 자리가 반대라 글리프를 갈아야 한다.
## ⚠️ 7살에게는 A·B 글자보다 **색과 자리**가 먼저 읽힌다 — 그건 도트가 맡는다.
class_name Keycap
extends RefCounted

const SPEC := "res://sprites/extracted/ui/screens.json"

static var _map := {}


## action 은 screens.json 의 glyphs.map 키다 — 이동 · 고르기 · 인사·정하기 · 그만두기 · 메뉴
static func texture_for(action: String) -> Texture2D:
	if _map.is_empty():
		_load()
	var pair: Dictionary = _map.get(action, {})
	if pair.is_empty():
		return null
	var relative := String(pair.get(_device(), pair.get("key", "")))
	if relative.is_empty():
		return null
	return SpriteLibrary.ui_texture(relative.get_file().get_basename())


## 키캡 한 장을 노드로 얹는다. ⚠️ Control 의 `_draw` 로 그리면 네모가 된다 (RUN.md).
static func place(parent: Node, action: String, at: Vector2) -> Sprite2D:
	var texture := texture_for(action)
	if texture == null:
		return null
	var node := Sprite2D.new()
	node.texture = texture
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.centered = false
	node.position = at.floor()
	parent.add_child(node)
	return node


## ⚠️ 오토로드를 **이름으로 바로 쓰지 않는다.** `class_name` 스크립트는 오토로드가
##    등록되기 전에 컴파일될 수 있어서 "Identifier not found: Game" 이 난다.
##    트리에서 찾아 쓰면 그 순서에 안 걸린다.
static func _device() -> String:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var game := (loop as SceneTree).root.get_node_or_null("Game")
		if game != null:
			return String(game.last_device)
	return "key"


static func _load() -> void:
	if not FileAccess.file_exists(SPEC):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	if parsed is Dictionary:
		_map = (parsed.get("glyphs", {}) as Dictionary).get("map", {})
