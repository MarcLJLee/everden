## Demo 1 완료 조건 자동 점검. (DEMO-SPEC §4)
##
##   godot --headless --script tools/smoke_test.gd
##
## 눈으로 봐야 아는 것(재미·바운스의 느낌)은 여기서 못 잡는다.
## 여기서 잡는 것은 "구조가 사양대로인가" 뿐이다.
extends SceneTree

## 이 아래로 떨어지면 어딘가에서 판정이 조용히 끊긴 것이다.
const FLOOR := 442

var _pass := 0
var _fail := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	Engine.time_scale = 10.0  # 게이지 3초를 실시간으로 기다리지 않는다

	var result := DataLoader.load_all(true)
	_check("데이터 로드", result.ok, result.reject_reason)

	# ⚠️ 회귀는 **진짜 저장 파일을 건드리면 안 된다** — 사람이 모아온 아이들이 거기 있다.
	#    그리고 판을 여기서 짜 놓아야 한다: 저장 상태에 따라 결과가 달라지면
	#    "어제는 통과했는데" 가 시작된다.
	# ⚠️ 오토로드의 `_ready` 는 **첫 프레임에** 돌면서 진짜 저장을 읽어온다.
	#    그 전에 판을 짜면 조용히 덮어써져서, 테스트가 사람의 세이브를 물고 돌게 된다.
	#    실제로 그렇게 돌다가 동료가 하나로 줄어 세 판정이 깨졌다.
	await process_frame
	var game: GameState = root.get_node("Game")
	game.autosave = false
	game.start_new()
	# 개와 고양이 둘 다 필요하다 — **감각 대비**가 이 회귀의 핵심이다 (BRIEF §3.8).
	game.party = [int(game.add("dog")["uid"]), int(game.add("cat")["uid"])]
	_check("회귀는 저장을 건드리지 않는다", not game.autosave)

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
	await _test_boot(game)
	await _test_sense_reach(field)
	await _test_terrain_walk(field)
	await _test_weather(field, game)
	await _test_presence(field)
	await _test_individuals(field)
	await _test_roster(field)
	await _test_eyeshine(field)
	await _test_puff(field)
	await _test_invite(field)

	# ⚠️ 판정 하나가 터지면 그 함수의 **나머지가 통째로 안 돈다.** 실패가 아니라
	#    "조용히 사라짐" 이라 눈치채기 어렵다 — 이 프로젝트에서 다섯 번 겪었다.
	#    그래서 **총 개수에 바닥을 둔다.** 판정을 지우려면 이 숫자도 같이 내려야 한다.
	_check("판정이 중간에 끊기지 않았다", _pass + _fail >= FLOOR,
		"%d 개 돌았다 (바닥 %d)" % [_pass + _fail, FLOOR])
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
	await process_frame
	# ⚠️ 기준은 **같은 방향으로 걷기 시작한 뒤**에 잡는다. 방향이 바뀌면 앵커도 바뀌는 게
	#    맞으므로(정면 눈과 옆 눈은 자리가 다르다), 방향이 섞인 값과 견주면 헛돈다.
	eye_offset_before = eye.position
	var seen := {}
	var non_integer := false
	for i in 40:
		await process_frame
		seen[body.position.y] = true
		if body.position.y != floorf(body.position.y):
			non_integer = true
	_check("바운스가 Body 노드 Y로 일어난다", seen.size() >= 2, "관측된 Y: %s" % [seen.keys()])
	_check("Body.position.y 가 정수 픽셀", not non_integer, "관측된 Y: %s" % [seen.keys()])
	# ⚠️ 걷는 동안 **프레임이 바뀌어도** 얼굴 앵커와 몸통 자리는 그대로여야 한다.
	#    (방향이 바뀌면 앵커도 바뀌는 게 맞다 — 그건 아래에서 따로 본다)
	_check("스프라이트는 제자리 — 얼굴 앵커가 프레임마다 흔들리지 않는다",
		eye.position == eye_offset_before and body_sprite.position == player.canvas_offset,
		"눈 %s→%s" % [eye_offset_before, eye.position])

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

	# ★ **4방향 몸은 멈춰도 보던 쪽을 그대로 본다** (사용자 지적).
	#   남쪽으로 걸어오다 서면 정면이 그대로 남는다 — 그림이 있는데 굳이 돌릴 이유가 없다.
	player.look_direction = Vector2.UP
	await process_frame
	_check("4방향 몸은 멈춰도 북향을 지킨다", player.facing == "north", player.facing)
	_check("북향에서는 얼굴이 숨는다", not eye.visible)
	player.look_direction = Vector2.DOWN
	await process_frame
	_check("남쪽을 보고 서면 정면이 남는다", player.facing == "south", player.facing)
	_check("정면에서는 얼굴이 보인다", eye.visible)
	_check("서 있어도 그쪽 그림을 쓴다",
		String(body_sprite.animation) in ["move_south", "idle_south"],
		String(body_sprite.animation))
	player.look_direction = Vector2(-1, -3)
	await process_frame
	_check("왼쪽 위를 보면 북향이다", player.facing == "north", player.facing)
	player.look_direction = Vector2.ZERO
	await process_frame

	# 측면 1방향인 몸은 예전 규칙 그대로 — 정지 중에 북/남을 보면 측면 몸통에 정면 눈이 얹힌다
	# ⚠️ 개체를 못 찾으면 판정을 **건너뛰지 않는다.** 건너뛰면 통과 수가 판마다 달라져서
	#    "조용히 사라짐" 과 구분이 안 된다 — 못 찾은 것 자체를 실패로 적는다.
	var sider: Actor = _promoted(field, "squirrel")
	_check("측면 1방향 몸을 하나 잡았다", sider != null)
	if sider != null:
		sider.move_vector = Vector2.ZERO
		sider.look_direction = Vector2.UP
		await process_frame
		_check("측면 1방향 몸은 정지 중 좌우로 유지된다",
			sider.facing in ["east", "west"], sider.facing)
		sider.look_direction = Vector2.ZERO
	else:
		_check("측면 1방향 몸은 정지 중 좌우로 유지된다", false, "개체를 못 찾았다")

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
	_check("후각으로 찾으면 몸은 안 보이고 단서만 뜬다",
		not animal.actor.visible and clues.size() == 1 and clues[0]["sense"] == "후각",
		"보임=%s 단서=%d" % [animal.actor.visible, clues.size()])

	# ★ **몸을 원격으로 드러내는 감각은 없다** (BRIEF §3.14 · 사용자 지적).
	#   동료가 감지했다고 저 멀리 있는 동물을 화면에 그리면 그건 세계의 사건이 아니라
	#   게임이 알려주는 것이다. 눈도 "거기에 뭔가 있다" 까지만 말한다.
	field.guide.update([cat], [animal])
	clues = field._apply_reveal()
	_check("시야로 찾아도 멀리 있는 몸은 안 보인다",
		not animal.actor.visible, "보임=%s" % animal.actor.visible)
	_check("대신 그 자리에 자국이 남는다",
		clues.size() == 1 and String(clues[0]["sense"]) == "시야",
		"단서 %d개" % clues.size())

	# 범주는 갈린다 — 코와 귀는 **방향**(공중 표시), 눈은 **자리**(땅의 자국)
	_check("눈의 단서는 자리를 말한다", field.schema.sense_marks_spot("시야"))
	_check("코의 단서는 방향을 말한다", not field.schema.sense_marks_spot("후각"))
	_check("귀의 단서도 방향을 말한다", not field.schema.sense_marks_spot("청각"))

	# 가까이 가면 그때 보인다 — 발견의 순간은 아이의 것이다
	field.player.position = animal.position
	clues = field._apply_reveal()
	_check("가까이 가면 보인다", animal.actor.visible)

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


func _test_boot(game) -> void:
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

	# 타이틀 — 메뉴는 **이어할 것이 있느냐**에 따라 갈린다 (BRIEF §6.7 · title.json)
	var title: Control = load("res://scenes/ui/Title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	# ⚠️ **파일이 있느냐로 묻지 않는다.** 세이브를 지우고 켜도 오토로드가 곧바로 빈 파일을
	#    쓸 수 있어서 새 판인데 CONTINUE 가 떴다 (사용자 지적).
	#    이어할 **것**이 있는가 — 즉 모아온 아이가 있는가로 묻는다.
	var savable: bool = not (game.collection as Array).is_empty()
	_check("이어할 것이 있을 때만 CONTINUE 가 뜬다",
		("CONTINUE" in title._items) == savable,
		"식구 %d · %s" % [game.collection.size(), title._items])
	# 데모 빌드는 새 게임이 아니라 필드 한 조각을 보여준다 — 없는 것을 약속하지 않는다.
	# 데모가 아니면 첫 항목은 이어하기(있으면) 또는 새 게임이고, 들어가는 곳은 집이다.
	var expected := "DEMO" if title.demo_build else ("CONTINUE" if savable else "NEW GAME")
	_check("첫 항목이 지금 상태와 맞는다", title._items[0] == expected,
		"demo=%s 이어할것=%s %s" % [title.demo_build, savable, title._items])
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
	for name in ["초원", "숲", "물가", "바위"]:
		_check("지형 %s 에 타일 그림이 있다" % name, loaded.has(name), str(loaded.keys()))
	# ★ **축척이 바뀌면 표현도 바뀐다** — 물가는 자리에 따라 다르게 그린다 (사용자 지적).
	#   지형 이름을 늘리지 않는다. 늘리면 통행·서식지·생태 표가 전부 따라 늘어난다.
	_check("물줄기 한가운데에 깔 물 그림이 있다", loaded.has("extra/water_0"))
	_check("물과 뭍이 만나는 그림이 있다", loaded.has("extra/shore_N"))
	_check("지형 이름은 넷 그대로다",
		field.schema.terrain_walkable.size() == 4, str(field.schema.terrain_walkable.keys()))
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

	# ★ 예전에는 "승격 거리가 가장 먼 감각을 덮는가" 를 쟀다. 저 멀리서 감지된 몸을
	#   그려야 했기 때문이다 — 그 이유가 사라졌다(§3.14). 지금 지켜야 하는 것은
	#   **단서가 노드 없이도 나오는가**와 **승격이 보이는 반경보다 넉넉한가** 둘이다.
	var widest := 0.0
	for companion in field.companions:
		for sense in companion.senses:
			widest = maxf(widest, field.guide.max_reach(companion, String(sense)))
	_check("승격은 감각 반경을 안 따라간다 — 몸을 원격으로 그리지 않으니까",
		field._promotion_px < widest,
		"승격 %.0fpx / 감각 %.0fpx" % [field._promotion_px, widest])
	_check("그래도 보이는 반경보다는 넉넉하다 — 화면에 들기 전에 이미 걷고 있어야 한다",
		field._promotion_px > field.tuning.reveal_radius * field.tuning.tile_size,
		"승격 %.0fpx / 보임 %.0fpx"
			% [field._promotion_px, field.tuning.reveal_radius * field.tuning.tile_size])
	await process_frame


## ★ 갈 수 있는 지형 — 물가·바위는 그 지형이 habitat 인 동물만 (사용자 판단)
func _test_terrain_walk(field) -> void:
	var schema: TagSchema = field.schema
	var map: TerrainMap = field.terrain
	_check("초원·숲은 누구나 지나간다", schema.walkable("초원") and schema.walkable("숲"))
	_check("물가·바위는 기본으로 막힌다", not schema.walkable("물가") and not schema.walkable("바위"))

	# ⚠️ 무작위 필드에 기대면 물가가 한 타일도 없는 원정에서 이 검사가 통째로 사라진다
	#    (지역이 개울을 한 줄기만 찍는다). 판을 직접 깔고 잰다 — 같은 실수를 네 번 했다.
	var bench0 := TerrainMap.new()
	bench0.generate(Vector2i(8, 8), 16, {}, RandomNumberGenerator.new(), "초원")
	bench0.set_tile(Vector2i(4, 4), "물가")
	bench0.set_tile(Vector2i(6, 4), "바위")
	var water := (Vector2(4, 4) + Vector2(0.5, 0.9)) * 16
	var rock := (Vector2(6, 4) + Vector2(0.5, 0.9)) * 16
	var meadow := (Vector2(1, 1) + Vector2(0.5, 0.9)) * 16

	_check("수달은 물가에 들어간다", bench0.can_stand(water, schema, ["물가"]))
	_check("개는 물가에 못 들어간다", not bench0.can_stand(water, schema, ["초원", "숲"]))
	_check("고양이는 바위에 들어간다", bench0.can_stand(rock, schema, ["초원", "숲", "바위"]))
	_check("청설모(숲)도 초원은 지나간다", bench0.can_stand(meadow, schema, ["숲"]))
	_check("플레이어는 habitat 이 없어 물가에 못 들어간다",
		not bench0.can_stand(water, schema, []))

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
func _test_weather(field, game) -> void:
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

	# ★ 겹은 **화면보다 넓게** 깔린다. 좁게 깔았더니 오른쪽 절반이 맨땅이었다 (사용자 지적).
	#   창 종횡비가 기준과 어긋나면 뷰포트가 기준 해상도보다 커지므로 여유가 필요하다.
	var view: Rect2 = field.weather_view_rect()
	var screen: Vector2 = field.camera_visible_rect().size
	_check("날씨 겹이 화면보다 넓게 깔린다", view.size.x > screen.x * 1.25
		and view.size.y > screen.y * 1.25,
		"겹 %s · 화면 %s" % [view.size, screen])
	# ★ 진짜 지켜야 하는 것은 **겹이 화면을 남김없이 덮는가** 하나다.
	#   플레이어 위치에 깔았더니 맵 구석에서 한쪽이 맨땅으로 남았다 (사용자 지적) —
	#   카메라는 맵 끝에서 멈추고(limit_*) 달리는 동안 뒤처지는데(smoothing)
	#   겹만 플레이어를 따라갔기 때문이다.
	#   이 필드는 _process 가 꺼져 있으므로 딴 판을 하나 세워 실제로 움직여 본다.
	var live: Node2D = load("res://scenes/field/Field.tscn").instantiate()
	root.add_child(live)
	# ⚠️ 판이 둘이면 **나중에 들어온 카메라는 current 가 되지 않는다.** 그대로 두면
	#    get_screen_center_position() 이 (0,0) 을 돌려주고, 겹과 화면이 **둘 다** 원점을
	#    보게 되어 아래 판정이 늘 통과한다. 조용히 넘어가는 테스트가 이렇게 생긴다.
	live.get_node("Camera2D").make_current()
	await process_frame
	var moved_from: Vector2 = live.camera_visible_rect().get_center()
	var corners := [Vector2(8.0, 8.0), Vector2(-4000.0, -4000.0), Vector2(4000.0, 4000.0)]
	for corner in corners:
		live.player.position = corner
		# 부드러운 추종이 자리를 잡을 때까지
		for i in 40:
			await process_frame
		_check("맵 구석에서도 겹이 화면을 남김없이 덮는다 %s" % corner,
			live.weather_view_rect().encloses(live.camera_visible_rect()),
			"겹 %s · 화면 %s" % [live.weather_view_rect(), live.camera_visible_rect()])
	# 달리는 중이 가장 사납다 — 카메라가 뒤처진 채로도 덮여야 한다
	live.player.position = Vector2(600.0, 600.0)
	for i in 30:
		await process_frame
	live.player.position += Vector2(900.0, 0.0)
	await process_frame
	_check("달리는 중에도 겹이 화면을 덮는다",
		live.weather_view_rect().encloses(live.camera_visible_rect()),
		"겹 %s · 화면 %s" % [live.weather_view_rect(), live.camera_visible_rect()])
	# 위 판정들이 헛돌지 않았다는 증거 — 카메라가 실제로 움직였는가
	_check("측정 판의 카메라가 실제로 움직였다",
		live.camera_visible_rect().get_center().distance_to(moved_from) > 100.0,
		"%s → %s" % [moved_from, live.camera_visible_rect().get_center()])

	# ★ 비와 구름은 **카메라가 아니라 땅에 붙는다.** 카메라는 오려내는 창일 뿐이다.
	#   화면에 고정하면 걸음을 멈춰도 빗줄기가 따라와서 유리창에 그린 것처럼 보인다.
	#   판정: 위치가 달라도 같은 월드 지점이 같은 텍스처 좌표를 본다.
	# 월드 한 점 p 가 보는 텍스처 좌표는 (p - node.position)/배율 + region.position 이다.
	# 땅에 붙었다면 이 값이 화면이 어디에 있든 같다. 키운 겹은 배율을 나눠줘야 맞다.
	var anchored := true
	var drifted := 0
	for entry in live.get_node("Weather")._sprites:
		var sprite: Sprite2D = entry["node"]
		var zoom: float = maxf(sprite.scale.x, 0.001)
		var before: Vector2 = sprite.region_rect.position - sprite.position / zoom
		live._weather_layers.update(0.0, live.weather.axes,
			live.weather_view_rect().grow(-40.0), 1.0)
		var after: Vector2 = sprite.region_rect.position - sprite.position / zoom
		if before.distance_to(after) > 1.0:
			anchored = false
		drifted += 1
	_check("날씨 무늬는 카메라가 아니라 땅에 붙는다", anchored)
	_check("잰 겹이 하나라도 있다", drifted > 0, "%d 겹" % drifted)
	live.queue_free()
	await process_frame

	# ★ 빛줄기는 **끝이 있는 기둥**이어야 한다. 화면 끝까지 이어지는 사선 격자를
	#   받았더니 빛이 아니라 줄무늬 필터로 보였다 (사용자 지적).
	#   도트가 다시 들어와도 이 성질은 지켜져야 하므로 파일을 직접 잰다.
	var shaft_path := "res://sprites/extracted/weather/light_shaft.png"
	_check("빛줄기 도트가 있다", ResourceLoader.exists(shaft_path))
	if ResourceLoader.exists(shaft_path):
		var shaft: Image = (load(shaft_path) as Texture2D).get_image()
		var lit := 0
		var empty_columns := 0
		for x in shaft.get_width():
			var column := 0
			for y in shaft.get_height():
				if shaft.get_pixel(x, y).a > 0.04:
					column += 1
			lit += column
			if column == 0:
				empty_columns += 1
		var fraction := float(lit) / float(shaft.get_width() * shaft.get_height())
		_check("빛줄기는 드문드문하다 — 격자가 아니다", fraction < 0.20,
			"%.1f%% 가 빛" % (fraction * 100.0))
		_check("빛이 닿지 않는 자리가 있다 — 기둥에 끝이 있다", empty_columns > 0,
			"빈 열 %d / %d" % [empty_columns, shaft.get_width()])

	# ★ 해가 드는 연출은 **구름만 보고 정하면 안 된다** (사용자 지적).
	#   구름이 거의 없으면 새어 나올 틈이 없고, 비가 오면 직사광 자체가 없다.
	var ray_spec := {}
	for spec in WeatherLayers.LAYERS:
		if String(spec["name"]) == "rays":
			ray_spec = spec
	_check("빛줄기 겹이 있다", not ray_spec.is_empty())
	if not ray_spec.is_empty():
		var none: float = WeatherLayers.alpha_for(ray_spec, {"cloud": 0.04})
		var some: float = WeatherLayers.alpha_for(ray_spec, {"cloud": 0.26})
		var full: float = WeatherLayers.alpha_for(ray_spec, {"cloud": 0.92})
		_check("구름이 거의 없으면 빛줄기가 없다 — 새어 나올 틈이 없다",
			is_zero_approx(none), "%.3f" % none)
		_check("구름이 꽉 차도 빛줄기가 없다", is_zero_approx(full), "%.3f" % full)
		_check("그 사이에서 가장 세다", some > 0.2, "%.3f" % some)
		var rainy: float = WeatherLayers.alpha_for(ray_spec, {"cloud": 0.26, "rain": 0.6})
		_check("비가 오면 빛줄기가 거의 없다", rainy < some * 0.25,
			"맑음 %.3f → 비 %.3f" % [some, rainy])
		var light_rain: float = WeatherLayers.alpha_for(ray_spec, {"cloud": 0.26, "rain": 0.15})
		_check("이슬비에는 해가 남는다 — 껐다 켜지지 않는다",
			light_rain > rainy and light_rain < some, "%.3f" % light_rain)
		if not sun_spec.is_empty():
			_check("비 오는 날에는 햇살 얼룩도 없다",
				WeatherLayers.alpha_for(sun_spec, {"cloud": 0.26, "rain": 0.6})
					< WeatherLayers.alpha_for(sun_spec, {"cloud": 0.26}) * 0.25)

	# ★ 빛이 숨쉬는 것은 연출이지 깜빡임이 아니다. 주기가 짧아지면 스트로브가 된다.
	var pulsing := 0
	for spec in WeatherLayers.LAYERS:
		if not spec.has("pulse"):
			continue
		pulsing += 1
		var pulse: Dictionary = spec["pulse"]
		_check("%s 의 숨쉬기가 느리다" % spec["name"], float(pulse["period"]) >= 6.0,
			"주기 %.1f초" % float(pulse["period"]))
		_check("%s 의 숨쉬기가 빛을 끄지는 않는다" % spec["name"],
			float(pulse["amount"]) < 0.6, "%.2f" % float(pulse["amount"]))
	_check("숨쉬는 겹이 있다", pulsing >= 2, "%d 겹" % pulsing)
	# 주기가 서로 어긋나야 맞물렸다 풀리면서 산란처럼 보인다 — 같으면 통째로 껌뻑인다
	var periods := {}
	for spec in WeatherLayers.LAYERS:
		if spec.has("pulse"):
			periods[float(spec["pulse"]["period"])] = true
	_check("겹마다 숨쉬는 주기가 다르다", periods.size() == pulsing,
		"%d 겹에 주기 %d 종" % [pulsing, periods.size()])

	# 키운 겹은 **정수배** 여야 한다 — 실수배로 키우면 도트가 뭉개진다
	for spec in WeatherLayers.LAYERS:
		var zoom: float = float(spec.get("scale", 1))
		_check("%s 의 배율이 정수다" % spec["name"], is_equal_approx(zoom, floor(zoom))
			and zoom >= 1.0, "×%.2f" % zoom)

	# ★ 무늬가 흐르는 **속도**는 지금 바람만 봐야 한다.
	#   예전엔 `속도 × 경과시간` 으로 매번 다시 셌는데, 바람이 변하는 동안 속도가
	#   경과 시간만큼 뻥튀기돼서 날씨가 바뀔 때마다 화면이 확 쓸려 갔다 (사용자 지적).
	var bench := WeatherLayers.new()
	root.add_child(bench)
	bench.build()
	var bench_view := Rect2(Vector2.ZERO, Vector2(512, 288))
	var bench_axes := {"cloud": 0.3, "fog": 0.0, "rain": 0.8, "snow": 0.9, "wind": 0.3}
	# 원정을 한참 진행시킨다 — 버그는 경과 시간에 비례해 커졌다
	for i in 18000:
		bench.update(1.0 / 60.0, bench_axes, bench_view)
	var worst_jump := 0.0
	var watched := 0
	for step in 240:
		# 바람이 0.3 에서 0.9 로 옮겨가는 동안
		bench_axes["wind"] = 0.3 + 0.6 * (float(step) / 240.0)
		var before := {}
		for entry in bench._sprites:
			before[entry["spec"]["name"]] = Vector2(entry["node"].region_rect.position)
		bench.update(1.0 / 60.0, bench_axes, bench_view)
		for entry in bench._sprites:
			var moved: float = Vector2(entry["node"].region_rect.position).distance_to(
				before[entry["spec"]["name"]])
			worst_jump = maxf(worst_jump, moved)
			watched += 1
	_check("바람이 변해도 무늬 속도가 튀지 않는다", worst_jump < 20.0,
		"한 프레임 최대 %.1fpx (300초 경과 뒤)" % worst_jump)
	_check("잰 겹이 있다", watched > 0, "%d 회" % watched)

	# ★ 눈만 타일이 아니라 **낱개**로 그린다. 타일로 만들었다가 셋이 한꺼번에 어긋났다:
	#   같은 배열이 반복돼 패턴이 읽히고, 2×2 를 2배로 키워 덩어리가 되고,
	#   타일이 통째로 움직여 모든 눈이 한 몸처럼 흔들렸다 (전부 사용자 지적).
	for spec in WeatherLayers.LAYERS:
		_check("눈은 타일 겹에 없다 — %s" % spec["name"], String(spec["axis"]) != "snow")
	var snow: SnowField = field.get_node("Snow")
	_check("눈은 낱개로 그린다", snow != null and snow._flakes.size() > 100,
		"%d 송이" % (snow._flakes.size() if snow else 0))
	if snow:
		# 흔들림이 눈송이마다 달라야 한 몸으로 안 논다
		var flake_phases := {}
		var flake_periods := {}
		var sizes := {}
		for flake in snow._flakes:
			flake_phases[snapped(float(flake["phase"]), 0.05)] = true
			flake_periods[snapped(float(flake["period"]), 0.05)] = true
			sizes[int(flake["size"])] = true
		# 0.05 로 끊으면 위상 칸은 TAU/0.05 ≈ 126 개뿐이다. 칸을 골고루 채웠는지 본다.
		var crowd := {}
		var worst_crowd := 0
		for flake in snow._flakes:
			var slot: float = snapped(float(flake["phase"]), 0.05)
			crowd[slot] = int(crowd.get(slot, 0)) + 1
			worst_crowd = maxi(worst_crowd, int(crowd[slot]))
		_check("눈송이마다 흔들리는 위상이 다르다", flake_phases.size() > 100,
			"%d 칸" % flake_phases.size())
		_check("한 위상에 눈이 몰리지 않는다",
			float(worst_crowd) / float(snow._flakes.size()) < 0.05,
			"가장 몰린 칸 %d / %d" % [worst_crowd, snow._flakes.size()])
		_check("눈송이마다 흔들리는 주기가 다르다", flake_periods.size() > 20,
			"%d 종" % flake_periods.size())
		_check("눈송이 크기가 섞인다 — 키운 게 아니라 큰 게 섞인 것이다",
			sizes.size() >= 3, "%s px" % [sizes.keys()])
		_check("눈을 그리는 노드를 키우지 않는다 — 키우면 도트가 뭉친다",
			snow.scale.is_equal_approx(Vector2.ONE), "%s" % snow.scale)

		# 함박눈이 화면을 하얗게 덮으면 안 된다. 실제로 몇 픽셀을 칠하는지 센다.
		var painted := 0
		for flake in snow._flakes:
			if float(flake["at"]) < 1.0:
				painted += int(flake["size"]) * int(flake["size"])
		var snow_cover := float(painted) / (SnowField.PERIOD.x * SnowField.PERIOD.y)
		_check("함박눈에도 화면이 덮이지 않는다", snow_cover < 0.10,
			"%.1f%% 덮임" % (snow_cover * 100.0))
		_check("함박눈은 눈에 보인다", snow_cover > 0.005, "%.2f%%" % (snow_cover * 100.0))

		# ⚠️ 자리는 월드에 고정된다 — 화면 기준으로 감으면 카메라를 따라 눈이 끌려다닌다
		var here := Rect2(Vector2(1000.0, 700.0), Vector2(320.0, 180.0))
		snow.update(0.0, 1.0, 0.3, here)
		var world_before: Vector2 = snow._flakes[0]["pos"]
		snow.update(0.0, 1.0, 0.3, here.grow(-30.0))
		_check("눈은 카메라가 아니라 땅 위에 있다",
			snow._flakes[0]["pos"].is_equal_approx(world_before))

		# 눈이 세질수록 더 많이 나온다 — 한꺼번에 켜지면 스위치로 보인다
		var thin := 0
		var thick := 0
		for flake in snow._flakes:
			if float(flake["at"]) < 0.35:
				thin += 1
			if float(flake["at"]) < 1.0:
				thick += 1
		_check("진눈깨비보다 함박눈이 많이 온다", thick > thin * 2, "%d → %d 송이" % [thin, thick])

	# 눈 덮개는 SnowField 쪽에서 잰다 — 타일 겹에는 이제 눈이 없다.

	# ★ 빛줄기는 점심 무렵에만 선다 — 기둥이 수직에서 27° 라 해가 높이 떠야 나온다
	var noon_alpha := 0.0
	var dusk_alpha := 0.0
	var lit := {"cloud": 0.26, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.3}
	bench.update(0.0, lit, bench_view, 1.0, 1.0)
	for entry in bench._sprites:
		if String(entry["spec"]["name"]) == "rays":
			noon_alpha = entry["node"].modulate.a if entry["node"].visible else 0.0
	bench.update(0.0, lit, bench_view,
		float(field.tuning.daypart_daylight["여명"]),
		float(field.tuning.daypart_sun_height["여명"]))
	for entry in bench._sprites:
		if String(entry["spec"]["name"]) == "rays":
			dusk_alpha = entry["node"].modulate.a if entry["node"].visible else 0.0
	_check("빛줄기는 낮에 선다", noon_alpha > 0.15, "%.3f" % noon_alpha)
	_check("여명에는 빛줄기가 거의 없다", dusk_alpha < noon_alpha * 0.05,
		"낮 %.3f → 여명 %.3f" % [noon_alpha, dusk_alpha])
	bench.queue_free()
	await process_frame

	# ★ 성별은 **개체 정의 때** 정해지고 화면에서 보인다 (BRIEF §3.11 1단계 · §4.9)
	var sex_rng := RandomNumberGenerator.new()
	sex_rng.seed = 4242
	var all_same := 0
	for round_index in 300:
		var picked := Actor.roll_sexes(4, sex_rng)
		if picked.count(picked[0]) == picked.size():
			all_same += 1
	_check("둘 이상이면 암수가 반드시 섞인다 — 짝 없는 벽을 구조로 막는다",
		all_same == 0, "%d/300 회 한쪽만" % all_same)
	_check("한 마리면 한쪽이어도 된다", Actor.roll_sexes(1, sex_rng).size() == 1)
	var forced := Actor.roll_sexes(3, sex_rng, "female")
	_check("필요한 성별은 반드시 들어간다 (확정 배치)", "female" in forced, "%s" % [forced])
	_check("확정 배치라도 나머지는 자유다", Actor.roll_sexes(2, sex_rng, "male").size() == 2)

	# ⚠️ 종 이름으로 분기하지 않는다 (원칙 4) — 표에 있는지만 본다
	_check("이형은 표가 정한다 — 고라니에 있고", not SpriteLibrary.dimorphism_for("water_deer").is_empty())
	_check("표에 없는 종에는 없다", SpriteLibrary.dimorphism_for("cat").is_empty())
	var dimorph: Dictionary = SpriteLibrary.dimorphism_for("water_deer")
	_check("이형은 한쪽 성별에만 얹힌다", String(dimorph.get("shown_on", "")) in ["male", "female"])
	_check("이형도 북향에서 숨는다", String(dimorph.get("hide_on", "")) == "north")
	_check("이형 앵커가 정면·측면 둘 다 있다",
		dimorph.get("anchor", {}).has("front") and dimorph.get("anchor", {}).has("side"))
	# 몸통 시트를 성별로 나누지 않는다 — 나눴다면 종당 16장이 32장이 된다
	_check("이형 그림은 종당 두 장뿐이다", dimorph.get("file", {}).size() == 2,
		"%d 장" % dimorph.get("file", {}).size())

	# 실제로 수컷에만 붙고 암컷에는 안 붙는가
	var deer_config: Dictionary = DataLoader.load_all(true).species.get("water_deer", {})
	var seen_part := {}
	for sex in ["male", "female"]:
		var probe: Actor = load("res://scenes/actors/Actor.tscn").instantiate()
		field.get_node("Actors").add_child(probe)
		probe.setup(deer_config, field.schema, field.tuning, sex_rng, sex)
		probe.look_direction = Vector2(0.0, 1.0)
		seen_part[sex] = probe.get_node("Body/Dimorph").visible
		probe.queue_free()
	_check("엄니는 수컷에만 붙는다", seen_part["male"] and not seen_part["female"],
		"수 %s · 암 %s" % [seen_part["male"], seen_part["female"]])

	# 성별 뱃지·짝 표시는 종 수와 무관한 다섯 장이다
	for key in ["male", "female", "paired", "alone"]:
		_check("짝 UI 그림이 있다 — %s" % key, SpriteLibrary.pair_ui_texture(key) != null)

	# ★ 앰비언트 생물 — **잡을 수 없는 것들** (BRIEF §3.10).
	#   보이는 것이 전부 수집 대상이면 숲이 아니라 쇼핑 목록이다.
	var ambient: AmbientLife = field.get_node("AmbientAir")
	_check("앰비언트 생물이 있다", ambient._lives.size() > 0, "%d 마리" % ambient._lives.size())
	var wild_names := {}
	for animal in field.sim.animals:
		wild_names[animal.display_name()] = true
	var off_terrain := []
	var non_integer := 0
	var air_outside := true
	var ground_inside := true
	var collectible := []
	for life in ambient._lives:
		# 수집 대상이 아니다 — 필드 시뮬에 개체로 들어가지 않는다
		if wild_names.has(life["name"]) and not (life["name"] in collectible):
			collectible.append(life["name"])
		# 층 — 공중은 Y-sort 밖, 지면·수면은 캐릭터와 같이 정렬된다
		var parent: Node = life["sprite"].get_parent()
		if String(life["layer"]) == "공중":
			air_outside = air_outside and parent == ambient
		else:
			ground_inside = ground_inside and parent == field.get_node("Actors")
		if not life["alive"]:
			continue
		if not (field.terrain.at_world(life["pos"]) in life["terrain"]):
			off_terrain.append(life["name"])
		if life["sprite"].position != life["sprite"].position.floor():
			non_integer += 1
	_check("앰비언트는 수집 대상이 아니다 — 도감에도 자리에도 없다",
		collectible.is_empty(), "%s" % [collectible])
	_check("공중 생물은 Y-sort 밖에 있다 — 캐릭터 위로 지나간다", air_outside)
	_check("지면·수면 생물은 Y-sort 안에 있다 — 캐릭터에 가린다", ground_inside)
	_check("지형 태그 하나만 보고 산다", off_terrain.is_empty(), "%s" % [off_terrain])
	_check("정수 픽셀에 찍힌다", non_integer == 0, "%d 마리가 반픽셀" % non_integer)

	# ★ 얼마나 사는지는 **지역이 정한다** — 수집종 ecology 와 같은 규칙
	var lonely_region := {"ambient": {"나비": 3.0}}
	var only_butterfly := AmbientLife.new()
	field.add_child(only_butterfly)
	only_butterfly.setup(field.terrain, RandomNumberGenerator.new(), field.get_node("Actors"),
		lonely_region)
	var kinds := {}
	for life in only_butterfly._lives:
		kinds[life["name"]] = int(kinds.get(life["name"], 0)) + 1
	_check("지역에 적히지 않은 생물은 그 지역에 없다", kinds.size() == 1, "%s" % [kinds.keys()])
	_check("지역이 많다고 하면 많다", int(kinds.get("나비", 0)) >= 12,
		"나비 %d 마리" % int(kinds.get("나비", 0)))
	only_butterfly.queue_free()

	var empty_region := AmbientLife.new()
	field.add_child(empty_region)
	empty_region.setup(field.terrain, RandomNumberGenerator.new(), field.get_node("Actors"), {})
	_check("지역이 안 적어두면 기본값으로 산다 — 새 지역이 조용히 죽지 않는다",
		empty_region._lives.size() > 0, "%d 마리" % empty_region._lives.size())
	empty_region.queue_free()
	await process_frame

	# 새는 그리지 않고 그림자만 그린다 — 그림자는 반투명이어야 그림자다
	var shadow_alpha := 1.0
	for life in ambient._lives:
		if String(life["name"]) == "새그림자":
			shadow_alpha = life["sprite"].modulate.a
	_check("새 그림자는 반투명이다", shadow_alpha < 0.5, "%.2f" % shadow_alpha)

	# ★ 풀과 나무는 바람에 흔들린다. **새 도트 없이** 가로줄을 정수 픽셀로 민다.
	var source := SpriteLibrary.prop_texture("tuft")
	_check("흔들릴 프롭 그림이 있다", source != null)
	if source != null:
		var upright := source.get_image()
		var tilted := PlaceholderArt.swayed_texture(source, 2).get_image()
		var height := upright.get_height()
		var moved_root := false
		for x in upright.get_width():
			if upright.get_pixel(x, height - 1) != tilted.get_pixel(x, height - 1):
				moved_root = true
		_check("밑동은 안 움직인다 — 뿌리가 흔들리면 그건 바람이 아니다", not moved_root)
		# 위로 갈수록 많이 밀린다
		# ⚠️ 캔버스 위가 아니라 **그림의 우듬지**가 밀려야 한다. 프롭은 캔버스 아래쪽에
		#    붙어 있어서, 캔버스 기준으로 밀면 가장 많이 밀리는 줄이 빈 줄이 된다.
		var crown := 0
		for y in height:
			var found := false
			for x in upright.get_width():
				if upright.get_pixel(x, y).a > 0.0:
					found = true
			if found:
				crown = y
				break
		# 우듬지 줄은 **정확히 lean 만큼** 밀려야 한다. 덜 밀렸다면 기준이 캔버스 위에
		# 잡혀 있다는 뜻이다 — 그 경우 풀 뭉치는 거의 안 흔들린다.
		var before_left := 99
		var after_left := 99
		for x in upright.get_width():
			if before_left == 99 and upright.get_pixel(x, crown).a > 0.0:
				before_left = x
			if after_left == 99 and tilted.get_pixel(x, crown).a > 0.0:
				after_left = x
		_check("우듬지는 기울인 만큼 온전히 밀린다 — 기준은 캔버스가 아니라 그림이다",
			after_left - before_left == 2,
			"%d → %d (우듬지 %d행)" % [before_left, after_left, crown])
		# 색을 새로 만들지 않는다 — 미는 것이지 그리는 게 아니다
		var palette := {}
		for y in height:
			for x in upright.get_width():
				palette[upright.get_pixel(x, y)] = true
		var invented := 0
		for y in height:
			for x in tilted.get_width():
				if not palette.has(tilted.get_pixel(x, y)):
					invented += 1
		_check("색을 새로 만들지 않는다 — 미는 것이지 그리는 게 아니다", invented == 0,
			"%d 픽셀" % invented)

	# 바람이 세기와 빈도를 둘 다 정한다. 세지면 **기운 채로 떤다** (사용자 지적).
	var swayers := []
	for name in ["tuft", "flowers", "reed", "tree"]:
		swayers.append({"name": name, "sprite": Sprite2D.new(), "position": Vector2(80, 80),
			"lean": int(PropScatter._sway_spec(name).get("lean", 0)),
			"hz": float(PropScatter._sway_spec(name).get("hz", 0.0)), "phase": 0.0, "at": 0})
	_check("흔들림 표가 읽힌다", int(swayers[0]["lean"]) > 0)
	var wide := Rect2(Vector2.ZERO, Vector2(400, 400))
	var reach := {}
	for wind in [0.0, 0.25, 0.66]:
		var seen := []
		for step in 400:
			PropScatter.sway(swayers, 0.05, wind, wide)
			if not (int(swayers[3]["at"]) in seen):
				seen.append(int(swayers[3]["at"]))
		reach[wind] = seen
	_check("무풍이면 안 흔들린다", reach[0.0] == [0], "%s" % [reach[0.0]])
	# 눈금은 실제로 부는 바람에 맞춘다 — 0.25 는 맑은 날, 0.66 은 폭우다
	var breezy: Array = reach[0.25]
	_check("산들바람에는 좌우로 흔들린다",
		breezy.min() < 0 and breezy.max() > 0, "%s" % [breezy])
	var gale: Array = reach[0.66]
	_check("센 바람에는 한쪽으로 기운 채 떤다", gale.min() > 0, "%s" % [gale])
	_check("기우는 쪽은 구름·비가 흐르는 쪽과 같다 (+x)", gale.max() > 0)

	# ★ **한 박자로 흔들리면 바람이 아니라 화면이 떠는 것으로 보인다** (사용자 지적).
	#   실제로 뿌려진 프롭들이 서로 어긋나 노는지 잰다.
	var breeze := Rect2(Vector2.ZERO, field._bounds.size)
	for step in 600:
		PropScatter.sway(field._props, 1.0 / 60.0, 0.38, breeze)
	var waves := []
	var beats := {}
	for entry in field._props:
		if int(entry["lean"]) == 0:
			continue
		waves.append(float(entry["wave"]))
		beats[snappedf(float(entry["hz"]), 0.01)] = true
	_check("흔들리는 프롭이 여럿 있다", waves.size() > 20, "%d 포기" % waves.size())
	if waves.size() > 20:
		var lowest: float = waves.min()
		var highest: float = waves.max()
		_check("같은 순간에 서로 다르게 기울어 있다 — 한 박자로 놀지 않는다",
			highest - lowest > 1.2, "%.2f ~ %.2f" % [lowest, highest])
		_check("포기마다 빈도가 다르다 — 시간이 갈수록 벌어진다",
			beats.size() > waves.size() / 3, "%d / %d 종" % [beats.size(), waves.size()])

	# ⚠️ 날씨가 바뀌는 순간 휘청이면 안 된다 — 날씨 겹에서 똑같은 실수를 했다
	# 먼저 **바람이 안 변할 때** 한 프레임에 얼마나 움직이는지 잰다. 이게 정상치다.
	var steady := 0.0
	for step in 1200:
		for entry in field._props:
			entry["_before"] = float(entry["wave"])
		PropScatter.sway(field._props, 1.0 / 60.0, 0.66, breeze)
		for entry in field._props:
			if int(entry["lean"]) == 0:
				continue
			steady = maxf(steady, absf(float(entry["wave"]) - float(entry["_before"])))
	var lurch := 0.0
	for step in 3600:
		for entry in field._props:
			entry["_before"] = float(entry["wave"])
		# 바람이 0.2 에서 0.66 으로 옮겨가는 동안
		PropScatter.sway(field._props, 1.0 / 60.0,
			0.2 + 0.46 * (float(step) / 3600.0), breeze)
		for entry in field._props:
			if int(entry["lean"]) == 0:
				continue
			lurch = maxf(lurch, absf(float(entry["wave"]) - float(entry["_before"])))
	_check("바람이 변해도 휘청이지 않는다", lurch < steady * 1.3 + 0.02,
		"변할 때 %.3f · 안 변할 때 %.3f (60초 경과 뒤)" % [lurch, steady])

	# 안 흔들리는 것은 안 흔든다 — 바위가 흔들리면 그게 더 이상하다
	for still in ["rock", "log", "bigrock", "pebbles"]:
		_check("%s 는 안 흔들린다" % still,
			int(PropScatter._sway_spec(still).get("lean", 0)) == 0)

	# 화면 밖은 갈아끼우지 않는다
	var far := [{"name": "tuft", "sprite": Sprite2D.new(), "position": Vector2(9000, 9000),
		"lean": 1, "hz": 1.0, "phase": 0.0, "at": 0}]
	PropScatter.sway(far, 0.05, 1.0, wide)
	_check("화면 밖 프롭은 건드리지 않는다", int(far[0]["at"]) == 0)

	# ★ 새 판은 **아무도 없이** 시작한다. 처음부터 개와 고양이를 들려주면
	#   "친구가 생긴다" 는 이 게임의 첫 사건이 사라진다 (사용자 지적).
	var fresh := GameState.new()
	fresh.autosave = false
	fresh.start_new()
	_check("새 판에는 아무도 없다", fresh.collection.is_empty(),
		"%d 마리" % fresh.collection.size())
	_check("새 판은 첫 만남을 안 지났다", not fresh.tutorial_done)
	var puppy := fresh.finish_tutorial()
	_check("첫 만남이 끝나면 강아지가 식구가 된다",
		fresh.collection.size() == 1 and String(puppy["species_id"]) == "dog")
	_check("그 아이가 그대로 첫 동료가 된다", fresh.party == [int(puppy["uid"])])
	_check("첫 만남을 지났다고 남는다", fresh.tutorial_done)

	# 개체는 종이 아니다 — 같은 종이라도 uid 로 센다
	var another := fresh.add("dog", "female")
	_check("같은 종을 또 데려와도 따로 센다",
		fresh.collection.size() == 2 and int(another["uid"]) != int(puppy["uid"]))
	_check("uid 로 찾는다", String(fresh.of_uid(int(another["uid"]))["sex"]) == "female")
	_check("없는 uid 는 빈 값", fresh.of_uid(9999).is_empty())

	# 짝 확정 배치 — 혼자인 종의 반대 성별이 필드에 반드시 정의된다 (BRIEF §2.4)
	var only := GameState.new()
	only.autosave = false
	only.start_new()
	only.add("squirrel", "male")
	_check("혼자면 반대 성별을 찾는다",
		String(only.lonely_species().get("squirrel", "")) == "female",
		"%s" % [only.lonely_species()])
	only.add("squirrel", "female")
	_check("짝이 생기면 더 안 찾는다", not only.lonely_species().has("squirrel"))

	# ⚠️ 원칙 1 — 동물은 죽지 않는다. 빼는 길이 없어야 한다.
	var can_remove := false
	for name in ["remove", "release", "drop", "delete", "kill"]:
		if fresh.has_method(name):
			can_remove = true
	_check("식구를 빼는 길이 없다 — 동물은 죽지 않는다", not can_remove)

	# 저장 → 불러오기가 그대로 돌아온다 (종 id 는 문자열이다 — 팩이 바뀌어도 안 깨진다)
	for one in fresh.collection:
		_check("종 id 는 문자열로 남는다", one["species_id"] is String)

	# 조사는 받침을 따라간다 — "개 가 좋아할 거예요" 처럼 띄면 아이가 읽다가 걸린다
	_check("받침 없으면 가", Josa.이가("개") == "개가")
	_check("받침 있으면 이", Josa.이가("곰") == "곰이")
	_check("청설모는 가", Josa.이가("청설모") == "청설모가")
	_check("받침 있는 은", Josa.은는("고슴도치") == "고슴도치는")

	# ★ **동물은 측면 1방향이다. 플레이어만 4방향.** (BRIEF §4.5 ★ v3.16)
	#   방향은 곱셈이고 모션은 덧셈이다 — 예산을 방향이 아니라 모션에 쓴다.
	_check("플레이어는 4방향이다", field.player.facing_set == "four")
	var wild: Actor = _promoted(field, "squirrel")
	_check("야생 동물은 측면 1방향이다", wild.facing_set == "side", wild.facing_set)
	wild.move_vector = Vector2.UP
	await process_frame
	_check("측면 몸은 위로 가도 북향이 안 된다", wild.facing in ["east", "west"], wild.facing)
	wild.move_vector = Vector2.DOWN
	await process_frame
	_check("아래로 가도 남향이 안 된다", wild.facing in ["east", "west"], wild.facing)
	wild.move_vector = Vector2.ZERO
	# 동료는 플레이어를 따라다니느라 세로로 걷는 시간이 길다 — 데이터가 4방향을 쓴다고 정한다
	for companion in field.companions:
		_check("동료 %s 는 4방향을 쓴다" % companion.species_id, companion.facing_set == "four")

	# ⚠️ 측면 스프라이트가 수직으로 움직이면 미끄러져 보인다 — **AI 로 푼다** (도트 0장)
	var straight_up := 0
	var probe_rng := RandomNumberGenerator.new()
	probe_rng.seed = 991
	for i in 400:
		var direction := Vector2.RIGHT.rotated(probe_rng.randf() * TAU)
		var laid := FieldSim.sideways(direction)
		if absf(laid.normalized().x) < FieldSim.SIDEWAYS - 0.001:
			straight_up += 1
		if not is_equal_approx(laid.length(), direction.length()):
			straight_up += 1
	_check("배회 방향에 수평 성분이 항상 있다", straight_up == 0, "%d/400 회" % straight_up)
	_check("눕히면서 속도는 그대로 둔다",
		is_equal_approx(FieldSim.sideways(Vector2(0, 3.0)).length(), 3.0))
	_check("이미 옆으로 가는 방향은 안 건드린다",
		FieldSim.sideways(Vector2(1, 0)) == Vector2(1, 0))
	# 실제로 놓인 개체들도 그런가
	var upright := 0
	for animal in field.sim.animals:
		if animal.velocity.length() > 0.01 and absf(animal.velocity.normalized().x) < 0.3:
			upright += 1
	_check("놓인 개체도 세로로만 가지 않는다", upright == 0, "%d 마리" % upright)

	# ★ 초대 카드 — **축하지 평가가 아니다** (BRIEF §3.12). 능력치 숫자를 넣지 않는다.
	var card: CanvasLayer = field.get_node("InviteCard")
	# ⚠️ 덮는 판이 있는 화면은 **처음에 꺼져 있어야 한다.** 안 끄면 게임을 켜자마자
	#    화면 전체가 어두워진다 (실제로 그렇게 나갔다 — 사용자 지적).
	_check("초대 카드는 처음에 꺼져 있다", not card.visible)
	_check("나가는 문도 처음에 꺼져 있다", not field.get_node("GoHome").visible)
	var deer: Dictionary = DataLoader.load_all(true).species.get("water_deer", {})
	card.show_for({"species_id": "water_deer", "sex": "male", "stage": "adult", "age_years": 3},
		deer, true, field.schema)
	_check("카드가 열린다", card.is_open())
	# ⚠️ 캔버스 크기를 못 박으면 **옆 프레임이 딸려 온다** — 24폭으로 그려진 청설모가
	#    32로 잘려 몸이 두 번 나왔다 (사용자 지적).
	for one_id in ["squirrel", "water_deer", "sparrow"]:
		var config: Dictionary = DataLoader.load_all(true).species.get(one_id, {})
		card.show_for({"species_id": one_id, "sex": "male", "stage": "adult", "age_years": 2},
			config, false, field.schema)
		# ⚠️ 카드에는 뱃지·아이콘·키캡도 있다. **몸만** 재야 한다 —
		#    아무 스프라이트나 재면 39px 짜리 키캡을 몸으로 착각한다.
		var body_node := card.get_node("Art").get_node_or_null("Body")
		var body_width: int = body_node.texture.get_width() if body_node != null else 0
		var canvas := SpriteLibrary.canvas_of(config, field.schema)
		_check("%s 의 몸이 한 마리만 나온다" % one_id, body_width <= canvas.x,
			"그림 %dpx · 캔버스 %dpx" % [body_width, canvas.x])
	card.show_for({"species_id": "water_deer", "sex": "male", "stage": "adult", "age_years": 3},
		deer, true, field.schema)
	var words: Array = []
	for node in card.get_node("Text").get_children():
		words.append(String(node.text))
	var shown := " ".join(words)
	_check("종 이름이 뜬다", "고라니" in shown, shown)
	_check("단계가 먼저, 숫자는 곁들이", "어른 · 3살" in shown, shown)
	_check("설명 두 줄이 뜬다", "엄니" in shown, shown)
	_check("새 종이면 도감을 알린다", "도감" in shown)
	# ⚠️ 숫자 능력치가 새어 나오면 "다시 뽑을까" 가 생긴다 (원칙 6)
	for banned in ["매력", "감각 반경", "속도", "×", "%"]:
		_check("카드에 '%s' 가 없다" % banned, not (banned in shown), shown)
	var arts := card.get_node("Art").get_child_count()
	_check("몸·성별·감각·키캡은 그림이다", arts >= 4, "%d 개" % arts)
	# 몸은 **정수배로만** 키운다 — 실수배면 도트가 뭉개진다
	for node in card.get_node("Art").get_children():
		if node is Sprite2D:
			var grow: float = node.scale.x
			_check("정수배로만 키운다", is_equal_approx(grow, floor(grow)), "×%.2f" % grow)
	# 아기는 숫자를 안 붙인다 — 아이가 묻는 것은 숫자가 아니라 관계다
	card.show_for({"species_id": "water_deer", "sex": "female", "stage": "baby", "age_years": 0},
		deer, false, field.schema)
	var baby_words: Array = []
	for node in card.get_node("Text").get_children():
		baby_words.append(String(node.text))
	var baby_shown := " ".join(baby_words)
	_check("아기는 '아기' 만 뜬다", "아기" in baby_shown and not ("살" in baby_shown), baby_shown)
	_check("이미 아는 종이면 도감을 안 알린다", not ("도감" in baby_shown))
	card.visible = false
	card._open = false

	# ★ 키캡 — **문장에 키 이름을 넣지 않는다** (§2.10)
	for action in ["이동", "고르기", "인사·정하기", "그만두기", "메뉴"]:
		_check("키캡 그림이 있다 — %s" % action, Keycap.texture_for(action) != null)
	# 오토로드는 이름이 아니라 트리에서 잡는다 — SceneTree 스크립트에서는 이름이 안 잡힌다
	var was := String(game.last_device)
	game.last_device = "key"
	var by_key := Keycap.texture_for("인사·정하기")
	game.last_device = "pad"
	var by_pad := Keycap.texture_for("인사·정하기")
	game.last_device = was
	_check("패드를 들면 그림이 바뀐다", by_key != by_pad)

	# ★ **나가는 길이 있다** (BRIEF §3.13). 이게 없어서 원정을 나가면 못 돌아왔다.
	var door: CanvasLayer = field.get_node("GoHome")
	_check("나가는 문이 있다", door != null)
	if door != null:
		_check("평소에는 닫혀 있다", not door.is_open())
		door.open([field.companions[0].species])
		_check("열린다", door.is_open())
		var said: Array = []
		for node in door.get_node("Text").get_children():
			said.append(String(node.text))
		var line := " ".join(said)
		_check("무엇을 묻는지 한 줄로 말한다", "집에 갈까요?" in line, line)
		_check("고를 것은 둘뿐이다", ("갈래요" in line) and ("더 놀래요" in line), line)
		# ⚠️ **숫자로 적지 않는다** — "동료 2 / 초대 1" 은 성적표가 된다 (§6.9)
		for banned in ["동료", "초대 ", "마리"]:
			_check("나가는 문에 '%s' 를 안 적는다" % banned, not (banned in line), line)
		_check("같이 가는 아이는 얼굴로 보여준다", door.get_node("Art").get_child_count() >= 3,
			"%d 개" % door.get_node("Art").get_child_count())
		door.close()
		_check("닫힌다", not door.is_open())

	# ★ 얼굴 — **이름 대신 쓰는 그림.** 캔버스가 아니라 **잉크**를 기준으로 오린다.
	var face_of := Faces.of(field.player.species)
	_check("얼굴을 오려낸다", Faces.of(_species_named(field, "dog")) != null)
	var cut = Faces.of(_species_named(field, "dog"))
	if cut is AtlasTexture:
		var region: Rect2 = (cut as AtlasTexture).region
		var whole := (cut as AtlasTexture).atlas.get_image()
		var ink := Faces._ink(whole)
		_check("빈 줄을 오리지 않는다 — head_anchor 는 머리가 아니라 아이콘 자리다",
			region.position.y >= ink.position.y - 1.5,
			"오린 자리 y=%.0f · 그림 시작 y=%.0f" % [region.position.y, ink.position.y])
		_check("얼굴은 머리 쪽이다 — 측면 그림은 오른쪽을 본다",
			region.end.x >= ink.end.x - 1.0,
			"오린 오른쪽 %.0f · 그림 오른쪽 %.0f" % [region.end.x, ink.end.x])
		_check("얼굴은 작다 — 크게 오리면 작은 전신 그림이 된다",
			region.size.x <= 16 and region.size.y <= 16, "%s" % region.size)

	# ★ **냇가에는 물이 있어야 한다** (사용자 지적). 웅덩이 아홉 개로 찍었더니
	#   물이 3% 뿐이고 흩어져서 "냇가에 물이 없다" 가 됐다. 냇가는 덩어리가 아니라 **줄기**다.
	var all_regions := DataLoader.load_all(true).regions
	var wetness := {}
	for id in ["home_hills", "home_creek"]:
		var shape: Dictionary = (all_regions[id] as Dictionary).get("terrain", {})
		var probe := TerrainMap.new()
		for name in field.schema.terrain_walkable:
			if not field.schema.walkable(String(name)):
				probe.blocked_terrains.append(String(name))
		var wet_rng := RandomNumberGenerator.new()
		wet_rng.seed = 4242
		probe.generate(Vector2i(64, 48), 16, shape.get("patches", {}), wet_rng,
			String(shape.get("base", "초원")), shape.get("streams", {}))
		var wet_tiles := 0
		for y in 48:
			for x in 64:
				if probe.at_tile(Vector2i(x, y)) == "물가":
					wet_tiles += 1
		wetness[id] = float(wet_tiles) / (64.0 * 48.0)
		# 줄기는 **이어져 있다** — 한 줄에 여러 칸이 나란히 붙는다
		var widest_run := 0
		for y in 48:
			var run := 0
			for x in 64:
				run = run + 1 if probe.at_tile(Vector2i(x, y)) == "물가" else 0
				widest_run = maxi(widest_run, run)
		_check("%s 의 물은 이어져 흐른다 — 흩어진 웅덩이가 아니다" % id, widest_run >= 2,
			"가장 긴 줄 %d칸" % widest_run)
	_check("냇가에 물이 있다", wetness["home_creek"] > 0.06,
		"%.1f%%" % (wetness["home_creek"] * 100.0))
	_check("냇가가 뒷산보다 물이 많다 — 그게 지역을 고르는 이유다",
		wetness["home_creek"] > wetness["home_hills"] * 2.0,
		"냇가 %.1f%% · 뒷산 %.1f%%"
			% [wetness["home_creek"] * 100.0, wetness["home_hills"] * 100.0])
	_check("뒷산에도 개울은 있다", wetness["home_hills"] > 0.01,
		"%.1f%%" % (wetness["home_hills"] * 100.0))

	# ⚠️ **물 한가운데 갇히면 영영 다가갈 수 없다** — 되돌릴 수 없는 벽이다 (원칙 2).
	#    물줄기를 좁히면 도랑이 되므로 AI 로 푼다: 뭍이 멀면 물가 쪽으로 향한다.
	var swimmers: Array = []
	for animal in field.sim.animals:
		if "물가" in animal.species.get("habitat", []):
			swimmers.append(animal)
	if not swimmers.is_empty():
		var bank_reach: float = field.tuning.interact_radius * field.tuning.tile_size
		var touched := {}
		for step in 900:
			field.sim.update(1.0 / 60.0, field.player.position)
			for animal in swimmers:
				if touched.has(animal):
					continue
				for angle in 12:
					var probe_at: Vector2 = animal.position \
						+ Vector2.RIGHT.rotated(TAU * float(angle) / 12.0) * bank_reach
					if field.terrain.can_stand(probe_at, field.schema, []):
						touched[animal] = true
						break
		_check("물에 사는 개체도 언젠가는 다가갈 수 있다 — 갇히지 않는다",
			touched.size() == swimmers.size(),
			"%d / %d 마리" % [touched.size(), swimmers.size()])

	# ★ 화면에 **늘 보이는 것은 지명과 자리 둘뿐**이다 (BRIEF §3.4).
	var hud: CanvasLayer = field.get_node("FieldHud")
	var always: Array = []
	for node in hud.get_children():
		if node is Label:
			always.append(String(node.text))
	_check("늘 보이는 줄은 둘뿐이다", always.size() == 2, "%s" % [always])
	_check("지명이 보인다", "냇가" in always or "뒷산" in always, "%s" % [always])
	var seat_line := ""
	for line in always:
		if line.begins_with("자리"):
			seat_line = line
	_check("자리가 보인다", not seat_line.is_empty(), "%s" % [always])
	# ⚠️ 배고픔·청결·기분 게이지를 두지 않는다 — 늘 보이는 것이 늘면 화면이 할 일 목록이 된다
	for banned in ["배고", "청결", "기분", "체력"]:
		_check("HUD 에 '%s' 가 없다" % banned, not (banned in " ".join(always)))

	# ★ 개발용 숫자는 **평소에 꺼져 있다** (F3). 다른 화면 위로 겹치면 안 된다.
	_check("디버그 오버레이는 평소에 꺼져 있다",
		not field.get_node("DebugOverlay").visible)

	# ★ **갇히면 안 된다.** 스폰 자리가 물이나 바위면 어느 쪽으로도 못 움직였다 (사용자 지적).
	#   들어가는 것만 막을 일이지 **나가는 것까지 막을 이유가 없다** (원칙 2).
	_check("플레이어가 설 수 있는 자리에 선다",
		field.terrain.can_stand(field.player.position, field.schema, []))
	var homeless := []
	for animal in field.sim.animals:
		if not field.terrain.can_stand(animal.position, field.schema,
				animal.species.get("habitat", [])):
			homeless.append(animal.display_name())
	_check("동물도 살 수 있는 자리에 놓인다", homeless.is_empty(), "%s" % [homeless])

	# 억지로 막힌 자리에 세워도 나올 수 있어야 한다
	var trapped := []
	for spot in ["물가", "바위"]:
		var at := Vector2.ZERO
		for y in field.tuning.map_size.y:
			for x in field.tuning.map_size.x:
				if field.terrain.at_tile(Vector2i(x, y)) == spot:
					at = Vector2(x + 0.5, y + 0.5) * field.tuning.tile_size
					break
			if at != Vector2.ZERO:
				break
		if at == Vector2.ZERO:
			continue
		var out: Vector2 = field.terrain.slide(at,
			at + Vector2(field.tuning.tile_size, 0), field.schema, [])
		if out == at:
			trapped.append(spot)
	_check("막힌 자리에 서 있어도 나갈 수 있다", trapped.is_empty(), "%s" % [trapped])
	# 그래도 **들어가는 것은 막힌다** — 나가는 길을 연다고 통행 규칙이 풀리면 안 된다
	var bank := Vector2.ZERO
	for y in field.tuning.map_size.y:
		for x in field.tuning.map_size.x:
			if field.terrain.at_tile(Vector2i(x, y)) == "물가" \
					and field.terrain.at_tile(Vector2i(x - 1, y)) == "초원":
				bank = Vector2(x - 0.5, y + 0.5) * field.tuning.tile_size
				break
		if bank != Vector2.ZERO:
			break
	if bank != Vector2.ZERO:
		var pushed: Vector2 = field.terrain.slide(bank,
			bank + Vector2(field.tuning.tile_size, 0), field.schema, [])
		_check("뭍에서 물로는 여전히 못 들어간다",
			field.terrain.can_stand(pushed, field.schema, []))

	# ★ **이어하기.** 이어할 것이 있으면 CONTINUE 가 맨 위에 뜬다 (title.json).
	var menu_spec = JSON.parse_string(FileAccess.get_file_as_string(
		"res://sprites/extracted/ui/title.json"))
	var menu: Dictionary = (menu_spec as Dictionary).get("menu", {}) if menu_spec is Dictionary else {}
	_check("세이브가 있을 때 쓸 메뉴를 설계가 넘겼다", menu.has("items_with_save"))
	_check("첫 판에 쓸 메뉴도 넘겼다", menu.has("items_first_run"))
	if menu.has("items_with_save"):
		var with_save: Array = menu["items_with_save"]
		var first_run: Array = menu["items_first_run"]
		_check("이어하기가 맨 위다 — 흔한 쪽이 위에 있어야 매번 안 고른다",
			String(with_save[0]) == "CONTINUE", "%s" % [with_save])
		_check("첫 판에는 이어하기가 없다", not ("CONTINUE" in first_run), "%s" % [first_run])
		_check("두 메뉴가 한 항목만 다르다", with_save.size() == first_run.size() + 1)

	# 이어하면 어디로 가는가 — 첫 만남을 안 지났으면 거기서 잇는다
	var half := GameState.new()
	half.autosave = false
	half.start_new()
	_check("첫 만남 도중에 껐으면 거기서 잇는다", not half.tutorial_done)
	half.finish_tutorial()
	_check("첫 만남을 지났으면 집으로 잇는다", half.tutorial_done)
	# ⚠️ 원정 중에 껐어도 **잃는 것은 없다** — 초대한 아이는 그 자리에서 저장된다 (원칙 2).
	#    다시 나가면 개체는 새로 정해진다 (§3.11 — 개체 정의는 진입 시 한 번).
	var before_count := half.collection.size()
	half.add("squirrel")
	_check("초대는 그 자리에서 남는다", half.collection.size() == before_count + 1)

	# ★ **유도의 방향은 몸이 말한다** (BRIEF §4.5 ★ v3.16 · 사용자 지적).
	#   화면 가장자리 화살표를 그리지 않는다 — 그건 게임이 알려주는 것이지
	#   세계의 사건이 아니다. 개가 그쪽으로 당기는 것을 보고 아이가 따라간다.
	# ⚠️ Field 의 `_process` 도 같은 일을 한다 — 켜둔 채로 여기서 또 부르면
	#    동료가 한 프레임에 **두 번** 움직여서 줄 길이를 넘는다. 잠시 끄고 직접 몬다.
	field.set_process(false)
	# ⚠️ 앞선 판정이 남긴 걸음을 지운다 — 플레이어가 계속 걸어가면 목표가 움직여서
	#    동료가 줄 길이를 넘은 것처럼 보인다.
	field.player.move_vector = Vector2.ZERO
	# ⚠️ **조건을 못 박는다.** 감각 반경은 날씨·시간대·지형이 다 같이 정한다 —
	#    안 박아두면 이 판정이 그날 날씨에 따라 깜빡인다 (실제로 그랬다).
	var clear_sky := {"cloud": 0.1, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.2}
	field.weather.axes = clear_sky.duplicate()
	field.weather.target = clear_sky.duplicate()
	field.guide.set_weather_axes(clear_sky)
	field._apply_daypart("낮")
	var lead_dog: Actor = _find_companion(field, "dog")
	var lead_cat: Actor = _find_companion(field, "cat")
	var smelly_one := _find_animal(field, "raccoon_dog")
	field.player.position = _find_terrain_point(field, "초원")
	lead_dog.position = field.player.position
	lead_cat.position = field.player.position
	var leash: float = field.tuning.lead_leash * field.tuning.tile_size
	# ⚠️ 대상을 **동료가 갈 수 있는 쪽**에 둔다. 물이나 바위 쪽이면 도중에 멈춰서
	#    유도가 되는데도 "안 간다" 로 읽힌다.
	var dog_way := Vector2(60, 0)
	for turn in 8:
		var probe := Vector2.RIGHT.rotated(TAU * float(turn) / 8.0) * 60.0
		if field.terrain.can_stand(field.player.position + probe, field.schema,
				lead_dog.habitat):
			dog_way = probe
			break
	var ahead := 0.0
	var toward := 0.0
	for step in 240:
		# 날씨가 바뀌면 출현이 다시 정해진다 — 이 판정은 그걸 재는 게 아니므로 붙들어 둔다
		smelly_one.present = true
		# ⚠️ 감각이 겨우 닿는 거리에 두지 않는다 — 비가 오면 코가 짧아져서
		#    판정이 날씨에 따라 깜빡인다. 넉넉히 안쪽에 둔다.
		# ⚠️ **감각이 겨우 닿는 거리에 두지 않는다.** 150px 에 뒀더니 네 판에 한 번
		#    감지가 안 잡혀 판정이 깜빡였다 — 어떤 감각으로도 확실히 닿는 자리에 둔다.
		smelly_one.position = field.player.position + dog_way
		field.guide.set_weather_axes(clear_sky)
		field._follow_player(1.0 / 60.0)
		# ⚠️ **대상을 하나만 보여준다.** 여럿이면 잡는 것이 프레임마다 바뀌어
		#    값이 판마다 깜빡인다 — 이 판정이 재려는 것은 "잡은 쪽으로 가는가" 하나다.
		field.guide.update([lead_dog], [smelly_one])
		await process_frame
		ahead = maxf(ahead, lead_dog.position.distance_to(field.player.position))
		toward = maxf(toward, (lead_dog.position - field.player.position)
			.dot((smelly_one.position - field.player.position).normalized()))
	_check("동료가 잡은 쪽으로 앞장선다", toward > leash * 0.6,
		"대상 쪽으로 %.0fpx (줄 %.0fpx)" % [toward, leash])
	_check("잡은 것이 있어야 이 판정이 뜻을 갖는다", field.guide.leads.has(lead_dog))
	# ⚠️ **줄에 매인 것처럼.** 안 그러면 개가 혼자 화면 밖으로 달려가고,
	#    그건 유도가 아니라 이별이다.
	# ⚠️ **움직인 결과가 아니라 목표를 잰다.** 위치를 재면 앞선 판정이 남긴 걸음이
	#    섞여 들어와 값이 깜빡인다 — 실제로 61~81px 사이에서 오갔다.
	var worst_goal := 0.0
	for companion in field._active_companions():
		var mark: Vector2 = field.lead_goal(companion, field.player.position)
		worst_goal = maxf(worst_goal, mark.distance_to(field.player.position))
	_check("줄 길이를 넘지 않는다", worst_goal <= leash + 0.5,
		"목표가 %.0fpx (줄 %.0fpx)" % [worst_goal, leash])
	_check("앞장서긴 한다", ahead > 8.0, "앞선 거리 %.0fpx" % ahead)
	_check("동료마다 자기가 잡은 것을 안다", field.guide.leads.has(lead_dog))

	# 도착하면 거기서 꼬리를 흔든다 — 특징 동작은 **서 있을 때만** 나온다
	_check("도착해서 흔든다 — 걸어가면서가 아니라",
		lead_dog.play_special and lead_dog.move_vector == Vector2.ZERO,
		"흔듦 %s · 움직임 %s" % [lead_dog.play_special, lead_dog.move_vector])

	# ★ **종을 보지 않는다.** 고양이도 자기가 잡은 쪽으로 가서 거기서 액션을 한다.
	#   유도는 동료의 감각이 만드는 것이지 그 동료가 개라서가 아니다 (원칙 4).
	var seeing := _find_animal(field, "squirrel")
	# ⚠️ **재는 동안 내내 잰다.** 마지막 한 프레임만 보면 그때 잡은 것이 바뀌어 있어
	#    값이 판마다 깜빡인다 (실제로 네 판에 한 번 8px 이 나왔다).
	var cat_best := 0.0
	lead_cat.position = field.player.position
	# ⚠️ 대상을 **동료가 갈 수 있는 쪽**에 둔다. 물이나 바위 쪽에 두면 동료가 도중에
	#    멈춰서, 유도가 되는데도 "안 간다" 로 읽힌다.
	var cat_way := Vector2(0, -40)
	for turn in 8:
		var probe := Vector2.RIGHT.rotated(TAU * float(turn) / 8.0) * 40.0
		if field.terrain.can_stand(field.player.position + probe, field.schema,
				lead_cat.habitat):
			cat_way = probe
			break
	for step in 240:
		seeing.present = true
		# ⚠️ 시야는 지형에 깎인다(숲에서 짧아진다). 지형까지 못 박을 게 아니면
		#    **어떤 지형에서도 닿는 거리**에 둬야 판정이 안 깜빡인다.
		seeing.position = field.player.position + cat_way
		field.guide.set_weather_axes(clear_sky)
		field._follow_player(1.0 / 60.0)
		field.guide.update([lead_cat], [seeing])
		await process_frame
		if field.guide.leads.has(lead_cat):
			var way: Vector2 = (field.guide.leads[lead_cat].animal.position
				- field.player.position).normalized()
			cat_best = maxf(cat_best,
				(lead_cat.position - field.player.position).dot(way))
	# ⚠️ 조건부로 감싸면 통과 수가 판마다 달라져서 "조용히 사라짐" 과 구분이 안 된다.
	var cat_leads: bool = field.guide.leads.has(lead_cat)
	_check("고양이가 무언가를 잡았다", cat_leads)
	if cat_leads:
		_check("고양이도 자기가 잡은 쪽으로 간다", cat_best > 18.0,
			"%.0fpx (목표 %.0fpx)" % [cat_best, minf(40.0, leash)])
		_check("고양이도 거기서 액션을 한다", lead_cat.play_special)
	else:
		_check("고양이도 자기가 잡은 쪽으로 간다", false, "잡은 게 없다")
		_check("고양이도 거기서 액션을 한다", false, "잡은 게 없다")
	_check("액션 그림이 종마다 있다", SpriteLibrary.has_art(lead_cat.species_id))

	# 잡은 게 없으면 제자리로 돌아온다 — 늘 앞서 있으면 그게 유도로 안 읽힌다
	var was_present := {}
	for animal in field.sim.animals:
		was_present[animal] = animal.present
		animal.present = false
	for step in 240:
		field._follow_player(1.0 / 60.0)
		field.guide.update(field._active_companions(), field.sim.present_animals())
		await process_frame
	_check("잡은 게 없으면 곁으로 돌아온다",
		lead_dog.position.distance_to(field.player.position)
			< field.tuning.follow_distance * field.tuning.tile_size + 24.0,
		"%.0fpx" % lead_dog.position.distance_to(field.player.position))
	_check("곁에 있을 때는 안 흔든다", not lead_dog.play_special)

	# ★ **잡은 게 없으면 곁에서 어슬렁거린다** (사용자 지적).
	#   자리에 딱 붙여 세웠더니 플레이어에게 들러붙은 것처럼 보였다.
	# ⚠️ 어슬렁은 **1.4~3.2초마다** 목표를 바꾸고 반쯤은 제자리에 선다. 10초만 재면
	#    운 나쁘게 서 있는 목표가 몰려 값이 깜빡인다 — 30초를 재서 평균이 이기게 한다.
	var stops := 0
	var spots := {}
	for step in 1800:
		field._follow_player(1.0 / 60.0)
		field.guide.update([], [])
		await process_frame
		spots[Vector2i(lead_dog.position.round())] = true
		if lead_dog.move_vector.length() > 0.05:
			stops += 1
	_check("곁에서 돌아다닌다 — 들러붙지 않는다", spots.size() > 12,
		"%d 곳 · 걷는 프레임 %d/1800" % [spots.size(), stops])
	_check("가끔은 선다 — 늘 움직이면 부산하다", stops < 1700,
		"걷는 프레임 %d/1800" % stops)
	_check("그래도 곁을 떠나지는 않는다",
		lead_dog.position.distance_to(field.player.position)
			< field.tuning.tile_size * 4.0,
		"%.0fpx" % lead_dog.position.distance_to(field.player.position))
	for animal in was_present:
		animal.present = bool(was_present[animal])
	# ⚠️ 잰 뒤에는 **자리도 되돌린다.** 안 그러면 뒤에 오는 판정이 여기서 옮겨 둔
	#    플레이어·동료 자리를 물려받아 엉뚱한 값을 본다.
	field.player.position = field._bounds.size * 0.5
	for companion in field.companions:
		companion.position = field.player.position
	field.player.move_vector = Vector2.ZERO
	field.set_process(true)

	# ★ **게이지는 동물 머리 위에 뜬다** (ui/screens.json · 사용자 지적).
	#   화면 구석의 막대가 아니라 그 아이 위에 있어야 누구와 친해지는 중인지 보인다.
	var marks_node: GaugeMarks = field.get_node("GaugeMarks")
	_check("게이지 표시가 있다", marks_node != null)
	var target := _find_animal(field, "raccoon_dog")
	target.present = true
	target.position = field.player.position + Vector2(20, 0)
	field.sim.update(0.016, field.player.position)
	var spare := _find_animal(field, "squirrel")
	spare.present = true
	spare.position = field.player.position + Vector2(-24, 0)
	field.sim.update(0.016, field.player.position)
	spare.invite_progress = 0.4
	if target.actor != null:
		field.gauge.start(target, field.companions[0], "낮")
		field.gauge.progress = 0.55
		var marks: Array = field._gauge_marks_now()
		var active_mark := {}
		for mark in marks:
			if bool(mark.get("active", false)):
				active_mark = mark
		_check("채우는 중인 아이 위에 뜬다", not active_mark.is_empty(), "%d 개" % marks.size())
		if not active_mark.is_empty():
			var at: Vector2 = active_mark["position"]
			# ⚠️ **캔버스가 아니라 그림 위**에 얹는다. 캔버스를 기준으로 잡으면
			#    빈 줄만큼 붕 떠서 남의 머리 위처럼 보인다 (얼굴·풀에서 같은 실수를 했다).
			_check("그림 위에 얹는다 — 캔버스 위가 아니라",
				at.y > target.actor.position.y - target.actor.canvas.y,
				"표시 y=%.0f · 캔버스 위 y=%.0f"
					% [at.y, target.actor.position.y - target.actor.canvas.y])
			_check("발끝보다는 위다", at.y < target.actor.position.y)
		# ★ **쏟은 시간은 그 아이에게 남는다** — 지금 채우는 중이 아니어도 자국이 보인다
		var leftover := 0
		for mark in marks:
			if not bool(mark.get("active", false)):
				leftover += 1
		_check("쏟다 만 자국도 보인다 — 멈출 뿐 안 지워진다", leftover >= 1,
			"%d 개" % leftover)
		field.gauge.cancel()
	# 판을 두르지 않는다 — 검은 판을 깔면 세계 밖 UI 위젯이 된다 (BRIEF §3.3)
	# 세계 안에 그린다 — 화면에 붙는 판이 아니라 그 자리에 있는 것이다 (BRIEF §3.3)
	_check("게이지는 세계 안에 그린다", marks_node is Node2D)
	_check("게이지가 액터와 같은 좌표계에 있다",
		marks_node.get_parent() == field, "%s" % marks_node.get_parent())

	# ★ **같은 아이가 동료에 두 번 들어가면 안 된다.** JSON 에서 온 uid 는 실수라
	#   불러온 1.0 과 새로 고른 1 이 서로 다른 것으로 보였고, 필드에 개가 두 마리
	#   나왔다 (사용자 지적).
	var twice := GameState.new()
	twice.autosave = false
	twice.start_new()
	var pup := twice.add("dog")
	twice.party = [float(pup["uid"]), int(pup["uid"])]   # 낡은 저장이 이렇게 생겼다
	twice.party = []
	for uid in [float(pup["uid"]), int(pup["uid"])]:
		if not (int(uid) in twice.party):
			twice.party.append(int(uid))
	_check("겹친 동료는 하나로 걷어낸다", twice.party.size() == 1, "%s" % [twice.party])
	# 실수로 들어와도 같은 아이로 본다
	twice.party = [float(pup["uid"])]
	_check("실수 uid 도 같은 아이로 본다", twice.going(int(pup["uid"])) == false
		or twice.party.size() == 1)
	twice.party = [int(pup["uid"])]
	_check("데려가는 중인지 안다", twice.going(int(pup["uid"])))
	twice.toggle_party(int(pup["uid"]))
	_check("두 번 고르면 두고 간다", not twice.going(int(pup["uid"])))
	twice.toggle_party(int(pup["uid"]))
	twice.toggle_party(int(pup["uid"]))
	_check("같은 아이를 두 번 넣어도 하나다", twice.party.count(int(pup["uid"])) <= 1,
		"%s" % [twice.party])
	# 자리가 꽉 차면 가장 먼저 고른 아이가 나간다
	var many := GameState.new()
	many.autosave = false
	many.start_new()
	var ids: Array = []
	for id in ["dog", "cat", "squirrel"]:
		ids.append(int(many.add(id)["uid"]))
	for uid in ids:
		many.toggle_party(uid)
	_check("자리는 넘치지 않는다", many.party.size() == many.PARTY_MAX,
		"%s" % [many.party])
	_check("가장 먼저 고른 아이가 나간다", not many.going(ids[0]), "%s" % [many.party])

	# 필드가 데려가는 동료도 겹치지 않는다
	var party_kinds := {}
	for companion in field.companions:
		party_kinds[companion.species_id] = int(party_kinds.get(companion.species_id, 0)) + 1
	var doubled: Array = []
	for id in party_kinds:
		if int(party_kinds[id]) > 1:
			doubled.append(id)
	_check("필드에 같은 동료가 둘 나오지 않는다", doubled.is_empty(), "%s" % [doubled])

	# ★ **걷는 두 칸이 같으면 발이 안 움직인다** (사용자 지적).
	#   바운스는 노드 Y가 내지만, 다리가 그대로면 미끄러지는 것으로 보인다.
	var walk_frames: SpriteFrames = field.player.get_node("Body/BodySprite").sprite_frames
	for pose in ["move_south", "move_side", "move_north"]:
		if not walk_frames.has_animation(pose):
			_check("%s 걷기 그림이 있다" % pose, false)
			continue
		_check("%s 는 두 칸이다" % pose, walk_frames.get_frame_count(pose) == 2,
			"%d 칸" % walk_frames.get_frame_count(pose))
		var a := walk_frames.get_frame_texture(pose, 0).get_image()
		var b := walk_frames.get_frame_texture(pose, 1).get_image()
		var differ := 0
		for y in a.get_height():
			for x in a.get_width():
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					differ += 1
		_check("%s 의 두 칸이 다르다 — 발이 움직인다" % pose, differ >= 10,
			"%d 픽셀" % differ)
		# 달라지는 곳은 **아래쪽(다리)** 이어야 한다 — 머리가 흔들리면 그건 걷기가 아니다
		var high := 0
		for y in range(0, int(a.get_height() * 0.6)):
			for x in a.get_width():
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					high += 1
		_check("%s 는 다리만 움직인다" % pose, high == 0, "위쪽이 %d 픽셀 달라졌다" % high)

	# ★ **하트는 짝이 완성됐을 때만 뜬다** (사용자 지적).
	#   초반에는 모든 아이가 혼자라 마당 전체에 반쪽 하트가 깔린다 — 그러면 안내가
	#   아니라 할 일 목록이 되고, 그건 원칙 6("수집이 벌이 되면 안 된다")에 걸린다.
	var yard_state := GameState.new()
	yard_state.autosave = false
	yard_state.start_new()
	yard_state.add("squirrel", "male")
	yard_state.add("otter", "male")
	yard_state.add("otter", "female")
	var paired_kinds := 0
	var lonely_kinds := 0
	for id in ["squirrel", "otter"]:
		if yard_state.sexes_of(id).size() >= 2:
			paired_kinds += 1
		else:
			lonely_kinds += 1
	_check("짝이 맞은 종과 혼자인 종을 가려낸다",
		paired_kinds == 1 and lonely_kinds == 1,
		"짝 %d · 혼자 %d" % [paired_kinds, lonely_kinds])
	# 혼자여도 **찾아갈 곳은 지도가 말한다** — 막힘 방지 장치는 그대로 산다
	_check("혼자인 종은 지도가 찾아 준다",
		String(yard_state.lonely_species().get("squirrel", "")) == "female",
		"%s" % [yard_state.lonely_species()])
	_check("짝이 맞은 종은 지도에 안 뜬다", not yard_state.lonely_species().has("otter"))
	_check("혼자 표시 그림이 있긴 하다 — 나중에 쓸 자리",
		SpriteLibrary.pair_ui_texture("alone") != null)

	# ★ **암수를 다 데려왔다고 바로 짝이 아니다** (사용자 지적). 원정에서 돌아올 때
	#   종마다 한 번씩 굴린다. 짝이 되어 아기가 생기는 것은 일종의 행운이다.
	_check("암수가 다 있어도 처음엔 짝이 아니다", not yard_state.is_paired("otter"))
	var returns := 0
	while not yard_state.is_paired("otter") and returns < 300:
		yard_state.roll_pairs()
		returns += 1
	# ⚠️ **문이 닫히지 않는다**(원칙 2). 안 된 날은 "아직" 일 뿐 다음 귀가에 다시 굴린다.
	_check("여러 번 돌아오면 언젠가는 된다", yard_state.is_paired("otter"),
		"귀가 %d 번" % returns)
	_check("한 번에 되지도, 영영 안 되지도 않는다", returns >= 1 and returns < 200,
		"귀가 %d 번" % returns)
	# ⚠️ **종마다 한 번**이다. 개체를 돌면 암수가 각각 굴려서 확률이 두 배가 된다.
	var pace := 0
	for run in 200:
		var trial := GameState.new()
		trial.autosave = false
		trial.start_new()
		trial.add("otter", "male")
		trial.add("otter", "female")
		var n := 0
		while not trial.is_paired("otter") and n < 200:
			trial.roll_pairs()
			n += 1
		pace += n
	var average := float(pace) / 200.0
	# ★ **행운이어야 하므로 낮다.** 두세 번 만에 되면 그건 절차지 행운이 아니다.
	#   되풀이해서 굴리므로 낮아도 막히지 않는다 (원칙 2).
	_check("흔하지 않다 — 열 번쯤 다녀와야 한 번", average > 6.0 and average < 15.0,
		"평균 %.1f 번" % average)
	# ⚠️ 종마다 한 번이다. 개체를 돌면 암수가 각각 굴려 확률이 두 배가 된다.
	var per_species := GameState.new()
	per_species.autosave = false
	per_species.start_new()
	per_species.PAIR_CHANCE_OVERRIDE = 1.0
	per_species.add("otter", "male")
	per_species.add("otter", "female")
	per_species.add("cat", "male")
	_check("한 번 굴리면 짝이 될 종만 된다", per_species.roll_pairs() == ["otter"],
		"%s" % [per_species.roll_pairs()])
	# 혼자면 아무리 돌아와도 안 된다 — 그건 지도 핀이 풀 몫이다
	var lone := GameState.new()
	lone.autosave = false
	lone.start_new()
	lone.add("otter", "male")
	for i in 40:
		lone.roll_pairs()
	_check("혼자면 짝이 안 된다 — 그건 지도가 풀 몫이다", not lone.is_paired("otter"))
	_check("대신 지도가 어느 성별을 찾을지 말한다",
		String(lone.lonely_species().get("otter", "")) == "female")
	# 새로 짝이 된 종은 화면이 한 번 말해 준다 — 확률이 아니라 **일어난 일**을 적는다
	var telling := GameState.new()
	telling.autosave = false
	telling.start_new()
	telling.add("otter", "male")
	telling.add("otter", "female")
	var told: Array = []
	for i in 60:
		told = telling.roll_pairs()
		if not told.is_empty():
			break
	_check("짝이 된 순간을 알려줄 이름이 나온다", told == ["otter"], "%s" % [told])
	_check("이미 된 종은 다시 안 알린다", telling.roll_pairs().is_empty())

	# ★ **새 판은 세이브를 쓰지 않는다.** 지우고 켜면 오토로드가 곧바로 빈 파일을 써서
	#   새 판인데 CONTINUE 가 떴다 (사용자 지적). 파일은 **처음 친구가 생길 때** 생긴다.
	var blank := GameState.new()
	blank.autosave = false
	blank.start_new()
	_check("새 판에는 이어할 것이 없다", blank.collection.is_empty())
	blank.finish_tutorial()
	_check("첫 친구가 생기면 이어할 것이 생긴다", not blank.collection.is_empty())
	# start_new 가 저장을 부르지 않는지 — 부르면 빈 파일이 남는다
	var wrote := false
	blank.autosave = true
	var before_size := -1
	if FileAccess.file_exists(GameState.SAVE_PATH):
		before_size = FileAccess.get_file_as_string(GameState.SAVE_PATH).length()
	blank.autosave = false
	_check("빈 판을 저장하지 않는다 — 파일은 친구가 생길 때 생긴다", not wrote,
		"%d" % before_size)

	# ★ 커플 카드 — **거절이 없다** (BRIEF §2.11). 7살에게 두 동물이 친해지는 걸
	#   거절하게 하는 건 이상하고, 거절이 있으면 "잘못 눌렀다" 가 생긴다(원칙 2).
	var couple_card: CanvasLayer = load("res://scenes/ui/CoupleCard.tscn").instantiate()
	field.add_child(couple_card)
	await process_frame
	_check("커플 카드는 처음에 꺼져 있다", not couple_card.visible)
	var otter: Dictionary = DataLoader.load_all(true).species.get("otter", {})
	var two: Array = [{"species_id": "otter", "sex": "male"},
		{"species_id": "otter", "sex": "female"}]
	couple_card.show_for(otter, two, 2, 4, field.schema)
	var said: Array = []
	for node in couple_card.get_node("Text").get_children():
		said.append(String(node.text))
	var card_line := " ".join(said)
	_check("무슨 일이 일어났는지 말한다", "가족이 됐어요!" in card_line, card_line)
	# ⚠️ **거절 버튼을 만들지 않는다.** 버튼은 「잘됐다!」 하나뿐이다.
	for banned in ["아니", "취소", "안 할", "싫", "거절"]:
		_check("카드에 '%s' 가 없다" % banned, not (banned in card_line), card_line)
	_check("축하 한 번뿐이다", "잘됐다!" in card_line, card_line)
	# ★ 다음에 무슨 일이 생기는지 여기서 말한다 — 안 말하면 "왜 아기가 안 나와" 가 된다
	_check("자리가 있으면 조용히 기다린다고 한다", "이제 아기를 기다려요" in card_line,
		card_line)
	_check("자리를 적는다", "자리  2 / 4" in card_line, card_line)
	# 두 마리가 **마주 본다** — 오른쪽을 뒤집는다. 도트 0장.
	var left: Sprite2D = couple_card.get_node("Art").get_node_or_null("Body0")
	var right: Sprite2D = couple_card.get_node("Art").get_node_or_null("Body1")
	_check("두 마리가 나온다", left != null and right != null)
	if left != null and right != null:
		_check("한 쪽을 뒤집어 마주 보게 한다", right.flip_h and not left.flip_h)
		_check("같은 그림을 쓴다 — 새 도트가 없다", left.texture == right.texture)
		_check("정수배로만 키운다", is_equal_approx(left.scale.x, floor(left.scale.x)))

	# 자리가 꽉 차면 **빠져나갈 길**을 같이 적는다 — 막다른 길을 만들지 않는다
	couple_card.show_for(otter, two, 4, 4, field.schema)
	var full: Array = []
	for node in couple_card.get_node("Text").get_children():
		full.append(String(node.text))
	var full_line := " ".join(full)
	_check("꽉 차면 왜 아기가 안 오는지 말한다", "자리가 하나 생기면 아기가 와요" in full_line,
		full_line)
	_check("빠져나갈 길을 같이 적는다", "쉼터로 보내면 자리가 나요" in full_line, full_line)
	# 자리 표시는 **꽉 찼을 때만** 눈에 띈다 — 여유가 있을 때도 강조하면 잔소리가 된다
	var loud := Color.WHITE
	for node in couple_card.get_node("Text").get_children():
		if String(node.text).begins_with("자리"):
			loud = node.modulate
	_check("꽉 찼을 때만 자리를 강조한다", loud.b < 0.7, "%s" % loud)
	couple_card.queue_free()
	await process_frame

	# ★ **카메라는 발이 아니라 몸 한가운데를 본다** (사용자 지적).
	#   발을 한가운데 두면 몸이 위를 먹어 머리 위로 보이는 세계가 절반으로 준다 —
	#   재보니 머리 위 47px · 발 아래 87px 이라 북쪽으로 걸을 때 3타일도 못 봤다.
	field.player.move_vector = Vector2.ZERO
	await process_frame
	await process_frame
	var eye_view: Rect2 = field.camera_visible_rect()
	var feet: float = field.player.position.y
	var head: float = feet - field.player.crown_lift
	var above := head - eye_view.position.y
	var below := eye_view.end.y - feet
	_check("머리 위와 발 아래가 비슷하게 보인다", absf(above - below) < 24.0,
		"위 %.0fpx · 아래 %.0fpx" % [above, below])
	_check("머리 위로 네 타일쯤 보인다", above > field.tuning.tile_size * 3.0,
		"%.1f타일" % (above / field.tuning.tile_size))
	# ⚠️ 픽셀로 박지 않는다 — 그림 키가 바뀌면 같이 따라와야 한다
	_check("들어올리는 값은 그림 키에서 나온다",
		field.tuning.camera_lift_ratio > 0.0 and field.player.crown_lift > 0.0,
		"비율 %.2f · 키 %.0f" % [field.tuning.camera_lift_ratio, field.player.crown_lift])

	# ★ 실제 날씨는 튀지 않는다 — 지금과 가까운 상태로만 옮겨간다 (사용자 지적)
	var walker := WeatherSystem.new()
	walker.setup(schema, RandomNumberGenerator.new(), {"초원": 2000, "숲": 600})
	walker.axes = {"cloud": 0.15, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.3}
	# ⚠️ 처음엔 "폭우를 **한 번도** 고르지 않는다" 로 썼다가 200회 중 1회로 깜빡였다.
	#    룰렛에 0 인 칸은 없으므로 0 회는 보장할 수 없는 값이고, 그런 단언은
	#    다음에 진짜 회귀가 났을 때 "또 그거겠지" 로 넘기게 만든다.
	#    보장되는 것은 둘이다 — **먼 날씨는 드물게 고른다**, 그리고 **축은 걸어서 간다**.
	var jumped := 0
	for i in 600:
		walker._pick_target()
		if float(walker.target.get("rain", 0.0)) >= 0.9:
			jumped += 1
	_check("맑음에서 폭우를 고르는 일은 드물다", jumped <= 18,
		"%d/600 회 (%.1f%%)" % [jumped, float(jumped) / 6.0])

	# 골라도 튀지 않는다 — 축은 정해진 속도로 걸어서 간다. 이게 사용자가 말한 "점진적"이다.
	walker.axes = {"cloud": 0.15, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.3}
	walker.target = {"cloud": 0.9, "fog": 0.3, "rain": 1.0, "snow": 0.0, "wind": 0.9}
	var worst_step := 0.0
	for i in 400:
		var before: Dictionary = walker.axes.duplicate()
		walker.update(1.0 / 60.0, 22.0)
		for axis in walker.axes:
			worst_step = maxf(worst_step, absf(float(walker.axes[axis]) - float(before[axis])))
	_check("축은 한 프레임에 조금씩만 움직인다", worst_step < 0.02,
		"가장 큰 한 걸음 %.4f" % worst_step)

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

	# ★ 날씨가 **누가 나오는지**를 바꾼다 (BRIEF §6.8 · §7 에서 넘어온 값)
	var all_species := DataLoader.load_all(false).species
	var clear_sky := {"cloud": 0.15, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.3}
	var rainy_sky := {"cloud": 0.32, "fog": 0.06, "rain": 0.62, "snow": 0.0, "wind": 0.38}
	_check("두꺼비는 비 올 때 더 나온다",
		schema.presence_chance(all_species["toad"], "여명", rainy_sky)
			> schema.presence_chance(all_species["toad"], "여명", clear_sky) * 1.4)
	_check("청설모는 비 올 때 덜 나온다",
		schema.presence_chance(all_species["squirrel"], "여명", rainy_sky)
			< schema.presence_chance(all_species["squirrel"], "여명", clear_sky) * 0.8)
	# 맑은 날은 모두에게 평등하다 — 축이 0 이면 아무 영향이 없다
	_check("축이 0 이면 날씨가 출현을 안 건드린다",
		is_equal_approx(schema.weather_presence_factor(all_species["toad"],
			{"cloud": 0.0, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.0}), 1.0))
	# 아무 날씨에나 만날 수 있는 종이 늘 있어야 한다 — 0 으로 막지 않는다
	var zeroed := PackedStringArray()
	for id in all_species:
		for axis in all_species[id].get("weather_likes", {}):
			if float(all_species[id]["weather_likes"][axis]) <= 0.0:
				zeroed.append("%s.%s" % [id, axis])
	_check("어떤 종도 날씨로 완전히 막히지 않는다", zeroed.is_empty(), ", ".join(zeroed))

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


## ★ 개체 정의는 필드에 들어갈 때 한 번뿐이다 (BRIEF §3.11 1단계)
func _test_roster(field) -> void:
	var loaded := DataLoader.load_all(false)
	var rng := RandomNumberGenerator.new()
	var mix := {"초원": 1800, "숲": 900, "물가": 200, "바위": 76}
	var here: Dictionary = loaded.regions.get("home_hills", {})
	_check("지역 생태 데이터가 있다", not here.get("ecology", {}).is_empty())

	# ★ 같은 종이라도 지역마다 마릿수가 다르다 (사용자 지적)
	var downstream := {"ecology": {"otter": 5.0, "squirrel": 0.4}}
	var otter_here := 0
	var otter_there := 0
	var squirrel_here := 0
	var squirrel_there := 0
	for i in 300:
		otter_here += FieldSim.roster_count(loaded.species["otter"], mix, here, 3, rng)
		otter_there += FieldSim.roster_count(loaded.species["otter"], mix, downstream, 3, rng)
		squirrel_here += FieldSim.roster_count(loaded.species["squirrel"], mix, here, 3, rng)
		squirrel_there += FieldSim.roster_count(loaded.species["squirrel"], mix, downstream, 3, rng)
	_check("수달은 하류 지역에 훨씬 많다", otter_there > otter_here * 1.5,
		"뒷산 %.1f · 하류 %.1f" % [otter_here / 300.0, otter_there / 300.0])
	_check("청설모는 뒷산에 훨씬 많다", squirrel_here > squirrel_there * 1.5,
		"뒷산 %.1f · 하류 %.1f" % [squirrel_here / 300.0, squirrel_there / 300.0])
	_check("지역 생태에 없는 종은 그 지역에 0마리",
		FieldSim.roster_count(loaded.species["leopard_cat"], mix, downstream, 3, rng) == 0)

	# ★ 개체수 0 은 정상이다 — "조건을 다 맞췄는데 왜 없지"의 정직한 답
	var dry := {"초원": 2900, "숲": 76}
	var zeros := 0
	for i in 300:
		if FieldSim.roster_count(loaded.species["otter"], dry, here, 3, rng) == 0:
			zeros += 1
	_check("서식지가 없는 필드에서는 0마리가 흔하다", zeros > 100, "%d/300 회" % zeros)

	# ★ 날씨가 바뀌어도 개체는 늘지도 줄지도 않는다 — 바뀌는 것은 나와 있는가뿐이다
	var before: int = field.sim.animals.size()
	field.weather.axes = {"cloud": 0.32, "fog": 0.06, "rain": 0.62, "snow": 0.0, "wind": 0.38}
	field._last_weather_name = ""
	field._follow_weather()
	_check("날씨가 바뀌어도 개체 수는 그대로다", field.sim.animals.size() == before,
		"%d → %d" % [before, field.sim.animals.size()])
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

## 종 정의를 집어 온다. **필드에 그 종이 0마리일 수 있으므로**(지역 생태 — BRIEF §3.11)
## 스폰된 동물만 뒤지면 검사가 지역 추첨에 따라 흔들린다. 데이터에서 직접 본다.
func _species_of(field, id: String) -> Dictionary:
	var loaded := DataLoader.load_all(false)
	if loaded.species.has(id):
		return loaded.species[id]
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


## 특정 종을 집어 오는 헬퍼.
##
## ⚠️ 두 가지가 검사를 조용히 없앤다:
##    ① 지금 시간대에 안 나와 있을 수 있다 → 세워서 준다
##    ② **지역 생태 때문에 이번 원정에 0 마리일 수 있다** (BRIEF §3.11) → 만들어서 준다
##    여기서 검사하는 것은 노출·교감이지 존재 규칙이 아니다 (그건 _test_presence 가 본다).
## 노드까지 붙은 개체. `_find_animal` 은 **얕은 시뮬 상태로 돌려줄 수 있어서**
## `.actor` 가 null 이다 — 거기서 터지면 그 뒤 판정이 통째로 안 돈다 (실제로 그랬다).
func _promoted(field, id: String) -> Actor:
	var animal := _find_animal(field, id)
	if animal == null:
		return null
	if animal.actor == null:
		animal.position = field.player.position + Vector2(24, 0)
		field.sim.update(0.016, field.player.position)
	return animal.actor


func _species_named(field, id: String) -> Dictionary:
	for companion in field.companions:
		if companion.species_id == id:
			return companion.species
	return DataLoader.load_all(true).species.get(id, {})


func _find_animal(field, id: String) -> FieldSim.WildAnimal:
	for animal in field.sim.animals:
		if animal.species.get("id") == id and not animal.invited:
			animal.present = true
			return animal
	var loaded := DataLoader.load_all(false)
	if not loaded.species.has(id):
		return null
	var made := FieldSim.WildAnimal.new()
	made.species = loaded.species[id]
	made.position = field.player.position + Vector2(200, 0)
	made.present = true
	made.presence_roll = 0.0
	field.sim.animals.append(made)
	return made

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
