## 첫 만남 — **새 판의 첫 사건.** (BRIEF §2.1 · §3.3)
##
## ★ 처음부터 개와 고양이를 들려주면 "친구가 생긴다" 는 이 게임의 첫 사건이 사라진다.
##   첫 강아지는 **초대해서 얻는 것**이고, 그 자리가 곧 초대 규칙을 배우는 자리다.
##
## 여기서 가르치는 것은 셋뿐이다:
##   ① 움직인다  ② **가까이 가서 붙어 있으면** 친구가 된다  ③ 강아지는 코로 찾아 준다
##
## ⚠️ 게이지는 시작하면 반드시 완료된다 (원칙 2). 여기서도 멀어지면 **멈출 뿐** 안 지워진다.
## ⚠️ Control 의 `_draw` 로 텍스처·글자를 그리지 않는다. 말은 Label, 게이지는 ColorRect 다.
extends Control

const ACTOR_SCENE := "res://scenes/actors/Actor.tscn"
const TUNING_PATH := "res://tuning/field_tuning.tres"
const HOME_SCENE := "res://scenes/home/Home.tscn"
const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
const NEAR := 26.0
const BAR_WIDE := 180.0

const LINES := [
	"우리 집 마당이에요.  [WASD] 로 걸어 봐요.",
	"어? 누가 왔어요.",
	"가까이 가서 [스페이스] 를 누르고 있어 봐요.",
	"친구가 됐어요!",
	"강아지는 코가 아주 좋아요.\n같이 나가면 냄새로 다른 아이를 찾아 줘요.",
]
## 걸어 봐야 넘어가는 줄 · 붙어 있어야 넘어가는 줄
const WALK_LINE := 0
const INVITE_LINE := 2

@onready var _ground: Node2D = $World/Ground
@onready var _actors: Node2D = $World/Actors
@onready var _say: Label = $Text/Say
@onready var _bar: ColorRect = $Text/Bar

var schema: TagSchema = null
var tuning: FieldTuning = null
var terrain := TerrainMap.new()
var player: Actor = null
var puppy: Actor = null

var _at := 0
var _walked := 0.0
var _progress := 0.0
var _rng := RandomNumberGenerator.new()
var _leaving := false


func _ready() -> void:
	_rng.randomize()
	var result := DataLoader.load_all(true)
	schema = result.schema
	tuning = load(TUNING_PATH)

	var screen := Vector2i(640, 360)
	var tiles := Vector2i(ceili(screen.x / 16.0), ceili(screen.y / 16.0))
	var view: FieldTuning = tuning.duplicate()
	view.map_size = tiles
	terrain.generate(tiles, view.tile_size, {}, _rng)
	terrain.fill("초원")
	_ground.setup(view, terrain)

	player = _make({
		"id": "player", "name": "나", "diet": "잡식", "activity": "주행성",
		"size_class": "중", "senses": [], "traits": [],
		"stats_range": {"sense_range": [1.0, 1.0], "charm": [1.0, 1.0]},
		"sprite_set": {"eye_style": "round", "head_anchor": [16, 3]},
	}, Vector2(300, 200), view)
	player.speed_tiles = view.move_speed

	puppy = _make(result.species.get("dog", {}), Vector2(470, 150), view)
	puppy.visible = false

	for label in [_say]:
		if ResourceLoader.exists(HANGUL_FONT):
			label.add_theme_font_override("font", load(HANGUL_FONT))
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	_bar.size.x = 0.0
	_show()


func _make(config: Dictionary, at: Vector2, view: FieldTuning) -> Actor:
	var actor: Actor = load(ACTOR_SCENE).instantiate()
	_actors.add_child(actor)
	actor.setup(config, schema, view, _rng)
	actor.position = at
	actor.bounds = Rect2(Vector2(24, 40), Vector2(592, 240))
	return actor


func _process(delta: float) -> void:
	if _leaving:
		return
	player.move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.position = player.position.clamp(player.bounds.position, player.bounds.end)

	match _at:
		WALK_LINE:
			# 말로 시키지 말고 **해 보면** 넘어간다. 7살은 글을 다 안 읽는다.
			_walked += player.move_vector.length() * delta
			if _walked > 1.6:
				_advance()
		1:
			puppy.visible = true
			puppy.look_direction = (player.position - puppy.position).normalized()
			if Input.is_action_just_pressed("interact"):
				_advance()
		INVITE_LINE:
			_invite(delta)
		_:
			if Input.is_action_just_pressed("interact"):
				_advance()


## ★ 붙어 있어야 찬다. 한 번 누르고 가만히 두면 되는 것은 넌센스다 (§2.3).
## ⚠️ 멀어지면 **멈출 뿐 안 지워진다** — 되돌릴 수 없는 실패를 만들지 않는다 (원칙 2).
func _invite(delta: float) -> void:
	var close := player.position.distance_to(puppy.position) <= NEAR
	var holding := Input.is_action_pressed("interact")
	if close and holding:
		_progress = minf(_progress + delta / 2.2, 1.0)
	_bar.size.x = BAR_WIDE * _progress
	_bar.color = Color(1, 0.86, 0.45) if (close and holding) else Color(0.6, 0.55, 0.4)
	puppy.look_direction = (player.position - puppy.position).normalized()
	if _progress >= 1.0:
		# 여기서 바로 저장한다 — 친구가 생긴 순간은 남아야 한다
		Game.finish_tutorial()
		_bar.size.x = 0.0
		_advance()


func _advance() -> void:
	_at += 1
	if _at >= LINES.size():
		_leaving = true
		get_tree().call_deferred("change_scene_to_file", HOME_SCENE)
		return
	_show()


func _show() -> void:
	_say.text = LINES[_at]
	if _at > INVITE_LINE:
		puppy.move_vector = Vector2.ZERO
