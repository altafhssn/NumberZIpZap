# GameState.gd
# Manages the current level state: path drawn, dots reached, hints
extends RefCounted

# Core data
var grid_size: int = 5
var level_data: Dictionary = {}       # Full level from generator
var dots: Array = []                  # Dot placements from level data
var solution: Array = []              # Full solution path [[r,c], ...]

# Player state
var player_path: Array = []           # Cells the player has drawn [[r,c], ...]
var next_dot_index: int = 0           # Index into dots array (0 = looking for dot 1)
var hints_used: int = 0
var is_completed: bool = false
var moves: int = 0
var start_time: float = 0.0
var elapsed_time: float = 0.0

# Grid of visited cells
var visited_cells: Dictionary = {}    # "r,c" -> true

# Colors for this level
var path_color_start: Color = Color("#4361EE")
var path_color_end: Color = Color("#7B2D8B")

# Theme palettes
const THEMES = [
	{ "name": "Sky", "start": Color("#4361EE"), "end": Color("#7B2D8B") },
	{ "name": "Sunrise", "start": Color("#C73E9A"), "end": Color("#FF6B6B") },
	{ "name": "Ocean", "start": Color("#00B4D8"), "end": Color("#0077B6") },
	{ "name": "Forest", "start": Color("#06D6A0"), "end": Color("#1B998B") },
	{ "name": "Nebula", "start": Color("#8B5CF6"), "end": Color("#EC4899") },
	{ "name": "Ember", "start": Color("#F59E0B"), "end": Color("#EF4444") }
]

const CELL_EMPTY = 0
const CELL_FILLED = 1
const CELL_DOT = 2
const CELL_CURSOR = 3

func _init():
	start_time = Time.get_ticks_msec()

# Load a level from generated data
func load_level(data: Dictionary):
	level_data = data
	grid_size = data.get("grid_size", 5)
	dots = data.get("dots", [])
	solution = data.get("solution", [])
	
	# Pick a theme based on difficulty
	var diff = data.get("difficulty", 50)
	var theme_idx = mini(int(diff / 17.0), THEMES.size() - 1)
	var theme = THEMES[theme_idx]
	path_color_start = theme["start"]
	path_color_end = theme["end"]
	
	reset()

# Reset player state (keep level data)
func reset():
	player_path.clear()
	visited_cells.clear()
	next_dot_index = 0
	hints_used = 0
	is_completed = false
	moves = 0
	start_time = Time.get_ticks_msec()

# Try to place a cell in the player path
# Returns: Dictionary with { "success": bool, "message": String, "dot_reached": bool }
func try_place_cell(row: int, col: int) -> Dictionary:
	if is_completed:
		return { "success": false, "message": "Level complete!", "dot_reached": false }
	
	var cell_key = "%d,%d" % [row, col]
	
	# If player_path is empty, must start at dot 1
	if player_path.is_empty():
		if _is_dot_at(1, row, col):
			player_path.append([row, col])
			visited_cells[cell_key] = true
			next_dot_index = 1
			moves += 1
			return { "success": true, "message": "Started!", "dot_reached": true }
		else:
			return { "success": false, "message": "Start at dot 1", "dot_reached": false }
	
	# Check if cell was already visited
	if visited_cells.has(cell_key):
		return { "success": false, "message": "Already visited", "dot_reached": false }
	
	# Check if it's adjacent to the last placed cell
	var last = player_path[-1]
	if abs(last[0] - row) + abs(last[1] - col) != 1:
		return { "success": false, "message": "Must be adjacent", "dot_reached": false }
	
	# Check if this is a dot we should be going to next
	var reached_dot = false
	if next_dot_index < dots.size():
		var next_dot = dots[next_dot_index]
		if row == next_dot["row"] and col == next_dot["col"]:
			reached_dot = true
			next_dot_index += 1
	
	# Place the cell
	player_path.append([row, col])
	visited_cells[cell_key] = true
	moves += 1
	
	# Check for win: all cells visited AND all dots reached
	var total_cells = grid_size * grid_size
	if visited_cells.size() >= total_cells and next_dot_index >= dots.size():
		is_completed = true
		elapsed_time = (Time.get_ticks_msec() - start_time) / 1000.0
		return { "success": true, "message": "Level complete!", "dot_reached": reached_dot, "completed": true }
	
	return { "success": true, "message": "", "dot_reached": reached_dot }


# Undo last placed cell (but not past a dot)
func undo():
	if player_path.is_empty():
		return false
	
	# Can't undo past the starting dot
	if player_path.size() <= 1:
		return false
	
	var last = player_path[-1]
	var cell_key = "%d,%d" % [last[0], last[1]]
	
	# If last cell is a dot, don't undo past it unless we also decrement dot index
	var was_dot = false
	for i in range(dots.size()):
		var d = dots[i]
		if last[0] == d["row"] and last[1] == d["col"]:
			was_dot = true
			# Only allow undo of dot if it's the last placed dot
			if i == next_dot_index - 1:
				next_dot_index -= 1
			break
	
	visited_cells.erase(cell_key)
	player_path.pop_back()
	return true


# Fully reset to start
func full_reset():
	reset()

# Get fill percentage
func get_fill_pct() -> float:
	var total = grid_size * grid_size
	if total <= 0:
		return 0.0
	return (float(visited_cells.size()) / float(total)) * 100.0

# Check if a cell has a dot
func get_dot_at(row: int, col: int) -> int:
	for d in dots:
		if d["row"] == row and d["col"] == col:
			return d["number"]
	return -1

func _is_dot_at(number: int, row: int, col: int) -> bool:
	for d in dots:
		if d["row"] == row and d["col"] == col and d["number"] == number:
			return true
	return false

# Get the next dot number to reach
func get_next_dot_number() -> int:
	if next_dot_index < dots.size():
		return dots[next_dot_index]["number"]
	return -1

# Calculate stars: 3 = no hints and efficient path, 2 = no hints or 1 hint, 1 = 2+
func get_stars() -> int:
	if not is_completed:
		return 0
	var optimal_len = solution.size()
	var par_moves = int(float(optimal_len) * 1.1)
	
	if hints_used == 0 and moves <= par_moves:
		return 3
	elif hints_used <= 1:
		return 2
	else:
		return 1

# Reveal next segment hint
func get_hint() -> Array:
	if is_completed or player_path.is_empty():
		return []
	
	hints_used += 1
	
	# Find next unfilled cell along the solution path
	var last_player = player_path[-1]
	var last_solution_idx = -1
	
	for i in range(solution.size()):
		var sol_cell = solution[i]
		if sol_cell[0] == last_player[0] and sol_cell[1] == last_player[1]:
			last_solution_idx = i
			break
	
	if last_solution_idx < 0 or last_solution_idx + 1 >= solution.size():
		return []
	
	# Return the next correct cell
	var next = solution[last_solution_idx + 1]
	return [next[0], next[1]]  # [row, col]
