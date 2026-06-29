# TouchScroll.gd
# Extends ScrollContainer to make touch scrolling reliable on Android. Godot
# 4's stock ScrollContainer relies on `scroll_deadzone` to hand off touch
# from a child Button to scrolling, but in practice the Button captures the
# touch first and never releases it — players touch a level tile or a pond
# card, try to swipe, and nothing scrolls.
#
# What this does instead:
#   - We watch global input via _input() so we see touches even after a
#     child Button has visually pressed.
#   - On touch_down inside the scroll's rect we record the start position
#     and the current scroll offsets.
#   - On drag, once the finger has moved past TAP_THRESHOLD pixels, we
#     manually update scroll_horizontal / scroll_vertical AND mark this
#     touch as a "drag" — when the finger eventually releases, we eat the
#     release event so the pressed Button never fires its `pressed` signal.
#   - On a clean tap (no drag detected), we let the release pass through
#     normally so the Button activates as expected.
extends ScrollContainer

# Pixels the finger has to travel before we hijack the touch from any
# child Button. Roughly a finger-width.
const TAP_THRESHOLD := 10.0
# Inertia coefficient — after release, residual velocity decays each frame.
const INERTIA_DECAY := 0.92
# Below this velocity (px/sec) we stop simulating inertia.
const INERTIA_MIN := 12.0

@export var scroll_horizontal_enabled: bool = true
@export var scroll_vertical_enabled: bool = false

var _touch_index: int = -1
var _start_pos: Vector2 = Vector2.ZERO
var _start_scroll: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _last_pos_time: float = 0.0
var _is_dragging: bool = false
# Tracks per-touch velocity for inertia after release.
var _velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	# We're handling scroll manually; the built-in deadzone would only get
	# in the way (it'd hijack at its own threshold, fighting ours).
	scroll_deadzone = 0
	set_process_input(true)
	# Inertia tick runs every frame; cheap.
	set_process(true)

func _process(delta: float) -> void:
	# Inertia decay after release — keeps scrolling for a moment so the
	# carousel feels like a phone scroll, not a jolted slider.
	if _touch_index == -1 and _velocity.length() > INERTIA_MIN:
		if scroll_horizontal_enabled:
			scroll_horizontal = int(scroll_horizontal - _velocity.x * delta)
		if scroll_vertical_enabled:
			scroll_vertical = int(scroll_vertical - _velocity.y * delta)
		_velocity *= INERTIA_DECAY
	elif _touch_index == -1:
		_velocity = Vector2.ZERO

func _input(event: InputEvent) -> void:
	# Only listen while the scroll's screen rect is on display — avoids
	# leaking input handling into other scenes.
	if not is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	# Mouse events for editor / desktop testing — same logic.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var fake := InputEventScreenTouch.new()
		fake.index = 0
		fake.position = event.position
		fake.pressed = event.pressed
		_handle_touch(fake)
	elif event is InputEventMouseMotion and _touch_index == 0:
		var fake_drag := InputEventScreenDrag.new()
		fake_drag.index = 0
		fake_drag.position = event.position
		_handle_drag(fake_drag)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Only start tracking if the touch landed on our visible rect.
		var rect := get_global_rect()
		if not rect.has_point(event.position):
			return
		_touch_index = event.index
		_start_pos = event.position
		_last_pos = event.position
		_last_pos_time = float(Time.get_ticks_msec()) / 1000.0
		_start_scroll = Vector2(scroll_horizontal, scroll_vertical)
		_is_dragging = false
		# Cancel any leftover inertia from a previous flick so a finger
		# touchdown snaps the scroll to a stop.
		_velocity = Vector2.ZERO
	else:
		# Release.
		if event.index != _touch_index:
			return
		_touch_index = -1
		if _is_dragging:
			# Swallow the release so any Button that visually pressed at
			# touch_down doesn't fire its `pressed` signal. Without this,
			# the player would swipe to scroll AND inadvertently open the
			# level they swiped from.
			get_viewport().set_input_as_handled()
			_is_dragging = false

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index:
		return
	var delta_from_start: Vector2 = event.position - _start_pos
	if not _is_dragging:
		if delta_from_start.length() < TAP_THRESHOLD:
			return  # still tap-sized; don't hijack from Buttons
		_is_dragging = true
	# Move the scroll opposite to finger movement.
	if scroll_horizontal_enabled:
		scroll_horizontal = int(_start_scroll.x - delta_from_start.x)
	if scroll_vertical_enabled:
		scroll_vertical = int(_start_scroll.y - delta_from_start.y)
	# Velocity for inertia — use the instantaneous delta vs. the previous
	# event so a fast flick produces a longer post-release glide.
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var dt: float = maxf(0.001, now - _last_pos_time)
	_velocity = (event.position - _last_pos) / dt
	_last_pos = event.position
	_last_pos_time = now
	# Eat the drag so it doesn't continue to bubble to child Buttons
	# (which would try to keep visually pressed).
	get_viewport().set_input_as_handled()
