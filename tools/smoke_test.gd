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
	_test_boot()
	await _test_sense_reach(field)
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
	gauge.start(animal, dog, "낮")
	_check("게이지가 시작된다", gauge.active)

	var completed := false
	for i in 400:
		# 게이지 도중에 대상이 멀어지고 플레이어가 딴 데로 가도 —
		animal.position += Vector2(500, 500)
		field.player.position += Vector2(-200, 0)
		if gauge.update(0.02):
			completed = true
			break
		if not gauge.active:
			break
	_check("멀어져도 게이지가 끊기지 않고 끝까지 찬다", completed)

	gauge.cancel()
	gauge.start(animal, dog, "낮")
	gauge.update(0.02)
	gauge.cancel()
	_check("취소는 명시적으로 눌렀을 때만 된다", not gauge.active and gauge.progress == 0.0)
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


## 부팅 화면 — 제작사 로고. 씬을 바꾸는 코드라 트리에 넣지 않고 계약만 확인한다.
func _test_boot() -> void:
	_check("로고 그림이 있다",
		ResourceLoader.exists("res://sprites/extracted/ui/logo_screen.png"))
	_check("게임이 부팅 화면부터 뜬다",
		String(ProjectSettings.get_setting("application/run/main_scene", ""))
			== "res://scenes/ui/Boot.tscn")
	var boot: Control = load("res://scenes/ui/Boot.tscn").instantiate()
	# "아이는 이 화면을 수백 번 본다" — 건너뛸 수 있어야 하고, 길면 안 된다
	_check("아무 키나 누르면 건너뛴다", boot.has_method("_unhandled_input"))
	var total: float = boot.fade_in + boot.hold + boot.fade_out
	_check("로고가 3초를 넘지 않는다", total <= 3.0, "%.1f초" % total)
	boot.free()


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
	# 동료 중에서 찾으면 그 종에 그림이 생기는 순간 검사가 조용히 사라진다 —
	# 그림 없는 종을 직접 세워서 고정한다.
	var placeholder: Actor = null
	for animal in field.sim.animals:
		if not SpriteLibrary.has_art(String(animal.species.get("id", ""))):
			placeholder = field.actor_scene.instantiate()
			field.add_child(placeholder)
			placeholder.setup(animal.species, field.schema, field.tuning, RandomNumberGenerator.new())
			break
	_check("그림 없는 종을 하나 세울 수 있다", placeholder != null)
	if placeholder != null:
		_check("그 종은 정말 색 사각형이다", not placeholder.has_drawn_art)
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


func _find_animal(field, id: String) -> FieldSim.WildAnimal:
	for animal in field.sim.animals:
		if animal.species.get("id") == id and not animal.invited:
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
