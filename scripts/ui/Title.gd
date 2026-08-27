## 타이틀 화면. (BRIEF §6.7 · ui/title.json)
##
## ★ **타이틀 화면 자체가 단서다.** 정지 일러스트를 그리지 않는다 —
##   켤 때마다 동물을 하나 고르고, **그 종이 사는 지형**을 깔고,
##   **그 종의 활동 시간대**로 색을 맞춘다. 글로 "얘는 숲에 살아요" 라고
##   알려주는 대신 숲을 깔고 그 위에 청설모를 세운다. 글을 못 읽어도 통한다.
##
## ⚠️ 짝이 어긋나면 틀린 것을 가르친다. 지형은 반드시 그 종의 habitat 에서 뽑는다.
extends Control

const DATA_PATH := "res://sprites/extracted/ui/title.json"
const ART_ROOT := "res://sprites/extracted/"
## 타이틀에서 고르면 **필드가 아니라 집으로 들어온다.** (BRIEF §2.7)
const HOME_SCENE := "res://scenes/home/Home.tscn"
const FIRST_SCENE := "res://scenes/ui/FirstMeeting.tscn"
const FIELD_SCENE := "res://scenes/field/Field.tscn"
const TUNING_PATH := "res://tuning/field_tuning.tres"
const ACTOR_SCENE := "res://scenes/actors/Actor.tscn"
const HANGUL_FONT := "res://fonts/Galmuri11.ttf"

## 데모 빌드인가. 켜면 첫 항목이 DEMO 가 되고 바로 필드로 들어간다.
## title.json 에 items_demo 가 생기면 그쪽을 쓴다.
## 데모 빌드인가. 켜면 첫 항목이 DEMO 가 되고 곧장 필드로 들어간다.
@export var demo_build := false

## 켜는 순간마다 배경이 달라야 하므로 시드를 고정하지 않는다.
@onready var _world: Node2D = $World
@onready var _ground: Node2D = $World/Ground
@onready var _props: Node2D = $World/Props
@onready var _dim: ColorRect = $Dim
@onready var _scrim: TextureRect = $Scrim
@onready var _mark: Sprite2D = $Mark
@onready var _grass: Sprite2D = $Grass
@onready var _menu: Control = $Menu
@onready var _label: Label = $CompanionName
@onready var _cursor: Sprite2D = $Cursor
@onready var _weather_layers: WeatherLayers = $World/Weather

enum State { MENU, CONFIRM, SETTING }

var data := {}
var schema: TagSchema = null
var tuning: FieldTuning = null
var terrain := TerrainMap.new()
## 배경이 단서인 화면이라 날씨도 그 지형의 날씨를 쓴다 —
## 비 오는 날 두꺼비가 앉아 있으면 그것만으로 하나를 배운다 (BRIEF §6.7)
var weather := WeatherSystem.new()
## 지금 배경이 낮에 가까운가(1) 밤에 가까운가(0). 햇살·빛줄기가 여기 묶인다.
var daylight := 1.0
var companion: Actor = null
var companion_name := ""
## 지형을 먼저 고른다. 종은 거기 사는 것 중에서 고른다.
var chosen_terrain := ""
## 후보가 들고 있는 동작 이름 (고양이는 special)
var chosen_animation := "idle"

var _rng := RandomNumberGenerator.new()
var _items: Array = []
var _selected := 0
var _state := State.MENU
var _confirm_lines: Array = []
var _confirm_yes := false        ## 기본 선택은 언제나 안전한 쪽
var _confirm_action := ""
var _idle := 0.0
var _selected_setting := 0
## 값은 숫자가 아니라 **칸 수**로 보인다 — 칸이 몇 개 찼는지가 곧 값이다.
const SETTING_STEPS := 8
var _settings := {"SOUND": 6, "MUSIC": 6, "FULLSCREEN": 0}
var _name_shown := false


func _ready() -> void:
	_rng.randomize()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) \
		if FileAccess.file_exists(DATA_PATH) else null
	data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}

	var result := DataLoader.load_all(false)
	if not result.ok:
		push_warning("타이틀: 데이터 로드 실패 — %s" % result.reject_reason)
	schema = result.schema
	tuning = load(TUNING_PATH)

	_pick_background(result.species)
	_place_marks()
	_build_menu()
	_setup_label()
	# Control 의 draw 시그널로 그린다 — 메뉴 하나 때문에 스크립트를 더 만들지 않는다
	_cursor.texture = _texture(String(data.get("menu", {}).get("cursor", "ui/cursor_paw.png")))
	weather.setup(schema, _rng, {chosen_terrain if not chosen_terrain.is_empty() else "초원": 1000})
	# 켤 때마다 날씨도 한 점을 골라 둔다. 타이틀에서는 흐르지 않고 그 자리에 머문다.
	weather._pick_target()
	weather.axes = weather.target.duplicate()
	_weather_layers.build()
	_scrim_setup()
	_load_settings()
	_menu.draw.connect(_menu_draw)
	_menu.queue_redraw()


# --- 배경 — 종이 지형과 시간대를 정한다 -------------------------------------

func _pick_background(species_by_id: Dictionary) -> void:
	var config := _pick_companion(species_by_id)
	if config.is_empty():
		return
	companion_name = String(config.get("name", ""))

	# 지형은 _pick_companion 이 먼저 정했다. 못 정했으면 그 종의 habitat 에서 뽑는다.
	var terrain_name := chosen_terrain
	if terrain_name.is_empty():
		var habitats: Array = config.get("habitat", ["초원"])
		terrain_name = String(habitats[_rng.randi_range(0, habitats.size() - 1)])

	var screen: Vector2i = Vector2i(data.get("canvas", [640, 360])[0], data.get("canvas", [640, 360])[1])
	var tiles := Vector2i(ceili(screen.x / float(tuning.tile_size)), ceili(screen.y / float(tuning.tile_size)))

	var view: FieldTuning = tuning.duplicate()
	view.map_size = tiles
	# 화면 전체를 한 지형으로 채운다 — 타이틀은 "이 종이 어디 사는가" 한 가지만 말한다
	view.forest_patches = 0
	view.water_patches = 0
	view.rock_patches = 0
	terrain.generate(tiles, view.tile_size, {}, _rng)
	terrain.fill(terrain_name)

	var background: Dictionary = data.get("background", {})
	var counts: Dictionary = background.get("prop_count", {})
	var count := int(counts.get(terrain_name, 40))
	view.prop_density = clampf(float(count) / float(tiles.x * tiles.y), 0.0, 0.5)

	_apply_daypart(String(config.get("activity", "주행성")), background)
	_ground.setup(view, terrain)
	PropScatter.scatter(_props, terrain, view, _rng)

	_dim.color = Color(0, 0, 0, 1.0 - float(background.get("dim", 0.58)))
	_spawn_companion(config, view)


## 동무 후보는 **title.json 의 candidates 를 그대로 읽는다.**
## 스프라이트가 있는지(available)는 아트 쪽이 아는 것이라, 엔진이 따로 판단하면
## 출처가 둘이 되어 언젠가 어긋난다.
##
## ★ 순서: **지형을 먼저 고르고 그 지형에 사는 종을 고른다.**
##   수달을 초원에 세우면 틀린 것을 가르친다.
func _pick_companion(species_by_id: Dictionary) -> Dictionary:
	var companion_data: Dictionary = data.get("companion", {})
	var available: Array = []
	for entry in companion_data.get("candidates", []):
		if bool(entry.get("available", false)) and species_by_id.has(String(entry.get("species", ""))):
			available.append(entry)
	if available.is_empty():
		var fallback: Dictionary = companion_data.get("fallback", {})
		return species_by_id.get(String(fallback.get("species", "dog")), {})

	# 지형 먼저 — 후보들이 사는 지형을 모으고 그중 하나를 고른 뒤, 거기 사는 종만 남긴다
	var terrains := {}
	for entry in available:
		for habitat in species_by_id[String(entry["species"])].get("habitat", []):
			terrains[String(habitat)] = true
	var terrain_names: Array = terrains.keys()
	chosen_terrain = String(terrain_names[_rng.randi_range(0, terrain_names.size() - 1)])

	var living: Array = []
	for entry in available:
		if chosen_terrain in species_by_id[String(entry["species"])].get("habitat", []):
			living.append(entry)
	var picked: Dictionary = living[_rng.randi_range(0, living.size() - 1)]
	# 고양이만 앉아서 앞발 든 프레임(special)이고 나머지는 idle 이다 — 후보가 들고 있다
	chosen_animation = String(picked.get("animation", "idle"))
	return species_by_id[String(picked["species"])]


## 시간대는 그 종의 activity 가 정한다 — 주행성 낮 · 야행성 밤 · 박명성 저녁.
func _apply_daypart(activity: String, background: Dictionary) -> void:
	var table: Dictionary = background.get("daypart", {})
	var t := float(table.get(activity, 0.3))
	var cycle: Array = DayPalette.cycle()
	if cycle.size() < 2:
		return
	# 0.3 이 낮, 0.86 이 밤이다 (title.json 의 daypart). 그 사이를 햇빛의 양으로 읽는다.
	daylight = clampf(1.0 - (t - 0.3) / 0.5, 0.0, 1.0)
	var position := t * (cycle.size() - 1)
	var index := clampi(int(floor(position)), 0, cycle.size() - 2)
	DayPalette.set_blend(String(cycle[index]), String(cycle[index + 1]), position - index)


func _spawn_companion(config: Dictionary, view: FieldTuning) -> void:
	var anchor: Array = data.get("companion", {}).get("anchor", [515, 159])
	var scale := float(data.get("companion", {}).get("scale", 2))
	companion = load(ACTOR_SCENE).instantiate()
	_world.add_child(companion)
	companion.setup(config, schema, view, _rng)
	companion.speed_tiles = 0.0
	companion.scale = Vector2.ONE * scale
	if chosen_animation == "special":
		companion.play_special = true
	# 앵커는 왼쪽 아래 — 종마다 키가 달라서 발을 기준으로 붙인다
	companion.position = Vector2(float(anchor[0]) + companion.canvas.x * scale * 0.5, float(anchor[1]))


# --- 글자 ------------------------------------------------------------------

func _place_marks() -> void:
	_mark.texture = _texture(String(data.get("title_mark", "")))
	_mark.position = _point(data.get("title_mark_at", [101, 46]))
	_grass.texture = _texture(String(data.get("title_grass", "")))
	_grass.position = _point(data.get("title_grass_at", [61, 46]))


## 이름만 적는다. 사는 곳은 배경이 말한다.
## 도감에 없어도 이름은 보여준다 — 미끼는 이름이다.
func _setup_label() -> void:
	var label_data: Dictionary = data.get("companion", {}).get("label", {})
	_label.position = _point(label_data.get("anchor", [475, 177]))
	_label.text = companion_name
	if ResourceLoader.exists(HANGUL_FONT):
		_label.add_theme_font_override("font", load(HANGUL_FONT))
	# 갈무리는 11px 로 찍고 정수배로만 키운다
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.modulate.a = 0.0


## 필드는 무늬가 많아 아래로 갈수록 어두워지는 스크림을 한 겹 깐다.
## 패널을 깔면 확실하지만 배경을 가려버린다. (BRIEF §6.7)
func _scrim_setup() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, Color(0, 0, 0, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0.35)
	texture.fill_to = Vector2(0, 1)
	texture.width = 8
	texture.height = 360
	_scrim.texture = texture


func _texture(relative: String) -> Texture2D:
	var path := ART_ROOT + relative
	return load(path) if not relative.is_empty() and ResourceLoader.exists(path) else null


func _point(at) -> Vector2:
	return Vector2(float(at[0]), float(at[1]))


# --- 메뉴 ------------------------------------------------------------------

## 첫 실행에는 CONTINUE 가 **아예 없다.** 회색으로 두지 않는다 —
## 고를 수 없는 것을 보여줄 이유가 없다. (BRIEF §6.7)
## 세이브는 아직 없으므로 지금은 언제나 첫 실행이다.
func _build_menu() -> void:
	var menu: Dictionary = data.get("menu", {})
	# ★ 이어할 것이 있으면 **CONTINUE 가 맨 위**다 (title.json 의 items_with_save).
	#   흔한 쪽이 위에 있어야 아이가 매번 고르지 않아도 된다 — 커서 기본값도 거기다.
	_items = menu.get("items_with_save" if _has_save() else "items_first_run",
		["NEW GAME", "EXIT"]).duplicate()
	if demo_build:
		# 데모 빌드에서는 첫 항목이 DEMO 다. 새 게임이 아니라 **필드 한 조각**을 보여주는 것이라
		# NEW GAME 이라고 적으면 없는 것을 약속하게 된다 (세이브도 사파리 층도 아직 없다).
		_items = menu.get("items_demo", ["DEMO", "SETTING", "EXIT"]).duplicate()
	_selected = 0


func _menu_draw() -> void:
	var menu: Dictionary = data.get("menu", {})
	var text_x := float(menu.get("text_x", 292))
	var cursor_x := float(menu.get("cursor_x", 250))
	var top := float(menu.get("top", 228))
	var gap := float(menu.get("gap", 29))
	var offset := float(menu.get("selected_offset_x", 6))

	for i in _items.size():
		var chosen: bool = (i == _selected and _state == State.MENU)
		var y := top + i * gap
		# 선택 표시는 밝기 + 오른쪽 6px. 둘 다 걸어야 작은 화면에서 읽힌다.
		var color := Color(1, 1, 1) if chosen else Color(0.62, 0.62, 0.60)
		BitmapFont5.draw(_menu, String(_items[i]),
			Vector2(text_x + (offset if chosen else 0.0), y), color, 2)
		if chosen:
			# 커서는 발자국이다. 이 게임이 흔적을 따라가는 게임이라는 걸 메뉴에서부터 말한다.
			# ⚠️ Control 의 _draw 안에서 draw_texture 를 쓰면 통짜 사각형이 된다 — 노드로 둔다.
			_cursor.position = Vector2(cursor_x, y - 2)
			_cursor.visible = _state == State.MENU

	BitmapFont5.draw(_menu, "RUN II", Vector2(8, 344), Color(0.72, 0.70, 0.66, 0.8), 1)
	BitmapFont5.draw(_menu, "V0.1 DEMO 1", Vector2(566, 344), Color(0.72, 0.70, 0.66, 0.8), 1)

	if _state == State.SETTING:
		_setting_draw()
	if _state == State.CONFIRM:
		_confirm_draw()


func _input_dir() -> int:
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		return 1
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		return -1
	return 0


func _process(delta: float) -> void:
	_idle += delta
	_weather_layers.update(delta, weather.axes, Rect2(Vector2(-160, -90), Vector2(960, 540)), daylight)
	_update_name_label()

	if _state == State.CONFIRM:
		_process_confirm()
		return
	if _state == State.SETTING:
		_process_setting()
		return

	var step := _input_dir()
	if step != 0:
		_selected = wrapi(_selected + step, 0, _items.size())
		_wake()
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
		_activate(String(_items[_selected]))


## 마우스에서만 얻는 정보를 만들지 않는다 — 호버하면 즉시, 가만히 있으면 몇 초 뒤에.
## 마우스는 더 빠를 뿐이다. (BRIEF §6.7)
func _update_name_label() -> void:
	var label_data: Dictionary = data.get("companion", {}).get("label", {})
	var idle_seconds := float(label_data.get("reveal", {}).get("idle_ms", 2000)) / 1000.0
	var hovered := companion != null and bool(label_data.get("reveal", {}).get("on_hover", true)) \
		and _hovering_companion()
	var show := hovered or _idle >= idle_seconds
	_name_shown = show
	_label.modulate.a = move_toward(_label.modulate.a, 1.0 if show else 0.0, get_process_delta_time() * 4.0)


func _hovering_companion() -> bool:
	if companion == null:
		return false
	var half := Vector2(companion.canvas) * companion.scale * 0.5
	var box := Rect2(companion.position - Vector2(half.x, half.y * 2.0), half * 2.0)
	return box.has_point(get_local_mouse_position())


func _wake() -> void:
	_idle = 0.0
	_menu.queue_redraw()


func _activate(item: String) -> void:
	match item:
		"NEW GAME":
			# 지울 세이브가 없으면 되돌릴 수 없는 것이 없다 — 묻지 않는다.
			if _has_save():
				_ask("new_game", item)
			else:
				_begin_new()
		"CONTINUE":
			get_tree().change_scene_to_file(
				HOME_SCENE if Game.tutorial_done else FIRST_SCENE)
		"DEMO":
			get_tree().change_scene_to_file(FIELD_SCENE)
		"SETTING":
			_state = State.SETTING
			_selected_setting = 0
			_wake()
		"EXIT":
			_ask("exit", item)
		_:
			_wake()


## 이어할 것이 있는가. **파일이 있으면 있다** — 첫 만남 도중에 껐어도 거기서 잇는다.
## ⚠️ 오토로드를 이름으로 쓰지 않는다: 타이틀이 먼저 뜰 수 있다.
func _has_save() -> bool:
	return FileAccess.file_exists(GameState.SAVE_PATH)


## 새 판은 **아무도 없이** 시작한다. 첫 강아지는 초대해서 얻는다 (§3.8).
func _begin_new() -> void:
	Game.start_new()
	get_tree().change_scene_to_file(FIRST_SCENE)


# --- 확인 창 — 되돌릴 수 없는 것에만 -----------------------------------------

func _ask(key: String, action: String) -> void:
	var confirm: Dictionary = data.get("confirm", {})
	_confirm_lines = confirm.get(key, ["계속할까요?"])
	_confirm_action = action
	_confirm_yes = false          # 기본 선택은 언제나 안전한 쪽
	_state = State.CONFIRM
	_wake()


func _process_confirm() -> void:
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left") \
		or Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
		_confirm_yes = not _confirm_yes
		_wake()
	if Input.is_action_just_pressed("interact_cancel") or Input.is_action_just_pressed("ui_cancel"):
		_state = State.MENU
		_wake()
		return
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
		var yes := _confirm_yes
		_state = State.MENU
		_wake()
		if not yes:
			return
		if _confirm_action == "EXIT":
			get_tree().quit()
		else:
			_begin_new()


## 문구는 한글이다 — 첫 플레이어가 EXIT 도 NEW GAME 도 못 읽는다.
func _confirm_draw() -> void:
	var box := Rect2(96, 122, 448, 116)
	_menu.draw_rect(Rect2(box.position - Vector2.ONE * 2, box.size + Vector2.ONE * 4), Color(0, 0, 0, 0.55))
	_menu.draw_rect(box, Color(0.09, 0.10, 0.13, 0.96))
	_menu.draw_rect(box, Color(0.85, 0.82, 0.74, 0.9), false, 2.0)

	var font: Font = load(HANGUL_FONT) if ResourceLoader.exists(HANGUL_FONT) else ThemeDB.fallback_font
	var y := box.position.y + 30.0
	for line in _confirm_lines:
		var width := font.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_menu.draw_string(font, Vector2(box.position.x + (box.size.x - width) * 0.5, y),
			String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.94, 0.92, 0.86))
		y += 18.0

	var choices := ["아니오", "예"]
	for i in choices.size():
		var chosen: bool = (i == 1) == _confirm_yes
		var at := Vector2(box.position.x + 120.0 + i * 190.0, box.end.y - 26.0)
		if chosen:
			_menu.draw_rect(Rect2(at + Vector2(-10, -12), Vector2(72, 20)), Color(1, 1, 1, 0.16))
		_menu.draw_string(font, at, choices[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1, 1, 1) if chosen else Color(0.6, 0.6, 0.58))


# --- 설정 — 셋뿐이다 (BRIEF §6.7) -------------------------------------------

const SETTINGS_PATH := "user://settings.cfg"


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key in _settings:
		_settings[key] = int(config.get_value("setting", key, _settings[key]))
	_apply_fullscreen()


func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in _settings:
		config.set_value("setting", key, _settings[key])
	config.save(SETTINGS_PATH)


func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN \
		if _settings["FULLSCREEN"] > 0 else DisplayServer.WINDOW_MODE_WINDOWED)


func _process_setting() -> void:
	var keys: Array = _settings.keys()
	var step := _input_dir()
	if step != 0:
		_selected_setting = wrapi(_selected_setting + step, 0, keys.size())
		_wake()
	var key: String = keys[_selected_setting]
	var delta := 0
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
		delta = 1
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left"):
		delta = -1
	if delta != 0:
		# 전체화면은 켜고 끄는 것이라 칸이 하나다
		var top: int = 1 if key == "FULLSCREEN" else SETTING_STEPS
		_settings[key] = clampi(_settings[key] + delta, 0, top)
		if key == "FULLSCREEN":
			_apply_fullscreen()
		_save_settings()
		_wake()
	if Input.is_action_just_pressed("interact_cancel") or Input.is_action_just_pressed("ui_cancel") \
		or Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
		_state = State.MENU
		_wake()


## 하위 화면은 전체를 한 겹 더 누른다.
func _setting_draw() -> void:
	_menu.draw_rect(Rect2(0, 0, 640, 360), Color(0, 0, 0, 0.5))
	var keys: Array = _settings.keys()
	var top := 132.0
	for i in keys.size():
		var key: String = keys[i]
		var chosen: bool = i == _selected_setting
		var y := top + i * 34.0
		var color := Color(1, 1, 1) if chosen else Color(0.62, 0.62, 0.60)
		BitmapFont5.draw(_menu, key, Vector2(176 + (6.0 if chosen else 0.0), y), color, 2)
		var steps: int = 1 if key == "FULLSCREEN" else SETTING_STEPS
		for slot in steps:
			var filled: bool = slot < _settings[key]
			var box := Rect2(352 + slot * 14, y, 10, 14)
			_menu.draw_rect(box, color if filled else Color(0, 0, 0, 0.45))
			_menu.draw_rect(box, color, false, 1.0)
	BitmapFont5.draw(_menu, "- BACK -", Vector2(272, top + keys.size() * 34.0 + 18.0),
		Color(0.72, 0.70, 0.66), 2)
