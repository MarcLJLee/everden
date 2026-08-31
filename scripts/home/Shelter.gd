## 쉼터 — 정원을 넘은 아이들이 지내는 **다른 마당**. (BRIEF §2.4)
##
## ★ **목록 UI 가 아니라 장소다.** 7살에게 "목록 화면에 있는 동물" 은 존재하지 않는
##   동물이다. 그래서 여기도 걸어 들어가고, 걸어 나가고, 옆에 서서 말을 건다.
##
## ★ **창고나 우리처럼 보이면 안 된다.** 집 마당 바닥을 그대로 쓰면 같은 곳으로 읽히고,
##   울타리를 두르면 가둬 둔 곳이 된다. 그늘막 아래 방석에 누워 자는 **작은 숲 마당**이다.
##
## ★ **여기 있는 아이도 원정에 데려갈 수 있다.** 이게 빠지면 정원 초과가 곧 벤치가 되고,
##   그건 "수집이 벌이 되면 안 된다"(원칙 6)에 정면으로 걸린다.
##
## ★ **방출은 없다.** 내보내는 버튼을 만들지 않는다 — 되돌릴 수 없는 실패다(원칙 2).
##   할 수 있는 일은 집으로 데려가는 것과, 자리가 없으면 **누구랑 바꿀지 묻는 것**뿐이다.
##
## ⚠️ 텍스트·텍스처는 전부 **노드**로 얹는다. Control 의 `_draw` 로 그리면 네모가 된다 (RUN.md).
extends Control

const ACTOR_SCENE := "res://scenes/actors/Actor.tscn"
const TUNING_PATH := "res://tuning/field_tuning.tres"
const HOME_SCENE := "res://scenes/home/Home.tscn"
const HANGUL_FONT := "res://fonts/Galmuri11.ttf"
const ART_ROOT := "res://sprites/extracted/"
## 옆에 서면 말을 건다. 집 대문과 같은 거리라 배울 게 없다.
const REACH := 26.0

@onready var _world: Node2D = $World
@onready var _ground: Node2D = $World/Ground
@onready var _props: Node2D = $World/Props
@onready var _actors: Node2D = $World/Actors
@onready var _weather_layers: WeatherLayers = $World/Weather
@onready var _text: Control = $Text
@onready var _prompt: Label = $Text/Prompt
@onready var _badge: Label = $Text/Badge

var schema: TagSchema = null
var tuning: FieldTuning = null
var terrain := TerrainMap.new()
var player: Actor = null

## {uid, actor, species} — 쉼터에서 지내는 아이들.
var guests: Array = []
## 바꿀 상대를 고르는 중이면 얼굴 줄이 뜬다. 비어 있으면 평소 화면이다.
var _swap: Array = []
var _swap_at := 0
var _swap_for := -1

var _bounds := Rect2()
var _exit := Vector2.ZERO
var _post := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _leaving := false
var _sky := {"cloud": 0.30, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.20}
var _species_by_id := {}


func _ready() -> void:
	_rng.randomize()
	var result := DataLoader.load_all(true)
	schema = result.schema
	_species_by_id = result.species
	tuning = load(TUNING_PATH)

	var screen := Vector2i(640, 360)
	var tiles := Vector2i(ceili(screen.x / float(tuning.tile_size)),
		ceili(screen.y / float(tuning.tile_size)))
	var view: FieldTuning = tuning.duplicate()
	view.map_size = tiles
	terrain.generate(tiles, view.tile_size, {}, _rng)
	# ★ 집 마당은 초원이다. 여기를 초원으로 깔면 **같은 곳**으로 읽힌다.
	terrain.fill("숲")
	_ground.setup(view, terrain)

	# 울타리를 두르지 않는다 — 가둔 곳이 아니다. 화면 가장자리가 곧 경계다.
	_bounds = Rect2(28, 52, screen.x - 56, screen.y - 96)
	_exit = Vector2(screen.x * 0.5, screen.y - 30)
	_post = Vector2(screen.x - 86, 74)

	_build_shade(screen)
	_spawn_guests(view)
	_spawn_player(view)
	_weather_layers.build(["cloud"])
	_text.draw.connect(_text_draw)
	for label in [_prompt, _badge]:
		if ResourceLoader.exists(HANGUL_FONT):
			label.add_theme_font_override("font", load(HANGUL_FONT))
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.visible = false
	_refresh()


# --- 마당 ------------------------------------------------------------------

## 그늘막과 방석. **자는 자리가 보여야** 쉬는 곳으로 읽힌다.
func _build_shade(screen: Vector2i) -> void:
	for i in 2:
		var at := Vector2(screen.x * (0.28 + 0.42 * i), 96.0)
		_put("home/obj_그늘막.png", at)
	for i in 6:
		var at := Vector2(screen.x * (0.20 + 0.12 * i), 132.0 + (i % 2) * 26.0)
		_put("home/obj_방석.png", at)


func _put(relative: String, at: Vector2) -> void:
	var path := ART_ROOT + relative
	if not ResourceLoader.exists(path):
		return
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.position = (at - Vector2(sprite.texture.get_size()) * 0.5).round()
	_props.add_child(sprite)


func _confine(_from: Vector2, at: Vector2) -> Vector2:
	return Vector2(clampf(at.x, _bounds.position.x, _bounds.end.x),
		clampf(at.y, _bounds.position.y, _bounds.end.y))


# --- 아이들 ----------------------------------------------------------------

func _spawn_guests(view: FieldTuning) -> void:
	var i := 0
	for one in Game.shelter_members():
		var id := String(one["species_id"])
		var species: Dictionary = _species_by_id.get(id, {})
		if species.is_empty():
			continue
		var actor: Actor = load(ACTOR_SCENE).instantiate()
		_actors.add_child(actor)
		actor.setup(species, schema, view, _rng, String(one["sex"]))
		# ★ **대기 중인 동물은 시간이 정지한다** (§2.4). 그래서 뛰어다니지 않는다 —
		#   느리게 움직이고 대부분 앉아 있다. 자라지도 않는다.
		actor.speed_tiles = view.wild_speed * 0.35
		actor.confine = _confine
		actor.position = Vector2(_bounds.position.x + 64 + (i % 4) * 108,
			132.0 + (i % 2) * 26.0 + int(i / 4) * 54)
		guests.append({"uid": int(one["uid"]), "actor": actor, "species": species})
		_name_tag(actor, String(species.get("name", id)))
		i += 1


## 이름표. 배지는 **옆에 섰을 때만** 붙인다 — 여섯 개가 한꺼번에 뜨면 안내가 아니라 소음이다.
func _name_tag(actor: Actor, name: String) -> void:
	var label := Label.new()
	label.text = name
	label.name = "NameTag"
	if ResourceLoader.exists(HANGUL_FONT):
		label.add_theme_font_override("font", load(HANGUL_FONT))
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = Vector2(-22, 8)
	label.size = Vector2(44, 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actor.add_child(label)


func _spawn_player(view: FieldTuning) -> void:
	player = load(ACTOR_SCENE).instantiate()
	_actors.add_child(player)
	player.setup(Actor.player_config(), schema, view, _rng)
	player.speed_tiles = view.move_speed
	player.confine = _confine
	player.position = _exit - Vector2(0, 26)


# --- 흐름 ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _leaving:
		return
	player.move_vector = Vector2.ZERO if not _swap.is_empty() \
		else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_weather_layers.update(delta, _sky, Rect2(Vector2(-160, -90), Vector2(960, 540)))
	if _swap.is_empty() and player.position.distance_to(_exit) < 18.0 \
			and player.move_vector.y > 0.0:
		_leaving = true
		get_tree().change_scene_to_file.call_deferred(HOME_SCENE)
		return
	_focus()
	_text.queue_redraw()


## ★ 배지는 **옆에 섰을 때만** 붙는다 (§2.4 의 "원정 갈 수 있어요").
##   여섯 아이에게 한꺼번에 띄우면 안내가 아니라 소음이고, 안 띄우면
##   정원 초과가 곧 벤치로 읽힌다 — 둘 다 원칙 6에 걸린다.
func _focus() -> void:
	if not _swap.is_empty():
		_prompt.text = "누구랑 바꿀까요?"
		_prompt.position = Vector2(0, 258)
		_prompt.size.x = 640
		_prompt.visible = true
		_badge.visible = false
		return
	var near := _nearest()
	if near < 0:
		_prompt.visible = player.position.distance_to(_post) < REACH
		if _prompt.visible:
			_prompt.text = "자리를 하나 넓힐까요?" if Game.coins >= Game.SEAT_PRICE \
				else "재화를 더 모으면 자리를 넓힐 수 있어요"
			_prompt.position = Vector2(0, 244)
			_prompt.size.x = 640
		_badge.visible = false
		return
	var actor: Actor = guests[near]["actor"]
	var name := String(guests[near]["species"].get("name", ""))
	_prompt.text = "%s 집으로 데려가기" % Josa.을를(name)
	_prompt.position = Vector2(0, 244)
	_prompt.size.x = 640
	_prompt.visible = true
	# ★ 여기 있어도 **원정에 데려갈 수 있다.** 이 줄이 빠지면 쉼터가 벤치가 된다.
	_badge.text = "원정 갈 수 있어요"
	_badge.position = Vector2(actor.position.x - 60, actor.position.y - 44)
	_badge.size.x = 120
	_badge.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not event.is_pressed():
		return
	if not _swap.is_empty():
		_swap_input(event)
		return
	if event.is_action("interact") and Input.is_action_just_pressed("interact"):
		if player.position.distance_to(_post) < REACH:
			_buy_seat()
			return
		var near := _nearest()
		if near >= 0:
			_take_home(near)


## 가까이 있는 아이. 없으면 -1.
func _nearest() -> int:
	var best := -1
	var best_d := REACH
	for i in guests.size():
		var d: float = player.position.distance_to((guests[i]["actor"] as Actor).position)
		if d < best_d:
			best_d = d
			best = i
	return best


## ★ 자리가 있으면 그냥 데려간다. 없으면 **막지 않고 묻는다.**
func _take_home(index: int) -> void:
	if Game.home_members().size() < Game.seats():
		Game.move_to(int(guests[index]["uid"]), "home")
		var actor: Actor = guests[index]["actor"]
		actor.queue_free()
		guests.remove_at(index)
		_refresh()
		return
	_swap = Game.home_members().duplicate()
	_swap_at = 0
	_swap_for = index
	_build_swap_row()


func _buy_seat() -> void:
	if Game.buy_seat():
		_refresh()


# --- 누구랑 바꿀까요 ---------------------------------------------------------

## ★ 얼굴로 고른다. 이름을 나열하지 않는다 (§3.9 와 같은 이유).
func _build_swap_row() -> void:
	_clear_swap_row()
	var row := Node2D.new()
	row.name = "SwapRow"
	add_child(row)
	for i in _swap.size():
		var id := String(_swap[i]["species_id"])
		var face := Faces.of(_species_by_id.get(id, {}), schema)
		if face == null:
			continue
		var sprite := Faces.place(row, face, Vector2(96 + i * 68, 292), 2)
		sprite.modulate = Color(1, 1, 1, 1.0 if i == _swap_at else 0.45)


func _clear_swap_row() -> void:
	var row := get_node_or_null("SwapRow")
	if row != null:
		row.free()


func _swap_input(event: InputEvent) -> void:
	if event.is_action("interact_cancel"):
		_swap.clear()
		_swap_for = -1
		_clear_swap_row()
		return
	if event.is_action("move_left"):
		_swap_at = maxi(_swap_at - 1, 0)
		_build_swap_row()
	elif event.is_action("move_right"):
		_swap_at = mini(_swap_at + 1, _swap.size() - 1)
		_build_swap_row()
	elif event.is_action("interact"):
		_do_swap()


## 자리를 맞바꾼다. **아무도 사라지지 않는다** — 둘 다 계속 내 아이다.
func _do_swap() -> void:
	if _swap_for < 0 or _swap.is_empty():
		return
	var going_home := int(guests[_swap_for]["uid"])
	var coming_here := int(_swap[_swap_at]["uid"])
	Game.move_to(coming_here, "shelter")
	Game.move_to(going_home, "home")
	_swap.clear()
	_swap_for = -1
	_clear_swap_row()
	# 마당이 통째로 바뀌었으니 다시 세운다 — 부분 수선보다 이쪽이 틀릴 데가 없다.
	get_tree().reload_current_scene.call_deferred()


# --- 글자 ------------------------------------------------------------------

func _refresh() -> void:
	_text.queue_redraw()


func _text_draw() -> void:
	var here := Game.home_members().size()
	BitmapFont5.draw(_text, "SHELTER", Vector2(14, 14), Color(0.90, 0.88, 0.82, 0.85), 1)
	BitmapFont5.draw(_text, "HOME %d/%d" % [here, Game.seats()], Vector2(14, 26),
		Color(0.90, 0.88, 0.82, 0.70), 1)
	BitmapFont5.draw(_text, "COIN %d" % Game.coins, Vector2(14, 38),
		Color(0.90, 0.88, 0.82, 0.70), 1)
	BitmapFont5.draw(_text, "SEAT +1  %d" % Game.SEAT_PRICE,
		_post + Vector2(-24, -30), Color(0.92, 0.90, 0.84, 0.85), 1)
	BitmapFont5.draw(_text, "HOME", _exit + Vector2(-12, 12),
		Color(0.92, 0.90, 0.84, 0.85), 1)
