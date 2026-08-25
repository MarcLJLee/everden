## 지형 위에 프롭을 뿌린다. (HANDOFF §2-3)
##
## 어느 프롭이 어느 지형에 어울리는지는 `palettes.json` 의 `prop_terrain` 에 있다 —
## 코드가 지형 이름으로 분기하지 않는다.
##
## 앵커는 **바닥 중앙**이고 루트 노드 하나가 Y-sort 대상이다. 액터와 같은 규칙이다.
class_name PropScatter
extends RefCounted

## 타일보다 높은 것만 발밑 그림자를 받는다 (BRIEF §4.4).
## 땅에 깔린 것(자갈·진흙)에 그림자를 넣으면 오히려 떠 보인다.
const STANDING_HEIGHT := 16


## parent 아래에 프롭을 만들고, 밤낮으로 텍스처를 갈아끼울 수 있게 목록을 돌려준다.
static func scatter(parent: Node2D, terrain: TerrainMap, tuning: FieldTuning,
		rng: RandomNumberGenerator) -> Array:
	var placed: Array = []
	for y in tuning.map_size.y:
		for x in tuning.map_size.x:
			if rng.randf() >= tuning.prop_density:
				continue
			var names := SpriteLibrary.props_for_terrain(terrain.at_tile(Vector2i(x, y)))
			if names.is_empty():
				continue
			var name := String(names[rng.randi_range(0, names.size() - 1)])
			var texture := SpriteLibrary.prop_texture(name)
			if texture == null:
				continue
			placed.append(_make(parent, name, texture, Vector2(x + 0.5, y + 0.95) * tuning.tile_size))
	return placed


static func _make(parent: Node2D, name: String, texture: Texture2D, position: Vector2) -> Dictionary:
	var root := Node2D.new()
	root.position = position.round()
	parent.add_child(root)

	var size := texture.get_size()
	if size.y > STANDING_HEIGHT:
		var shadow := Sprite2D.new()
		shadow.centered = false
		# 나무 줄기가 캔버스 폭을 다 쓰지는 않는다. 밑동만큼만 잡는다.
		shadow.texture = PlaceholderArt.shadow_texture(int(size.x * 0.6))
		shadow.position = -shadow.texture.get_size() * 0.5
		root.add_child(shadow)

	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = texture
	# 바닥 중앙이 앵커 — 액터와 같다
	sprite.position = Vector2(-int(size.x / 2.0), -size.y)
	root.add_child(sprite)
	return {"name": name, "sprite": sprite}


## 팔레트가 바뀌면 텍스처만 갈아끼운다. 노드는 그대로 둔다.
static func refresh_textures(placed: Array) -> void:
	for entry in placed:
		var texture := SpriteLibrary.prop_texture(String(entry["name"]))
		if texture != null:
			entry["sprite"].texture = texture
