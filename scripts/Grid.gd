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
var bg_color = Color("#0D0D1A")
var grid_bg = Color("#1A1A2E")
var grid_border = Color("#2A2A4E")
var dot_fill = Color("#000000")
var dot_text = Color("#FFFFFF")
var path_start: Color = Color("#4361EE")
var path_end: Color = Color("#7B2D8B")
var hint_color = Color("#FFD166")
var error_color = Color("#EF4444")
var complete_flash = Color("#FFFFFF")

# Touch tracking
var is_dragging: bool = false
var last_touch_cell: Vector2i = Vector2i(-1, -1)

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
	var offset_y = (screen_size.y * 0.25)  # Below top UI area
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
	is_dragging = false
	hint_cell = Vector2i(-1, -1)
	error_cell = Vector2i(-1, -1)
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
	error_timer = 0.8
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
		if hint_timer <= 0:
			hint_cell = Vector2i(-1, -1)
			needs_redraw = true
	
	if error_timer > 0:
		error_timer -= delta
		if error_timer <= 0:
			error_cell = Vector2i(-1, -1)
			needs_redraw = true
	
	if needs_redraw:
		queue_redraw()

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
	_draw_grid_background()
	_draw_path()
	_draw_hint()
	_draw_errors()
	_draw_dots()

func _draw_grid_background():
	# Draw grid background
	draw_rect(grid_rect, grid_bg)
	
	# Draw cell borders
	for r in range(grid_size):
		for c in range(grid_size):
			var x = grid_rect.position.x + c * cell_size
			var y = grid_rect.position.y + r * cell_size
			var cell_rect = Rect2(x, y, cell_size, cell_size)
			draw_rect(cell_rect, grid_border, false, 1.0)
	
	# Draw empty cell backgrounds
	for r in range(grid_size):
		for c in range(grid_size):
			var key = "%d,%d" % [r, c]
			if not cells.has(key):
				var x = grid_rect.position.x + c * cell_size + padding
				var y = grid_rect.position.y + r * cell_size + padding
				var w = cell_size - padding * 2
				var inner_rect = Rect2(x, y, w, w)
				draw_rect(inner_rect, Color("#151530"))

func _draw_path():
	for r in range(grid_size):
		for c in range(grid_size):
			var key = "%d,%d" % [r, c]
			if cells.has(key):
				var x = grid_rect.position.x + c * cell_size + padding
				var y = grid_rect.position.y + r * cell_size + padding
				var w = cell_size - padding * 2
				var color = cells[key]["fill_color"]
				
				if is_completing:
					# Flash effect on completion
					var flash = complete_flash.lerp(color, 1.0 - completion_progress)
					draw_rect(Rect2(x, y, w, w), flash)
				else:
					draw_rect(Rect2(x, y, w, w), color)
	
	# Draw connection lines between path cells
	if path_cells.size() >= 2:
		for i in range(path_cells.size() - 1):
			var c1 = path_cells[i]
			var c2 = path_cells[i + 1]
			var p1 = _cell_center(c1[0], c1[1])
			var p2 = _cell_center(c2[0], c2[1])
			var progress = float(i) / float(maxi(1, path_cells.size()))
			var line_color = path_start.lerp(path_end, progress)
			line_color.a = 0.9
			draw_line(p1, p2, line_color, 3.0, true)

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
				
				# Dot circle - white fill with dark number for visibility
				var radius = dot_radius
				if is_next and not is_reached:
					# Pulsing next dot
					var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.005) * 0.1
					radius *= pulse
				
				# Outer glow
				draw_circle(center, radius + 3, Color("#4361EE").darkened(0.6))
				# White fill
				draw_circle(center, radius, Color("#FFFFFF"))
				# Accent border
				draw_circle(center, radius, Color("#4361EE"), 2.0)
				
				# Dot number in dark for contrast on white
				var font_size = clampi(int(radius * 1.1), 10, 18)
				var font = ThemeDB.fallback_font
				var font_size_dp = font_size
				var text = str(dot_num)
				var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_dp)
				var text_pos = center - text_size / 2.0
				draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_dp, Color("#0D0D1A"))

func _draw_hint():
	if hint_cell.x >= 0:
		var r = hint_cell.x
		var c = hint_cell.y
		var center = _cell_center(r, c)
		var alpha = 0.4 + sin(Time.get_ticks_msec() * 0.008) * 0.3
		var color = hint_color
		color.a = alpha
		draw_circle(center, cell_size * 0.35, color)
		
		# Hint dashed border
		var rect = Rect2(
			grid_rect.position.x + c * cell_size + 2,
			grid_rect.position.y + r * cell_size + 2,
			cell_size - 4,
			cell_size - 4
		)
		draw_rect(rect, hint_color, false, 2.0)

func _draw_errors():
	if error_cell.x >= 0:
		var r = error_cell.x
		var c = error_cell.y
		var center = _cell_center(r, c)
		var alpha = error_timer / 0.8  # Fade out
		var color = error_color
		color.a = alpha * 0.5
		
		var shake = (1.0 - alpha) * 4.0
		draw_circle(center + Vector2(shake, 0), cell_size * 0.4, color)
		draw_circle(center + Vector2(shake, 0), cell_size * 0.4, error_color, false, 2.0)

func _cell_center(row: int, col: int) -> Vector2:
	return Vector2(
		grid_rect.position.x + col * cell_size + cell_size / 2.0,
		grid_rect.position.y + row * cell_size + cell_size / 2.0
	)
