## 캐릭터 하나. 이동·방향·바운스를 담당한다. (DEMO-SPEC §3.1, §3.2)
##
## ★ 이 노드가 Y-sort 대상이다. 몸통·눈·입·아이콘은 전부 자식이라 통째로 정렬된다.
## ★ 걷기 바운스는 스프라이트가 아니라 Body 노드의 Y로 처리하고 정수 픽셀로 스냅한다.
class_name Actor
extends Node2D

const FACINGS := ["south", "north", "east", "west"]

# setup() 안에서 직접 잡는다. @onready 로 두면 트리에 들어가기 전에는 비어 있어서,
# 인스턴스를 만들자마자 setup() 을 부르는 쪽이 조용히 깨진다.
var _shadow: Sprite2D = null
var _body: Node2D = null
var _body_sprite: AnimatedSprite2D = null
var _emote: Sprite2D = null

## 이 프레임에 가고 싶은 방향. 정규화되어 있지 않아도 된다.
var move_vector := Vector2.ZERO
## 타일/초
var speed_tiles := 3.0
## 필드 밖으로 나가지 않게 하는 경계 (픽셀)
var bounds := Rect2()
## 경계가 사각형이 아닐 때 쓴다 — 울타리처럼 한 군데만 뚫려 있는 경우.
## `func(from: Vector2, to: Vector2) -> Vector2`. 비어 있으면 bounds 로 자른다.
## 이전 위치를 같이 넘기는 것은 **막힌 곳에서 미끄러지게** 하기 위해서다 —
## 그냥 되돌리면 벽에 비스듬히 붙었을 때 아예 안 움직인다.
var confine := Callable()
## 특징 동작(개의 꼬리흔들기)을 재생할 것인가. 유도 중인 동료가 켠다 —
## "동료가 그 방향을 보고 킁킁댄다"가 장식이 아니라 기능이 되는 지점이다. (BRIEF §3.3)
var play_special := false
## 멈춰 있을 때 바라볼 방향. 유도 중인 동료가 대상 쪽을 본다. 비어 있으면 무시.
var look_direction := Vector2.ZERO

var species := {}
var species_id := ""
var display_name := ""
var diet := ""
var activity := ""
var senses: Array = []
## 이 동물이 들어갈 수 있는 막힌 지형. 기본 지형은 habitat 과 무관하게 지나간다.
var habitat: Array = []
var traits: Array = []
## 개체의 성별. 개체 정의 때 정해진다 (BRIEF §3.11 1단계) — 원정 중에 바뀌지 않는다.
## 화면에서 보인다: 이형이 있는 종은 도트로, 없는 종은 이름표 뱃지로. (§4.9)
var sex := ""
## 몸이 몇 방향을 쓰는가 — "side" 면 좌우 둘, "four" 면 네 방향. (BRIEF §4.5 ★ v3.16)
##
## ★ **방향은 곱셈이고 모션은 덧셈이다.** 3방향이면 새 모션 하나가 종당 6장,
##   측면이면 2장이다. 그래서 예산을 방향이 아니라 모션에 쓴다 —
##   같은 16장으로 먹기·자기·놀기·기뻐하기를 산다.
## ★ 개·고양이·다람쥐의 4방향 도트를 **버리지는 않는다.** 본체는 능력을 갖고
##   얼마나 쓸지는 데이터(`sprite_set.facing`)가 정한다. 지금 four 는 플레이어뿐이다.
var facing_set := "side"
## 그림의 우듬지가 발끝에서 얼마나 위인가(px). **캔버스가 아니라 그림 기준**이다.
var crown_lift := 0.0
## 개체값 — 능력치가 무언가를 결정해야 한다 (BRIEF §2.5)
var sense_scale := 1.0
var charm := 1.0
## 이 개체의 이동속도 배율. 종마다 범위가 다르고 개체마다 그 안에서 다르다 —
## 두꺼비는 느리고 참새는 빠르다. **숫자로 보여주지 않는다. 걷는 걸 보면 안다.**
var move_scale := 1.0
## 이 개체의 개성. 선택지는 종 데이터(quirk_pool)가 갖는다. 없을 수도 있다.
var quirks: Array = []

var facing := "south"
var canvas := Vector2i(32, 32)
## 캔버스 좌상단이 Actor 원점에서 어디에 놓이는가. 몸통·눈·입·아이콘이 모두 이것을 쓴다.
var canvas_offset := Vector2.ZERO
## 색 사각형이 아니라 실제로 그려진 그림을 쓰고 있는가
var has_drawn_art := false

var _last_horizontal := "east"
var _walk_phase := 0.0
var _tuning: FieldTuning = null
var _moving := false


## 성별 하나. 반반이다 — 확률을 화면에 노출하지 않으므로 기울일 이유가 없다.
static func roll_sex(rng: RandomNumberGenerator) -> String:
	return "male" if rng.randf() < 0.5 else "female"


## 단계와 나이 하나. 표(`growth`)에 있는 단계만 쓴다 — 종 이름으로 분기하지 않는다.
##
## ★ 야생 개체의 나이는 **게임적 허용으로 닫는다** (BRIEF §3.15). 근거를 만들지 않는다 —
##   아이가 분명히 궁금해하기 때문에 답을 주는 것이다: "얘는 엄마 사슴인가? 아기인가?"
## ★ 아기가 드물어야 만났을 때 사건이 된다. 다섯에 하나쯤.
static func roll_stage(species: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var stages: Array = species.get("growth", [])
	var baby := ""
	for one in stages:
		if String(one.get("stage", "")) == "baby":
			baby = "baby"
	if not baby.is_empty() and rng.randf() < 0.2:
		return {"stage": "baby", "age_years": 0}
	var span: Array = species.get("adult_age_years", [1, 5])
	return {"stage": "adult",
		"age_years": rng.randi_range(int(span[0]), int(span[1]))}


## 마릿수만큼 성별을 뽑되, **둘 이상이면 암수가 반드시 섞인다.**
## 짝이 없다는 이유로 영구히 막히는 일을 구조적으로 없앤다 (BRIEF §2.4 확정 배치).
## `required` 를 주면 그 성별이 반드시 하나 들어간다 — 집에 혼자인 개체가 있을 때 쓴다.
static func roll_sexes(count: int, rng: RandomNumberGenerator, required := "") -> Array:
	var out: Array = []
	for i in count:
		out.append(roll_sex(rng))
	if count >= 2 and out.count(out[0]) == count:
		out[rng.randi_range(0, count - 1)] = "female" if out[0] == "male" else "male"
	if not required.is_empty() and count > 0 and not (required in out):
		out[rng.randi_range(0, count - 1)] = required
	return out


## config 는 animals.json 의 종 정의 한 덩어리다. 플레이어처럼 종이 없는 액터는
## 같은 모양의 딕셔너리를 만들어 넘긴다 — 특수 분기를 만들지 않기 위해서다.
func setup(config: Dictionary, schema: TagSchema, tuning: FieldTuning,
		rng: RandomNumberGenerator, individual_sex := "") -> void:
	_shadow = get_node("Shadow")
	_body = get_node("Body")
	_body_sprite = get_node("Body/BodySprite")
	_emote = get_node("Body/Emote")

	species = config
	facing_set = String((config.get("sprite_set", {}) as Dictionary).get("facing", "side"))
	sex = individual_sex if not individual_sex.is_empty() else roll_sex(rng)
	_tuning = tuning
	species_id = String(config.get("id", ""))
	display_name = String(config.get("name", species_id))
	diet = String(config.get("diet", ""))
	activity = String(config.get("activity", ""))
	senses = config.get("senses", [])
	habitat = config.get("habitat", [])
	traits = config.get("traits", [])
	canvas = SpriteLibrary.canvas_for(species_id,
		schema.canvas_for(String(config.get("size_class", "중"))))

	var stats: Dictionary = config.get("stats_range", {})
	sense_scale = _roll(stats.get("sense_range", [1.0, 1.0]), rng)
	charm = _roll(stats.get("charm", [1.0, 1.0]), rng)
	quirks = roll_quirks(config, schema, rng)
	move_scale = _roll(stats.get("move_speed", [1.0, 1.0]), rng) \
		* schema.quirk_product(quirks, "move_scale")

	var sprite_set: Dictionary = SpriteLibrary.apply_meta_anchors(
		species_id, config.get("sprite_set", {}))
	var art := SpriteLibrary.body_frames(config, canvas)
	has_drawn_art = art["real"]
	_body_sprite.sprite_frames = art["frames"]
	# 캔버스 바닥이 아니라 **그림의 접지선**이 Actor 원점에 와야 한다.
	var ground: Dictionary = SpriteLibrary.ground_info(species_id, art["frames"], canvas)
	canvas_offset = Vector2(-int(canvas.x / 2.0), -(canvas.y - int(ground["gap"])))
	# ⚠️ 머리 위에 얹는 것은 **그림 위**에 얹어야 한다. 캔버스 위를 기준으로 잡으면
	#    빈 줄만큼 붕 뜬다 — 얼굴 오리기·풀 흔들림에서 겪은 것과 같은 실수다.
	crown_lift = float(canvas.y - int(ground["gap"]) - int(ground["crown"]))
	if not art["missing"].is_empty():
		SpriteLibrary.warn_once(species_id, "%s: 그림이 없어 대역으로 채운 애니메이션 — %s"
			% [species_id, ", ".join(art["missing"])])
	_body_sprite.position = canvas_offset
	_body_sprite.animation = "idle"
	_body_sprite.pause()

	# 그림자는 몸통 폭이 아니라 **발이 닿는 폭**에 맞춘다. 너무 넓으면 따로 논다.
	var shadow_texture := PlaceholderArt.shadow_texture(int(ground["foot_width"]))
	_shadow.texture = shadow_texture
	_shadow.position = -shadow_texture.get_size() * 0.5

	_body.setup(sprite_set, canvas, canvas_offset, has_drawn_art, species_id, sex)
	_emote.setup(sprite_set, canvas_offset)
	_apply_facing("south")


func _process(delta: float) -> void:
	if _tuning == null:
		return
	_moving = move_vector.length() > 0.05
	if _moving:
		var step := move_vector.normalized() * speed_tiles * move_scale * _tuning.tile_size * delta
		var came_from := position
		position += step
		if confine.is_valid():
			position = confine.call(came_from, position)
		elif bounds.size != Vector2.ZERO:
			position = position.clamp(bounds.position, bounds.end)
		_apply_facing(_facing_from(move_vector))
		_walk_phase += delta * _tuning.walk_cycle_hz
	elif absf(look_direction.x) > 0.05:
		# 대기 스프라이트는 좌우 2방향뿐이다 (BRIEF §4.5).
		# 정지 상태에서 북/남을 바라보게 두면 측면 몸통에 정면 눈이 얹힌다.
		_apply_facing("east" if look_direction.x > 0.0 else "west")
	else:
		_apply_facing(_last_horizontal)

	_update_body_frame()


## 지배적 축으로 4방향을 정한다. (DEMO-SPEC §3.1)
func _facing_from(vector: Vector2) -> String:
	if absf(vector.x) >= absf(vector.y):
		return "east" if vector.x >= 0.0 else "west"
	# 측면 1방향인 몸은 북·남을 쓰지 않는다 — 그 그림이 없다 (§4.5)
	if facing_set != "four":
		return "east" if _last_horizontal == "east" else "west"
	return "south" if vector.y >= 0.0 else "north"


func _apply_facing(new_facing: String) -> void:
	facing = new_facing
	if facing == "east" or facing == "west":
		_last_horizontal = facing
	_body.apply_facing(facing)


## 걷기 프레임과 바운스를 같은 위상에서 뽑는다 — 둘이 어긋나면 발이 땅에서 뜬다.
func _update_body_frame() -> void:
	var step := int(_walk_phase) % 2
	if _moving:
		match facing:
			"north": _body_sprite.animation = "move_north"
			"south": _body_sprite.animation = "move_south"
			_: _body_sprite.animation = "move_side"
		_body_sprite.frame = step
		# ★ 노드 Y를 정수 픽셀로. 안 하면 얼굴이 떨린다. (DEMO-SPEC §3.2)
		_body.position.y = float(-_tuning.bounce_height_px * step)
	else:
		var special := play_special and _body_sprite.sprite_frames.has_animation("special")
		_body_sprite.animation = "special" if special else "idle"
		_body_sprite.frame = int(_walk_phase) % 2 if special else 0
		if special:
			_walk_phase += 0.08   # 대기 중에도 특징 동작은 움직여야 한다
		_body.position.y = 0.0
	_body_sprite.flip_h = facing == "west" or (not _moving and _last_horizontal == "west")


## 어두울 때 눈이 되비춘다. 종이 아니라 activity 로 정해진다.
func set_eyeshine(on: bool, color: Color, cancel: Color) -> void:
	_body.set_eyeshine(on, color, cancel)


func show_sense_icon(sense: String, icon_name := "") -> void:
	_emote.show_sense(sense, icon_name)

func hide_sense_icon() -> void:
	_emote.hide_icon()

## 게이지·이펙트를 띄울 머리 위 월드 좌표
## 머리 위 한 뼘. 감각 아이콘·게이지·먼지가 여기 뜬다.
func head_position() -> Vector2:
	return position + Vector2(0, -crown_lift - 4.0)

## 종이 내건 선택지에서 개성을 뽑는다. 코드가 개성 이름을 고르지 않는다.
static func roll_quirks(config: Dictionary, schema: TagSchema, rng: RandomNumberGenerator) -> Array:
	var pool: Array = config.get("quirk_pool", []).duplicate()
	var span: Array = config.get("quirk_count", [0, 0])
	if pool.is_empty() or span.size() < 2:
		return []
	var count := rng.randi_range(int(span[0]), mini(int(span[1]), pool.size()))
	var picked: Array = []
	for i in count:
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picked


static func _roll(range_array, rng: RandomNumberGenerator) -> float:
	if typeof(range_array) != TYPE_ARRAY or range_array.size() < 2:
		return 1.0
	return rng.randf_range(float(range_array[0]), float(range_array[1]))
