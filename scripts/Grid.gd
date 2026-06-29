# Grid.gd
# Renders the N×N grid, dots, player path, and handles touch input
extends Node2D

@onready var main = get_parent()

var grid_size: int = 5
var cell_size: float = 80.0
var padding: float = 4.0
var dot_radius: float = 14.0

# Visual state
var grid_rect: Rect2
var cells: Dictionary = {}      # "r,c" -> {"fill_color": Color, "is_dot": bool, "dot_num": int}
var path_cells: Array = []      # [[r,c], ...] in order placed
var dot_positions: Dictionary = {}  # "r,c" -> int (dot number)
var blocked_cells: Dictionary = {}  # "r,c" -> true (impassable)
var show_solution_hint: bool = false  # tutorial-only breadcrumb trail
var solution_dots: Array = []   # Full dot data from level

# Hint
var hint_cell: Vector2i = Vector2i(-1, -1)
var hint_timer: float = 0.0
# Smart-hint trail (HintSolver continuation): up to 3 cells from the head
# toward the next un-reached number, rendered as a dashed breadcrumb.
var hint_trail: Array = []

# Lock animation (auto-lock): the cell scales up briefly and an expanding
# white ring radiates from it. Lasts LOCK_DUR seconds. _lock_anim.t is the
# elapsed time; null when no animation is active.
const LOCK_DUR := 0.85
var _lock_anim: Dictionary = {}

# Dot pop bursts — small celebratory particles + dual ring when the player
# reaches a numbered dot. State is { pos, t, motes: [{dir, speed}], ... }.
const DOT_BURST_DUR := 0.65
var _dot_bursts: Array = []

# Completion retrace — two-phase wave that REPLAYS the player's path. Phase 1
# (back, 0.5s) sweeps a bright pulse from head→start, "rewinding" the trace.
# Phase 2 (forward, 0.7s) sweeps from start→head, "redrawing" it fresh. Each
# cell in the path lights up as the wavefront crosses it and stays brighter
# in the cumulative trail behind. The visible total is 1.2s, so the popup
# defer in Main is bumped to ~1.4s.
const WAVE_BACK_DUR := 0.5
const WAVE_FWD_DUR := 0.7
const WAVE_DUR := WAVE_BACK_DUR + WAVE_FWD_DUR  # 1.2s total
var _wave_t: float = 0.0

# Per-sector theme + level applied by Main on every level load. Drives the
# background particle field, ambient effects, and the dynamic ribbon hue
# (Nova / Infinite). Empty until apply_theme is called; until then the
# background falls back to plain bg_color → bg_color_bottom.
var current_theme: Dictionary = {}
var current_level: int = 1
# Background particle pool — rebuilt by apply_theme. Each entry:
# { pos, vel, base_size, twinkle_phase, twinkle2_phase, hue_offset, depth_mult }
var _bg_particles: Array = []
# Sector ambient timers (Spark flares, Infinite shooting stars).
var _spark_flare_t: float = -1.0
var _spark_flare_idx: int = -1
var _spark_flare_next: float = 0.0
var _shooting_stars: Array = []  # { pos, vel, t }
var _shooting_next: float = 0.0
const SHOOTING_DUR := 0.85

# Error feedback
var error_cell: Vector2i = Vector2i(-1, -1)
var error_timer: float = 0.0
var error_message: String = ""

# Colors
var bg_color: Color = Color("#0B0B16")
var bg_color_bottom: Color = Color("#13132A")
var grid_bg: Color = Color("#16162C")
var grid_border: Color = Color("#2A2A4E")
var cell_empty: Color = Color("#1C1C38")
var dot_fill: Color = Color("#000000")
var dot_text: Color = Color("#FFFFFF")
var path_start: Color = Color("#4361EE")
var path_end: Color = Color("#7B2D8B")
var hint_color: Color = Color("#FFD166")
var error_color: Color = Color("#EF4444")
var complete_flash: Color = Color("#FFFFFF")

# Layout
var grid_radius: float = 18.0

# Touch tracking
var is_dragging: bool = false
var last_touch_cell: Vector2i = Vector2i(-1, -1)
var active_touch_index: int = -1
var touch_slop: float = 16.0

# VFX
var ripples: Array = []   # [{ "pos": Vector2, "t": float }]
const RIPPLE_DUR := 0.55

# Animation
var anim_timer: float = 0.0
var is_completing: bool = false
var completion_progress: float = 0.0

func _ready():
	pass

func setup(level_data: Dictionary):
	grid_size = level_data.get("grid_size", 5)
	solution_dots = level_data.get("dots", [])
	
	# Build dot lookup
	dot_positions.clear()
	for d in solution_dots:
		dot_positions["%d,%d" % [d["row"], d["col"]]] = d["number"]

	# Blocked (impassable) cells
	blocked_cells.clear()
	for b in level_data.get("blocked", []):
		blocked_cells["%d,%d" % [b[0], b[1]]] = true
	
	# Calculate cell size to fit screen
	var screen_size = get_viewport_rect().size
	var max_grid_pixels = minf(screen_size.x * 0.85, screen_size.y * 0.65)
	cell_size = floorf(max_grid_pixels / float(grid_size))
	
	# Center the grid
	var total_size = cell_size * grid_size
	var offset_x = (screen_size.x - total_size) / 2.0
	var offset_y = (screen_size.y * 0.19)  # Below top UI area
	grid_rect = Rect2(offset_x, offset_y, total_size, total_size)
	
	position = Vector2(0, 0)
	
	# Reset state
	path_cells.clear()
	cells.clear()
	is_dragging = false
	active_touch_index = -1
	is_completing = false
	hint_cell = Vector2i(-1, -1)
	error_cell = Vector2i(-1, -1)
	
	# Set colors from game state
	if main and main.has_node(".") and main.game_state:
		path_start = main.game_state.path_color_start
		path_end = main.game_state.path_color_end
	
	queue_redraw()

func refresh_from_state(state):
	path_cells.clear()
	cells.clear()
	for cell in state.player_path:
		add_path_cell(cell[0], cell[1], _is_dot(cell[0], cell[1]))
	
	is_completing = false
	# NOTE: do not reset is_dragging here — refresh_from_state runs mid-drag
	# during tap/drag-back rewind; clearing it would freeze input until release.
	hint_cell = Vector2i(-1, -1)
	error_cell = Vector2i(-1, -1)
	if state.player_path.size() > 0:
		var tail = state.player_path[-1]
		last_touch_cell = Vector2i(tail[0], tail[1])
	queue_redraw()

func add_path_cell(row: int, col: int, reached_dot: bool):
	var key = "%d,%d" % [row, col]
	
	# Calculate color gradient
	var progress = float(path_cells.size()) / float(maxi(1, grid_size * grid_size))
	var color = path_start.lerp(path_end, progress)
	
	cells[key] = {
		"fill_color": color,
		"is_dot": reached_dot,
		"dot_num": dot_positions.get(key, -1)
	}
	
	if not is_completing:
		path_cells.append([row, col])
	
	# Animate cell fill
	_create_fill_animation(row, col, color)
	
	queue_redraw()

func show_error(row: int, col: int, message: String):
	error_cell = Vector2i(row, col)
	error_message = message
	error_timer = 1.4
	queue_redraw()

func show_hint(row: int, col: int):
	hint_cell = Vector2i(row, col)
	hint_trail = []
	hint_timer = 2.0
	queue_redraw()

# Render a HintSolver continuation as a dashed breadcrumb trail. Each cell on
# the trail gets a dashed ring chip; the first cell pops strongest so the
# eye latches on, subsequent cells fade off to suggest direction. Used for
# both the hint button (full path to next number) and the tutorial guide.
func show_hint_trail(trail: Array) -> void:
	hint_trail = trail.duplicate()
	hint_cell = Vector2i(-1, -1)  # the trail supersedes the single-cell hint
	# Longer hold for longer trails so the player can read the whole path.
	hint_timer = clampf(2.0 + 0.25 * float(trail.size()), 2.4, 5.0)
	queue_redraw()

func get_cell_at(pos: Vector2) -> Vector2i:
	var hit_rect := grid_rect.grow(touch_slop)
	if not hit_rect.has_point(pos):
		return Vector2i(-1, -1)
	
	var local := pos - grid_rect.position
	var col := clampi(int(floorf(local.x / cell_size)), 0, grid_size - 1)
	var row := clampi(int(floorf(local.y / cell_size)), 0, grid_size - 1)
	
	if row >= 0 and row < grid_size and col >= 0 and col < grid_size:
		return Vector2i(row, col)
	return Vector2i(-1, -1)

func _is_dot(row: int, col: int) -> bool:
	return dot_positions.has("%d,%d" % [row, col])

func _input(event):
	if is_completing:
		return

	if event is InputEventScreenTouch:
		if not event.pressed:
			_handle_press(event.position, false, event.index)
			return
		if _gameplay_input_blocked(event.position):
			return
		_handle_press(event.position, event.pressed, event.index)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_handle_press(event.position, false, -1)
			return
		if _gameplay_input_blocked(event.position):
			return
		_handle_press(event.position, event.pressed, -1)
	elif event is InputEventScreenDrag:
		if _gameplay_input_blocked(event.position):
			return
		if active_touch_index == -1 or event.index == active_touch_index:
			_handle_drag(event.position, event.index)
	elif event is InputEventMouseMotion and is_dragging and active_touch_index == -1:
		if _gameplay_input_blocked(event.position):
			return
		_handle_drag(event.position, -1)

func _gameplay_input_blocked(pos: Vector2) -> bool:
	if get_tree().paused:
		return true
	if main == null:
		return false
	if main.game_state != null and main.game_state.is_completed:
		return true
	for popup_name in ["DailyCard", "PaletteUnlockPopup", "Pause"]:
		if main.has_node(popup_name):
			return true
	var hud_layer = main.get_node_or_null("HUD")
	if hud_layer == null:
		return false
	for path in ["PauseBtn", "UndoBtn", "ResetBtn", "HintBtn", "ContinueBtn", "CompletePanel"]:
		var control := hud_layer.get_node_or_null(path) as Control
		if control and control.visible and control.get_global_rect().has_point(pos):
			return true
	return false

func _handle_press(pos: Vector2, pressed: bool, touch_index: int) -> void:
	if pressed:
		if is_dragging and active_touch_index != touch_index:
			return
		var cell = get_cell_at(pos)
		if cell.x >= 0:
			is_dragging = true
			active_touch_index = touch_index
			last_touch_cell = cell
			main.on_cell_tapped(cell.x, cell.y)
			get_viewport().set_input_as_handled()
	else:
		if is_dragging and active_touch_index == touch_index:
			is_dragging = false
			active_touch_index = -1
			last_touch_cell = Vector2i(-1, -1)
			get_viewport().set_input_as_handled()

func _handle_drag(pos: Vector2, touch_index: int) -> void:
	if not is_dragging:
		var first_cell := get_cell_at(pos)
		if first_cell.x >= 0:
			is_dragging = true
			active_touch_index = touch_index
			last_touch_cell = first_cell
			main.on_cell_tapped(first_cell.x, first_cell.y)
			get_viewport().set_input_as_handled()
		return

	var cell: Vector2i = get_cell_at(pos)
	if cell.x >= 0 and cell != last_touch_cell:
		# Drag interpolation: a fast finger can move from cell A to cell C
		# without ever generating an event inside cell B.
		var from_cell: Vector2i = last_touch_cell
		var to_cell: Vector2i = cell
		if from_cell.x >= 0:
			var sr: int = signi(to_cell.x - from_cell.x)
			var sc: int = signi(to_cell.y - from_cell.y)
			var cur: Vector2i = from_cell
			var steps: int = 0
			while cur != to_cell and steps < 32:
				if absi(to_cell.x - cur.x) >= absi(to_cell.y - cur.y):
					cur.x += sr
				else:
					cur.y += sc
				main.on_cell_drag(cur.x, cur.y)
				steps += 1
		else:
			main.on_cell_drag(cell.x, cell.y)
		last_touch_cell = cell
		get_viewport().set_input_as_handled()

func _unhandled_input(event):
	if is_completing:
		return
	
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pos = event.position
		if event.pressed:
			var cell = get_cell_at(pos)
			if cell.x >= 0:
				is_dragging = true
				last_touch_cell = cell
				main.on_cell_tapped(cell.x, cell.y)
		else:
			is_dragging = false
			last_touch_cell = Vector2i(-1, -1)
	
	if (event is InputEventScreenDrag or (event is InputEventMouseMotion and is_dragging)):
		if is_dragging:
			var cell: Vector2i = get_cell_at(event.position)
			if cell.x >= 0 and cell != last_touch_cell:
				# Drag interpolation: a fast finger can move from cell A to
				# cell C without ever generating an event inside cell B. The
				# stable-line rule + GameState's adjacency check both refuse
				# non-adjacent moves, so without filling the gap a fast
				# back-drag silently does nothing. Walk the Manhattan gap one
				# cell at a time, preferring the larger axis at each step, and
				# forward each intermediate cell.
				var from_cell: Vector2i = last_touch_cell
				var to_cell: Vector2i = cell
				if from_cell.x >= 0:
					var sr: int = signi(to_cell.x - from_cell.x)
					var sc: int = signi(to_cell.y - from_cell.y)
					var cur: Vector2i = from_cell
					# Cap to prevent pathological long sweeps from blowing
					# stack/frame — 32 cells is far beyond any real puzzle.
					var steps: int = 0
					while cur != to_cell and steps < 32:
						if absi(to_cell.x - cur.x) >= absi(to_cell.y - cur.y):
							cur.x += sr
						else:
							cur.y += sc
						main.on_cell_drag(cur.x, cur.y)
						steps += 1
				else:
					main.on_cell_drag(cell.x, cell.y)
				last_touch_cell = cell

func _process(delta):
	var needs_redraw = false
	
	if hint_timer > 0:
		hint_timer -= delta
		needs_redraw = true  # animate pulse
		if hint_timer <= 0:
			hint_cell = Vector2i(-1, -1)
			hint_trail = []

	if error_timer > 0:
		error_timer -= delta
		needs_redraw = true  # animate shake + toast fade
		if error_timer <= 0:
			error_cell = Vector2i(-1, -1)
			error_message = ""
	
	if not ripples.is_empty():
		var alive: Array = []
		for rp in ripples:
			rp["t"] += delta
			if rp["t"] < RIPPLE_DUR:
				alive.append(rp)
		ripples = alive
		needs_redraw = true

	if not _lock_anim.is_empty():
		_lock_anim["t"] = float(_lock_anim["t"]) + delta
		if float(_lock_anim["t"]) >= LOCK_DUR:
			_lock_anim = {}
		needs_redraw = true

	if not _dot_bursts.is_empty():
		var alive2: Array = []
		for b in _dot_bursts:
			b["t"] = float(b["t"]) + delta
			if float(b["t"]) < DOT_BURST_DUR:
				alive2.append(b)
		_dot_bursts = alive2
		needs_redraw = true

	if _wave_t > 0.0:
		_wave_t = maxf(0.0, _wave_t - delta)
		needs_redraw = true

	# Background particles drift continuously. We always run the tick when the
	# pool is populated; the redraw flag is set only if there's enough motion
	# to be visible (saves a redraw per frame when the field is mostly idle).
	if not _bg_particles.is_empty():
		_step_bg_particles(delta)
		needs_redraw = true
		# Sector ambient timers (Spark flares, Infinite shooting stars).
		_step_sector_ambient(delta)

	# Ribbon's 3-pass glow uses time-driven sine pulses, so whenever the player
	# has any path drawn we need a steady redraw cadence for the breathing
	# effect. Cheap at 60fps on a phone — same draw work, just every frame.
	if path_cells.size() > 0:
		needs_redraw = true

	if is_completing:
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

# Per-sector theme application. Main calls this on every level load so the
# background, ribbon glow, dot colors, particles, and ambient effects all
# read from one source. Without it the Grid renders with its default navy
# palette and no particle field. The theme dict structure is defined by
# SectorThemes.gd — see swatch / ribbon / glow / dot_base / particle / etc.
func apply_theme(theme: Dictionary, level: int) -> void:
	current_theme = theme
	current_level = level
	# Bake every color into the plain Color fields so the hot draw path
	# doesn't allocate inside _draw. Missing keys fall back to existing
	# values so a partially-populated theme still draws cleanly.
	bg_color = theme.get("bg_top", bg_color)
	bg_color_bottom = theme.get("bg_bottom", bg_color_bottom)
	grid_border = theme.get("grid_line", grid_border)
	cell_empty = theme.get("cell_empty", cell_empty)
	path_start = theme.get("ribbon", path_start)
	path_end = theme.get("glow", path_end)
	# Dot colors come from the player's equipped palette via GameState. If the
	# player hasn't equipped a custom palette (the daily default), use the
	# sector's dot_base + dot_pulse so each sector still feels distinct.
	# (Equipped palette wins later — applied via Main._apply_equipped_palette.)
	_rebuild_bg_particles()
	# Reset sector ambient timers so we don't carry residue from the prior
	# sector (e.g. an in-flight shooting star).
	_spark_flare_t = -1.0
	_spark_flare_idx = -1
	_spark_flare_next = randf_range(3.0, 5.5)
	_shooting_stars.clear()
	_shooting_next = randf_range(3.0, 5.0)
	queue_redraw()

# Build the per-sector particle field. Count, base size, and behavior come
# from the theme's pack_index; the actual particles get random positions
# inside the viewport, a slow drift velocity, and dual twinkle phases for
# organic flicker. Cheap to rebuild on level load; particles are stored as
# untyped dicts so the draw loop can branch per-sector behavior.
func _rebuild_bg_particles() -> void:
	_bg_particles.clear()
	if current_theme.is_empty():
		return
	var sector_name: String = String(current_theme.get("name", ""))
	# Config per sector: count, size range, speed, omni (rises if false), hue
	# jitter range (only used for Infinite). Tuned for portrait 480×854.
	var cfg: Dictionary
	match sector_name:
		"Spark":     cfg = { "count": 12, "size_min": 2.5, "size_max": 5.5, "speed": 12.0, "omni": false, "hue": 0.0 }
		"Glow":      cfg = { "count": 55, "size_min": 0.6, "size_max": 1.8, "speed": 20.0, "omni": false, "hue": 0.0 }
		"Ember":     cfg = { "count": 60, "size_min": 1.0, "size_max": 2.6, "speed": 24.0, "omni": false, "hue": 0.0 }
		"Nova":      cfg = { "count": 38, "size_min": 1.2, "size_max": 3.0, "speed": 14.0, "omni": true,  "hue": 0.0 }
		"Infinite":  cfg = { "count": 30, "size_min": 1.0, "size_max": 2.8, "speed": 10.0, "omni": true,  "hue": 360.0 }
		_:           return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var vp: Vector2 = get_viewport_rect().size
	for i in range(int(cfg["count"])):
		var size_v: float = rng.randf_range(float(cfg["size_min"]), float(cfg["size_max"]))
		var speed: float = float(cfg["speed"]) * rng.randf_range(0.6, 1.4)
		var vel: Vector2
		if cfg["omni"]:
			var ang: float = rng.randf() * TAU
			vel = Vector2(cos(ang), sin(ang)) * speed
		else:
			# Drift mostly upward with a slight horizontal wander, plus 25% of
			# Ember particles fall as ash.
			var falling := sector_name == "Ember" and rng.randf() < 0.25
			var v_dir: float = 1.0 if falling else -1.0
			vel = Vector2(rng.randf_range(-0.25, 0.25) * speed, v_dir * speed)
		# Depth parallax — smaller particles move slower (further away),
		# bigger particles move faster (closer). 60% / 110% spread.
		var size_norm: float = (size_v - float(cfg["size_min"])) / maxf(0.001, float(cfg["size_max"]) - float(cfg["size_min"]))
		var depth: float = lerp(0.6, 1.1, size_norm)
		var hue_off: float = rng.randf_range(-30.0, 30.0) if float(cfg["hue"]) > 0.0 else 0.0
		_bg_particles.append({
			"pos": Vector2(rng.randf() * vp.x, rng.randf() * vp.y),
			"vel": vel,
			"base_size": size_v,
			"twinkle_phase": rng.randf() * TAU,
			"twinkle2_phase": rng.randf() * TAU,
			"hue_offset": hue_off,
			"depth_mult": depth,
			"falling": false,  # set below for Ember ash
		})
	# Mark falling Ember ash particles for color override.
	if sector_name == "Ember":
		for p in _bg_particles:
			if p["vel"].y > 0.0:
				p["falling"] = true

func spawn_ripple(row: int, col: int):
	ripples.append({ "pos": _cell_center(row, col), "t": 0.0 })
	spawn_dot_burst(row, col)
	queue_redraw()

# Celebratory mote burst at a dot — 14 motes shoot outward at random angles
# with eased-decelerating speed, plus a dual themed+white ring expanding
# from the cell center. Fades over DOT_BURST_DUR seconds.
func spawn_dot_burst(row: int, col: int) -> void:
	var motes: Array = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(14):
		var angle: float = rng.randf() * TAU
		var speed: float = rng.randf_range(cell_size * 0.9, cell_size * 1.6)
		motes.append({ "dir": Vector2(cos(angle), sin(angle)), "speed": speed })
	_dot_bursts.append({
		"pos": _cell_center(row, col),
		"t": 0.0,
		"motes": motes,
	})

# Auto-lock animation — scale-pop on the closing cell + an expanding white
# ring. Also kicks off the completion wave so the path lights up sequentially
# from start to head while the popup is still deferred. Lock SFX + haptic are
# owned by Main; this is the pure visual.
func play_lock_animation(row: int, col: int) -> void:
	_lock_anim = { "pos": _cell_center(row, col), "t": 0.0 }
	_wave_t = WAVE_DUR
	queue_redraw()

func _draw_ripples():
	for rp in ripples:
		var k: float = rp["t"] / RIPPLE_DUR
		var radius: float = lerp(cell_size * 0.25, cell_size * 0.85, k)
		var col := path_end
		col.a = (1.0 - k) * 0.6
		draw_circle(rp["pos"], radius, col, false, maxf(2.0, cell_size * 0.06), true)
		var inner := Color("#FFFFFF")
		inner.a = (1.0 - k) * 0.35
		draw_circle(rp["pos"], radius * 0.55, inner, false, maxf(1.5, cell_size * 0.03), true)

# Dot pop celebration draw — eased-decelerating motes shoot outward from
# the cell while two concentric rings (themed + white) expand and fade.
func _draw_dot_bursts() -> void:
	for b in _dot_bursts:
		var t: float = float(b["t"]) / DOT_BURST_DUR
		var ease_t: float = 1.0 - pow(1.0 - t, 2.2)  # ease-out
		var center: Vector2 = b["pos"]
		# Motes
		var mote_radius: float = maxf(1.5, cell_size * 0.05)
		for m in b["motes"]:
			var dist: float = float(m["speed"]) * ease_t
			var pos: Vector2 = center + Vector2(m["dir"]) * dist
			var mote_col: Color = path_end.lerp(Color("#FFFFFF"), 0.4)
			mote_col.a = (1.0 - t) * 0.85
			draw_circle(pos, mote_radius * (1.0 - 0.4 * t), mote_col)
		# Dual expanding rings
		var ring_t: float = ease_t
		var r1: float = lerp(cell_size * 0.18, cell_size * 0.95, ring_t)
		var r2: float = lerp(cell_size * 0.10, cell_size * 0.70, ring_t)
		var ring_col1: Color = path_end
		ring_col1.a = (1.0 - t) * 0.55
		draw_circle(center, r1, ring_col1, false, maxf(2.0, cell_size * 0.05), true)
		var ring_col2: Color = Color("#FFFFFF")
		ring_col2.a = (1.0 - t) * 0.40
		draw_circle(center, r2, ring_col2, false, maxf(1.5, cell_size * 0.035), true)

# Completion retrace — two-phase animated replay of the player's path.
#
#   Phase 1 (back):    bright wavefront sweeps head→start, ERASING the
#                      cumulative bright trail behind it (path "rewinds").
#   Phase 2 (forward): wavefront sweeps start→head, BUILDING the cumulative
#                      trail as it goes (path "redraws fresh").
#
# Cells the wave has already passed sit in a steady themed brightness so the
# eye reads the replay; the wavefront itself has a sharper white pop so the
# motion is unmistakable. Returns silently if there's no path yet.
func _draw_completion_wave() -> void:
	if _wave_t <= 0.0:
		return
	if path_cells.size() < 2:
		return
	var n: int = path_cells.size()
	var w: float = maxf(6.0, cell_size * 0.34)

	# Time elapsed since the wave started (counts up).
	var elapsed: float = WAVE_DUR - _wave_t
	# Which phase are we in, and where is the wavefront in [0,1]?
	#   front_frac = position of the head of the wave along the path
	#   trail_filled(i) = true if cell i sits in the cumulative bright trail
	var front_frac: float
	var phase_back: bool
	if elapsed < WAVE_BACK_DUR:
		# Rewinding: wavefront slides from head (1.0) to start (0.0).
		phase_back = true
		front_frac = 1.0 - (elapsed / WAVE_BACK_DUR)
	else:
		# Redrawing: wavefront slides from start (0.0) to head (1.0).
		phase_back = false
		front_frac = (elapsed - WAVE_BACK_DUR) / WAVE_FWD_DUR
	front_frac = clampf(front_frac, 0.0, 1.0)
	# Width of the bright wavefront and how quickly cells outside it fall off.
	var band: float = 0.06
	var falloff: float = 0.14
	# A slight bias keeps the very last cell from popping for a frame at the
	# end of the forward phase.
	var head_done: bool = (not phase_back) and front_frac >= 0.999

	for i in range(n):
		var frac: float = float(i) / float(maxi(1, n - 1))
		var dist: float = absf(frac - front_frac)
		# Wavefront intensity — sharp peak at the wavefront.
		var wave_i: float
		if dist <= band:
			wave_i = 1.0
		else:
			wave_i = 1.0 - smoothstep(0.0, falloff, dist - band)

		# Cumulative trail intensity:
		# - back phase: cells AHEAD of the wavefront (frac > front_frac) are
		#   still lit (they haven't been erased yet)
		# - fwd phase:  cells BEHIND the wavefront (frac < front_frac) are
		#   lit (they've been drawn)
		var trail_lit: bool
		if phase_back:
			trail_lit = frac > front_frac
		else:
			trail_lit = frac <= front_frac or head_done

		var cell = path_cells[i]
		var center: Vector2 = _cell_center(cell[0], cell[1])

		# Steady trail glow on lit cells — themed, gentle.
		if trail_lit:
			var trail_col: Color = path_end
			trail_col.a = 0.55
			draw_circle(center, w * 0.85, trail_col)
			var trail_inner: Color = path_start.lerp(path_end, 0.5)
			trail_inner.a = 0.45
			draw_circle(center, w * 0.50, trail_inner)

		# Bright wavefront pop on top of trail.
		if wave_i > 0.02:
			var flash: Color = Color("#FFFFFF").lerp(path_end, 1.0 - wave_i)
			flash.a = wave_i * 0.95
			draw_circle(center, w * (0.60 + 0.45 * wave_i), flash)
			var halo: Color = path_end
			halo.a = wave_i * 0.55
			draw_circle(center, w * (1.20 + 0.55 * wave_i), halo, false, maxf(1.8, cell_size * 0.06), true)

# ---------------------------------------------------------------- per-sector
# Background decorations drawn between the bg gradient and the grid panel:
# the per-sector particle field plus any sector ambient layer (Spark glow,
# Nova nebulae, Infinite circuit grid + shooting stars). Skipped silently if
# no theme has been applied yet.
func _draw_bg_decorations() -> void:
	if current_theme.is_empty():
		return
	_draw_sector_ambient()
	_draw_bg_particles()

# Drift particles slowly, wrapping at viewport edges so the field is "always
# there." Each particle moves at depth_mult * vel * delta — bigger particles
# parallax faster, giving a layered feel.
func _step_bg_particles(delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	for p in _bg_particles:
		var step: Vector2 = (p["vel"] as Vector2) * (p["depth_mult"] as float) * delta
		var pos: Vector2 = (p["pos"] as Vector2) + step
		# Wrap with a small margin so particles re-enter slightly off-screen
		# instead of popping at the edge.
		var margin: float = 12.0
		if pos.x < -margin:
			pos.x = vp.x + margin
		elif pos.x > vp.x + margin:
			pos.x = -margin
		if pos.y < -margin:
			pos.y = vp.y + margin
		elif pos.y > vp.y + margin:
			pos.y = -margin
		p["pos"] = pos

# Per-sector timers: Spark flare events fire on a random particle every
# 3.0–5.5s. Infinite shoots a star every 3.0–5.0s.
func _step_sector_ambient(delta: float) -> void:
	var sector := String(current_theme.get("name", ""))
	# Spark flares
	if sector == "Spark":
		if _spark_flare_t < 0.0:
			_spark_flare_next -= delta
			if _spark_flare_next <= 0.0 and not _bg_particles.is_empty():
				_spark_flare_idx = randi() % _bg_particles.size()
				_spark_flare_t = 0.0
		else:
			_spark_flare_t += delta
			if _spark_flare_t >= 1.2:
				_spark_flare_t = -1.0
				_spark_flare_idx = -1
				_spark_flare_next = randf_range(3.0, 5.5)
	# Infinite shooting stars
	if sector == "Infinite":
		_shooting_next -= delta
		if _shooting_next <= 0.0:
			var vp: Vector2 = get_viewport_rect().size
			var start := Vector2(-50.0, randf_range(0.0, vp.y * 0.5))
			var vel := Vector2(randf_range(400.0, 700.0), randf_range(140.0, 260.0))
			_shooting_stars.append({ "pos": start, "vel": vel, "t": 0.0 })
			_shooting_next = randf_range(3.0, 5.0)
		var alive: Array = []
		for s in _shooting_stars:
			s["t"] = float(s["t"]) + delta
			s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
			if float(s["t"]) < SHOOTING_DUR:
				alive.append(s)
		_shooting_stars = alive

# Render the particle field in 4 stacked layers so each particle reads as a
# soft star (wide outer halo → mid glow → bright core → white pinprick) and
# never as a flat dot. Per-particle twinkle uses two stacked sine frequencies
# so the field doesn't pulse mechanically — 70/30 mix.
func _draw_bg_particles() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var sector := String(current_theme.get("name", ""))
	var particle_col: Color = current_theme.get("particle", Color("#FFFFFF"))
	var ash_col := Color("#C8B8A0")  # Ember falling ash
	for i in range(_bg_particles.size()):
		var p: Dictionary = _bg_particles[i]
		var twinkle_a: float = 0.5 + 0.5 * sin(now * 2.2 + float(p["twinkle_phase"]))
		var twinkle_b: float = 0.5 + 0.5 * sin(now * 5.3 + float(p["twinkle2_phase"]))
		var twinkle: float = twinkle_a * 0.70 + twinkle_b * 0.30
		var size_v: float = float(p["base_size"])
		# Spark flare: the lucky particle for this event scales up over a
		# bell curve. Adds the "this little spark just bloomed" beat.
		if sector == "Spark" and i == _spark_flare_idx and _spark_flare_t >= 0.0:
			var ft: float = _spark_flare_t / 1.2
			var bell: float = exp(-pow((ft - 0.5) * 3.0, 2.0))
			size_v *= 1.0 + bell * 1.8
		# Per-particle color: Infinite jitters the hue; Ember falling ash uses
		# the dedicated ash color; everything else uses the theme particle.
		var col: Color
		if sector == "Infinite":
			var base_hue: float = fposmod(float(current_level * 37) + float(p["hue_offset"]), 360.0)
			col = Color.from_hsv(base_hue / 360.0, 0.65, 1.0)
		elif sector == "Ember" and bool(p.get("falling", false)):
			col = ash_col
		else:
			col = particle_col
		var pos: Vector2 = p["pos"]
		# 4-layer stack: wide outer halo, mid glow, bright core, white pinprick.
		var outer: Color = col
		outer.a = 0.10 * twinkle
		draw_circle(pos, size_v * 3.0, outer)
		var mid: Color = col
		mid.a = 0.22 * twinkle
		draw_circle(pos, size_v * 1.8, mid)
		var core: Color = col
		core.a = 0.85 * twinkle
		draw_circle(pos, size_v, core)
		# Pinprick — only bright enough to spot. Skipped on the smallest
		# particles so the field doesn't shimmer with white dots.
		if size_v > 1.2:
			var pin: Color = Color("#FFFFFF")
			pin.a = 0.65 * twinkle
			draw_circle(pos, maxf(0.6, size_v * 0.30), pin)

# Sector ambient layers — drawn before the particle field so particles
# composite on top. Per-sector branches keep the impl tight.
func _draw_sector_ambient() -> void:
	var sector := String(current_theme.get("name", ""))
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	match sector:
		"Spark":
			# Warm radial glow from below the screen — three concentric
			# circles that breathe slowly. Anchors the world identity in
			# the first 10 levels.
			var vp: Vector2 = get_viewport_rect().size
			var origin: Vector2 = -global_position + Vector2(vp.x * 0.5, vp.y * 1.05)
			var breath: float = 0.6 + 0.4 * sin(now * 0.7)
			var particle_col: Color = current_theme.get("particle", Color("#FFD23F"))
			var c1: Color = particle_col
			c1.a = 0.14 * breath
			draw_circle(origin, vp.y * 0.9, c1)
			var c2: Color = particle_col
			c2.a = 0.10 * breath
			draw_circle(origin, vp.y * 1.2, c2)
			var c3: Color = particle_col
			c3.a = 0.06 * breath
			draw_circle(origin, vp.y * 1.5, c3)
		"Nova":
			# 8 drifting nebula blobs behind the cells. Each has its own
			# breath phase so they don't pulse together. Colors lerp between
			# accent and dot_pulse for cosmic depth.
			var vp2: Vector2 = get_viewport_rect().size
			var origin2: Vector2 = -global_position
			var accent: Color = current_theme.get("accent", Color("#E1BFFF"))
			var dot_pulse: Color = current_theme.get("dot_pulse", Color("#FFB3C8"))
			for i in range(8):
				var phase: float = float(i) * 0.7 + now * 0.18
				var bx: float = vp2.x * (0.2 + 0.6 * fposmod(phase * 0.31, 1.0))
				var by: float = vp2.y * (0.2 + 0.6 * fposmod(phase * 0.47, 1.0))
				var blob_pos: Vector2 = origin2 + Vector2(bx, by)
				var radius: float = lerp(220.0, 380.0, fposmod(phase * 0.13, 1.0))
				var mix_t: float = 0.5 + 0.5 * sin(now * 0.4 + float(i))
				var blob_col: Color = accent.lerp(dot_pulse, mix_t)
				var breath2: float = 0.6 + 0.4 * sin(now * 0.5 + float(i) * 0.9)
				blob_col.a = 0.22 * breath2
				draw_circle(blob_pos, radius, blob_col)
				blob_col.a = 0.13 * breath2
				draw_circle(blob_pos, radius * 0.72, blob_col)
				blob_col.a = 0.06 * breath2
				draw_circle(blob_pos, radius * 0.42, blob_col)
		"Infinite":
			# Circuit grid — pale lines on a 60px spacing, drifting horizontally
			# over time. Brighter "circuit node" dots at every 3rd intersection.
			var vp3: Vector2 = get_viewport_rect().size
			var origin3: Vector2 = -global_position
			var grid_pulse: float = 0.5 + 0.5 * sin(now * 0.9)
			var line_col: Color = current_theme.get("ribbon", Color("#FFFFFF"))
			line_col.a = 0.18 * grid_pulse + 0.05
			var spacing: float = 60.0
			var drift: float = fposmod(now * 8.0, spacing)
			# Horizontal lines
			var y: float = -drift
			while y < vp3.y + spacing:
				draw_line(origin3 + Vector2(0, y), origin3 + Vector2(vp3.x, y), line_col, 1.0)
				y += spacing
			# Vertical lines
			var x: float = -drift
			while x < vp3.x + spacing:
				draw_line(origin3 + Vector2(x, 0), origin3 + Vector2(x, vp3.y), line_col, 1.0)
				x += spacing
			# Circuit nodes — every 3rd intersection brighter.
			var node_col: Color = current_theme.get("dot_pulse", Color("#FFFFFF"))
			node_col.a = 0.45 * grid_pulse + 0.15
			var ny: float = -drift
			var row_idx: int = 0
			while ny < vp3.y + spacing:
				var nx: float = -drift
				var col_idx: int = 0
				while nx < vp3.x + spacing:
					if (row_idx + col_idx) % 3 == 0:
						draw_circle(origin3 + Vector2(nx, ny), 2.4, node_col)
					nx += spacing
					col_idx += 1
				ny += spacing
				row_idx += 1
			# Shooting stars — fast diagonal head + bright halo + trailing line.
			for s in _shooting_stars:
				var t: float = float(s["t"]) / SHOOTING_DUR
				var alpha: float = 1.0 - t
				var head_pos: Vector2 = origin3 + (s["pos"] as Vector2)
				var tail_pos: Vector2 = head_pos - (s["vel"] as Vector2) * 0.06
				var trail_col: Color = Color("#FFFFFF")
				trail_col.a = alpha * 0.65
				draw_line(tail_pos, head_pos, trail_col, 3.5, true)
				var halo_col: Color = Color("#FFFFFF")
				halo_col.a = alpha * 0.30
				draw_circle(head_pos, 9.0, halo_col)
				var head_col: Color = Color("#FFFFFF")
				head_col.a = alpha * 0.95
				draw_circle(head_pos, 12.0 * (1.0 - 0.4 * t), head_col)
		_:
			pass

# Cinematic vignette — 4 trapezoidal gradient panels stacked at the screen
# edges, darker at the corners. Drawn LAST so it sits over everything else
# including the dots and lock animation. Caps at 0.32 alpha so the playfield
# stays comfortably visible.
func _draw_vignette() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	# Local position of the grid root within the viewport; vignette covers the
	# whole viewport regardless of where the grid is placed.
	var origin: Vector2 = -global_position
	var w: float = vp_size.x
	var h: float = vp_size.y
	# Each trapezoid: two outside vertices at the edge (alpha 0.32), two inside
	# vertices set in by `depth` (alpha 0). draw_polygon with per-vertex colors
	# gives a clean gradient.
	var depth: float = minf(w, h) * 0.18
	var dark: Color = Color(0, 0, 0, 0.32)
	var clear: Color = Color(0, 0, 0, 0.0)

	# Top
	_vignette_quad(
		[origin + Vector2(0, 0), origin + Vector2(w, 0),
		 origin + Vector2(w - depth, depth), origin + Vector2(depth, depth)],
		[dark, dark, clear, clear])
	# Bottom
	_vignette_quad(
		[origin + Vector2(0, h), origin + Vector2(w, h),
		 origin + Vector2(w - depth, h - depth), origin + Vector2(depth, h - depth)],
		[dark, dark, clear, clear])
	# Left
	_vignette_quad(
		[origin + Vector2(0, 0), origin + Vector2(0, h),
		 origin + Vector2(depth, h - depth), origin + Vector2(depth, depth)],
		[dark, dark, clear, clear])
	# Right
	_vignette_quad(
		[origin + Vector2(w, 0), origin + Vector2(w, h),
		 origin + Vector2(w - depth, h - depth), origin + Vector2(w - depth, depth)],
		[dark, dark, clear, clear])

func _vignette_quad(verts: Array, cols: Array) -> void:
	var pts := PackedVector2Array()
	for v in verts:
		pts.append(v)
	var c := PackedColorArray()
	for col in cols:
		c.append(col)
	draw_polygon(pts, c)

# Auto-lock visual: full-screen flash + bright disc pops at the closing cell
# + two expanding rings (themed + white) radiate outward. Tuned to be
# undeniable: the previous pass was too subtle to register among the other
# completion effects.
func _draw_lock_animation():
	if _lock_anim.is_empty():
		return
	var t: float = float(_lock_anim["t"]) / LOCK_DUR
	var pos: Vector2 = _lock_anim["pos"]

	# Full-screen white flash on the FIRST 0.18s, peaks immediately then
	# fades — frames the moment so the eye knows "something just happened"
	# even if it was looking elsewhere on screen.
	if t < 0.32:
		var flash_t: float = clampf(t / 0.18, 0.0, 1.0)
		var flash_a: float = (1.0 - flash_t) * 0.45
		var vp: Vector2 = get_viewport_rect().size
		var origin: Vector2 = -global_position
		var flash_col := Color("#FFFFFF")
		flash_col.a = flash_a
		draw_rect(Rect2(origin, vp), flash_col)

	# Pop disc — bigger now, brighter, slower fade.
	var pop_t: float = clampf(t / 0.25, 0.0, 1.0)
	var pop_radius: float = lerp(cell_size * 0.25, cell_size * 0.85, smoothstep(0.0, 1.0, pop_t))
	var pop_alpha: float = (1.0 - smoothstep(0.30, 1.0, t)) * 0.95
	var pop_col := Color("#FFFFFF")
	pop_col.a = pop_alpha
	draw_circle(pos, pop_radius, pop_col)

	# Themed glow disc behind the white pop — gives the pop color.
	var glow_alpha: float = (1.0 - smoothstep(0.40, 1.0, t)) * 0.65
	var glow_col := path_end
	glow_col.a = glow_alpha
	draw_circle(pos, pop_radius * 1.4, glow_col)

	# Outer expanding ring — wider, brighter, longer fade. Cell_size * 3.5
	# means the ring sweeps a 3-cell radius, so even at distance the player
	# sees the wave.
	var ring_radius: float = lerp(cell_size * 0.30, cell_size * 3.5, smoothstep(0.0, 1.0, t))
	var ring_alpha: float = (1.0 - t) * 0.85
	var ring_col := path_end
	ring_col.a = ring_alpha
	draw_circle(pos, ring_radius, ring_col, false, maxf(4.0, cell_size * 0.14), true)
	# Inner thinner white ring trailing — gives the wave a "sheen" leading edge.
	var inner_radius: float = ring_radius * 0.72
	var inner_col := Color("#FFFFFF")
	inner_col.a = ring_alpha * 0.75
	draw_circle(pos, inner_radius, inner_col, false, maxf(1.5, cell_size * 0.035), true)

func _create_fill_animation(_row: int, _col: int, _color: Color):
	# Simple pulse - just queue redraw
	queue_redraw()

func start_completion_animation():
	is_completing = true
	completion_progress = 0.0
	
	var tween = create_tween()
	tween.tween_property(self, "completion_progress", 1.0, 1.2).set_ease(Tween.EASE_IN)

func _draw():
	if grid_size <= 0 or cell_size <= 0:
		return
	_draw_background()
	_draw_bg_decorations()
	_draw_grid_background()
	_draw_solution_hint()
	_draw_path()
	_draw_ripples()
	_draw_dot_bursts()
	_draw_completion_wave()
	_draw_lock_animation()
	_draw_hint()
	_draw_errors()
	_draw_dots()
	_draw_vignette()

# Tutorial guide: dashed pulsing line from the player's current head to the
# NEXT numbered dot. Reads from the live HintSolver continuation (same source
# the hint button uses), so the trail is always valid for the path the player
# has actually drawn — not the canonical solution, which can wander when the
# player has taken an off-canon (but still solvable) detour.
func _draw_solution_hint():
	if not show_solution_hint:
		return
	if main == null or main.game_state == null:
		return
	var state = main.game_state
	if state.player_path.is_empty():
		return  # the pulsing first-dot ring guides them when path is empty
	var trail: Array = state.get_continuation_to_next_dot()
	if trail.is_empty():
		return

	var w := maxf(2.0, cell_size * 0.08)
	var col := path_end
	# Subtle pulse so the trail feels alive without being garish.
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var pulse: float = 0.6 + 0.4 * sin(now * 4.0)
	col.a = 0.30 * pulse + 0.18
	var dash := cell_size * 0.14
	var gap := cell_size * 0.10

	# Head → first trail cell, then chain through subsequent trail cells.
	var head_cell = state.player_path[-1]
	var prev: Vector2 = _cell_center(head_cell[0], head_cell[1])
	for tc in trail:
		var v: Vector2i = tc
		var here: Vector2 = _cell_center(v.x, v.y)
		_draw_dashed(prev, here, w, col, dash, gap)
		prev = here

func _draw_dashed(a: Vector2, b: Vector2, width: float, color: Color, dash: float, gap: float):
	var diff := b - a
	var length := diff.length()
	if length < 0.5:
		return
	var dir := diff / length
	var t := 0.0
	while t < length:
		var t2 := minf(t + dash, length)
		draw_line(a + dir * t, a + dir * t2, color, width, true)
		t = t2 + gap

func _draw_round_rect(rect: Rect2, radius: float, color: Color, width: float = -1.0):
	radius = minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	if width >= 0.0:
		# Outline only
		var pts := PackedVector2Array()
		var corners = [
			[Vector2(rect.position.x + radius, rect.position.y + radius), 180, 270],
			[Vector2(rect.end.x - radius, rect.position.y + radius), 270, 360],
			[Vector2(rect.end.x - radius, rect.end.y - radius), 0, 90],
			[Vector2(rect.position.x + radius, rect.end.y - radius), 90, 180],
		]
		for cdef in corners:
			for a in range(int(cdef[1]), int(cdef[2]) + 1, 9):
				pts.append(cdef[0] + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * radius)
		pts.append(pts[0])
		draw_polyline(pts, color, width, true)
		return
	# Filled
	draw_rect(Rect2(rect.position.x + radius, rect.position.y, rect.size.x - 2 * radius, rect.size.y), color)
	draw_rect(Rect2(rect.position.x, rect.position.y + radius, rect.size.x, rect.size.y - 2 * radius), color)
	draw_circle(Vector2(rect.position.x + radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.position.x + radius, rect.end.y - radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.end.y - radius), radius, color)

func _draw_background():
	var vp = get_viewport_rect().size
	var verts = PackedVector2Array([
		Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)
	])
	var cols = PackedColorArray([bg_color, bg_color, bg_color_bottom, bg_color_bottom])
	draw_polygon(verts, cols)
	for i in range(80):
		var x := fmod(float(i * 67 + 23), maxf(1.0, vp.x))
		var y := fmod(float(i * 43 + 11), maxf(1.0, vp.y))
		var grain := Color(0.263, 0.380, 0.933, 0.06)
		if i % 3 == 0:
			grain = Color(0.482, 0.176, 0.545, 0.05)
		draw_circle(Vector2(x, y), 0.7 + float(i % 5) * 0.18, grain)

func _draw_grid_background():
	# Soft drop shadow + rounded panel
	var shadow = grid_rect.grow(5.0)
	_draw_round_rect(shadow, grid_radius + 4.0, Color(0, 0, 0, 0.35))
	_draw_round_rect(grid_rect, grid_radius, grid_bg)

	# Cell tiles: empty cells get the base tone; cells the line has passed
	# through are filled with a shade-darker version of their path color.
	var inset = padding + 1.0
	var cr = maxf(4.0, cell_size * 0.16)
	for r in range(grid_size):
		for c in range(grid_size):
			var key = "%d,%d" % [r, c]
			var x = grid_rect.position.x + c * cell_size + inset
			var y = grid_rect.position.y + r * cell_size + inset
			var w = cell_size - inset * 2
			if blocked_cells.has(key):
				# Impassable block — drawn as a clear "do not enter" mark:
				# pure-black pit + thick themed border + diagonal X. Reads as
				# an obstacle at a glance instead of a slightly-darker cell.
				var stone_border := Color("#9E8FC7")
				_draw_round_rect(Rect2(x, y, w, w), cr, Color("#000000"))
				_draw_round_rect(Rect2(x, y, w, w), cr, stone_border, 2.5)
				var x_inset: float = w * 0.22
				var x_col: Color = stone_border.lightened(0.45)
				var lw: float = maxf(2.0, w * 0.06)
				draw_line(
					Vector2(x + x_inset, y + x_inset),
					Vector2(x + w - x_inset, y + w - x_inset),
					x_col, lw, true
				)
				draw_line(
					Vector2(x + x_inset, y + w - x_inset),
					Vector2(x + w - x_inset, y + x_inset),
					x_col, lw, true
				)
				continue
			var tile_col = cell_empty
			if cells.has(key):
				tile_col = (cells[key]["fill_color"] as Color).lightened(0.34)
			_draw_round_rect(Rect2(x, y, w, w), cr, tile_col)
			# Single subtle inner highlight on filled cells — adds depth without
			# making the cells look like they're glowing on their own (which
			# would compete with the ribbon's glow). Skipped on empty cells so
			# the unvisited grid stays calm.
			if cells.has(key):
				var fc: Color = cells[key]["fill_color"] as Color
				var inner: Color = fc.darkened(0.30)
				inner.a = 0.50
				var pad: float = w * 0.20
				_draw_round_rect(Rect2(x + pad, y + pad, w - 2.0 * pad, w - 2.0 * pad), cr * 0.55, inner)

func _draw_path():
	if path_cells.size() == 0:
		return

	var w := maxf(6.0, cell_size * 0.34)

	# Three-pass glow ribbon: outer halo (slow LFO) → mid → inner core. Each
	# pass scales the line width and tracks its own alpha curve so the ribbon
	# breathes without ever looking pulsy on its own. Tuned so the halo lights
	# the path without bleeding past the cell edges.
	if path_cells.size() >= 2:
		var now: float = float(Time.get_ticks_msec()) / 1000.0
		var pulse: float = 0.5 + 0.5 * sin(now * 2.6)
		var pulse_slow: float = 0.5 + 0.5 * sin(now * 1.2)
		var passes = [
			{ "mult": 3.0, "a": lerp(0.05, 0.10, pulse_slow) },
			{ "mult": 2.0, "a": lerp(0.11, 0.20, pulse) },
			{ "mult": 1.4, "a": lerp(0.25, 0.40, pulse) },
		]
		for pass_def in passes:
			for i in range(path_cells.size() - 1):
				var g1 = _cell_center(path_cells[i][0], path_cells[i][1])
				var g2 = _cell_center(path_cells[i + 1][0], path_cells[i + 1][1])
				var gc = path_start.lerp(path_end, float(i) / float(maxi(1, path_cells.size())))
				gc.a = pass_def["a"]
				draw_line(g1, g2, gc, w * pass_def["mult"], true)

	# Rounded ribbon: caps at every node + thick segments
	for i in range(path_cells.size()):
		var cell = path_cells[i]
		var center = _cell_center(cell[0], cell[1])
		var prog = float(i) / float(maxi(1, path_cells.size()))
		var node_col = path_start.lerp(path_end, prog)
		if is_completing:
			node_col = complete_flash.lerp(node_col, 1.0 - completion_progress)
		draw_circle(center, w / 2.0, node_col)
		if i < path_cells.size() - 1:
			var nxt = _cell_center(path_cells[i + 1][0], path_cells[i + 1][1])
			var seg_col = path_start.lerp(path_end, prog)
			if is_completing:
				seg_col = complete_flash.lerp(seg_col, 1.0 - completion_progress)
			draw_line(center, nxt, seg_col, w, true)

	# Quiet leading droplet
	if not is_completing:
		var head = _cell_center(path_cells[-1][0], path_cells[-1][1])
		var halo = path_end
		halo.a = 0.26
		draw_circle(head, w * 0.78, halo)
		var hc = path_end
		hc.a = 0.46
		draw_circle(head, w * 0.6, hc)
		draw_circle(head, w * 0.34, Color("#FFFFFF"))

func _draw_dots():
	for r in range(grid_size):
		for c in range(grid_size):
			var key = "%d,%d" % [r, c]
			var dot_num = dot_positions.get(key, -1)
			if dot_num > 0:
				var center = _cell_center(r, c)
				var is_reached = false
				var is_next = false
				
				if cells.has(key) and cells[key]["is_dot"]:
					is_reached = true
				
				if main and main.game_state:
					if main.game_state.get_next_dot_number() == dot_num:
						is_next = true
				
				var radius = maxf(dot_radius, cell_size * 0.32)

				var accent = path_start

				# Attention ring for the next stone
				if is_next and not is_reached:
					var ring_col = accent
					ring_col.a = 0.28
					draw_circle(center, radius + 8, ring_col)

				# Soft glow
				var glow = accent
				glow.a = 0.24
				draw_circle(center, radius + 5, glow)
				# Filled accent disc (reached dots get a brighter core)
				var disc = dot_fill if not is_reached else accent.lightened(0.22)
				draw_circle(center, radius, disc)
				# Disc luminance drives text and ring color so the number stays
				# legible whether the disc is dark (default) or near-white (next
				# target in Spark theme). Without this, a bright "6" on a
				# bright disc disappears.
				var disc_lum: float = disc.r * 0.299 + disc.g * 0.587 + disc.b * 0.114
				var dark_on_light: bool = disc_lum > 0.55
				var ring_col: Color = (Color(0, 0, 0, 1) if dark_on_light else accent)
				draw_circle(center, radius, ring_col, false, maxf(2.0, radius * 0.10), true)

				# Dot number — color picked against disc luminance.
				var font = ThemeDB.fallback_font
				var fs = clampi(int(radius * 1.15), 14, 30)
				var text = str(dot_num)
				var tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var ascent = font.get_ascent(fs)
				var descent = font.get_descent(fs)
				var baseline_y = center.y + (ascent - descent) / 2.0
				var tx = center.x - tw / 2.0
				var num_col: Color = Color(0, 0, 0, 1) if dark_on_light else dot_text
				var outline_col: Color = Color(1, 1, 1, 1) if dark_on_light else Color(0, 0, 0, 1)
				for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					draw_string(font, Vector2(tx, baseline_y) + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline_col)
				draw_string(font, Vector2(tx, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_col)

func _draw_hint():
	# Single-cell hint (legacy path used by tutorial and ad-rewarded fallback).
	if hint_cell.x >= 0:
		var r = hint_cell.x
		var c = hint_cell.y
		var center = _cell_center(r, c)
		var alpha = 0.45
		var color = hint_color
		color.a = alpha
		draw_circle(center, cell_size * 0.32, color)

		# Hint highlight border
		var rect = Rect2(
			grid_rect.position.x + c * cell_size + 4,
			grid_rect.position.y + r * cell_size + 4,
			cell_size - 8,
			cell_size - 8
		)
		_draw_round_rect(rect, cell_size * 0.16, hint_color, 2.5)

	# Smart-hint dashed trail (HintSolver continuation): each cell gets a
	# fading dashed-ring chip. First cell pops strongest so the eye latches on,
	# subsequent cells trail off to suggest direction without screaming the
	# answer.
	if hint_trail.size() > 0:
		# Subtle pulse synced with the hint_timer so the trail feels alive.
		var pulse: float = 0.6 + 0.4 * sin(hint_timer * 6.0)
		for i in range(hint_trail.size()):
			# Coerce per element — callers may pass Vector2 (HintSolver's
			# native type) or Vector2i. Assigning a Vector2 directly to a
			# Vector2i-typed var raises a strict type error and aborts the
			# whole loop, so the trail must be normalized here.
			var raw = hint_trail[i]
			var cr: int = int(raw.x)
			var cc: int = int(raw.y)
			var step_alpha: float = lerpf(0.85, 0.30, float(i) / float(maxi(1, hint_trail.size() - 1)))
			var center: Vector2 = _cell_center(cr, cc)
			# Dashed ring drawn as evenly-spaced arcs so the trail reads as
			# "guidance" not "this exact answer".
			var radius: float = cell_size * 0.32
			var ring_color: Color = hint_color
			ring_color.a = step_alpha * pulse
			var dashes: int = 8
			for d in range(dashes):
				if d % 2 != 0:
					continue
				var a0: float = (float(d) / float(dashes)) * TAU
				var a1: float = (float(d + 1) / float(dashes)) * TAU
				var arc_points: PackedVector2Array = PackedVector2Array()
				var steps: int = 6
				for s in range(steps + 1):
					var t: float = a0 + (a1 - a0) * (float(s) / float(steps))
					arc_points.append(center + Vector2(cos(t), sin(t)) * radius)
				draw_polyline(arc_points, ring_color, 2.4, true)
			# Soft inner glow on the FIRST trail cell only — the eye needs a
			# single anchor to "start" the path.
			if i == 0:
				var glow: Color = hint_color
				glow.a = 0.28 * pulse
				draw_circle(center, cell_size * 0.20, glow)

func _draw_errors():
	if error_cell.x >= 0:
		var r = error_cell.x
		var c = error_cell.y
		var center = _cell_center(r, c)
		var alpha = clampf(error_timer / 1.4, 0.0, 1.0)  # Fade out
		var color = error_color
		color.a = alpha * 0.28
		
		var shake = sin(error_timer * 50.0) * (1.0 - alpha) * 5.0
		draw_circle(center + Vector2(shake, 0), cell_size * 0.4, color)
		var outline := error_color
		outline.a = alpha * 0.65
		draw_circle(center + Vector2(shake, 0), cell_size * 0.4, outline, false, 2.0, true)

		# Toast message below the grid
		if error_message != "":
			var font = ThemeDB.fallback_font
			var fs = clampi(int(cell_size * 0.28), 14, 22)
			var msg_w = font.get_string_size(error_message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pad_x = 18.0
			var pad_y = 10.0
			var box_w = msg_w + pad_x * 2
			var box_h = fs + pad_y * 2
			var box_x = grid_rect.position.x + (grid_rect.size.x - box_w) / 2.0
			var box_y = grid_rect.end.y + 16.0
			var bg = Color("#1C1C38")
			bg.a = alpha
			_draw_round_rect(Rect2(box_x, box_y, box_w, box_h), box_h / 2.0, bg)
			var tcol = Color("#FFFFFF")
			tcol.a = alpha
			var ty = box_y + pad_y + font.get_ascent(fs)
			draw_string(font, Vector2(box_x + pad_x, ty), error_message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol)

func _cell_center(row: int, col: int) -> Vector2:
	return Vector2(
		grid_rect.position.x + col * cell_size + cell_size / 2.0,
		grid_rect.position.y + row * cell_size + cell_size / 2.0
	)
