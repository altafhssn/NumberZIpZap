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

# Error feedback
var error_cell: Vector2i = Vector2i(-1, -1)
var error_timer: float = 0.0
var error_message: String = ""

# Colors — all populated by apply_theme() (called by Main on level load).
# Defaults are Void-flavored so the grid still draws sensibly if a theme has
# not been applied yet (e.g. before the first level loads).
var bg_color: Color = Color("#0B0B16")
var bg_color_bottom: Color = Color("#13132A")
var grid_bg: Color = Color("#16162C")
var grid_border: Color = Color("#2A2A4E")
var cell_empty: Color = Color("#1C1C38")
var block_fill: Color = Color("#05050C")
var block_border: Color = Color("#3A2030")
var dot_fill: Color = Color("#000000")
var dot_text: Color = Color("#FFFFFF")
var path_start: Color = Color("#4361EE")
var path_end: Color = Color("#7B2D8B")
var dot_accent: Color = Color("#4361EE")
var dot_pulse_col: Color = Color("#7B2D8B")
var target_glow_col: Color = Color("#FFB347")
var particle_col: Color = Color("#F2A65A")
var ripple_col: Color = Color("#7B2D8B")
var accent_col: Color = Color("#FFD166")
var hint_color: Color = Color("#FFD166")
var error_color: Color = Color("#EF4444")
var complete_flash: Color = Color("#FFFFFF")
var dot_text_col: Color = Color("#FFFFFF")
var dot_outline_col: Color = Color("#FFFFFF")

# Theme / sector state (Feature: per-sector theming)
var current_theme: Dictionary = {}
var dynamic_ribbon_mode: String = ""  # "" | "singularity"
var current_level_index: int = 1

# Dynamic background particles. Each entry:
#   { pos: Vector2(0..1, 0..1), vel: Vector2, r: float, phase: float,
#     hue_off: float }
# Positions are normalised so the field works at any viewport size; we scale
# on draw. `omni` sectors (Nova, Infinite) let particles drift in any
# direction; non-omni sectors are "rising" (warm packs). `hue_off` is only
# non-zero on Infinite — each particle nudges away from the base hue for
# a prismatic look.
var _bg_particles: Array = []

# Sector-specific feature effects:
# - Spark: a random particle "flares" (briefly grows & brightens) every few s.
# - Ember: ~25% of particles are slow falling ash (lighter colour).
# - Nova:  soft nebula blobs drift behind the gameplay.
# - Infinite: rare shooting-star streaks fly across the screen.
var _flare_idx: int = -1            # index of currently flaring particle, or -1
var _flare_t: float = 0.0           # 0..FLARE_DUR remaining
var _flare_timer: float = 0.0       # countdown to next flare
const FLARE_DUR := 1.2

var _nebula_blobs: Array = []       # [{ pos:V2(0..1), vel:V2, r:px, hue:0..1 }]

var _streaks: Array = []            # [{ start:V2(0..1), vel:V2, t, life, col }]
var _streak_timer: float = 0.0

# Dot pop bursts — radial particle spray spawned when a numbered dot is
# reached. Each burst lives ~0.65s and consists of N small motes flying
# outward + an expanding ring.
var _dot_bursts: Array = []         # [{ pos, t, life, particles:[{angle, speed, r}] }]
const DOT_BURST_DUR := 0.65

# Completion light wave — when the level auto-locks, a bright "wave head"
# travels from path[0] to path[-1] over WAVE_DUR seconds; cells light up
# briefly as the wave passes through them. Set when play_lock_animation runs.
var _wave_t: float = 0.0
const WAVE_DUR := 0.9

const BG_PARTICLE_PER_SECTOR := {
	# Drastically different counts and sizes per sector so each world reads as
	# its own thing the moment you enter it.
	"Spark":    { "count": 12, "speed": 0.035, "spread": 0.012, "size_min": 2.5, "size_max": 5.5, "omni": false, "hue_jitter": 0.0 },
	"Glow":     { "count": 55, "speed": 0.045, "spread": 0.022, "size_min": 0.6, "size_max": 1.8, "omni": false, "hue_jitter": 0.0 },
	"Ember":    { "count": 60, "speed": 0.10,  "spread": 0.06,  "size_min": 0.8, "size_max": 4.5, "omni": false, "hue_jitter": 0.0 },
	"Nova":     { "count": 38, "speed": 0.025, "spread": 0.03,  "size_min": 1.5, "size_max": 4.5, "omni": true,  "hue_jitter": 0.0 },
	"Infinite": { "count": 30, "speed": 0.04,  "spread": 0.04,  "size_min": 1.0, "size_max": 4.8, "omni": true,  "hue_jitter": 0.7 },
}

# Layout
var grid_radius: float = 18.0

# Touch tracking
var is_dragging: bool = false
var last_touch_cell: Vector2i = Vector2i(-1, -1)

# VFX
var ripples: Array = []   # [{ "pos": Vector2, "t": float }]
const RIPPLE_DUR := 0.55

# Animation
var anim_timer: float = 0.0
var is_completing: bool = false
var completion_progress: float = 0.0

# Auto-lock snap animation (Feature 1) — runs on the final dot at lock moment.
var lock_cell: Vector2i = Vector2i(-1, -1)
var lock_t: float = 0.0
const LOCK_DUR := 0.32

# Hint visuals (Feature 2). Each has a countdown timer; -1 cell = inactive.
var hint_arrow_from: Vector2i = Vector2i(-1, -1)
var hint_arrow_to: Vector2i = Vector2i(-1, -1)
var hint_arrow_t: float = 0.0
var hint_glow_cell: Vector2i = Vector2i(-1, -1)
var hint_glow_t: float = 0.0
var hint_trail: Array = []          # Array[Vector2i]
var hint_trail_t: float = 0.0
var rewind_cell: Vector2i = Vector2i(-1, -1)
var rewind_t: float = 0.0

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
	is_completing = false
	hint_cell = Vector2i(-1, -1)
	error_cell = Vector2i(-1, -1)
	lock_cell = Vector2i(-1, -1)
	lock_t = 0.0
	_dot_bursts.clear()
	_wave_t = 0.0
	clear_hints()

	queue_redraw()

# Apply a sector palette. Called by Main on every level load. All draw colors
# are cached as plain Color fields so the hot path never allocates Colors.
func apply_theme(theme: Dictionary, level_index: int):
	current_theme = theme
	current_level_index = level_index
	dynamic_ribbon_mode = theme.get("dynamic_ribbon", "")

	bg_color = theme.get("bg_top", bg_color)
	bg_color_bottom = theme.get("bg_bottom", bg_color_bottom)
	grid_border = theme.get("grid_line", grid_border)
	cell_empty = theme.get("cell_empty", cell_empty)
	# Panel-behind-cells uses the theme's grid_line tone so cell tiles always
	# have visible separation. (Light themes like Paper have cell_empty
	# LIGHTER than the bg, so reusing cell_empty here would make the whole
	# grid disappear into the background.)
	grid_bg = theme.get("grid_line", cell_empty)
	block_fill = theme.get("block_fill", block_fill)
	block_border = theme.get("block_border", block_border)
	path_start = theme.get("ribbon", path_start)
	path_end = theme.get("glow", path_end)
	dot_accent = theme.get("dot_base", dot_accent)
	dot_pulse_col = theme.get("dot_pulse", dot_pulse_col)
	target_glow_col = theme.get("target_glow", target_glow_col)
	particle_col = theme.get("particle", particle_col)
	ripple_col = theme.get("ripple", ripple_col)
	accent_col = theme.get("accent", accent_col)
	# Hint color stays warm amber on dark themes for visibility; on light
	# themes (Tutorial / Sunrise) use the theme accent which is dark enough.
	if theme.get("light_bg", false):
		hint_color = accent_col
	else:
		hint_color = Color("#FFD166")
	# Number text on dots: black-on-white for light-bg packs would clash with
	# the accent disc colors, so we keep white-with-outline universally.
	dot_text_col = Color("#FFFFFF")

	_seed_bg_particles(theme.get("name", ""))
	queue_redraw()

# Seed the drifting-particle field from the sector's tuning. Positions are
# normalised so we can scale to any viewport. Each particle gets a random
# size, twinkle phase, and (Infinite only) hue offset so the field doesn't
# look procedurally regular.
func _seed_bg_particles(sector_name: String):
	var cfg: Dictionary = BG_PARTICLE_PER_SECTOR.get(sector_name,
		BG_PARTICLE_PER_SECTOR["Spark"])
	var count: int = int(cfg["count"])
	var speed: float = float(cfg["speed"])
	var spread: float = float(cfg["spread"])
	var size_min: float = float(cfg["size_min"])
	var size_max: float = float(cfg["size_max"])
	var omni: bool = bool(cfg["omni"])
	var hue_jitter: float = float(cfg["hue_jitter"])
	_bg_particles.clear()
	for i in range(count):
		var vel: Vector2
		if omni:
			# Cosmic drift — random direction in [-speed, +speed] on both axes.
			vel = Vector2(randf_range(-speed, speed), randf_range(-speed, speed))
		else:
			# Warm packs — rising with a light horizontal sway.
			vel = Vector2(randf_range(-spread, spread), -randf_range(speed * 0.4, speed))
		var color_override: Color = particle_col
		var is_ash := false
		# Ember: every ~4th particle is falling ash — slower, lighter colour.
		if sector_name == "Ember" and i % 4 == 0:
			is_ash = true
			vel = Vector2(randf_range(-0.012, 0.012), randf_range(0.012, 0.028))
			color_override = Color("#C8B8A0")
		var radius := randf_range(size_min, size_max)
		# Parallax depth: small particles drift at ~60% speed (further), big
		# at ~110% (closer). Normalised to the sector's size range.
		var size_norm: float = 0.0
		if size_max > size_min:
			size_norm = clampf((radius - size_min) / (size_max - size_min), 0.0, 1.0)
		var depth: float = lerpf(0.6, 1.1, size_norm)
		_bg_particles.append({
			"pos": Vector2(randf(), randf()),
			"vel": vel,
			"r": radius,
			"phase": randf() * TAU,
			"phase2": randf() * TAU,
			"hue_off": randf_range(-hue_jitter, hue_jitter) * 0.5,
			"color": color_override,
			"ash": is_ash,
			"depth": depth,
		})
	# Reset per-sector feature state.
	_flare_idx = -1
	_flare_t = 0.0
	_flare_timer = randf_range(2.5, 5.0)
	_streaks.clear()
	_streak_timer = randf_range(2.0, 4.0)
	_seed_nebula_blobs(sector_name)

# Seed slow drifting nebula blobs (Nova only). Big soft colored circles
# painted behind everything; gives the sector a sense of depth.
func _seed_nebula_blobs(sector_name: String):
	_nebula_blobs.clear()
	if sector_name != "Nova":
		return
	for i in range(8):
		_nebula_blobs.append({
			"pos": Vector2(randf(), randf()),
			"vel": Vector2(randf_range(-0.012, 0.012), randf_range(-0.012, 0.012)),
			"r": randf_range(220.0, 380.0),
			"hue": randf(),
		})

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
	# Path changed (undo/reset/rewind) — any on-screen hint is now stale.
	clear_hints()
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

	# A forward move stales any visible hint (the trail's first cell is now
	# behind the head, the glow/arrow target may already be played, etc).
	# Clear so we don't draw lines through cells the player has walked past.
	clear_hints()

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
	hint_timer = 2.0
	queue_redraw()

# --- Auto-lock snap (Feature 1) ---
func play_lock_animation(row: int, col: int):
	clear_hints()
	lock_cell = Vector2i(row, col)
	lock_t = LOCK_DUR
	# Kick off the completion light wave — a bright sweep travels from the
	# start of the path to the head, lighting each cell as it passes.
	_wave_t = WAVE_DUR
	queue_redraw()

# --- Hint visuals (Feature 2) ---
func clear_hints():
	hint_arrow_from = Vector2i(-1, -1)
	hint_arrow_to = Vector2i(-1, -1)
	hint_arrow_t = 0.0
	hint_glow_cell = Vector2i(-1, -1)
	hint_glow_t = 0.0
	hint_trail = []
	hint_trail_t = 0.0
	rewind_cell = Vector2i(-1, -1)
	rewind_t = 0.0

# Stage 0: directional arrow on the head pointing at the best next cell.
func show_hint_arrow(from_rc: Vector2i, to_rc: Vector2i):
	clear_hints()
	hint_arrow_from = from_rc
	hint_arrow_to = to_rc
	hint_arrow_t = 2.0
	queue_redraw()

# Stage 1: soft pulsing glow on the recommended next cell.
func show_hint_glow(rc: Vector2i):
	clear_hints()
	hint_glow_cell = rc
	hint_glow_t = 2.5
	queue_redraw()

# Stage 2: translucent dashed ghost trail over the next few cells.
func show_hint_trail(cells: Array):
	clear_hints()
	hint_trail = cells.duplicate()
	hint_trail_t = 4.0
	queue_redraw()

# Dead-end: "rewind to here" arrow on an earlier path cell.
func show_rewind_arrow(rc: Vector2i):
	clear_hints()
	rewind_cell = rc
	rewind_t = 3.0
	queue_redraw()

func get_cell_at(pos: Vector2) -> Vector2i:
	if not grid_rect.has_point(pos):
		return Vector2i(-1, -1)
	
	var local = pos - grid_rect.position
	var col = int(local.x / cell_size)
	var row = int(local.y / cell_size)
	
	if row >= 0 and row < grid_size and col >= 0 and col < grid_size:
		return Vector2i(row, col)
	return Vector2i(-1, -1)

func _is_dot(row: int, col: int) -> bool:
	return dot_positions.has("%d,%d" % [row, col])

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
			if main and main.has_method("on_touch_released"):
				main.on_touch_released()
	
	if (event is InputEventScreenDrag or (event is InputEventMouseMotion and is_dragging)):
		if is_dragging:
			var cell = get_cell_at(event.position)
			if cell.x >= 0 and cell != last_touch_cell:
				# Drag interpolation: if the finger jumped over cells (fast
				# drag or small touch target), walk the gap one Manhattan
				# step at a time so every cell between the previous and
				# current finger position is fed to the game. Without this,
				# fast drags silently skip cells and the line either won't
				# extend (non-adjacent reject) or — pre stable-line rule —
				# would jump backwards. Combined with the rewind-only-on
				# -step-back rule, this lets backward drags fluidly retrace
				# the path while sideways slips can't collapse it.
				_walk_drag_to(cell)
				last_touch_cell = cell

func _walk_drag_to(target: Vector2i):
	# Step from last_touch_cell to target one Manhattan unit at a time, picking
	# the dominant axis at each step. Each intermediate cell is forwarded to
	# the game so a fast drag is treated like a slow one.
	if last_touch_cell.x < 0:
		main.on_cell_drag(target.x, target.y)
		return
	var cur := last_touch_cell
	var safety := 0
	while cur != target and safety < 64:
		safety += 1
		var dr := target.x - cur.x
		var dc := target.y - cur.y
		var step := Vector2i(0, 0)
		if absi(dr) >= absi(dc):
			step.x = signi(dr)
		else:
			step.y = signi(dc)
		if step == Vector2i(0, 0):
			break
		cur += step
		main.on_cell_drag(cur.x, cur.y)

func _process(delta):
	# Drift background particles. Positions are normalised (0..1) so this is
	# resolution-independent; wrap when they leave the viewport. Velocity is
	# scaled by a parallax depth factor: small particles drift slower (they
	# read as further away), big ones drift faster — gives a sense of layered
	# depth instead of a flat field.
	for p in _bg_particles:
		p["pos"] += p["vel"] * delta * float(p.get("depth", 1.0))
		if p["ash"]:
			# Falling ash wraps from bottom back to the top.
			if p["pos"].y > 1.02:
				p["pos"].y = -0.02
				p["pos"].x = randf()
		else:
			if p["pos"].y < -0.02:
				p["pos"].y = 1.02
				p["pos"].x = randf()
			elif p["pos"].y > 1.02:
				# Omni packs may drift downward off the bottom.
				p["pos"].y = -0.02
				p["pos"].x = randf()
		if p["pos"].x < -0.02:
			p["pos"].x = 1.02
		elif p["pos"].x > 1.02:
			p["pos"].x = -0.02
	_step_flare(delta)
	_step_nebula(delta)
	_step_streaks(delta)

	var needs_redraw = false

	if hint_timer > 0:
		hint_timer -= delta
		needs_redraw = true  # animate pulse
		if hint_timer <= 0:
			hint_cell = Vector2i(-1, -1)

	if error_timer > 0:
		error_timer -= delta
		needs_redraw = true  # animate shake + toast fade
		if error_timer <= 0:
			error_cell = Vector2i(-1, -1)
			error_message = ""

	if not ripples.is_empty():
		var alive_ripples: Array = []
		for rp in ripples:
			rp["t"] += delta
			if rp["t"] < RIPPLE_DUR:
				alive_ripples.append(rp)
		ripples = alive_ripples

	# Auto-lock snap counts down to 0.
	if lock_t > 0:
		lock_t -= delta
		needs_redraw = true
		if lock_t <= 0:
			lock_cell = Vector2i(-1, -1)

	# Completion light wave — advances over WAVE_DUR, cells light up as the
	# wave head passes through them.
	if _wave_t > 0.0:
		_wave_t -= delta
		needs_redraw = true
		if _wave_t < 0.0:
			_wave_t = 0.0

	# Dot bursts — advance each, drop those past their life.
	if not _dot_bursts.is_empty():
		var alive_b: Array = []
		for b in _dot_bursts:
			b["t"] += delta
			if b["t"] < b["life"]:
				alive_b.append(b)
		_dot_bursts = alive_b
		needs_redraw = true

	# Hint visual timers (auto-fade).
	if hint_arrow_t > 0:
		hint_arrow_t -= delta
		needs_redraw = true
		if hint_arrow_t <= 0:
			hint_arrow_from = Vector2i(-1, -1)
	if hint_glow_t > 0:
		hint_glow_t -= delta
		needs_redraw = true
		if hint_glow_t <= 0:
			hint_glow_cell = Vector2i(-1, -1)
	if hint_trail_t > 0:
		hint_trail_t -= delta
		needs_redraw = true
		if hint_trail_t <= 0:
			hint_trail = []
	if rewind_t > 0:
		rewind_t -= delta
		needs_redraw = true
		if rewind_t <= 0:
			rewind_cell = Vector2i(-1, -1)

	# Continuous redraw keeps the glow pulse, dot pulse, ripples and
	# completion shimmer animating smoothly.
	queue_redraw()

# Spark flare: schedule the next flare, advance the active one.
func _step_flare(delta):
	if current_theme.get("name", "") != "Spark" or _bg_particles.is_empty():
		return
	if _flare_t > 0.0:
		_flare_t -= delta
		if _flare_t <= 0.0:
			_flare_idx = -1
		return
	_flare_timer -= delta
	if _flare_timer <= 0.0:
		_flare_timer = randf_range(3.0, 5.5)
		_flare_idx = randi() % _bg_particles.size()
		_flare_t = FLARE_DUR

func _step_nebula(delta):
	if _nebula_blobs.is_empty():
		return
	for b in _nebula_blobs:
		b["pos"] += b["vel"] * delta
		if b["pos"].x < -0.2: b["pos"].x = 1.2
		elif b["pos"].x > 1.2: b["pos"].x = -0.2
		if b["pos"].y < -0.2: b["pos"].y = 1.2
		elif b["pos"].y > 1.2: b["pos"].y = -0.2

# Infinite shooting stars — spawn one every 6..11s; brief life.
func _step_streaks(delta):
	if current_theme.get("name", "") != "Infinite":
		return
	var alive: Array = []
	for s in _streaks:
		s["t"] += delta
		if s["t"] < s["life"]:
			alive.append(s)
	_streaks = alive
	_streak_timer -= delta
	if _streak_timer <= 0.0:
		_streak_timer = randf_range(3.0, 5.0)
		var dir := Vector2(randf_range(0.7, 1.0), randf_range(-0.4, 0.2)).normalized()
		_streaks.append({
			"start": Vector2(randf_range(-0.15, 0.4), randf_range(0.05, 0.85)),
			"vel": dir * 1.1,
			"t": 0.0,
			"life": 0.85,
			"hue": randf(),
		})

func spawn_ripple(row: int, col: int):
	ripples.append({ "pos": _cell_center(row, col), "t": 0.0 })
	# Every ripple also fires a directional dot-pop burst — the dot has just
	# been reached, so this is the celebratory micro-feedback.
	spawn_dot_burst(row, col)
	queue_redraw()

# Spray particles outward from a cell — the "tactile" feedback when a
# numbered dot is reached. Uses the theme's particle colour.
func spawn_dot_burst(row: int, col: int):
	var center := _cell_center(row, col)
	var motes: Array = []
	var count := 14
	for i in range(count):
		var angle: float = (float(i) / float(count)) * TAU + randf_range(-0.18, 0.18)
		motes.append({
			"angle": angle,
			"speed": randf_range(0.7, 1.4) * cell_size,
			"r": randf_range(2.0, 4.0),
		})
	_dot_bursts.append({
		"pos": center,
		"t": 0.0,
		"life": DOT_BURST_DUR,
		"motes": motes,
	})

func _draw_ripples():
	for rp in ripples:
		var k: float = rp["t"] / RIPPLE_DUR
		var radius: float = lerpf(cell_size * 0.25, cell_size * 0.85, k)
		var col: Color = ripple_col
		col.a = (1.0 - k) * 0.6
		draw_circle(rp["pos"], radius, col, false, maxf(2.0, cell_size * 0.06), true)
		var inner := Color("#FFFFFF")
		inner.a = (1.0 - k) * 0.35
		draw_circle(rp["pos"], radius * 0.55, inner, false, maxf(1.5, cell_size * 0.03), true)

# Radial spray of motes from a dot, plus a white expanding ring at the
# centre — the satisfying "pop" when a number is reached.
func _draw_dot_bursts():
	for b in _dot_bursts:
		var k: float = b["t"] / b["life"]
		var fade: float = 1.0 - k
		# Soft expanding ring
		var ring_r: float = lerpf(cell_size * 0.18, cell_size * 0.95, k)
		var ring_col: Color = particle_col
		ring_col.a = fade * 0.65
		draw_circle(b["pos"], ring_r, ring_col, false, maxf(2.0, cell_size * 0.07), true)
		var w_ring := Color("#FFFFFF")
		w_ring.a = fade * fade * 0.55
		draw_circle(b["pos"], ring_r * 0.7, w_ring, false, maxf(1.5, cell_size * 0.04), true)
		# Spraying motes
		for m in b["motes"]:
			var distance: float = m["speed"] * b["t"] * (1.0 - k * 0.4)  # ease-out
			var pos: Vector2 = b["pos"] + Vector2(cos(m["angle"]), sin(m["angle"])) * distance
			var r: float = m["r"] * (1.0 - k * 0.5)
			var col: Color = particle_col
			col.a = fade * 0.85
			draw_circle(pos, r * 2.0, col)
			col = Color("#FFFFFF")
			col.a = fade * fade * 0.70
			draw_circle(pos, r * 0.7, col)

# Completion sweep — a bright wavefront travels along the played path from
# start to head when the level locks. Each cell brightens for a brief window
# as the wave passes it, the head of the wave painting a luminous halo.
func _draw_completion_wave():
	if _wave_t <= 0.0 or path_cells.size() < 2:
		return
	var k: float = 1.0 - (_wave_t / WAVE_DUR)
	var head_idx: float = k * float(path_cells.size() - 1)
	for i in range(path_cells.size()):
		var dist: float = absf(float(i) - head_idx)
		if dist > 3.5:
			continue
		var localk: float = 1.0 - (dist / 3.5)
		localk = localk * localk * (3.0 - 2.0 * localk)  # smoothstep
		var center := _cell_center(path_cells[i][0], path_cells[i][1])
		var c1: Color = Color("#FFFFFF")
		c1.a = 0.70 * localk
		draw_circle(center, cell_size * 0.55 * localk, c1)
		var c2: Color = path_end
		c2.a = 0.60 * localk
		draw_circle(center, cell_size * 0.85 * localk, c2)

func _create_fill_animation(row: int, col: int, color: Color):
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
	# Singularity: rotate the ribbon hue 0..360 over 4s. We swap path_start /
	# path_end for the duration of this frame, then restore so the theme
	# fields remain authoritative.
	var saved_start := path_start
	var saved_end := path_end
	if dynamic_ribbon_mode == "nova":
		var hue := fposmod(Time.get_ticks_msec() / 4000.0, 1.0)
		path_start = Color.from_hsv(hue, 0.85, 1.0)
		path_end = Color.from_hsv(fposmod(hue + 0.08, 1.0), 0.55, 1.0)

	_draw_background()
	_draw_grid_background()
	_draw_solution_hint()
	_draw_hint_visuals()
	_draw_completion_wave()
	_draw_path()
	_draw_ripples()
	_draw_dot_bursts()
	_draw_hint()
	_draw_errors()
	_draw_dots()
	_draw_lock()
	_draw_vignette()

	if dynamic_ribbon_mode == "nova":
		path_start = saved_start
		path_end = saved_end

# Tutorial guide: dashed pulsing trail from the player's head, through each
# adjacent cell, to the NEXT un-reached numbered dot. The trail is computed
# by the same solver the hint button uses, so it's always a real walkable
# path — and trimmed at the next dot so the player learns one number at a
# time. (We deliberately don't draw the full canonical Hamiltonian solution
# here — it can wind arbitrarily and confuses newcomers.)
func _draw_solution_hint():
	if not show_solution_hint:
		return
	if main == null or main.game_state == null:
		return
	var state = main.game_state
	if state.player_path.is_empty():
		return
	if state.next_dot_index >= state.dots.size():
		return
	var trail: Array = state.get_continuation_to_next_dot()
	if trail.is_empty():
		return
	var head = state.player_path[-1]
	var w := maxf(2.0, cell_size * 0.08)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
	var col: Color = accent_col
	col.a = lerpf(0.35, 0.65, pulse)
	var dash := cell_size * 0.14
	var gap := cell_size * 0.10
	# First segment: head -> first cell of the trail.
	var prev := _cell_center(head[0], head[1])
	for c in trail:
		var nxt := _cell_center(int(c.x), int(c.y))
		_draw_dashed(prev, nxt, w, col, dash, gap)
		prev = nxt

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

# Draws a filled pill without overlapping geometry — the central bar and the
# two semicircular caps don't share pixels, so semi-transparent colors don't
# composite to a brighter shade at the ends (which _draw_round_rect does when
# radius == height/2 because its four corner circles collapse to two
# positions and each is drawn twice).
# Cinematic vignette — gentle dark falloff at the screen edges. Drawn LAST
# so it sits over everything, but kept light (~0.20 max) so it doesn't dim
# the playfield centre.
func _draw_vignette():
	var vp := get_viewport_rect().size
	var dark := Color(0.0, 0.0, 0.0, 0.32)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	# Top edge fading down
	var top_depth: float = vp.y * 0.18
	var top_v := PackedVector2Array([
		Vector2(0, 0), Vector2(vp.x, 0),
		Vector2(vp.x, top_depth), Vector2(0, top_depth),
	])
	var top_c := PackedColorArray([dark, dark, clear, clear])
	draw_polygon(top_v, top_c)
	# Bottom edge fading up
	var bot_depth: float = vp.y * 0.22
	var bot_v := PackedVector2Array([
		Vector2(0, vp.y - bot_depth), Vector2(vp.x, vp.y - bot_depth),
		Vector2(vp.x, vp.y), Vector2(0, vp.y),
	])
	var bot_c := PackedColorArray([clear, clear, dark, dark])
	draw_polygon(bot_v, bot_c)
	# Left / right edges (narrower since we're already in portrait)
	var side_w: float = vp.x * 0.10
	var l_v := PackedVector2Array([
		Vector2(0, 0), Vector2(side_w, 0),
		Vector2(side_w, vp.y), Vector2(0, vp.y),
	])
	var l_c := PackedColorArray([dark, clear, clear, dark])
	draw_polygon(l_v, l_c)
	var r_v := PackedVector2Array([
		Vector2(vp.x - side_w, 0), Vector2(vp.x, 0),
		Vector2(vp.x, vp.y), Vector2(vp.x - side_w, vp.y),
	])
	var r_c := PackedColorArray([clear, dark, dark, clear])
	draw_polygon(r_v, r_c)

func _draw_sector_ambient(vp: Vector2):
	var t_ms := Time.get_ticks_msec()
	var name: String = current_theme.get("name", "")
	match name:
		"Spark":
			# Warm radial glow at the bottom edge — fireside firelight.
			var center := Vector2(vp.x * 0.5, vp.y * 1.05)
			var pulse: float = 0.85 + 0.15 * sin(t_ms * 0.0008)
			var radii: Array = [vp.x * 0.95, vp.x * 0.65, vp.x * 0.4]
			var alphas: Array = [0.06, 0.10, 0.14]
			for i in range(radii.size()):
				var col: Color = particle_col
				col.a = float(alphas[i]) * pulse
				draw_circle(center, float(radii[i]), col)
		# Glow and Ember intentionally have NO ambient layer — their dense
		# particle fields (tiny dust motes / chaotic embers + ash) already
		# give them strong visual identity and the extra bands/gradient just
		# competed for attention.
		"Infinite":
			# Bright pulsing grid lines + diagonals — clearly "digital void",
			# now strong enough to see (was hiding at 0.06 alpha).
			var spacing: float = 60.0
			var pulse3: float = 0.55 + 0.35 * sin(t_ms * 0.0009)
			var col: Color = accent_col
			col.a = 0.20 * pulse3
			var lw: float = 1.2
			var ox: float = fposmod(t_ms * 0.006, spacing)
			var oy: float = fposmod(t_ms * 0.004, spacing)
			var x: float = -ox
			while x < vp.x:
				draw_line(Vector2(x, 0), Vector2(x, vp.y), col, lw, false)
				x += spacing
			var y: float = -oy
			while y < vp.y:
				draw_line(Vector2(0, y), Vector2(vp.x, y), col, lw, false)
				y += spacing
			# Brighter "nodes" at intersections of every 3rd line — gives the
			# grid an active circuitry look.
			var node_col: Color = accent_col
			node_col.a = 0.40 * pulse3
			x = -ox
			var ix: int = 0
			while x < vp.x:
				if ix % 3 == 0:
					y = -oy
					var iy: int = 0
					while y < vp.y:
						if iy % 3 == 0:
							draw_circle(Vector2(x, y), 2.0, node_col)
						y += spacing
						iy += 1
				x += spacing
				ix += 1

func _draw_pill(rect: Rect2, color: Color):
	var r := minf(rect.size.x, rect.size.y) * 0.5
	if rect.size.x <= 2.0 * r:
		draw_circle(rect.position + rect.size * 0.5, r, color)
		return
	var cy := rect.position.y + r
	draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - 2.0 * r, rect.size.y), color)
	draw_circle(Vector2(rect.position.x + r, cy), r, color)
	draw_circle(Vector2(rect.end.x - r, cy), r, color)

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
	# Gradient breath — bg brightness inhales ±0.03 in linear space over ~9s.
	# Just enough motion that even an empty playfield feels alive without
	# the bg pulsing distractingly.
	var breath: float = 0.015 + 0.015 * sin(Time.get_ticks_msec() * 0.0007)
	var top_b: Color = Color(
		clampf(bg_color.r + breath, 0.0, 1.0),
		clampf(bg_color.g + breath, 0.0, 1.0),
		clampf(bg_color.b + breath, 0.0, 1.0), 1.0)
	var bot_b: Color = Color(
		clampf(bg_color_bottom.r + breath, 0.0, 1.0),
		clampf(bg_color_bottom.g + breath, 0.0, 1.0),
		clampf(bg_color_bottom.b + breath, 0.0, 1.0), 1.0)
	var verts = PackedVector2Array([
		Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)
	])
	var cols = PackedColorArray([top_b, top_b, bot_b, bot_b])
	draw_polygon(verts, cols)

	# Per-sector ambient effect — distinctive bg element so the sector reads
	# at a glance, even before you notice the particle palette.
	_draw_sector_ambient(vp)

	# Nova nebula blobs — large soft colored clouds drifting behind cells.
	# Each blob has its own slow breath so the field doesn't pulse in lockstep.
	for i in range(_nebula_blobs.size()):
		var b: Dictionary = _nebula_blobs[i]
		var bp := Vector2(b["pos"].x * vp.x, b["pos"].y * vp.y)
		var col: Color = accent_col.lerp(dot_pulse_col, b["hue"])
		var t_ms_n := Time.get_ticks_msec()
		var breath_n: float = 0.75 + 0.25 * sin(t_ms_n * 0.0008 + float(i) * 1.7)
		col.a = 0.22 * breath_n
		draw_circle(bp, b["r"], col)
		col.a = 0.36 * breath_n
		draw_circle(bp, b["r"] * 0.55, col)
		col.a = 0.48 * breath_n
		draw_circle(bp, b["r"] * 0.28, col)

	# Drifting sector particles — themed sparks/embers/cosmic dust. Each
	# particle is rendered in 4 stacked layers (wide soft halo → mid glow →
	# bright core → white pinprick) so it reads as a soft luminous star
	# rather than a flat dot.
	if not _bg_particles.is_empty():
		var t_ms := Time.get_ticks_msec()
		for i in range(_bg_particles.size()):
			var p: Dictionary = _bg_particles[i]
			var pos := Vector2(p["pos"].x * vp.x, p["pos"].y * vp.y)
			# Two-frequency twinkle: primary slow breath + secondary faster
			# wobble in a 70/30 mix so it doesn't pulse mechanically.
			var tw_a: float = sin(t_ms * 0.0017 + p["phase"])
			var tw_b: float = sin(t_ms * 0.0009 + p["phase2"])
			var twinkle: float = 0.5 + 0.5 * (tw_a * 0.7 + tw_b * 0.3)
			var base: Color = p["color"]
			var hoff: float = p["hue_off"]
			if hoff != 0.0:
				base = Color.from_hsv(fposmod(base.h + hoff, 1.0), base.s, base.v)
			# Spark flare boost — picked particle grows/brightens briefly.
			var boost: float = 1.0
			if i == _flare_idx and _flare_t > 0.0:
				# Bell curve over the flare's life: peak at the midpoint.
				var k: float = sin((1.0 - _flare_t / FLARE_DUR) * PI)
				boost = 1.0 + 1.8 * k
			var r: float = p["r"] * boost
			# Layer 1 — wide soft outer halo
			var c1: Color = base
			c1.a = lerpf(0.025, 0.085, twinkle) * boost
			draw_circle(pos, r * 5.0, c1)
			# Layer 2 — mid glow
			var c2: Color = base
			c2.a = lerpf(0.08, 0.22, twinkle) * boost
			draw_circle(pos, r * 2.4, c2)
			# Layer 3 — bright core
			var c3: Color = base
			c3.a = lerpf(0.40, 0.78, twinkle)
			draw_circle(pos, r, c3)
			# Layer 4 — white pinprick at the centre, gives the "star" sparkle
			var c4: Color = Color("#FFFFFF")
			c4.a = lerpf(0.0, 0.42, twinkle) * 0.55
			draw_circle(pos, r * 0.4, c4)

	# Infinite shooting stars — fast head + bright fading trail. Drawn thick
	# enough to clearly read against the grid.
	for s in _streaks:
		var k: float = s["t"] / s["life"]
		var head: Vector2 = s["start"] + s["vel"] * s["t"]
		var tail_t: float = maxf(0.0, s["t"] - 0.22)
		var tail: Vector2 = s["start"] + s["vel"] * tail_t
		var hp: Vector2 = Vector2(head.x * vp.x, head.y * vp.y)
		var tp: Vector2 = Vector2(tail.x * vp.x, tail.y * vp.y)
		var shue: float = fposmod(particle_col.h + s["hue"] * 0.25, 1.0)
		var sc: Color = Color.from_hsv(shue, 0.4, 1.0)
		# Soft tail halo
		var halo: Color = sc
		halo.a = (1.0 - k) * 0.30
		draw_line(tp, hp, halo, 9.0, true)
		# Tail core
		sc.a = (1.0 - k) * 0.85
		draw_line(tp, hp, sc, 3.5, true)
		# Head halo + bright white core
		var head_halo: Color = sc
		head_halo.a = (1.0 - k) * 0.55
		draw_circle(hp, 12.0, head_halo)
		head_halo.a = (1.0 - k) * 0.95
		draw_circle(hp, 6.0, head_halo)
		var white := Color("#FFFFFF")
		white.a = (1.0 - k)
		draw_circle(hp, 2.5, white)

func _draw_grid_background():
	# Soft drop shadow + rounded panel
	var shadow = grid_rect.grow(6.0)
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
				# Impassable block — drawn as a clear "do not enter" mark
				# (pure-black pit, thicker themed border, diagonal X) so it
				# reads as an obstacle to avoid, not just another empty cell.
				_draw_round_rect(Rect2(x, y, w, w), cr, Color("#000000"))
				_draw_round_rect(Rect2(x, y, w, w), cr, block_border, 2.5)
				var x_inset: float = w * 0.22
				var x_col: Color = block_border.lightened(0.45)
				var lw: float = maxf(2.0, w * 0.06)
				draw_line(Vector2(x + x_inset, y + x_inset), Vector2(x + w - x_inset, y + w - x_inset), x_col, lw, true)
				draw_line(Vector2(x + x_inset, y + w - x_inset), Vector2(x + w - x_inset, y + x_inset), x_col, lw, true)
				continue
			var tile_col = cell_empty
			if cells.has(key):
				tile_col = (cells[key]["fill_color"] as Color).darkened(0.5)
			_draw_round_rect(Rect2(x, y, w, w), cr, tile_col)
			# Filled cells get a single subtle inner highlight — adds depth
			# without making the cells look like they're glowing on their own
			# (which competes with the ribbon's glow for attention).
			if cells.has(key):
				var fc: Color = cells[key]["fill_color"] as Color
				var inner: Color = fc.darkened(0.30)
				inner.a = 0.50
				var pad: float = w * 0.20
				_draw_round_rect(Rect2(x + pad, y + pad, w - 2.0 * pad, w - 2.0 * pad),
					cr * 0.55, inner)

func _draw_path():
	if path_cells.size() == 0:
		return

	var w := maxf(6.0, cell_size * 0.34)

	# Animated glowing line — three passes (outer halo + mid + inner) tuned
	# so the halo lights up the path without bleeding into surrounding empty
	# cells. The outer halo breathes on a slow LFO; the inner pulses faster.
	if path_cells.size() >= 2:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		var pulse_slow: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0017)
		var passes = [
			{ "mult": 3.0, "a": lerpf(0.05, 0.10, pulse_slow) },   # outer halo
			{ "mult": 2.0, "a": lerpf(0.11, 0.20, pulse) },         # mid
			{ "mult": 1.4, "a": lerpf(0.25, 0.40, pulse) },         # inner core
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

	# Flowing highlight — a soft bead travels from path start to head every
	# ~1.5s, signalling the ribbon is "live". Skipped during the completion
	# tween so the win flash isn't muddied by an extra layer.
	if not is_completing and path_cells.size() >= 2:
		var flow_period_ms: float = 1500.0
		var flow_t: float = fposmod(Time.get_ticks_msec() / flow_period_ms, 1.0)
		var head_idx: float = flow_t * float(path_cells.size() - 1)
		var span: float = 3.0   # cells covered by the moving highlight
		for i in range(path_cells.size()):
			var dist: float = absf(float(i) - head_idx)
			if dist > span:
				continue
			# Smooth falloff (smoothstep) so the trail tapers naturally.
			var k: float = 1.0 - (dist / span)
			k = k * k * (3.0 - 2.0 * k)
			var center := _cell_center(path_cells[i][0], path_cells[i][1])
			var glow_col: Color = path_end
			glow_col.a = 0.50 * k
			draw_circle(center, w * (0.55 + 0.20 * k), glow_col)
			var core: Color = Color("#FFFFFF")
			core.a = 0.55 * k
			draw_circle(center, w * 0.22 * k, core)

	# Bright pulsing head marker
	if not is_completing:
		var head = _cell_center(path_cells[-1][0], path_cells[-1][1])
		var hp: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		var halo = path_end
		halo.a = lerpf(0.20, 0.45, hp)
		draw_circle(head, w * lerpf(0.7, 0.95, hp), halo)
		var hc = path_end
		hc.a = 0.55
		draw_circle(head, w * 0.6, hc)
		draw_circle(head, w * 0.34, Color("#FFFFFF"))

func _max_dot_number() -> int:
	var m := 0
	for k in dot_positions.keys():
		var n: int = dot_positions[k]
		if n > m:
			m = n
	return m

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
				if is_next and not is_reached:
					# Pulsing next dot
					var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.005) * 0.10
					radius *= pulse

				# Numbered-dot base color; the final/target dot uses the
				# theme's "target_glow" to make the end of the puzzle pop.
				var is_final_dot: bool = dot_num == _max_dot_number()
				var accent: Color = target_glow_col if is_final_dot else dot_accent

				# Pulsing attention ring for the next target dot
				if is_next and not is_reached:
					var ring = 0.30 + sin(Time.get_ticks_msec() * 0.006) * 0.22
					var ring_col: Color = dot_pulse_col
					ring_col.a = ring
					draw_circle(center, radius + 8, ring_col)

				# Soft glow
				var glow: Color = accent
				glow.a = 0.40
				draw_circle(center, radius + 5, glow)
				# Filled accent disc (reached dots get a brighter core)
				var disc: Color = accent if not is_reached else accent.lightened(0.15)
				draw_circle(center, radius, disc)
				# Crisp ring — picks dark/light so it's visible on any disc.
				var ring_outline: Color = Color("#0A0A14") if disc.get_luminance() > 0.55 else Color("#FFFFFF")
				draw_circle(center, radius, ring_outline, false, maxf(2.0, radius * 0.12), true)

				# Dot number — contrast against the disc so it's readable on
				# both light discs (e.g. Spark's white target) and dark ones.
				var font = ThemeDB.fallback_font
				var fs = clampi(int(radius * 1.15), 14, 30)
				var text = str(dot_num)
				var tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var ascent = font.get_ascent(fs)
				var descent = font.get_descent(fs)
				var baseline_y = center.y + (ascent - descent) / 2.0
				var tx = center.x - tw / 2.0
				var light_disc := disc.get_luminance() > 0.55
				var num_col: Color = Color("#0A0A14") if light_disc else Color("#FFFFFF")
				var outline_col: Color = Color("#FFFFFF") if light_disc else Color("#0A0A14")
				for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					draw_string(font, Vector2(tx, baseline_y) + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline_col)
				draw_string(font, Vector2(tx, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_col)

func _draw_hint():
	if hint_cell.x >= 0:
		var r = hint_cell.x
		var c = hint_cell.y
		var center = _cell_center(r, c)
		var alpha = 0.4 + sin(Time.get_ticks_msec() * 0.008) * 0.3
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

func _draw_errors():
	if error_cell.x >= 0:
		var r = error_cell.x
		var c = error_cell.y
		var center = _cell_center(r, c)
		var alpha = clampf(error_timer / 1.4, 0.0, 1.0)  # Fade out
		var color = error_color
		color.a = alpha * 0.5
		
		var shake = sin(error_timer * 50.0) * (1.0 - alpha) * 5.0
		draw_circle(center + Vector2(shake, 0), cell_size * 0.4, color)
		draw_circle(center + Vector2(shake, 0), cell_size * 0.4, error_color, false, 2.0, true)

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
			var bg = Color("#EF4444")
			bg.a = alpha
			_draw_pill(Rect2(box_x, box_y, box_w, box_h), bg)
			var tcol = Color("#FFFFFF")
			tcol.a = alpha
			var ty = box_y + pad_y + font.get_ascent(fs)
			draw_string(font, Vector2(box_x + pad_x, ty), error_message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol)

# Progressive hint visuals. All suppressed once the level is won.
func _draw_hint_visuals():
	if main and main.game_state and main.game_state.is_completed:
		return
	var accent: Color = accent_col

	# Hint trail — dashed pulsing ribbon from head to the next un-reached
	# numbered dot. This is the visible hint (paid or free).
	if not hint_trail.is_empty() and hint_trail_t > 0:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var fade: float = clampf(hint_trail_t / 4.0, 0.0, 1.0)
		var a: float = fade * lerpf(0.55, 0.85, pulse)
		var col: Color = accent
		col.a = a
		var w := maxf(2.5, cell_size * 0.09)
		var pts: Array = []
		if main and not main.game_state.player_path.is_empty():
			var h = main.game_state.player_path[-1]
			pts.append(_cell_center(h[0], h[1]))
		for rc in hint_trail:
			pts.append(_cell_center(rc.x, rc.y))
		for i in range(pts.size() - 1):
			_draw_dashed(pts[i], pts[i + 1], w, col, cell_size * 0.14, cell_size * 0.10)
		# Bright stepping-stone marker in the centre of each trail cell.
		for rc in hint_trail:
			var gc: Color = accent
			gc.a = clampf(a + 0.2, 0.0, 1.0)
			draw_circle(_cell_center(int(rc.x), int(rc.y)), cell_size * 0.16, gc)

	# Stage 1: glow on the recommended next cell (1.2s sine pulse).
	if hint_glow_cell.x >= 0 and hint_glow_t > 0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var center := _cell_center(hint_glow_cell.x, hint_glow_cell.y)
		var col := accent
		col.a = lerp(0.30, 0.50, pulse)
		draw_circle(center, cell_size * lerp(0.30, 0.34, pulse), col)

	# Stage 0: directional arrow from head toward the best next cell.
	if hint_arrow_from.x >= 0 and hint_arrow_t > 0:
		var fade := clampf(hint_arrow_t, 0.0, 1.0) * 0.6 + 0.0
		var a := _cell_center(hint_arrow_from.x, hint_arrow_from.y)
		var b := _cell_center(hint_arrow_to.x, hint_arrow_to.y)
		var col := accent
		col.a = clampf(fade, 0.0, 0.6)
		_draw_arrow(a.lerp(b, 0.15), a.lerp(b, 0.85), col, maxf(3.0, cell_size * 0.10))

	# Dead-end: amber pulse on the cell the player should rewind to. We don't
	# draw a line from head to that cell — head and target are arbitrary
	# distances apart, and a long diagonal across the play area reads as a
	# wrong move-direction cue rather than a "go back to" cue.
	if rewind_cell.x >= 0 and rewind_t > 0:
		var center := _cell_center(rewind_cell.x, rewind_cell.y)
		var col: Color = hint_color
		col.a = clampf(rewind_t, 0.0, 1.0) * 0.7
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_circle(center, cell_size * lerpf(0.30, 0.36, pulse), col)
		# A wider faint ring around it helps the eye land on this specific cell.
		var ring_col: Color = hint_color
		ring_col.a = col.a * 0.4
		draw_circle(center, cell_size * 0.45, ring_col, false, maxf(2.0, cell_size * 0.04), true)

func _draw_arrow(a: Vector2, b: Vector2, color: Color, width: float):
	draw_line(a, b, color, width, true)
	var dir := (b - a)
	if dir.length() < 0.5:
		return
	dir = dir.normalized()
	var head := cell_size * 0.20
	var left := b - dir.rotated(0.5) * head
	var right := b - dir.rotated(-0.5) * head
	draw_line(b, left, color, width, true)
	draw_line(b, right, color, width, true)

# Auto-lock snap: scale pop + white flash + expanding lock ring on the final dot.
func _draw_lock():
	if lock_cell.x < 0 or lock_t <= 0:
		return
	var k := 1.0 - (lock_t / LOCK_DUR)   # 0 -> 1 over the animation
	var center := _cell_center(lock_cell.x, lock_cell.y)
	var base := maxf(dot_radius, cell_size * 0.32)

	# Expanding stroked ring, alpha fading out.
	var ring_r := lerpf(base, base + cell_size * 0.55, k)
	var ring := path_end
	ring.a = (1.0 - k) * 0.7
	draw_circle(center, ring_r, ring, false, maxf(2.0, cell_size * 0.05), true)

	# Scale pop 1.0 -> 1.4 -> 1.0 with a brief white flash near the apex.
	var scale_k: float = 1.0 + 0.4 * sin(clampf(k, 0.0, 1.0) * PI)
	var disc := path_end.lerp(Color("#FFFFFF"), clampf(1.0 - k * 1.6, 0.0, 1.0))
	draw_circle(center, base * scale_k, disc)

func _cell_center(row: int, col: int) -> Vector2:
	return Vector2(
		grid_rect.position.x + col * cell_size + cell_size / 2.0,
		grid_rect.position.y + row * cell_size + cell_size / 2.0
	)
