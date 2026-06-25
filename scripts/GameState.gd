# GameState.gd
# Manages the current level state: path drawn, dots reached, hints
extends RefCounted

# Fired the instant the path becomes a complete, valid Hamiltonian solution on
# appending the final dot (auto-lock). Main runs the win sequence in response.
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

# Auto-lock (Feature 1)
var auto_lock_enabled: bool = true    # Main disables this in Tutorial (level 1)
var level_solved: bool = false        # one-shot guard so auto_locked fires once
var win_ready: bool = false           # grid full + valid, awaiting finger-lift
                                      # (only used when auto_lock_enabled == false)

# Hint system (Feature 2)
var hint_stage: int = 0               # 0 = arrow, 1 = glow, 2 = ghost trail
var free_hints_used: int = 0          # how many free hints used this level
var last_hint_time: float = -100.0    # seconds, for the 5s escalation window
var _hint_solver = preload("res://scripts/HintSolver.gd").new()
var _hint_cache: Array = []           # cached continuation from current head
var _hint_cache_valid: bool = false

# Grid of visited cells
var visited_cells: Dictionary = {}    # "r,c" -> true
var blocked: Dictionary = {}          # "r,c" -> true (impassable cells)

# Path colors are now driven by the active SectorThemes palette and set on
# Grid directly. Kept here for any callers that still reference them, but no
# longer chosen from a difficulty-bucketed list.
var path_color_start: Color = Color("#4361EE")
var path_color_end: Color = Color("#7B2D8B")

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
	level_solved = false
	win_ready = false
	reset_hint_state()
	_invalidate_hint_cache()

# Clear per-attempt hint progression (stage / free quota / escalation timer).
func reset_hint_state():
	hint_stage = 0
	free_hints_used = 0
	last_hint_time = -100.0

func _invalidate_hint_cache():
	_hint_cache_valid = false
	_hint_cache = []

# Try to place a cell in the player path
# Returns: Dictionary with { "success": bool, "message": String, "dot_reached": bool }
func try_place_cell(row: int, col: int) -> Dictionary:
	if is_completed:
		return { "success": false, "message": "Level complete!", "dot_reached": false }
	
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
			return { "success": true, "message": "Started!", "dot_reached": true }
		else:
			return { "success": false, "message": "Start at dot 1", "dot_reached": false }
	
	# Stable-line rule: the only way to shorten the path is to drag back onto
	# the cell IMMEDIATELY before the head (step-by-step backward tracing).
	# Any other visited cell — the head itself, the start dot, or any cell
	# deeper in the path — is a silent no-op. This stops a sloppy finger or a
	# tap on the middle of the line from collapsing the drawn path.
	if visited_cells.has(cell_key):
		if player_path.size() >= 2 and player_path[-2][0] == row and player_path[-2][1] == col:
			var old_head = player_path[-1]
			var old_head_key := "%d,%d" % [old_head[0], old_head[1]]
			# If the popped head was the most recently reached dot, uncount it.
			for i in range(dots.size()):
				var d = dots[i]
				if old_head[0] == d["row"] and old_head[1] == d["col"]:
					if i == next_dot_index - 1:
						next_dot_index -= 1
					break
			player_path.pop_back()
			visited_cells.erase(old_head_key)
			# Rewinding breaks any pending win and stales the cached hint.
			win_ready = false
			_invalidate_hint_cache()
			return { "success": true, "message": "", "dot_reached": false, "rewound": true }
		# Visited but not the step-back cell — keep the line, no feedback.
		return { "success": false, "silent": true, "message": "", "dot_reached": false }
	
	# Check if it's adjacent to the last placed cell
	var last = player_path[-1]
	if abs(last[0] - row) + abs(last[1] - col) != 1:
		return { "success": false, "message": "Must be adjacent", "dot_reached": false }
	
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
			return { "success": false, "message": "Reach dot %d first" % expected_num, "dot_reached": false }
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
			if auto_lock_enabled:
				# Feature 1: lock in instantly, no finger-lift required.
				_mark_solved()
				emit_signal("auto_locked", row, col)
				return { "success": true, "message": "Level complete!", "dot_reached": reached_dot, "completed": true }
			else:
				# Tutorial: hold the win until the player lifts their finger so
				# the manual release flow is taught. on_touch_released finishes it.
				win_ready = true
				return { "success": true, "message": "", "dot_reached": reached_dot, "win_ready": true }
		return {
			"success": true,
			"failed": true,
			"dot_reached": reached_dot,
			"message": "Path must end on dot %d" % dots.size()
		}

	return { "success": true, "message": "", "dot_reached": reached_dot }

# Single source of truth for "the cell just appended completes the level":
# the grid is full (all non-block cells visited), every numbered dot was hit in
# order, and this cell is the highest-numbered dot.
func _check_win_on_append(row: int, col: int) -> bool:
	if dots.is_empty():
		return false
	var total_cells = grid_size * grid_size - blocked.size()
	if visited_cells.size() < total_cells:
		return false
	if next_dot_index < dots.size():
		return false  # not all dots reached in order
	var last_dot = dots[-1]
	return row == last_dot["row"] and col == last_dot["col"]

func _mark_solved():
	if level_solved:
		return
	level_solved = true
	is_completed = true
	win_ready = false
	elapsed_time = (Time.get_ticks_msec() - start_time) / 1000.0

# Tutorial path: complete the level on finger-lift when a valid full path is
# already drawn. Returns true if this lift actually finished the level.
func finish_on_release() -> bool:
	if is_completed or not win_ready:
		return false
	_mark_solved()
	return true


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
	win_ready = false
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

# --- Hint system (Feature 2) ---------------------------------------------

# True if the player's head has at least one legal unvisited, non-block
# neighbour (i.e. a move is physically possible). Used for stuck detection.
func has_legal_move() -> bool:
	if player_path.is_empty():
		return true
	var head = player_path[-1]
	for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
		var r = head[0] + d[0]
		var c = head[1] + d[1]
		if r < 0 or r >= grid_size or c < 0 or c >= grid_size:
			continue
		var key = "%d,%d" % [r, c]
		if visited_cells.has(key) or blocked.has(key):
			continue
		return true
	return false

# Escalate the progressive hint stage. A press within 5s of the previous one
# bumps the stage (arrow -> glow -> ghost trail); otherwise it resets to stage 0.
func advance_hint_stage():
	var now := Time.get_ticks_msec() / 1000.0
	if hints_used > 0 and (now - last_hint_time) <= 5.0:
		hint_stage = mini(hint_stage + 1, 2)
	else:
		hint_stage = 0
	last_hint_time = now

# Count a granted hint toward the star penalty.
func register_hint():
	hints_used += 1

# Compute a hint from the player's ACTUAL current head (recomputed every call,
# cached until the path changes). Returns a Dictionary:
#   { "type": "next",   "next": Vector2i, "trail": Array[Vector2i] }  normal
#   { "type": "rewind", "cell": Vector2i }                            dead-end
#   { "type": "none" }                                                no help
func get_smart_hint() -> Dictionary:
	if is_completed or player_path.is_empty():
		return { "type": "none" }

	var head := Vector2(player_path[-1][0], player_path[-1][1])
	var cont := _cached_continuation(head)
	if not cont.is_empty():
		var trail: Array = []
		for i in range(mini(3, cont.size())):
			trail.append(Vector2i(int(cont[i].x), int(cont[i].y)))
		return { "type": "next", "next": trail[0], "trail": trail }

	# Dead-end from the current head: point at the rewind target instead.
	var rt: Vector2 = _hint_solver.find_rewind_target(player_path, blocked, grid_size, dots, 50)
	if rt.x >= 0:
		return { "type": "rewind", "cell": Vector2i(int(rt.x), int(rt.y)) }
	return { "type": "none" }

# Solver result cache, invalidated on any path change.
func _cached_continuation(head: Vector2) -> Array:
	if _hint_cache_valid:
		return _hint_cache
	_hint_cache = _hint_solver.solve_from(head, visited_cells, blocked, grid_size, dots, next_dot_index, 50)
	_hint_cache_valid = true
	return _hint_cache

# Tutorial trail: returns the cells from JUST AFTER the head up to and
# including the next un-reached numbered dot, computed from a real solution.
# This is what the dashed tutorial trail visualises. Returns [] if no
# solution exists within the solver budget, in which case the trail just
# isn't drawn (caller falls back to its default).
func get_continuation_to_next_dot() -> Array:
	if player_path.is_empty() or next_dot_index >= dots.size():
		return []
	var head := Vector2(player_path[-1][0], player_path[-1][1])
	var full := _cached_continuation(head)
	if full.is_empty():
		return []
	var nd = dots[next_dot_index]
	var trail: Array = []
	for c in full:
		trail.append(c)
		if int(c.x) == nd["row"] and int(c.y) == nd["col"]:
			break
	return trail
