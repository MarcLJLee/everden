## UI 레이어 — 교감 게이지와 화면 가장자리 방향 화살표. (BRIEF §6.2 레이어 분리)
extends Control

const EDGE_MARGIN := 26.0

var _state := {}

func set_state(state: Dictionary) -> void:
	_state = state
	queue_redraw()


func _draw() -> void:
	if _state.is_empty():
		return
	var gauge: Gauge = _state["gauge"]
	var hit: GuideSystem.Hit = _state["hit"]
	for puff in _state.get("puffs", []):
		_draw_puff(puff, float(_state.get("puff_life", 0.45)))
	if hit != null and not _on_screen(hit.animal.position):
		_draw_edge_arrow(hit)
	for partial in _state.get("partial", []):
		_draw_partial(partial)
	if gauge.active:
		_draw_gauge(gauge)


## 보이던 동물이 사라지는(또는 나타나는) 순간에 먼지를 남긴다.
## 그냥 없어지면 아이는 사라진 줄도 모른다 — "숨었다"로 읽혀야 한다.
func _draw_puff(puff: Dictionary, life: float) -> void:
	var t: float = clampf(float(puff["age"]) / maxf(life, 0.01), 0.0, 1.0)
	var screen := _to_screen(puff["position"])
	if not Rect2(Vector2.ZERO, size).grow(20.0).has_point(screen):
		return
	var hiding: bool = puff["hiding"]
	# 숨을 때는 밖으로 퍼지고, 나타날 때는 안으로 모인다
	var spread: float = 6.0 + 20.0 * (t if hiding else 1.0 - t)
	var alpha: float = (1.0 - t) * 0.85
	var color := Color(0.86, 0.84, 0.74, alpha) if hiding else Color(1.0, 0.96, 0.72, alpha)
	for i in 6:
		var angle := TAU * float(i) / 6.0 + t * 1.2
		var offset := Vector2.RIGHT.rotated(angle) * spread
		offset.y *= 0.6
		var box: float = 4.0 * (1.0 - t) + 1.0
		draw_rect(Rect2(screen + offset - Vector2.ONE * box * 0.5, Vector2.ONE * box), color)


## 대상이 이미 화면에 보이면 화살표는 군더더기다. 밖에 있을 때만 띄운다.
func _on_screen(world_position: Vector2) -> bool:
	var screen := _to_screen(world_position)
	return Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN).has_point(screen)


## 유도 중인 대상 방향을 화면 가장자리에 찍는다. (DEMO-SPEC §3.4)
func _draw_edge_arrow(hit: GuideSystem.Hit) -> void:
	var center := size * 0.5
	var direction := (_to_screen(hit.animal.position) - center)
	if direction.length() < 1.0:
		return
	direction = direction.normalized()
	var half := size * 0.5 - Vector2.ONE * EDGE_MARGIN
	# 사각형 화면 경계와 만나는 지점
	var scale_x := half.x / maxf(absf(direction.x), 0.0001)
	var scale_y := half.y / maxf(absf(direction.y), 0.0001)
	var tip := center + direction * minf(scale_x, scale_y)

	var color: Color = PlaceholderArt.SENSE_COLOR.get(hit.sense, Color.WHITE)
	var side := direction.orthogonal() * 8.0
	draw_colored_polygon(
		PackedVector2Array([tip + direction * 10.0, tip - direction * 6.0 + side, tip - direction * 6.0 - side]),
		color)


## 게이지는 대상 머리 위에. 끊기지 않는다는 것이 눈에 보여야 한다. (DEMO-SPEC §3.5)
func _draw_gauge(gauge: Gauge) -> void:
	var head := gauge.target.position + Vector2(0, -32)
	if gauge.target.is_active():
		head = gauge.target.actor.head_position()
	var anchor := _to_screen(head) + Vector2(0, -14)
	var bar := Vector2(64, 8)
	var origin := anchor - Vector2(bar.x * 0.5, 0)
	draw_rect(Rect2(origin - Vector2.ONE, bar + Vector2.ONE * 2), Color(0, 0, 0, 0.55))
	var fill := Color(1.0, 0.87, 0.45) if not gauge.paused else Color(0.62, 0.60, 0.52)
	draw_rect(Rect2(origin, Vector2(bar.x * gauge.progress, bar.y)), fill)
	if gauge.paused:
		# 왜 안 차는지가 보여야 한다 — 대상까지 선을 긋고 테두리를 깜빡인다.
		var blink: float = 0.45 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.008)
		draw_rect(Rect2(origin - Vector2.ONE, bar + Vector2.ONE * 2),
			Color(1.0, 0.9, 0.6, blink), false, 1.0)
		var player_at := _to_screen(_state["player"].position)
		draw_dashed_line(player_at, _to_screen(head), Color(1.0, 0.9, 0.6, 0.5), 1.0, 5.0)
	else:
		_draw_sparkles(_to_screen(head), gauge.progress)


## 대상의 상호작용 모션은 만들지 않는다 — 기존 대기 스프라이트 + 이펙트다. (DEMO-SPEC §3.5)
func _draw_sparkles(center: Vector2, progress: float) -> void:
	for i in 5:
		var angle := TAU * (float(i) / 5.0 + progress)
		var offset := Vector2.RIGHT.rotated(angle) * (14.0 + 5.0 * sin(progress * TAU * 2.0))
		draw_rect(Rect2(center + offset - Vector2.ONE * 1.5, Vector2.ONE * 3),
			Color(1.0, 0.97, 0.7, 0.85))


## 쏟다 만 아이 위에 작게 남겨둔다. 다시 오면 여기서부터 찬다.
func _draw_partial(partial: Dictionary) -> void:
	var anchor := _to_screen(partial["position"]) + Vector2(0, -10)
	var bar := Vector2(28, 4)
	var origin := anchor - Vector2(bar.x * 0.5, 0)
	draw_rect(Rect2(origin - Vector2.ONE, bar + Vector2.ONE * 2), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(origin, Vector2(bar.x * float(partial["progress"]), bar.y)),
		Color(0.86, 0.76, 0.44, 0.85))


func _to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position
