## 얼굴 — 화면에서 **이름 대신 쓰는 그림**. (BRIEF §6.9 · ui/screens.json)
##
## ★ 인계 규약이 `art` 로 표시한 자리에 라벨이 들어가 있으면 **구현 실수가 아니라
##   인계 실패**다. "만난 적 있는 아이: 청설모 · 너구리" 처럼 이름을 나열하지 않는다 —
##   7살은 이름을 읽는 것보다 **얼굴을 알아보는 게 빠르다.**
##
## ★ 새로 그리는 도트 0장. 이미 있는 몸 그림의 **머리 언저리를 오려** 쓴다.
## ⚠️ 오리는 자리는 `sprite_set.head_anchor` 가 정한다. 없으면 위쪽 가운데다.
class_name Faces
extends RefCounted

## 오리는 크기. 32px 몸에서 머리는 12~14px 이다 — 크게 잡으면 얼굴이 아니라
## 작은 전신 그림이 된다 (실제로 20 으로 잡았다가 등이 나왔다).
const SIZE := 14

static var _cache := {}


## 그 종의 얼굴 한 장. 없으면 null.
static func of(species: Dictionary) -> Texture2D:
	var id := String(species.get("id", ""))
	if _cache.has(id):
		return _cache[id]
	var canvas := SpriteLibrary.canvas_for(id, Vector2i(32, 32))
	var frames: Dictionary = SpriteLibrary.body_frames(species, canvas)
	var sheet: SpriteFrames = frames["frames"]
	if sheet == null or not sheet.has_animation("idle") or sheet.get_frame_count("idle") == 0:
		_cache[id] = null
		return null
	var source: Texture2D = sheet.get_frame_texture("idle", 0)
	# ⚠️ 캔버스 위쪽을 그냥 오리면 **등이 나온다.** 동물은 캔버스 아래쪽에 서 있고
	#    측면 그림은 오른쪽을 본다 — 그림이 실제로 차지한 자리를 찾아 그 **오른쪽 위**를
	#    오려야 얼굴이 된다. 풀 흔들림에서 배운 것과 같은 실수다(캔버스 ≠ 그림).
	# ⚠️ `head_anchor` 를 쓰지 않는다. 그건 머리가 아니라 **머리 위 아이콘이 뜨는 자리**라
	#    (개는 [16, 2]) 그걸 기준으로 오리면 그림 위쪽 빈 줄을 오려 온다 — 실제로 그랬다.
	# ★ 측면 그림은 오른쪽을 본다. **잉크의 오른쪽 위**가 머리다.
	var mark := _ink(source.get_image())
	var box := Rect2()
	box.position = Vector2(mark.end.x - SIZE, mark.position.y - 1.0)
	box.position.x = clampf(box.position.x, 0.0, maxf(source.get_width() - SIZE, 0.0))
	box.position.y = clampf(box.position.y, 0.0, maxf(source.get_height() - SIZE, 0.0))
	box.size = Vector2(mini(SIZE, source.get_width()), mini(SIZE, source.get_height()))
	var face := AtlasTexture.new()
	face.atlas = source
	face.region = box
	_cache[id] = face
	return face


## 얼굴 + **기쁨 눈**. 목적지를 좋아할 동료를 이걸로 보여준다 —
## 유불리를 말하지 않고 **그 아이의 기분**만 말한다 (§3.9).
static func glad(species: Dictionary) -> Texture2D:
	var id := "glad:" + String(species.get("id", ""))
	if _cache.has(id):
		return _cache[id]
	var face := of(species)
	if face == null:
		_cache[id] = null
		return null
	var eye := SpriteLibrary.eye_texture(String(species.get("id", "")), "side", "기쁨",
		String((species.get("sprite_set", {}) as Dictionary).get("eye_style", "round")))
	if eye == null:
		eye = PlaceholderArt.eye_texture("round")
	var image := face.get_image()
	var patch := eye.get_image()
	# 눈은 얼굴 위 가운데쯤에 얹는다. 정확한 앵커는 몸통 기준이라 여기선 못 쓴다 —
	# 얼굴을 오려낸 뒤라서다. 작은 그림이라 눈으로 맞추는 편이 정확하다.
	var at := Vector2i(int(image.get_width() * 0.42), int(image.get_height() * 0.30))
	image.blend_rect(patch, Rect2i(Vector2i.ZERO, patch.get_size()), at)
	var made := ImageTexture.create_from_image(image)
	_cache[id] = made
	return made


## 그림이 실제로 차지한 사각형. 캔버스가 아니라 **잉크**를 재는 것이다.
static func _ink(image: Image) -> Rect2:
	var left := image.get_width()
	var right := 0
	var top := image.get_height()
	var bottom := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.02:
				continue
			left = mini(left, x)
			right = maxi(right, x + 1)
			top = mini(top, y)
			bottom = maxi(bottom, y + 1)
	if right <= left:
		return Rect2(Vector2.ZERO, Vector2(image.get_size()))
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


## 얼굴 스프라이트 하나를 노드로 얹는다.
static func place(parent: Node, texture: Texture2D, at: Vector2, grow := 2) -> Sprite2D:
	if texture == null:
		return null
	var node := Sprite2D.new()
	node.texture = texture
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.centered = false
	node.scale = Vector2.ONE * grow
	node.position = at.floor()
	parent.add_child(node)
	return node


## 아직 못 만난 아이 — **실루엣 하나**로 말한다. 몇 종인지 세지 않는다.
static func unknown(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			image.set_pixel(x, y, Color(0.12, 0.13, 0.15, pixel.a))
	return ImageTexture.create_from_image(image)
