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
var solution_dots: Array = []   # Full dot data from level

# Hint
var hint_cell: Vector2i = Vector2i(-1, -1)
var hint_timer: float = 0.0

# Error feedback
var error_cell: Vector2i = Vector2i(-1, -1)
var error_timer: float = 0.0
var error_message: String = ""

# Colors
var bg_color = Color("#0B0B16")
var bg_color_bottom = Color("#13132A")
var grid_bg = Color("#16162C")
var grid_border = Color("#2A2A4E")
var cell_empty = Color("#1C1C38")
var dot_fill = Color("#000000")
var dot_text = Color("#FFFFFF")
var path_start: Color = Color("#4361EE")
var path_end: Color = Color("#7B2D8B")
var hint_color = Color("#FFD166")
var error_color = Color("#EF4444")
var complete_flash = Color("#FFFFFF")

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

func _ready():
	pass

func setup(level_data: Dictionary):
	grid_size = level_data.get("grid_size", 5)
	solution_dots = level_data.get("dots", [])
	
	# Build dot lookup
	dot_positions.clear()
	for d in solution_dots:
		dot_positions["%d,%d" % [d["row"], d["col"]]] = d["number"]
	
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
	hint_timer = 2.0
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
	
	if (event is InputEventScreenDrag or (event is InputEventMouseMotion and is_dragging)):
		if is_dragging:
			var cell = get_cell_at(event.position)
			if cell.x >= 0 and cell != last_touch_cell:
				last_touch_cell = cell
				main.on_cell_drag(cell.x, cell.y)

func _process(delta):
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
		var alive: Array = []
		for rp in ripples:
			rp["t"] += delta
			if rp["t"] < RIPPLE_DUR:
				alive.append(rp)
		ripples = alive

	# Continuous redraw keeps the glow pulse, dot pulse, ripples and
	# completion shimmer animating smoothly.
	queue_redraw()

func spawn_ripple(row: int, col: int):
	ripples.append({ "pos": _cell_center(row, col), "t": 0.0 })
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
	_draw_background()
	_draw_grid_background()
	_draw_path()
	_draw_ripples()
	_draw_hint()
	_draw_errors()
	_draw_dots()

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
			var tile_col = cell_empty
			if cells.has(key):
				tile_col = (cells[key]["fill_color"] as Color).darkened(0.5)
			_draw_round_rect(Rect2(x, y, w, w), cr, tile_col)

func _draw_path():
	if path_cells.size() == 0:
		return

	var w := maxf(6.0, cell_size * 0.34)

	# Animated glowing line — two soft passes whose alpha breathes over time
	if path_cells.size() >= 2:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		var passes = [
			{ "mult": 2.6, "a": lerp(0.06, 0.14, pulse) },
			{ "mult": 1.7, "a": lerp(0.18, 0.30, pulse) },
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

	# Bright pulsing head marker
	if not is_completing:
		var head = _cell_center(path_cells[-1][0], path_cells[-1][1])
		var hp: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		var halo = path_end
		halo.a = lerp(0.20, 0.45, hp)
		draw_circle(head, w * lerp(0.7, 0.95, hp), halo)
		var hc = path_end
		hc.a = 0.55
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
				if is_next and not is_reached:
					# Pulsing next dot
					var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.005) * 0.10
					radius *= pulse

				var accent = path_start

				# Pulsing attention ring for the next target dot
				if is_next and not is_reached:
					var ring = 0.30 + sin(Time.get_ticks_msec() * 0.006) * 0.22
					var ring_col = accent
					ring_col.a = ring
					draw_circle(center, radius + 8, ring_col)

				# Soft glow
				var glow = accent
				glow.a = 0.40
				draw_circle(center, radius + 5, glow)
				# Filled accent disc (reached dots get a brighter core)
				var disc = accent if not is_reached else accent.lightened(0.15)
				draw_circle(center, radius, disc)
				# Crisp white ring
				draw_circle(center, radius, Color("#FFFFFF"), false, maxf(2.0, radius * 0.12), true)

				# Dot number — white, properly centered, faux-bold
				var font = ThemeDB.fallback_font
				var fs = clampi(int(radius * 1.15), 14, 30)
				var text = str(dot_num)
				var tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var ascent = font.get_ascent(fs)
				var descent = font.get_descent(fs)
				var baseline_y = center.y + (ascent - descent) / 2.0
				var tx = center.x - tw / 2.0
				var num_col = Color("#FFFFFF")
				for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					draw_string(font, Vector2(tx, baseline_y) + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_col)
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
