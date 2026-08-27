## Demo 1 완료 조건 자동 점검. (DEMO-SPEC §4)
##
##   godot --headless --script tools/smoke_test.gd
##
## 눈으로 봐야 아는 것(재미·바운스의 느낌)은 여기서 못 잡는다.
## 여기서 잡는 것은 "구조가 사양대로인가" 뿐이다.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	Engine.time_scale = 10.0  # 게이지 3초를 실시간으로 기다리지 않는다

	var result := DataLoader.load_all(true)
	_check("데이터 로드", result.ok, result.reject_reason)

	var field: Node2D = load("res://scenes/field/Field.tscn").instantiate()
	root.add_child(field)
	await process_frame
	await process_frame
	# Field 는 매 프레임 입력으로 move_vector 를 덮어쓴다. 테스트가 직접 몰기 위해 끈다.
	field.set_process(false)
	# Field 가 마지막으로 넣어둔 추종 벡터가 남아 동료가 계속 걸어가지 않도록 비운다.
	for companion in field.companions:
		companion.move_vector = Vector2.ZERO
	field.player.move_vector = Vector2.ZERO

	await _test_facing_and_bounce(field)
	await _test_guide_contrast(field)
	await _test_field_sim(field)
	_test_gauge_factor(field)
	await _test_gauge_uninterruptible(field)

	await _test_reveal(field)
	await _test_animation_set(field)
	await _test_art_wiring(field)
	await _test_home()
	await _test_boot()
	await _test_sense_reach(field)
	await _test_terrain_walk(field)
	await _test_weather(field)
	await _test_presence(field)
	await _test_individuals(field)
	await _test_eyeshine(field)
	await _test_puff(field)
	await _test_invite(field)

	print("")
	print("=== 통과 %d / 실패 %d ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


## 북향 얼굴 숨김 + 바운스가 노드 Y이고 정수인지 (DEMO-SPEC §3.1, §3.2)
func _test_facing_and_bounce(field) -> void:
	var player: Actor = field.player
	var body: Node2D = player.get_node("Body")
	var eye: Sprite2D = body.get_node("Eye")
	var body_sprite: AnimatedSprite2D = body.get_node("BodySprite")

	var eye_offset_before := eye.position

	player.move_vector = Vector2.DOWN
	await process_frame
	_check("남향에서 얼굴이 보인다", eye.visible)

	player.move_vector = Vector2.UP
	await process_frame
	_check("북향에서 눈·입이 숨는다", not eye.visible and not body.get_node("Mouth").visible)

	player.move_vector = Vector2.RIGHT
	var seen := {}
	var non_integer := false
	for i in 40:
		await process_frame
		seen[body.position.y] = true
		if body.position.y != floorf(body.position.y):
			non_integer = true
	_check("바운스가 Body 노드 Y로 일어난다", seen.size() >= 2, "관측된 Y: %s" % [seen.keys()])
	_check("Body.position.y 가 정수 픽셀", not non_integer, "관측된 Y: %s" % [seen.keys()])
	_check("스프라이트는 제자리 — 얼굴 앵커가 프레임마다 흔들리지 않는다",
		eye.position == eye_offset_before and body_sprite.position == player.canvas_offset)

	# 접지선이 캔버스 맨 아래가 아닌 그림이 있다 — 그대로 놓으면 그림자 위에 뜬다
	var ground: Dictionary = SpriteLibrary.ground_info(
		player.species_id, body_sprite.sprite_frames, player.canvas)
	_check("발끝이 Actor 원점에 온다 (그림자와 붙는다)",
		is_equal_approx(player.canvas_offset.y, -(player.canvas.y - int(ground["gap"]))),
		"오프셋 %.0f / 캔버스 %d / 빈 줄 %d" % [player.canvas_offset.y, player.canvas.y, ground["gap"]])
	_check("그림자 폭이 발 폭을 따른다",
		player.get_node("Shadow").texture.get_width() == maxi(int(ground["foot_width"]), 4),
		"그림자 %d / 발 %d" % [player.get_node("Shadow").texture.get_width(), ground["foot_width"]])

	player.move_vector = Vector2.ZERO
	await process_frame
	await process_frame
	_check("정지하면 바운스가 0으로 돌아온다", body.position.y == 0.0)

	# 대기는 좌우 2방향뿐 — 정지 중에 북/남을 보면 측면 몸통에 정면 눈이 얹힌다 (BRIEF §4.5)
	player.look_direction = Vector2.UP
	await process_frame
	_check("정지 중 위를 봐도 방향은 좌우로 유지된다",
		player.facing == "east" or player.facing == "west", player.facing)
	_check("정지 중에는 얼굴이 사라지지 않는다", eye.visible)
	player.look_direction = Vector2(-1, -3)
	await process_frame
	_check("정지 중 왼쪽 위를 보면 서향이 된다", player.facing == "west", player.facing)
	player.look_direction = Vector2.ZERO
	await process_frame

	# 눈은 공용이 원칙이고, 어느 쪽을 볼지는 데이터의 eye_style 이 정한다.
	# 폴더가 있느냐로 정하면 종 폴더가 다시 생성되는 순간 조용히 그쪽으로 끌려간다.
	var round_eye := SpriteLibrary.eye_texture("cat", "front", "기본", "round")
	var shared_eye := SpriteLibrary.eye_texture("dog", "front", "기본", "round")
	_check("eye_style 이 round 면 종 폴더가 있어도 공용 눈을 쓴다",
		round_eye != null and round_eye == shared_eye,
		"" if round_eye == null else round_eye.resource_path)
	var big_eye := SpriteLibrary.eye_texture("cat", "front", "기본", "big")
	_check("round 가 아니면 종 폴더를 먼저 본다",
		big_eye != null and big_eye != shared_eye,
		"" if big_eye == null else big_eye.resource_path)

	var emote: Sprite2D = body.get_node("Emote")
	player.show_sense_icon("후각")
	await process_frame
	var body_top := player.global_position.y - player.canvas.y
	_check("감각 아이콘이 머리 위에 붙는다",
		emote.global_position.y + emote.texture.get_height() <= body_top + 1.0,
		"아이콘 하단 %.1f / 몸통 상단 %.1f" % [
			emote.global_position.y + emote.texture.get_height(), body_top])
	player.hide_sense_icon()
	player.position = field.player.bounds.size * 0.5


## ★ 이 데모의 핵심 대비 — 코드에 종 id 가 없어야 이렇게 나온다 (DEMO-SPEC §3.4)
func _test_guide_contrast(field) -> void:
	var schema: TagSchema = field.schema
	var expected := {
		"dog": {"squirrel": false, "raccoon_dog": true, "otter": true, "water_deer": false},
		"cat": {"squirrel": true, "raccoon_dog": true, "otter": true, "water_deer": true},
	}
	var ok := true
	var detail := PackedStringArray()
	for companion in field.companions:
		if not expected.has(companion.species_id):
			continue
		for target_id in expected[companion.species_id]:
			var target: Dictionary = _species_of(field, target_id)
			var detected := false
			for trait_name in target.get("traits", []):
				if schema.sense_for_trait(String(trait_name)) in companion.senses:
					detected = true
			if detected != expected[companion.species_id][target_id]:
				ok = false
				detail.append("%s→%s" % [companion.species_id, target_id])
	_check("개는 청설모·고라니를 못 찾고 고양이는 찾는다", ok, ", ".join(detail))

	# 그리고 그 판정이 GuideSystem 을 실제로 통과하는지
	var animal: FieldSim.WildAnimal = _find_animal(field, "squirrel")
	var dog: Actor = _find_companion(field, "dog")
	var cat: Actor = _find_companion(field, "cat")
	animal.position = dog.position + Vector2(16, 0)
	var hit_with_dog = field.guide.update([dog], [animal])
	animal.position = cat.position + Vector2(16, 0)
	var hit_with_cat = field.guide.update([cat], [animal])
	_check("붙어 있어도 개는 청설모에 반응하지 않는다", hit_with_dog == null)
	_check("감지가 없으면 특징 동작도 꺼진다", not dog.play_special)
	_check("유도 중인 동료는 특징 동작을 재생한다", cat.play_special)
	_check("고양이는 같은 청설모에 시야로 반응한다",
		hit_with_cat != null and hit_with_cat.sense == "시야",
		"" if hit_with_cat == null else hit_with_cat.sense)
	await process_frame


## 얕은 시뮬 ↔ 풀 AI 승격 (DEMO-SPEC §3.3)
func _test_field_sim(field) -> void:
	var animal: FieldSim.WildAnimal = field.sim.animals[0]
	var tuning: FieldTuning = field.tuning
	field.player.position = field.player.bounds.size * 0.5
	var far: Vector2 = field.player.position + Vector2(tuning.activation_radius + 20, 0) * tuning.tile_size
	animal.position = far
	field.sim.update(0.016, field.player.position)
	_check("멀리 있으면 노드 없이 얕은 시뮬", not animal.is_active())
	var before := animal.position
	field.sim.update(0.5, field.player.position)
	_check("노드가 없어도 위치는 계속 움직인다", animal.position != before)

	animal.position = field.player.position + Vector2(8, 0)
	field.sim.update(0.016, field.player.position)
	_check("가까워지면 풀 AI 로 승격된다", animal.is_active())


## 상성 계수 (DEMO-SPEC §3.5)
func _test_gauge_factor(field) -> void:
	var tuning: FieldTuning = field.tuning
	var dog: Actor = _find_companion(field, "dog")
	dog.charm = 1.0
	var squirrel: Dictionary = _species_of(field, "squirrel")   # 초식 · 주행성
	var otter: Dictionary = _species_of(field, "otter")         # 육식 · 박명성

	var matched: Dictionary = Gauge.compute_factor(squirrel, dog, "낮", tuning)
	_check("상성이 맞으면 계수 1.0", is_equal_approx(matched["factor"], 1.0),
		"%.2f — %s" % [matched["factor"], ", ".join(matched["reasons"])])

	var night: Dictionary = Gauge.compute_factor(squirrel, dog, "밤", tuning)
	_check("시간대가 어긋나면 계수가 커진다", night["factor"] > matched["factor"] * 1.4,
		"%.2f" % night["factor"])

	var herbivore_lead := _find_companion(field, "cat")
	herbivore_lead.diet = "초식"   # 초식 동료를 아직 안 만들었으므로 값만 바꿔 본다
	herbivore_lead.charm = 1.0
	var clash: Dictionary = Gauge.compute_factor(otter, herbivore_lead, "여명", tuning)
	_check("먹이 유형이 어긋나면 계수가 커진다", clash["factor"] > 1.4,
		"%.2f — %s" % [clash["factor"], ", ".join(clash["reasons"])])

	herbivore_lead.charm = 2.0
	var charming: Dictionary = Gauge.compute_factor(otter, herbivore_lead, "여명", tuning)
	_check("매력이 높으면 게이지가 짧아진다", charming["factor"] < clash["factor"],
		"%.2f < %.2f" % [charming["factor"], clash["factor"]])
	herbivore_lead.diet = "육식"


## ★ 절대 규칙: 게이지는 중간에 끊기지 않는다 (DEMO-SPEC §3.5)
func _test_gauge_uninterruptible(field) -> void:
	var animal: FieldSim.WildAnimal = _find_animal(field, "raccoon_dog")
	var dog: Actor = _find_companion(field, "dog")
	var gauge: Gauge = field.gauge
	gauge.cancel()
	animal.invite_progress = 0.0
	gauge.start(animal, dog, "낮")
	_check("게이지가 시작된다", gauge.active)

	# 붙어 있으면 끝까지 찬다. 방해 요소도 실패 조건도 없다.
	animal.invite_progress = 0.0
	var completed := false
	for i in 400:
		if gauge.update(0.02, 0.0):
			completed = true
			break
		if not gauge.active:
			break
	_check("붙어 있으면 게이지가 끝까지 찬다", completed)

	# ★ 점유 시간 게이지다 — 자리를 비우면 차오르지 않는다.
	#   다만 **멈출 뿐 줄지 않는다.** 되돌릴 수 없는 실패를 만들지 않는다(원칙 2).
	gauge.cancel()
	animal.invite_progress = 0.0   # 앞 시나리오가 채운 것을 물려받지 않게
	gauge.start(animal, dog, "낮")
	for i in 20:
		gauge.update(0.02, 0.0)
	var held: float = gauge.progress
	var far: float = field.tuning.hold_radius * field.tuning.tile_size + 40.0
	for i in 60:
		gauge.update(0.02, far)
	_check("멀어지면 게이지가 멈춘다", gauge.paused and is_equal_approx(gauge.progress, held),
		"%.3f → %.3f" % [held, gauge.progress])
	_check("멀어져도 게이지가 줄지는 않는다", gauge.progress >= held - 0.001)
	_check("멀어져도 취소되지 않는다 — 실패가 아니다", gauge.active)
	gauge.update(0.02, 0.0)
	_check("돌아오면 이어서 찬다", not gauge.paused and gauge.progress > held)
	var finished := false
	for i in 400:
		if gauge.update(0.02, 0.0):
			finished = true
			break
	_check("결국 완료된다 — 시작한 게이지는 반드시 끝난다", finished)

	gauge.cancel()
	animal.invite_progress = 0.0
	gauge.start(animal, dog, "낮")
	gauge.update(0.02)
	gauge.cancel()
	_check("취소는 명시적으로 눌렀을 때만 된다", not gauge.active and gauge.progress == 0.0)

	# ★ 쏟은 시간은 **개체가** 들고 있다. 다른 아이에게 갔다 와도 이어서 찬다.
	var other: FieldSim.WildAnimal = _find_animal(field, "otter")
	gauge.close()
	animal.invite_progress = 0.0
	gauge.start(animal, dog, "낮")
	for i in 15:
		gauge.update(0.02, 0.0)
	var kept: float = animal.invite_progress
	_check("쏟은 시간이 그 개체에 남는다", kept > 0.0, "%.3f" % kept)

	gauge.close()
	gauge.start(other, dog, "낮")
	_check("다른 아이에게 가면 게이지가 처음부터", is_zero_approx(gauge.progress))
	_check("먼저 아이의 시간은 그대로다", is_equal_approx(animal.invite_progress, kept))

	gauge.close()
	gauge.start(animal, dog, "낮")
	_check("돌아오면 쏟다 만 자리에서 이어 찬다", is_equal_approx(gauge.progress, kept),
		"%.3f vs %.3f" % [gauge.progress, kept])
	gauge.close()
	await process_frame


## ★ 감각이 없으면 멀리 있는 동물은 그냥 안 보인다 (BRIEF §3.3)
func _test_reveal(field) -> void:
	var tuning: FieldTuning = field.tuning
	field.player.position = field.player.bounds.size * 0.5
	var dog: Actor = _find_companion(field, "dog")
	var cat: Actor = _find_companion(field, "cat")

	# 후각(냄새강함) + 시야(발자국) 둘 다 가진 대상을, 눈으로 볼 수 있는 거리 밖에 둔다.
	# 지형이 시야를 깎으므로 초원 위에 세운다 — 지형 효과는 따로 검사한다.
	var animal: FieldSim.WildAnimal = _find_animal(field, "raccoon_dog")
	animal.position = _find_terrain_point(field, "초원")
	var gap := Vector2(tuning.reveal_radius * tuning.tile_size + 40, 0)
	field.player.position = animal.position - gap
	dog.position = field.player.position
	cat.position = field.player.position
	field.sim.update(0.016, field.player.position)
	if not animal.is_active():
		_check("노출 테스트 준비 — 대상이 활성화된다", false)
		return

	field.guide.update([], [animal])
	var clues: Array = field._apply_reveal()
	_check("동료가 없으면 멀리 있는 동물은 안 보인다", not animal.actor.visible and clues.is_empty())

	field.guide.update([dog], [animal])
	clues = field._apply_reveal()
	_check("후각으로 잡으면 몸은 안 보이고 단서만 뜬다",
		not animal.actor.visible and clues.size() == 1 and clues[0]["sense"] == "후각",
		"보임=%s 단서=%d" % [animal.actor.visible, clues.size()])

	field.guide.update([cat], [animal])
	clues = field._apply_reveal()
	_check("시야로 잡으면 멀리서도 몸이 보인다", animal.actor.visible and clues.is_empty())

	# 감각이 하나도 없어도 코앞이면 보인다
	animal.position = field.player.position + Vector2(8, 0)
	field.guide.update([], [animal])
	clues = field._apply_reveal()
	_check("감각이 없어도 가까이 가면 보인다", animal.actor.visible and clues.is_empty())
	await process_frame


## 집 — 사파리 층. 설계 규칙이 코드에서 유지되는지만 본다. (BRIEF §2.7)
func _test_home() -> void:
	var home: Control = load("res://scenes/home/Home.tscn").instantiate()
	root.add_child(home)
	await process_frame
	await process_frame

	_check("마당에 사물이 놓인다", home.objects.size() > 0, str(home.objects.size()))

	# ★ 사물은 새 열거형을 만들지 않는다. for_tags 의 값이 전부 tags.json 에 이미 있다.
	var known := {}
	for field_name in ["temperament", "diet", "behavior_tags", "habitat", "social", "noise"]:
		for value in home.schema.allowed(field_name):
			known[String(value)] = true
	var invented := PackedStringArray()
	for entry in home.objects:
		for tag in entry["for_tags"]:
			if not known.has(String(tag)):
				invented.append("%s:%s" % [entry["name"], tag])
	_check("사물이 새 태그를 만들지 않는다", invented.is_empty(), ", ".join(invented))

	# for_tags 가 비면 누구나, 아니면 하나라도 겹치는 동물이 쓴다
	var open_to_all := 0
	var matched := 0
	for entry in home.objects:
		if entry["for_tags"].is_empty():
			open_to_all += 1
		for resident in home.residents:
			if resident.uses(entry["for_tags"]):
				matched += 1
	_check("태그 없는 사물은 누구나 쓴다", open_to_all > 0)
	_check("태그가 맞는 동물이 사물을 쓴다", matched > 0, str(matched))

	# ★ HUD 는 재화와 자리 둘뿐이다. 배고픔·청결·기분 게이지가 생기면 집이 할 일 목록이 된다.
	var labels := 0
	for child in home.get_node("Hud").get_children():
		if child is Label:
			labels += 1
	_check("HUD 는 두 줄뿐이다 (재화·자리)", labels == 2, str(labels))

	# ★ 사물이 새 동작을 요구하지 않는다 — 재생하는 것은 그 동물의 기존 특징 동작뿐
	var resident: Resident = home.residents[0]
	resident.target = home.objects[0]
	resident._playing = true
	resident._timer = 1.0
	resident.update(0.016, home.objects, home.yard.yard, RandomNumberGenerator.new())
	_check("사물 옆에서 그 동물의 기존 동작이 재생된다", resident.actor.play_special)
	_check("사물이 자기 동작을 들고 있지 않다", not home.objects[0].has("animation"))

	# ★ 울타리는 막는다. 사각형으로 자르면 아래쪽 울타리를 아무 데서나 통과한다.
	var below := Vector2(home.yard.yard.position.x + 40, home.yard.gate.y + 8)
	var pushed: Vector2 = home.yard.confine_walker(below, below, home.yard.gate.y + 12.0)
	_check("대문이 아닌 곳에서는 울타리를 못 지나간다",
		pushed.y <= home.yard.yard.end.y + 0.01, "%s → %s" % [below, pushed])
	var at_gate := Vector2(home.yard.gate.x, home.yard.gate.y + 8)
	var through: Vector2 = home.yard.confine_walker(at_gate, at_gate, home.yard.gate.y + 12.0)
	_check("대문 앞에서는 나갈 수 있다", through.y > home.yard.yard.end.y, str(through))
	var wanderer: Vector2 = home.yard.confine_resident(below, below)
	_check("동물은 대문으로도 못 나간다", wanderer.y <= home.yard.yard.end.y + 0.01, str(wanderer))

	_check("대문이 마당 아래 한가운데에 있다",
		absf(home.yard.gate.x - 320.0) < 24.0 and home.yard.gate.y > home.yard.yard.end.y)
	home.queue_free()
	await process_frame


## 부팅 화면 — 제작사 로고. 씬을 바꾸는 코드라 트리에 넣지 않고 계약만 확인한다.
func _species_habitats(title) -> Array:
	for id in DataLoader.load_all(false).species:
		var species: Dictionary = DataLoader.load_all(false).species[id]
		if String(species.get("name", "")) == title.companion_name:
			return species.get("habitat", [])
	return ["초원", "숲", "물가", "바위"]


func _test_boot() -> void:
	_check("로고 그림이 있다",
		ResourceLoader.exists("res://sprites/extracted/ui/logo_screen.png"))
	_check("게임이 부팅 화면부터 뜬다",
		String(ProjectSettings.get_setting("application/run/main_scene", ""))
			== "res://scenes/ui/Boot.tscn")
	var boot: Control = load("res://scenes/ui/Boot.tscn").instantiate()
	# "아이는 이 화면을 수백 번 본다" — 건너뛸 수 있어야 하고, 길면 안 된다
	_check("아무 키나 누르면 건너뛴다", boot.has_method("_unhandled_input"))
	# json 의 시퀀스 + 머무는 시간 + 페이드. 길면 두 번째부터 벌이 된다.
	var timing: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://sprites/extracted/ui/logo.json")).get("timing", {})
	var total: float = int(timing.get("frames", 32)) * float(timing.get("frame_ms", 80)) / 1000.0 \
		+ boot.hold_after + boot.fade_out
	_check("로고가 4초를 넘지 않는다", total <= 4.0, "%.1f초" % total)
	_check("로고 조각과 좌표가 다 있다",
		ResourceLoader.exists("res://sprites/extracted/ui/logo_paw_big.png")
		and ResourceLoader.exists("res://sprites/extracted/ui/logo_paw_small.png")
		and not timing.is_empty())
	boot.free()

	# 타이틀 — 첫 실행에는 CONTINUE 가 아예 없다 (BRIEF §6.7)
	var title: Control = load("res://scenes/ui/Title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	_check("타이틀 메뉴에 CONTINUE 가 없다 (세이브가 없으므로)",
		not ("CONTINUE" in title._items), str(title._items))
	# 데모 빌드는 새 게임이 아니라 필드 한 조각을 보여준다 — 없는 것을 약속하지 않는다.
	# 데모가 아니면 NEW GAME 이고, 들어가는 곳은 필드가 아니라 집이다 (BRIEF §2.7).
	_check("데모 여부에 따라 첫 항목이 갈린다",
		title._items[0] == ("DEMO" if title.demo_build else "NEW GAME"),
		"demo=%s %s" % [title.demo_build, title._items])
	_check("타이틀에서 고르면 집으로 들어간다",
		ResourceLoader.exists(title.HOME_SCENE))
	_check("동무 후보는 title.json 의 candidates 에서 온다",
		not title.data.get("companion", {}).get("candidates", []).is_empty())
	_check("타이틀이 종의 habitat 에서 지형을 뽑는다",
		title.terrain.at_tile(Vector2i(2, 2)) in _species_habitats(title))
	_check("확인 창의 기본 선택은 안전한 쪽",
		not title._confirm_yes)
	title.queue_free()


## 아트 인계 — 지형 타일 · 프롭 · 단서 마커 · 밤낮 (HANDOFF §2)
func _test_art_wiring(field) -> void:
	var ground: Node2D = field.get_node("Ground")
	var loaded: Dictionary = ground._sheets
	_check("지형 4종이 모두 타일 그림을 갖는다", loaded.size() == 4, str(loaded.keys()))
	_check("변형 개수가 이미지 폭에서 나온다",
		ground._variants.get("초원", 0) == 6 and ground._variants.get("바위", 0) == 1,
		str(ground._variants))

	# 같은 지형이 가로로 이어져도 변형이 한 종류로 몰리면 줄무늬가 된다
	var seen := {}
	for x in 24:
		seen[Ground._variant_for(x, 7, 6)] = true
	_check("변형이 좌표 해시로 흩어진다", seen.size() >= 4, "한 줄에서 %d종" % seen.size())

	_check("프롭이 놓였다", field._props.size() > 0, str(field._props.size()))
	var misplaced := PackedStringArray()
	for entry in field._props:
		var root: Node2D = entry["sprite"].get_parent()
		var terrain: String = field.terrain.at_world(root.position)
		if not (String(entry["name"]) in SpriteLibrary.props_for_terrain(terrain)):
			misplaced.append("%s@%s" % [entry["name"], terrain])
	_check("프롭이 어울리는 지형 위에만 놓인다", misplaced.is_empty(),
		", ".join(misplaced.slice(0, 4)))

	# 단서 마커는 월드 노드다 — 화면 레이어에 그리면 배율·틴트가 따로 논다
	field._sync_clue_markers([{"position": Vector2(100, 100), "sense": "후각", "clue": ""}])
	_check("단서 마커가 월드에 뜬다",
		field._clue_markers.size() >= 1 and field._clue_markers[0].visible
		and field._clue_markers[0].texture != null)
	field._sync_clue_markers([])
	_check("단서가 사라지면 마커도 꺼진다", not field._clue_markers[0].visible)

	# 밤낮
	if DayPalette.has_data():
		field._apply_daypart("낮")
		field._advance_palette(10.0)
		var day_tint := DayPalette.tint()
		field._apply_daypart("밤")
		field._advance_palette(10.0)
		var night_tint := DayPalette.tint()
		_check("밤이면 화면 틴트가 어두워진다", night_tint.r < day_tint.r and night_tint.b >= day_tint.b * 0.9,
			"%s → %s" % [day_tint, night_tint])
		_check("밤 지형 타일이 낮과 다른 텍스처가 된다",
			ground._sheets.get("초원") != null and DayPalette.texture_for(
				"res://sprites/extracted/terrain/초원.png") != load("res://sprites/extracted/terrain/초원.png"))
		field._apply_daypart("낮")
		field._advance_palette(10.0)
	await process_frame


## 그린 종이든 색 사각형이든 애니메이션 집합이 같아야 한다.
## 하나라도 비면 그 동작에 들어가는 순간 매 프레임 에러가 난다.
func _test_animation_set(field) -> void:
	var missing := PackedStringArray()
	for actor in [field.player] + field.companions:
		for anim in SpriteLibrary.ANIMATIONS:
			if not actor.get_node("Body/BodySprite").sprite_frames.has_animation(anim):
				missing.append("%s.%s" % [actor.species_id, anim])
	for animal in field.sim.active_animals():
		for anim in SpriteLibrary.ANIMATIONS:
			if not animal.actor.get_node("Body/BodySprite").sprite_frames.has_animation(anim):
				missing.append("%s.%s" % [animal.actor.species_id, anim])
	_check("모든 액터가 애니메이션 집합을 빠짐없이 갖는다", missing.is_empty(), ", ".join(missing))

	# 유도 중 특징 동작을 켜도 색 사각형 액터가 터지지 않는다.
	# 실제 종에서 고르면 그 종에 그림이 생기는 순간 검사가 사라진다 —
	# 실제로 모든 종에 idle 이 들어오면서 그렇게 사라졌다. 없는 종을 지어서 고정한다.
	var nobody := {
		"id": "_그림없는종", "name": "없음", "diet": "잡식", "activity": "주행성",
		"size_class": "중", "senses": [], "traits": [], "habitat": [],
		"stats_range": {}, "sprite_set": {"eye_style": "round", "head_anchor": [16, 3]},
	}
	var placeholder: Actor = field.actor_scene.instantiate()
	field.add_child(placeholder)
	placeholder.setup(nobody, field.schema, field.tuning, RandomNumberGenerator.new())
	_check("그림 없는 종은 색 사각형으로 떨어진다", not placeholder.has_drawn_art)
	placeholder.play_special = true
	placeholder.move_vector = Vector2.ZERO
	await process_frame
	_check("그림 없는 액터도 특징 동작을 재생할 수 있다",
		placeholder.get_node("Body/BodySprite").animation == "special")
	placeholder.queue_free()
	await process_frame


## ★ 감각마다 닿는 거리가 다르다 — 시간대와 지형까지 (BRIEF §3.3)
func _test_sense_reach(field) -> void:
	var dog: Actor = _find_companion(field, "dog")
	var cat: Actor = _find_companion(field, "cat")

	field._apply_daypart("낮")
	var nose_day: float = field.guide.reach_tiles(dog, "후각")
	var eye_day: float = field.guide.reach_tiles(cat, "시야")
	_check("후각이 시야보다 훨씬 멀리 간다", nose_day > eye_day * 1.8,
		"후각 %.1f타일 / 시야 %.1f타일" % [nose_day, eye_day])

	field._apply_daypart("밤")
	var nose_night: float = field.guide.reach_tiles(dog, "후각")
	var eye_night: float = field.guide.reach_tiles(cat, "시야")
	_check("밤에는 시야가 크게 줄어든다", eye_night < eye_day * 0.5,
		"낮 %.1f → 밤 %.1f" % [eye_day, eye_night])
	_check("밤이어도 후각은 그대로다", is_equal_approx(nose_night, nose_day))
	field._apply_daypart("낮")

	# 지형은 대상이 어디에 서 있느냐로 걸린다
	var animal: FieldSim.WildAnimal = _find_animal(field, "squirrel")  # 나무흔적 → 시야
	var open_reach: float = field.guide.reach(cat, "시야")
	var forest := _find_terrain_point(field, "숲")
	var meadow := _find_terrain_point(field, "초원")
	if forest == Vector2.INF or meadow == Vector2.INF:
		_check("지형 테스트 준비 — 숲과 초원이 생성된다", false)
		return

	animal.position = meadow
	cat.position = meadow + Vector2(open_reach * 0.7, 0)
	field.guide.update([cat], [animal])
	_check("초원에 선 대상은 그 거리에서 시야에 잡힌다",
		"시야" in field.guide.detected_senses(animal))

	animal.position = forest
	cat.position = forest + Vector2(open_reach * 0.7, 0)
	field.guide.update([cat], [animal])
	_check("같은 거리라도 숲에 서 있으면 시야에 안 잡힌다",
		field.guide.detected_senses(animal).is_empty())

	# 그리고 그 자리에서 코는 여전히 닿는다 — 이것이 개를 데려갈 이유다
	var smelly: FieldSim.WildAnimal = _find_animal(field, "raccoon_dog")
	smelly.position = forest
	dog.position = forest + Vector2(open_reach * 0.7, 0)
	field.guide.update([dog], [smelly])
	_check("숲에 있어도 후각은 닿는다", "후각" in field.guide.detected_senses(smelly))

	# 승격 거리가 감각보다 좁으면 감각이 헛돈다
	var widest := 0.0
	for companion in field.companions:
		for sense in companion.senses:
			widest = maxf(widest, field.guide.max_reach(companion, String(sense)))
	_check("풀 AI 승격 거리가 가장 먼 감각을 덮는다", field._promotion_px >= widest,
		"승격 %.0fpx / 감각 %.0fpx" % [field._promotion_px, widest])
	await process_frame


## ★ 갈 수 있는 지형 — 물가·바위는 그 지형이 habitat 인 동물만 (사용자 판단)
func _test_terrain_walk(field) -> void:
	var schema: TagSchema = field.schema
	var map: TerrainMap = field.terrain
	_check("초원·숲은 누구나 지나간다", schema.walkable("초원") and schema.walkable("숲"))
	_check("물가·바위는 기본으로 막힌다", not schema.walkable("물가") and not schema.walkable("바위"))

	var water := _find_terrain_point(field, "물가")
	var meadow := _find_terrain_point(field, "초원")
	if water == Vector2.INF or meadow == Vector2.INF:
		_check("지형 통행 테스트 준비 — 물가와 초원이 있다", false)
		return

	_check("수달은 물가에 들어간다", map.can_stand(water, schema, ["물가"]))
	_check("개는 물가에 못 들어간다", not map.can_stand(water, schema, ["초원", "숲"]))
	_check("고양이는 바위에 들어간다",
		map.can_stand(_find_terrain_point(field, "바위"), schema, ["초원", "숲", "바위"])
		or _find_terrain_point(field, "바위") == Vector2.INF)
	_check("청설모(숲)도 초원은 지나간다", map.can_stand(meadow, schema, ["숲"]))
	_check("플레이어는 habitat 이 없어 물가에 못 들어간다",
		not map.can_stand(water, schema, []))

	# 막히면 미끄러진다 — 그냥 되돌리면 비스듬히 붙었을 때 갇힌 것처럼 느껴진다.
	# 무작위 지형에 기대면 검사가 조용히 건너뛰어진다. 판을 직접 깔고 잰다.
	var bench := TerrainMap.new()
	bench.generate(Vector2i(8, 8), 16, {}, RandomNumberGenerator.new())
	bench.fill("초원")
	for y in 8:
		bench.set_tile(Vector2i(4, y), "물가")
	var from_left := Vector2(3.5 * 16, 3.5 * 16)
	var into_water := Vector2(4.5 * 16, 4.5 * 16)     # 오른쪽 아래로 비스듬히
	var slid: Vector2 = bench.slide(from_left, into_water, schema, [])
	_check("막힌 지형에 비스듬히 닿으면 미끄러진다",
		slid != from_left and slid != into_water, "%s → %s" % [from_left, slid])
	_check("미끄러져도 막힌 지형에는 안 들어간다", bench.can_stand(slid, schema, []))
	_check("물가가 habitat 이면 그대로 들어간다",
		bench.slide(from_left, into_water, schema, ["물가"]) == into_water)

	# ★ 막힌 지형은 얇아야 한다. 두꺼우면 한가운데 선 동물에게 교감 반경 안으로
	#   다가갈 수 없어 초대가 아예 불가능해진다 (두껍게 찍었을 때 물가의 60%가 그랬다).
	var tile: int = field.tuning.tile_size
	var deepest := 0.0
	for y in map.size.y:
		for x in map.size.x:
			if schema.walkable(map.at_tile(Vector2i(x, y))):
				continue
			var here := (Vector2(x, y) + Vector2(0.5, 0.9)) * tile
			var nearest := INF
			for radius in range(1, 8):
				for step in 12:
					var probe := here + Vector2.RIGHT.rotated(TAU * step / 12.0) * radius * tile
					if map.can_stand(probe, schema, []):
						nearest = minf(nearest, here.distance_to(probe))
				if nearest < INF:
					break
			deepest = maxf(deepest, nearest)
	_check("막힌 지형 한가운데도 설 수 있는 자리에서 3타일 안이다",
		deepest <= 3.0 * tile, "%.1f타일" % (deepest / tile))
	await process_frame


## ★ 날씨는 이름이 아니라 축이다 (BRIEF §6.8)
func _test_weather(field) -> void:
	var schema: TagSchema = field.schema
	var dog: Actor = _find_companion(field, "dog")
	var cat: Actor = _find_companion(field, "cat")
	var weather: WeatherSystem = field.weather
	field._apply_daypart("낮")

	_check("축 다섯 개를 들고 있다", weather.axes.size() == 5
		and weather.axes.has("cloud") and weather.axes.has("wind"))

	# 이름이 아니라 축에 걸린다 — 옅은 안개는 시야가 조금만 깎인다
	var light := schema.sense_weather_scale("시야", {"fog": 0.2})
	var heavy := schema.sense_weather_scale("시야", {"fog": 0.52})
	_check("옅은 안개는 시야가 조금만 깎인다", light > heavy and light < 1.0,
		"옅음 ×%.2f · 짙음 ×%.2f" % [light, heavy])
	_check("비는 후각을 씻는다", schema.sense_weather_scale("후각", {"rain": 1.0}) < 0.6)
	_check("바람은 청각을 흩는다", schema.sense_weather_scale("청각", {"wind": 1.0}) < 0.7)
	_check("안개는 후각을 건드리지 않는다",
		is_equal_approx(schema.sense_weather_scale("후각", {"fog": 0.52}), 1.0))

	# ★ 강도에 상한이 있다 — 화면이 안 보이면 7살은 그냥 못 논다
	for i in 40:
		weather._pick_target()
		_check_once("안개가 상한을 넘지 않는다", float(weather.target["fog"]) <= 0.521)
		_check_once("구름이 상한을 넘지 않는다", float(weather.target["cloud"]) <= 0.461)

	# ★ 자연스럽게 흘러간다 — 툭 바뀌지 않는다
	weather.axes["rain"] = 0.0
	weather.target["rain"] = 1.0
	weather.update(0.1, 20.0)
	var after_tick := float(weather.axes["rain"])
	_check("한 틱에 목표까지 뛰지 않는다", after_tick > 0.0 and after_tick < 0.05,
		"%.3f" % after_tick)
	for i in 400:
		weather.update(0.1, 20.0)
	_check("시간이 지나면 목표에 닿는다", float(weather.axes["rain"]) > 0.5
		or float(weather.target["rain"]) < 1.0)

	# ★ 지형이 어느 축을 세우는지 정한다
	var wet := WeatherSystem.new()
	wet.setup(schema, RandomNumberGenerator.new(), {"물가": 900})
	var dry := WeatherSystem.new()
	dry.setup(schema, RandomNumberGenerator.new(), {"바위": 900})
	_check("물가가 넓으면 안개가 잘 선다",
		float(wet.weights["fog"]) > float(dry.weights["fog"]),
		"물가 %.2f vs 바위 %.2f" % [wet.weights["fog"], dry.weights["fog"]])
	_check("바위가 많으면 바람이 세다",
		float(dry.weights["wind"]) > float(wet.weights["wind"]),
		"바위 %.2f vs 물가 %.2f" % [dry.weights["wind"], wet.weights["wind"]])

	# 틴트를 표로 적지 않는다 — 강도가 저절로 따라온다
	weather.axes = {"cloud": 0.15, "fog": 0.0, "rain": 0.1, "snow": 0.0, "wind": 0.3}
	var drizzle := weather.tint()
	weather.axes = {"cloud": 0.46, "fog": 0.1, "rain": 1.0, "snow": 0.0, "wind": 0.66}
	var downpour := weather.tint()
	_check("가랑비와 폭우가 같은 색일 수 없다", downpour.r < drizzle.r - 0.05,
		"%.2f vs %.2f" % [drizzle.r, downpour.r])

	# ★ 지형이 실제로 뽑히는 날씨를 바꾼다 (사용자 요청)
	# 지형을 섞으면 신호가 묽어지고 표본이 흔들린다. 순수 지형으로 크게 벌려서 본다.
	var wet_fog := _fog_share(schema, {"물가": 1000})
	var dry_fog := _fog_share(schema, {"바위": 1000})
	_check("물가 필드가 바위 필드보다 안개가 잦다", wet_fog > dry_fog * 1.4,
		"물가 %.0f%% vs 바위 %.0f%%" % [wet_fog * 100.0, dry_fog * 100.0])

	# ★ 한 날씨에 갇히지 않는다.
	#   처음엔 축 합이 큰 프리셋이 이기게 짰다가 **늘 폭우만 나왔다** —
	#   축 합은 "얼마나 사나운가"이지 "얼마나 잦은가"가 아니다.
	var roamer := WeatherSystem.new()
	roamer.setup(schema, RandomNumberGenerator.new(), {"초원": 2000, "숲": 500})
	var names := {}
	for i in 60:
		roamer._pick_target()
		names[roamer.nickname_of(roamer.target)] = true
	_check("한 날씨에 갇히지 않는다", names.size() >= 4, str(names.keys()))
	_check("사나운 날씨가 기본값이 되지 않는다", not ("폭우" in names) or names.size() >= 5,
		str(names.keys()))

	# ★ 날씨는 연출이지 장애물이 아니다. 상한에서도 길과 캐릭터가 읽혀야 한다.
	#   처음엔 구름 그림자를 곱연산으로 통째로 깔아서 **맑은 날에도 화면이 까맸다.**
	var caps: Dictionary = weather.data.get("caps", {})
	var worst := {"cloud": float(caps.get("cloud", 0.46)), "fog": float(caps.get("fog", 0.52)),
		"rain": 1.0, "snow": 0.0, "wind": 1.0}
	var cover: float = WeatherLayers.total_cover(worst)
	_check("가장 사나운 날씨에도 화면이 덮이지 않는다", cover < 0.6, "%.0f%% 덮임" % (cover * 100.0))
	var clear: float = WeatherLayers.total_cover(
		{"cloud": 0.15, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.3})
	_check("맑은 날은 거의 안 덮인다", clear < 0.15, "%.0f%% 덮임" % (clear * 100.0))
	# 구름 그림자는 맑은 날에도 켜져 있다 — 날씨가 "없는" 상태를 만들지 않는 장치다
	_check("맑은 날에도 구름 그림자는 흐른다", clear > 0.02, "%.0f%%" % (clear * 100.0))

	# ★ 햇살 얼룩은 맑을수록 세지고 밤에는 없다
	var sun_spec := {}
	for spec in WeatherLayers.LAYERS:
		if String(spec["name"]) == "sun":
			sun_spec = spec
	_check("햇살 얼룩 겹이 있다", not sun_spec.is_empty())
	if not sun_spec.is_empty():
		var sunny: float = WeatherLayers.alpha_for(sun_spec, {"cloud": 0.10})
		var cloudy: float = WeatherLayers.alpha_for(sun_spec, {"cloud": 0.46})
		_check("맑을수록 햇살이 세다", sunny > cloudy * 1.4,
			"맑음 %.3f · 흐림 %.3f" % [sunny, cloudy])
		_check("햇살은 시간대에 묶인다 — 밤엔 없다",
			bool(sun_spec.get("daylight", false))
			and is_zero_approx(float(field.tuning.daypart_daylight.get("밤", 1.0))))
		_check("햇살은 화면을 가리지 않는다 (더하는 빛이다)",
			is_zero_approx(float(sun_spec.get("cover", 1.0))))

	# ★ 실제 날씨는 튀지 않는다 — 지금과 가까운 상태로만 옮겨간다 (사용자 지적)
	var walker := WeatherSystem.new()
	walker.setup(schema, RandomNumberGenerator.new(), {"초원": 2000, "숲": 600})
	walker.axes = {"cloud": 0.15, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.3}
	var jumped := 0
	for i in 200:
		walker._pick_target()
		if float(walker.target.get("rain", 0.0)) >= 0.9:
			jumped += 1
	_check("맑음에서 폭우로 바로 가지 않는다", jumped == 0, "%d/200 회" % jumped)

	# 멀리 있는 상태일수록 옮겨가는 데 오래 걸린다 (속도가 일정하므로 저절로)
	walker.axes["rain"] = 0.0
	walker.target = {"cloud": 0.15, "fog": 0.0, "rain": 0.2, "snow": 0.0, "wind": 0.3}
	var short_ticks := 0
	while float(walker.axes["rain"]) < 0.199 and short_ticks < 2000:
		walker.update(0.1, 22.0)
		short_ticks += 1
	walker.axes["rain"] = 0.0
	walker.target["rain"] = 0.8
	var long_ticks := 0
	while float(walker.axes["rain"]) < 0.799 and long_ticks < 2000:
		walker.update(0.1, 22.0)
		long_ticks += 1
	_check("크게 바뀔수록 오래 걸린다", long_ticks > short_ticks * 3,
		"0.2까지 %d틱 · 0.8까지 %d틱" % [short_ticks, long_ticks])

	# 어떤 지형도 축을 0 으로 막지 않는다 — 기다림을 강요하게 된다
	var blocked := PackedStringArray()
	for terrain_name in schema.weather_bias:
		for axis in schema.weather_bias[terrain_name]:
			if is_zero_approx(float(schema.weather_bias[terrain_name][axis])):
				blocked.append("%s.%s" % [terrain_name, axis])
	_check("어느 지형도 날씨 축을 아주 막지 않는다", blocked.is_empty(), ", ".join(blocked))
	await process_frame


## 그 지형 구성에서 안개 계열이 뽑히는 비율
func _fog_share(schema: TagSchema, mix: Dictionary) -> float:
	var weather := WeatherSystem.new()
	weather.setup(schema, RandomNumberGenerator.new(), mix)
	var foggy := 0
	for i in 800:
		weather._pick_target()
		if float(weather.target.get("fog", 0.0)) >= 0.2:
			foggy += 1
	return float(foggy) / 800.0


var _once := {}
func _check_once(label: String, condition: bool) -> void:
	if _once.has(label):
		_once[label] = _once[label] and condition
		return
	_once[label] = condition
	_check(label, condition)


## ★ 시간대는 감각 반경만이 아니라 **누가 나와 있는가**를 바꾼다 (사용자 요청)
func _test_presence(field) -> void:
	var schema: TagSchema = field.schema
	# 박쥐(야행성)를 낮에 못 찾는 것이 이 규칙이다
	_check("야행성은 낮에 필드에 없다",
		is_zero_approx(schema.presence_chance({"activity": "야행성"}, "낮")))
	_check("주행성은 밤에 필드에 없다",
		is_zero_approx(schema.presence_chance({"activity": "주행성"}, "밤")))
	_check("박명성은 여명에 가장 많다",
		schema.presence_chance({"activity": "박명성"}, "여명")
			> schema.presence_chance({"activity": "박명성"}, "낮"))
	# 박명성을 0 으로 두지 않은 것은 게이지의 시간대 계수가 살아 있어야 해서다
	_check("박명성은 낮에도 가끔 있다 — 게이지의 시간대 계수가 죽지 않게",
		schema.presence_chance({"activity": "박명성"}, "낮") > 0.0)

	# ★ 종이 자기 조건을 직접 들 수 있다. 같은 야행성이라도 강도가 다르다.
	var strict := {"activity": "야행성", "presence": {"여명": 0.0}}
	_check("종의 presence 가 activity 기본값을 덮는다",
		is_zero_approx(schema.presence_chance(strict, "여명"))
		and schema.presence_chance({"activity": "야행성"}, "여명") > 0.0)

	# 실제 필드에서도 그대로 나와야 한다
	field._apply_daypart("낮")
	var night_out := 0
	for animal in field.sim.animals:
		if String(animal.species.get("activity", "")) == "야행성" and animal.present:
			night_out += 1
	_check("낮에는 야행성이 한 마리도 안 나와 있다", night_out == 0, str(night_out))

	field._apply_daypart("밤")
	var day_out := 0
	for animal in field.sim.animals:
		if String(animal.species.get("activity", "")) == "주행성" and animal.present:
			day_out += 1
	_check("밤에는 주행성이 한 마리도 안 나와 있다", day_out == 0, str(day_out))
	_check("사라진 동물은 유도 대상에서도 빠진다",
		field.sim.count_present() < field.sim.animals.size())

	field._apply_daypart("낮")
	await process_frame


## ★ 개체의 개성 — 능력치가 무언가를 결정하고, 숫자가 아니라 보이는 것으로 (BRIEF §2.5)
func _test_individuals(field) -> void:
	var schema: TagSchema = field.schema
	var all := DataLoader.load_all(false).species

	# 종마다 이동속도가 다르다 — 두꺼비는 느리고 참새는 빠르다
	var toad: Array = all["toad"]["stats_range"]["move_speed"]
	var sparrow: Array = all["sparrow"]["stats_range"]["move_speed"]
	_check("종마다 이동속도 범위가 다르다", float(toad[1]) < float(sparrow[0]),
		"두꺼비 %s vs 참새 %s" % [toad, sparrow])

	# 같은 종 안에서도 개체가 다르다
	var seen := {}
	for animal in field.sim.animals:
		if String(animal.species.get("id", "")) == "squirrel":
			seen[snappedf(animal.move_scale, 0.01)] = true
	_check("같은 종 안에서도 개체마다 속도가 다르다", seen.size() >= 2, str(seen.keys()))

	# ★ 선택지는 종 데이터가 갖는다. 코드가 개성 이름을 고르지 않는다.
	var outside := PackedStringArray()
	var too_many := PackedStringArray()
	for animal in field.sim.animals:
		var pool: Array = animal.species.get("quirk_pool", [])
		var span: Array = animal.species.get("quirk_count", [0, 0])
		for quirk in animal.quirks:
			if not (String(quirk) in pool):
				outside.append("%s:%s" % [animal.species.get("id"), quirk])
		if span.size() == 2 and animal.quirks.size() > int(span[1]):
			too_many.append(String(animal.species.get("id")))
	_check("개성은 그 종의 quirk_pool 에서만 나온다", outside.is_empty(), ", ".join(outside))
	_check("개성 개수가 quirk_count 를 넘지 않는다", too_many.is_empty(), ", ".join(too_many))

	# 옵셔널이다 — 아무 개성 없는 개체가 나올 수 있어야 한다
	_check("개성이 없는 개체도 나올 수 있다",
		int(all["dog"]["quirk_count"][0]) == 0)

	# 전부 화면에서 보이는 것이어야 한다 (원칙 5)
	var invisible := PackedStringArray()
	for quirk in schema.quirk_names():
		if schema.quirk_shows(String(quirk)).is_empty():
			invisible.append(String(quirk))
	_check("모든 개성이 화면에서 무엇으로 보이는지 적혀 있다", invisible.is_empty(),
		", ".join(invisible))

	# 붙임성이 게이지를 눈에 띄게 줄인다
	var dog: Actor = _find_companion(field, "dog")
	dog.charm = 1.0
	var plain: Dictionary = Gauge.compute_factor(all["squirrel"], dog, "낮", field.tuning, [], schema)
	var friendly: Dictionary = Gauge.compute_factor(all["squirrel"], dog, "낮", field.tuning,
		["붙임성"], schema)
	_check("붙임성 개체는 게이지가 짧다", friendly["factor"] < plain["factor"] * 0.8,
		"%.2f → %.2f" % [plain["factor"], friendly["factor"]])
	await process_frame


## ★ 어두울 때 눈이 되비춘다 — 종이 아니라 activity 로 (사용자 요청)
func _test_eyeshine(field) -> void:
	var schema: TagSchema = field.schema
	_check("주행성은 밤에도 눈이 빛나지 않는다", not schema.eyeshines_at("주행성", "밤"))
	_check("박명성은 밤에 눈이 빛난다", schema.eyeshines_at("박명성", "밤"))
	_check("야행성은 여명에도 빛난다", schema.eyeshines_at("야행성", "여명"))
	_check("어느 활동이든 낮에는 빛나지 않는다",
		not schema.eyeshines_at("야행성", "낮") and not schema.eyeshines_at("박명성", "낮"))

	var cat: Actor = _find_companion(field, "cat")     # 박명성
	var dog: Actor = _find_companion(field, "dog")     # 주행성
	var eye: Sprite2D = cat.get_node("Body/Eye")
	var dog_eye: Sprite2D = dog.get_node("Body/Eye")
	cat.move_vector = Vector2.RIGHT
	dog.move_vector = Vector2.RIGHT
	await process_frame

	field._apply_daypart("낮")
	field._advance_palette(10.0)
	field._apply_eyeshine()
	await process_frame
	var day_eye := eye.texture
	_check("낮에는 눈 텍스처가 원본 그대로", eye.self_modulate == Color.WHITE)

	field._apply_daypart("밤")
	field._advance_palette(10.0)
	field._apply_eyeshine()
	await process_frame
	_check("박명성 동료의 눈이 밤에 되비추는 판으로 바뀐다",
		eye.texture != day_eye and eye.self_modulate != Color.WHITE)
	_check("되비추는 값이 화면 틴트를 되돌린다 (어둠에 묻히지 않는다)",
		eye.self_modulate.r > 1.0 and eye.self_modulate.b > 1.0,
		str(eye.self_modulate))
	_check("주행성 동료의 눈은 밤에도 그대로", dog_eye.self_modulate == Color.WHITE)

	field._apply_daypart("낮")
	field._advance_palette(10.0)
	field._apply_eyeshine()
	await process_frame


## 보이던 게 사라지면 먼지가 남는다 — 아이가 "숨었다"로 읽을 수 있게 (사용자 요청)
func _test_puff(field) -> void:
	field.player.position = field.player.bounds.size * 0.5
	var animal: FieldSim.WildAnimal = _find_animal(field, "otter")
	animal.position = field.player.position + Vector2(8, 0)
	field.sim.update(0.016, field.player.position)
	field.guide.update([], [animal])
	field._puffs.clear()
	field._apply_reveal()
	# 다른 동물도 같은 프레임에 상태가 바뀔 수 있다. 이 대상 자리에 뜬 것만 본다.
	_check("안 보이던 게 보이면 이펙트가 뜬다", _puff_near(field, animal.actor.position, false))

	animal.position = field.player.position + Vector2(600, 0)
	field.guide.update([], [animal])
	field._puffs.clear()
	field._apply_reveal()
	# 먼지는 대상의 현재 좌표가 아니라 **보이던 자리**에 남아야 한다
	_check("보이던 게 사라지면 이펙트가 뜬다", _puff_near(field, animal.actor.position, true))

	field._age_puffs(1.0)
	_check("이펙트는 잠깐 있다 사라진다", field._puffs.is_empty())
	await process_frame


## 게이지가 다 차면 초대된다 — 대상이 사라지고 카운터가 오른다 (DEMO-SPEC §3.5)
func _test_invite(field) -> void:
	# 앞 테스트가 플레이어를 필드 밖으로 밀어놨을 수 있다. 가운데로 되돌리고 시작한다.
	field.player.position = field.player.bounds.size * 0.5
	var animal: FieldSim.WildAnimal = _find_animal(field, "otter")
	animal.position = field.player.position + Vector2(8, 0)
	field.sim.update(0.016, field.player.position)
	var active_before: int = field.sim.count_active()
	var counter_before: int = field.metrics.invited_count

	field.gauge.cancel()
	field.gauge.start(animal, _find_companion(field, "dog"), "낮")
	var done := false
	for i in 600:
		if field.gauge.update(0.02):
			done = true
			break
	field.sim.invite(field.gauge.target)
	field.metrics.note_invited()
	await process_frame

	_check("게이지가 다 찬다", done)
	_check("초대된 대상은 필드에서 사라진다",
		animal.invited and not animal.is_active() and field.sim.count_active() < active_before)
	_check("초대 카운터가 오른다", field.metrics.invited_count == counter_before + 1)
	_check("초대된 대상은 유도 대상에서도 빠진다",
		field.guide.update([_find_companion(field, "dog")], field.sim.active_animals()) == null
		or field.guide.update([_find_companion(field, "dog")], field.sim.active_animals()).animal != animal)


# --- 도우미 ---------------------------------------------------------------

func _species_of(field, id: String) -> Dictionary:
	for animal in field.sim.animals:
		if animal.species.get("id") == id:
			return animal.species
	for companion in field.companions:
		if companion.species_id == id:
			return companion.species
	return {}

func _puff_near(field, position: Vector2, hiding: bool) -> bool:
	for puff in field._puffs:
		if puff["hiding"] == hiding and puff["position"].distance_to(position) < 64.0:
			return true
	return false


func _find_terrain_point(field, terrain_name: String) -> Vector2:
	var map: TerrainMap = field.terrain
	var center := Vector2(map.size) * 0.5
	var best := Vector2.INF
	var best_distance := INF
	for y in map.size.y:
		for x in map.size.x:
			if map.at_tile(Vector2i(x, y)) != terrain_name:
				continue
			var distance := Vector2(x, y).distance_to(center)
			if distance < best_distance:
				best_distance = distance
				best = (Vector2(x, y) + Vector2(0.5, 0.9)) * map.tile_size
	return best


## 특정 종을 집어 오는 헬퍼. 지금 시간대에 안 나와 있을 수 있으므로 세워서 준다 —
## 여기서 검사하는 것은 노출·교감이지 존재 규칙이 아니다 (그건 _test_presence 가 본다).
func _find_animal(field, id: String) -> FieldSim.WildAnimal:
	for animal in field.sim.animals:
		if animal.species.get("id") == id and not animal.invited:
			animal.present = true
			return animal
	return null

func _find_companion(field, id: String) -> Actor:
	for companion in field.companions:
		if companion.species_id == id:
			return companion
	return null

func _check(label: String, condition: bool, detail := "") -> void:
	if condition:
		_pass += 1
		print("  [OK] " + label)
	else:
		_fail += 1
		print("  [실패] %s %s" % [label, ("— " + detail) if detail != "" else ""])
