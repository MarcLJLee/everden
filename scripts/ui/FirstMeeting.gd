## 첫 만남 — **튜토리얼이 아니라 첫 번째 초대다.** (BRIEF §2.9 · ui/screens.json)
##
## ★ 절대 규칙: **본편과 같은 조작 · 같은 게이지 · 같은 카드.**
##   별도 코드로 게이지를 다시 짜면 반드시 갈라진다 — `Gauge` 를 그대로 쓴다.
##   (처음엔 여기만 따로 짰고, 그게 §2.9 가 브리프에 새로 쓰인 이유다.)
## ★ **누르고 있게 만들지 않는다.** 초대는 누르는 게 아니라 **곁에 있어 주는** 것이다 (§3.4).
## ★ 문장에 키 이름을 넣지 않는다 — **어떻게 누르는지는 키캡 그림이 말한다** (§2.10).
##   마지막 칸에는 **키캡이 없다.** 누를 게 없다는 것을 부재로 말한다.
##
## 마당은 비어 있다 — 산 사물도, 사는 동물도 없다. 여기서 배우는 것은 셋뿐이다:
## 걷는다 · 인사한다 · **곁에 있으면 친구가 된다.**
extends Control

const ACTOR_SCENE := "res://scenes/actors/Actor.tscn"
const TUNING_PATH := "res://tuning/field_tuning.tres"
const HOME_SCENE := "res://scenes/home/Home.tscn"
const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
const SPEC := "res://sprites/extracted/ui/screens.json"
## 강아지가 다가와 멈추는 거리
const MEET := 30.0

@onready var _ground: Node2D = $World/Ground
@onready var _actors: Node2D = $World/Actors
@onready var _say: Label = $Text/Say
@onready var _bar: ColorRect = $Text/Bar
@onready var _card: CanvasLayer = $InviteCard

var schema: TagSchema = null
var tuning: FieldTuning = null
var terrain := TerrainMap.new()
var player: Actor = null
var puppy: Actor = null
var gauge := Gauge.new()

var _steps: Array = []
var _at := 0
var _walked := 0.0
var _keycap: Sprite2D = null
var _prey: FieldSim.WildAnimal = null
var _rng := RandomNumberGenerator.new()
var _leaving := false


func _ready() -> void:
	_rng.randomize()
	var result := DataLoader.load_all(true)
	schema = result.schema
	tuning = load(TUNING_PATH)
	gauge.setup(tuning, schema)
	_steps = _read_steps()

	var screen := Vector2i(640, 360)
	var tiles := Vector2i(ceili(screen.x / 16.0), ceili(screen.y / 16.0))
	var view: FieldTuning = tuning.duplicate()
	view.map_size = tiles
	terrain.generate(tiles, view.tile_size, {}, _rng)
	terrain.fill("초원")
	_ground.setup(view, terrain)

	player = _make(Actor.player_config(), Vector2(300, 210), view)
	player.speed_tiles = view.move_speed

	var dog: Dictionary = result.species.get("dog", {})
	puppy = _make(dog, Vector2(520, 150), view)
	# 다가오는 걸음은 조금 빨라야 한다 — 배회 속도로 걸어오면 20초가 넘는다
	puppy.speed_tiles = view.move_speed * 0.75
	puppy.visible = false
	# 게이지는 **본편과 같은 개체 모양**을 받는다 — 여기만 다른 자료구조를 쓰면 갈라진다
	_prey = FieldSim.WildAnimal.new()
	_prey.species = dog
	_prey.actor = puppy
	_prey.sex = Actor.roll_sex(_rng)
	var grown := Actor.roll_stage(dog, _rng)
	_prey.stage = "baby"          # 첫 친구는 강아지다 — 자라서 같이 여행을 다닌다
	_prey.age_years = 0
	puppy.sex = _prey.sex

	if ResourceLoader.exists(HANGUL_FONT):
		_say.add_theme_font_override("font", load(HANGUL_FONT))
	_say.add_theme_font_size_override("font_size", 11)
	_say.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_say.add_theme_constant_override("shadow_offset_x", 1)
	_say.add_theme_constant_override("shadow_offset_y", 1)
	_bar.size.x = 0.0
	_bar.visible = false
	_card.closed.connect(_go_home)
	_show()


## 대사와 키캡은 **설계가 넘긴 표**에서 온다 (ui/screens.json · §6.9).
## 여기 없으면 화면이 조용히 달라진다 — 기본값을 두되 표가 있으면 표가 이긴다.
func _read_steps() -> Array:
	var fallback := [
		{"say": "걸어 볼까요?", "keycap": "wasd"},
		{"say": "어? 누가 왔어요.", "keycap": null},
		{"say": "가까이 가서 인사해요.", "keycap": "space"},
		{"say": "곁에 있어 주면 돼요.", "keycap": null},
	]
	if not FileAccess.file_exists(SPEC):
		return fallback
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	if not (parsed is Dictionary):
		return fallback
	var steps: Array = ((parsed.get("screens", {}) as Dictionary)
		.get("first_meeting", {}) as Dictionary).get("steps", [])
	return steps if not steps.is_empty() else fallback


func _make(config: Dictionary, at: Vector2, view: FieldTuning) -> Actor:
	var actor: Actor = load(ACTOR_SCENE).instantiate()
	_actors.add_child(actor)
	actor.setup(config, schema, view, _rng)
	actor.position = at
	actor.bounds = Rect2(Vector2(24, 60), Vector2(592, 220))
	return actor


func _process(delta: float) -> void:
	if _leaving or _card.is_open():
		player.move_vector = Vector2.ZERO
		return
	player.move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.position = player.position.clamp(player.bounds.position, player.bounds.end)
	_prey.position = puppy.position

	match _at:
		0:
			# 말로 시키지 말고 **해 보면** 넘어간다. 7살은 글을 다 안 읽는다.
			_walked += player.move_vector.length() * delta
			if _walked > 1.6:
				_advance()
		1:
			puppy.visible = true
			_walk_puppy(delta)
			if puppy.position.distance_to(player.position) <= MEET + 8.0:
				_advance()
		2:
			puppy.move_vector = Vector2.ZERO
			puppy.look_direction = (player.position - puppy.position).normalized()
			if Input.is_action_just_pressed("interact") \
					and player.position.distance_to(puppy.position) <= tuning.interact_radius \
						* tuning.tile_size:
				gauge.start(_prey, null, "낮")
				_advance()
		3:
			_hold_still(delta)


## 강아지가 먼저 다가온다 — 아이가 쫓아가는 게 아니다.
func _walk_puppy(delta: float) -> void:
	var toward := player.position - puppy.position
	if toward.length() <= MEET:
		puppy.move_vector = Vector2.ZERO
		return
	puppy.move_vector = FieldSim.sideways(toward.normalized())


## ★ **곁에 있어 주면 찬다.** 누르고 있는 게 아니다 (§3.4).
##   멀어지면 멈출 뿐 안 지워진다 — 되돌릴 수 없는 실패를 만들지 않는다 (원칙 2).
func _hold_still(delta: float) -> void:
	puppy.move_vector = Vector2.ZERO
	puppy.look_direction = (player.position - puppy.position).normalized()
	_bar.visible = true
	var gap := player.position.distance_to(puppy.position)
	var done := gauge.update(delta, gap)
	_bar.size.x = 180.0 * gauge.progress
	_bar.color = Color(0.6, 0.55, 0.4) if gauge.paused else Color(1, 0.86, 0.45)
	if not done:
		return
	_bar.visible = false
	gauge.close()
	# 여기서 바로 저장한다 — 친구가 생긴 순간은 남아야 한다
	var puppy_row := Game.finish_tutorial()
	puppy_row["sex"] = _prey.sex
	puppy_row["stage"] = _prey.stage
	puppy_row["age_years"] = _prey.age_years
	Game.save_game()
	# 본편과 **같은 카드**다
	_card.show_for(puppy_row, _prey.species, true, schema)


func _advance() -> void:
	_at += 1
	if _at >= _steps.size():
		return
	_show()


func _show() -> void:
	var step: Dictionary = _steps[_at]
	_say.text = String(step.get("say", ""))
	if _keycap != null:
		_keycap.queue_free()
		_keycap = null
	# ⚠️ 마지막 칸에는 키캡이 없다 — 누를 게 없다는 것을 **부재로** 말한다
	var cap = step.get("keycap", null)
	if cap == null:
		return
	var action := "이동" if String(cap) == "wasd" else "인사·정하기"
	_keycap = Keycap.place($Text, action, Vector2(20, 268))


func _go_home() -> void:
	_leaving = true
	get_tree().call_deferred("change_scene_to_file", HOME_SCENE)
