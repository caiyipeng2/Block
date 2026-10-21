extends Control

## A presentation queue independent of the current board animation. Each
## logical event arrives exactly once, even when several share a visual gem.
signal target_arrived(kind: String, counted: bool)
signal collections_settled

const BlockArt = preload("res://scripts/ui/block_art.gd")
const POP_DURATION := 0.10
const SCATTER_DURATION := 0.10
const HOLD_DURATION := 0.04
const FLIGHT_DURATION := 0.44
const MAX_STAGGER := 0.18
const MAX_BATCH_VISUALS := 16
const MAX_DRAWN_VISUALS := 48

var _flights: Array[Dictionary] = []
var _paused := false
var _board_offset := Vector2.ZERO
var _settled_emitted := true
var _epoch := 0
var _delivery_depth := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func enqueue(
		events: Array[Dictionary], board_rect: Rect2, cell_size: float,
		destinations: Dictionary, fallback_destination: Vector2,
		launch_delay: float, reduced_motion: bool
	) -> void:
	if events.is_empty():
		return
	var kind_groups: Dictionary = {}
	for event in events:
		var kind := str(event.get("kind", "red_star"))
		if not kind_groups.has(kind):
			kind_groups[kind] = []
		kind_groups[kind].append(event.duplicate())
	var visual_index := 0
	var group_index := 0
	for raw_kind in kind_groups:
		var kind := str(raw_kind)
		var entries: Array = kind_groups[kind]
		var visual_budget := maxi(1, floori(float(MAX_BATCH_VISUALS) / float(maxi(1, kind_groups.size()))))
		var stride := maxi(1, int(ceil(float(entries.size()) / float(visual_budget))))
		for start in range(0, entries.size(), stride):
			var arrivals: Array[Dictionary] = []
			var origin := Vector2.ZERO
			for index in range(start, mini(start + stride, entries.size())):
				var event: Dictionary = entries[index]
				var coordinate: Vector2i = event["cell"]
				origin += board_rect.position + (Vector2(coordinate) + Vector2.ONE * 0.5) * cell_size
				arrivals.append({"kind": kind, "counted": bool(event.get("counted", true))})
			origin /= float(arrivals.size())
			# Six short slots keep large clears bounded rather than adding one
			# full delay for every target. Different kinds still arrive in waves.
			var slot := floori(float(start) / float(stride)) % 6
			var stagger := minf(float(group_index) * 0.055 + float(slot) * 0.026, MAX_STAGGER)
			var angle := float(visual_index) * 2.399963 + float(group_index) * 0.41
			var spread := Vector2(cos(angle), sin(angle) * 0.58 - 0.22) * cell_size * (0.58 + float(visual_index % 3) * 0.18)
			_flights.append({
				"kind": kind,
				"arrivals": arrivals,
				"origin": origin,
				"scatter": spread,
				"destination": destinations.get(kind, fallback_destination),
				"cell_size": maxf(cell_size, 1.0),
				"delay": maxf(launch_delay, 0.0),
				"stagger": stagger,
				"elapsed": 0.0,
				"rotation": sin(angle) * 0.14,
			})
			visual_index += 1
		group_index += 1
	_settled_emitted = false
	if reduced_motion:
		finish_collections()
	else:
		set_process(true)
		queue_redraw()

func has_pending_collections() -> bool:
	return not _flights.is_empty() or _delivery_depth > 0

func set_paused(paused: bool) -> void:
	_paused = paused

func set_board_offset(offset: Vector2) -> void:
	_board_offset = offset
	queue_redraw()

## Used before a layout change or when reduced motion is enabled. Clear first
## so synchronous arrival callbacks cannot cause duplicate arrivals.
func finish_collections() -> void:
	var events: Array[Dictionary] = []
	for flight in _flights:
		for event in flight["arrivals"]:
			events.append(event)
	_flights.clear()
	set_process(false)
	queue_redraw()
	_deliver_arrivals(events, _epoch)
	_emit_settled_if_empty()

## A new game discards old presentation without changing its new HUD counts.
func reset() -> void:
	_epoch += 1
	_flights.clear()
	_settled_emitted = true
	_board_offset = Vector2.ZERO
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	if _paused:
		return
	var remaining: Array[Dictionary] = []
	var arrivals: Array[Dictionary] = []
	var current_epoch := _epoch
	for flight in _flights:
		flight["elapsed"] = float(flight["elapsed"]) + delta
		var total := float(flight["delay"]) + POP_DURATION + SCATTER_DURATION + HOLD_DURATION + float(flight["stagger"]) + FLIGHT_DURATION
		if float(flight["elapsed"]) >= total:
			for event in flight["arrivals"]:
				arrivals.append(event)
		else:
			remaining.append(flight)
	_flights = remaining
	set_process(not _flights.is_empty())
	queue_redraw()
	_deliver_arrivals(arrivals, current_epoch)
	if current_epoch == _epoch:
		_emit_settled_if_empty()

func _deliver_arrivals(events: Array[Dictionary], current_epoch: int) -> void:
	_delivery_depth += 1
	for event in events:
		if current_epoch != _epoch:
			break
		target_arrived.emit(str(event["kind"]), bool(event["counted"]))
	_delivery_depth -= 1

func _emit_settled_if_empty() -> void:
	if _flights.is_empty() and _delivery_depth == 0 and not _settled_emitted:
		_settled_emitted = true
		collections_settled.emit()

func _draw() -> void:
	var drawn := 0
	for flight in _flights:
		var elapsed := float(flight["elapsed"]) - float(flight["delay"])
		if elapsed < 0.0:
			continue
		if drawn >= MAX_DRAWN_VISUALS:
			break
		drawn += 1
		_draw_flight(flight, elapsed)

func _draw_flight(flight: Dictionary, elapsed: float) -> void:
	var cell_size := float(flight["cell_size"])
	var origin: Vector2 = flight["origin"]
	var spread: Vector2 = flight["scatter"]
	var destination: Vector2 = flight["destination"]
	var point := origin + _board_offset
	var side := cell_size * 0.92
	var travel := 0.0
	var alpha := 1.0
	if elapsed < POP_DURATION:
		var pop := elapsed / POP_DURATION
		var eased := 1.0 - pow(1.0 - pop, 3.0)
		side = cell_size * lerpf(0.92, 1.45, eased)
	elif elapsed < POP_DURATION + SCATTER_DURATION:
		var scatter := (elapsed - POP_DURATION) / SCATTER_DURATION
		point += spread * (1.0 - pow(1.0 - scatter, 2.0))
		side = cell_size * lerpf(1.45, 1.32, scatter)
	else:
		var travel_start := POP_DURATION + SCATTER_DURATION + HOLD_DURATION + float(flight["stagger"])
		travel = clampf((elapsed - travel_start) / FLIGHT_DURATION, 0.0, 1.0)
		var eased := travel * travel * (3.0 - 2.0 * travel)
		point = (origin + spread + _board_offset * (1.0 - travel)).lerp(destination, eased)
		point.y -= sin(travel * PI) * minf(cell_size, 56.0)
		side = cell_size * lerpf(1.32, 0.58, eased)
		alpha = 1.0 - clampf((travel - 0.94) / 0.06, 0.0, 1.0)
	var rotation := float(flight["rotation"]) * sin(travel * PI)
	# One faint halo replaces the former double glow, so the icon reads as a
	# small collected token rather than a large special-effect burst.
	var tint := _target_glow(str(flight["kind"]))
	draw_circle(point, side * 0.48, Color(tint.r, tint.g, tint.b, alpha * 0.10))
	if travel > 0.08:
		var trail_point := point + (origin + spread - destination).normalized() * cell_size * 0.14
		BlockArt.draw_target_marker(self, Rect2(trail_point - Vector2.ONE * side * 0.5, Vector2.ONE * side), alpha * 0.10, 1.5, str(flight["kind"]))
	draw_set_transform(point, rotation)
	BlockArt.draw_target_marker(self, Rect2(-Vector2.ONE * side * 0.5, Vector2.ONE * side), alpha, 1.8, str(flight["kind"]))
	draw_set_transform(Vector2.ZERO)

func _target_glow(kind: String) -> Color:
	match kind:
		"blue_diamond": return Color("#6cf7ff")
		"gold_gem", "yellow_star": return Color("#ffdd5e")
		_: return Color("#ff929f")
