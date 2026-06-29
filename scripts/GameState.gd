# GameState.gd
# Manages the current level state: path drawn, dots reached, hints
extends RefCounted

# Fired the instant the player's last appended cell completes the level
# (auto-lock — no finger-lift required). Main wires this to the lock-snap
# feedback so the satisfying "click" plays the moment the puzzle resolves.
signal auto_locked(row, col)

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
# One-shot guard so auto_locked fires exactly once per attempt even if a
# caller pokes try_place_cell again before reset.
var level_solved: bool = false

# Grid of visited cells
var visited_cells: Dictionary = {}    # "r,c" -> true
var blocked: Dictionary = {}          # "r,c" -> true (impassable cells)

# Hint solver — recomputes a continuation from the player's actual head every
# time it's asked, with a 50ms wall-clock budget so it can never hang. The
# cache stays valid until the player's path changes (append / undo / reset /
# rewind). See HintSolver.gd.
var _hint_solver = preload("res://scripts/HintSolver.gd").new()
var _hint_cache: Array = []
var _hint_cache_valid: bool = false

# Colors for this level
var path_color_start: Color = Color("#4361EE")
var path_color_end: Color = Color("#7B2D8B")

# Theme palettes
const THEMES = [
	{ "name": "Dawn",  "start": Color("#C73E9A"), "end": Color("#FF6B6B") },  # Sunrise
	{ "name": "Day",   "start": Color("#00B4D8"), "end": Color("#0077B6") },  # Ocean
	{ "name": "Dusk",  "start": Color("#F59E0B"), "end": Color("#EF4444") },  # Ember
	{ "name": "Night", "start": Color("#8B5CF6"), "end": Color("#EC4899") }   # Nebula
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

	blocked.clear()
	for b in data.get("blocked", []):
		blocked["%d,%d" % [b[0], b[1]]] = true
	
	# Pick a theme based on difficulty
	var diff = data.get("difficulty", 50)
	var theme_idx = mini(int(diff / 25.0), THEMES.size() - 1)
	var theme = THEMES[theme_idx]
	path_color_start = theme["start"]
	path_color_end = theme["end"]
	
	reset()

func _invalidate_hint_cache() -> void:
	_hint_cache_valid = false
	_hint_cache = []

# Reset player state (keep level data)
func reset():
	player_path.clear()
	visited_cells.clear()
	next_dot_index = 0
	hints_used = 0
	is_completed = false
	moves = 0
	start_time = Time.get_ticks_msec()
	level_solved = false
	_invalidate_hint_cache()

# Try to place a cell in the player path
# Returns: Dictionary with { "success": bool, "message": String, "dot_reached": bool }
func try_place_cell(row: int, col: int) -> Dictionary:
	if is_completed:
		return { "success": false, "message": "The pool is already still.", "dot_reached": false }
	
	var cell_key = "%d,%d" % [row, col]

	# Impassable block
	if blocked.has(cell_key):
		return { "success": false, "message": "Blocked", "dot_reached": false }

	# If player_path is empty, must start at dot 1
	if player_path.is_empty():
		if _is_dot_at(1, row, col):
			player_path.append([row, col])
			visited_cells[cell_key] = true
			next_dot_index = 1
			moves += 1
			_invalidate_hint_cache()
			return { "success": true, "message": "The tide begins.", "dot_reached": true }
		else:
			return { "success": false, "message": "Begin at the first stone.", "dot_reached": false }

	# Stable-line rule: the ONLY way to shorten the path is to drag back onto
	# the cell IMMEDIATELY before the head (step-by-step retrace). Every other
	# tap/drag onto a visited cell — the head itself, an earlier cell, a
	# numbered stone you already passed — is a silent no-op. Stops a sloppy
	# finger from collapsing a long correct path, while still letting the
	# player retrace freely by dragging the head back one cell at a time
	# (including past numbered stones, which get uncounted).
	if visited_cells.has(cell_key):
		if player_path.size() >= 2 and player_path[-2][0] == row and player_path[-2][1] == col:
			# Step-back retrace: pop the head off the path.
			var old_head = player_path[-1]
			var old_head_key := "%d,%d" % [old_head[0], old_head[1]]
			# If the popped head was the most recently reached numbered stone,
			# uncount it so the player's next target is that same number again.
			for i in range(dots.size()):
				var d = dots[i]
				if old_head[0] == d["row"] and old_head[1] == d["col"]:
					if i == next_dot_index - 1:
						next_dot_index -= 1
					break
			player_path.pop_back()
			visited_cells.erase(old_head_key)
			_invalidate_hint_cache()
			return { "success": true, "message": "", "dot_reached": false, "rewound": true }
		# Visited but not the step-back cell — silent no-op.
		return { "success": false, "silent": true, "message": "", "dot_reached": false }
	
	# Check if it's adjacent to the last placed cell
	var last = player_path[-1]
	if abs(last[0] - row) + abs(last[1] - col) != 1:
		return { "success": false, "message": "The water moves one tile at a time.", "dot_reached": false }
	
	# Enforce dot ordering: you may only step onto a numbered dot if it is
	# the next one in sequence. Stepping onto a later number first is illegal
	# (otherwise the grid can be filled into an unsolvable 100% dead state).
	var this_dot = get_dot_at(row, col)
	var expected_num = -1
	if next_dot_index < dots.size():
		expected_num = dots[next_dot_index]["number"]

	var reached_dot = false
	if this_dot != -1:
		if this_dot != expected_num:
			return { "success": false, "message": "Visit stone %d first" % expected_num, "dot_reached": false }
		reached_dot = true
		next_dot_index += 1
	
	# Place the cell
	player_path.append([row, col])
	visited_cells[cell_key] = true
	moves += 1
	_invalidate_hint_cache()

	# Grid full: the path must END exactly on the highest-numbered dot,
	# with every dot linked in order — otherwise the attempt fails.
	var total_cells = grid_size * grid_size - blocked.size()
	if visited_cells.size() >= total_cells:
		if _check_win_on_append(row, col):
			_mark_solved()
			emit_signal("auto_locked", row, col)
			return { "success": true, "message": "Level complete!", "dot_reached": reached_dot, "completed": true }
		return {
			"success": true,
			"failed": true,
			"dot_reached": reached_dot,
			"message": "The tide should rest on stone %d" % dots.size()
		}

	return { "success": true, "message": "", "dot_reached": reached_dot }

# Single source of truth for "the cell just appended completes the level":
# grid is full (all non-block cells visited), every numbered dot was hit in
# order, and this cell is the highest-numbered dot.
func _check_win_on_append(row: int, col: int) -> bool:
	if dots.is_empty():
		return false
	var total_cells = grid_size * grid_size - blocked.size()
	if visited_cells.size() < total_cells:
		return false
	if next_dot_index < dots.size():
		return false
	var last_dot = dots[-1]
	return row == last_dot["row"] and col == last_dot["col"]

func _mark_solved() -> void:
	if level_solved:
		return
	level_solved = true
	is_completed = true
	elapsed_time = (Time.get_ticks_msec() - start_time) / 1000.0


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
	_invalidate_hint_cache()
	return true


# Fully reset to start
func full_reset():
	reset()

# Get fill percentage
func get_fill_pct() -> float:
	var total = grid_size * grid_size - blocked.size()
	if total <= 0:
		return 0.0
	return (float(visited_cells.size()) / float(total)) * 100.0

# Check if a cell has a dot
func get_dot_at(row: int, col: int) -> int:
	for d in dots:
		if d["row"] == row and d["col"] == col:
			return d["number"]
	return -1

# Rewinds the path back to the position right after the previous numbered
# dot. Used when the player closes the puzzle on the last dot but leaves
# cells empty — we auto-revert their last segment so they can retry from
# the most recent stone instead of having to manually undo many times.
# Returns the number of cells removed.
func rewind_to_previous_dot() -> int:
	if player_path.size() <= 1:
		return 0
	# Find every index in the path that sits on a numbered dot.
	var dot_positions: Array = []
	for i in range(player_path.size()):
		var cell = player_path[i]
		if _is_any_dot_at(cell[0], cell[1]):
			dot_positions.append(i)
	# Trim length:
	#   2+ dots in path → trim back to right after the second-to-last dot
	#   1 dot in path   → keep only the first dot
	#   0 dots in path  → clear entirely
	var target_len: int
	if dot_positions.size() >= 2:
		target_len = dot_positions[-2] + 1
	elif dot_positions.size() == 1:
		target_len = dot_positions[0] + 1
	else:
		target_len = 0
	var removed := 0
	while player_path.size() > target_len:
		var last = player_path[-1]
		visited_cells.erase("%d,%d" % [last[0], last[1]])
		player_path.pop_back()
		removed += 1
	# Recompute next_dot_index from the trimmed path.
	next_dot_index = 0
	for cell in player_path:
		if next_dot_index < dots.size():
			var d = dots[next_dot_index]
			if d["row"] == cell[0] and d["col"] == cell[1]:
				next_dot_index += 1
	_invalidate_hint_cache()
	return removed

func _is_any_dot_at(row: int, col: int) -> bool:
	for d in dots:
		if d["row"] == row and d["col"] == col:
			return true
	return false

# Double-tap shortcut — trims the path so it ends exactly at the numbered
# stone at (row, col). Only valid if (row, col) IS a numbered dot, is already
# in player_path, and isn't the current head. Returns true on success so the
# caller (Main) can fire the rewind feedback. The strict-line drag rule still
# applies to all other input — this is the ONE exception that lets the
# player jump back to a checkpoint without dragging through every cell.
func try_rewind_to_dot(row: int, col: int) -> bool:
	if get_dot_at(row, col) == -1:
		return false
	if is_completed:
		return false
	var target_idx := -1
	for i in range(player_path.size()):
		if player_path[i][0] == row and player_path[i][1] == col:
			target_idx = i
			break
	if target_idx < 0:
		return false
	if target_idx == player_path.size() - 1:
		return false  # already at this stone — no-op
	player_path = player_path.slice(0, target_idx + 1)
	visited_cells.clear()
	for cell in player_path:
		visited_cells["%d,%d" % [cell[0], cell[1]]] = true
	next_dot_index = 0
	for cell in player_path:
		if next_dot_index < dots.size():
			var d = dots[next_dot_index]
			if d["row"] == cell[0] and d["col"] == cell[1]:
				next_dot_index += 1
	_invalidate_hint_cache()
	return true

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

# Smart hint computed from the player's ACTUAL current head — works even when
# the player has wandered off the canonical solution but is still in a solvable
# state. Returns up to 3 cells ahead as a dashed trail. Falls back to "none"
# if the head is a dead-end (caller can keep its old behaviour).
#   { "type": "next", "trail": [Vector2i, ...] }   normal — show dashed trail
#   { "type": "none" }                              dead-end or completed
func get_smart_hint() -> Dictionary:
	if is_completed or player_path.is_empty():
		return { "type": "none" }
	var head := Vector2(player_path[-1][0], player_path[-1][1])
	var cont := _cached_continuation(head)
	if cont.is_empty():
		return { "type": "none" }
	var trail: Array = []
	for i in range(mini(3, cont.size())):
		trail.append(Vector2i(int(cont[i].x), int(cont[i].y)))
	return { "type": "next", "trail": trail }

# Solver result cache — invalidated on every path change so a stale hint can't
# point the player at a cell that's no longer reachable.
func _cached_continuation(head: Vector2) -> Array:
	if _hint_cache_valid:
		return _hint_cache
	_hint_cache = _hint_solver.solve_from(head, visited_cells, blocked, grid_size, dots, next_dot_index, 50)
	_hint_cache_valid = true
	return _hint_cache

# Trim the cached continuation at the next un-reached numbered dot. Used by
# both the tutorial breadcrumb trail and the smart hint visual so they read
# the same thing — "here is what's between you and the next number, computed
# from where you actually are." Returns [] if no continuation exists yet.
func get_continuation_to_next_dot() -> Array:
	if player_path.is_empty() or next_dot_index >= dots.size():
		return []
	var head := Vector2(player_path[-1][0], player_path[-1][1])
	var full := _cached_continuation(head)
	if full.is_empty():
		return []
	var nd: Dictionary = dots[next_dot_index]
	var trail: Array = []
	for c in full:
		trail.append(c)
		if int(c.x) == nd["row"] and int(c.y) == nd["col"]:
			break
	return trail
