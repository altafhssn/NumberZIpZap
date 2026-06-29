# HintSolver.gd
# Reusable, time-budgeted solver used by the hint system. Finds a completion of
# the player's CURRENT path: a Hamiltonian continuation from the player's head
# that visits every remaining non-block cell exactly once, steps onto the
# remaining numbered dots in strict ascending order, and ends on the highest
# numbered dot.
#
# It mirrors the move rules in GameState and the Warnsdorff heuristic in
# LevelGenerator, but is constrained by the cells the player has already
# visited. Everything is bounded by a wall-clock budget so a hint request can
# never hang the game (same failure mode that froze level 11 generation).
extends RefCounted

const DIRS := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]

# Solver scratch state (reset per solve_from call)
var _deadline_ms: int = 0
var _aborted: bool = false
var _nodes: int = 0
var _grid_size: int = 0
var _blocked: Dictionary = {}
var _dot_num_at: Dictionary = {}   # "r,c" -> dot number
var _dots: Array = []              # ordered dot dicts
var _last_dot: Vector2 = Vector2.ZERO

# Find a continuation from `head`. Returns an Array[Vector2] of the cells AFTER
# head (head excluded), ending on the last dot, or [] if no solution is found
# within the budget.
#   visited_in : "r,c" -> true (cells already on the player's path, incl. head)
#   blocked    : "r,c" -> true
#   dots       : full ordered dot dicts ({ number, row, col, ... })
#   next_dot_index : index into dots of the next dot still to be reached
func solve_from(head: Vector2, visited_in: Dictionary, blocked: Dictionary, grid_size: int, dots: Array, next_dot_index: int, budget_ms: int = 50) -> Array:
	if dots.is_empty():
		return []
	_grid_size = grid_size
	_blocked = blocked
	_dots = dots
	_last_dot = Vector2(dots[-1]["row"], dots[-1]["col"])
	_dot_num_at.clear()
	for d in dots:
		_dot_num_at["%d,%d" % [d["row"], d["col"]]] = d["number"]

	var need_count := grid_size * grid_size - blocked.size() - visited_in.size()
	if need_count <= 0:
		return []

	_deadline_ms = Time.get_ticks_msec() + budget_ms
	_aborted = false
	_nodes = 0
	var visited := visited_in.duplicate()
	var result: Array = []
	if _dfs(head, next_dot_index, need_count, visited, result):
		return result
	return []

func _dfs(pos: Vector2, cur_idx: int, remaining: int, visited: Dictionary, result: Array) -> bool:
	_nodes += 1
	# Check the wall-clock budget periodically (cheap, avoids a syscall per node).
	if (_nodes & 0x3FF) == 0 and Time.get_ticks_msec() > _deadline_ms:
		_aborted = true
		return false

	# Gather legal next cells
	var nexts: Array = []
	for d in DIRS:
		var n: Vector2 = pos + d
		if n.x < 0 or n.x >= _grid_size or n.y < 0 or n.y >= _grid_size:
			continue
		var key := "%d,%d" % [int(n.x), int(n.y)]
		if visited.has(key) or _blocked.has(key):
			continue
		# Dot-ordering: may only step onto a numbered dot if it is the next one.
		if _dot_num_at.has(key):
			var required := -1
			if cur_idx < _dots.size():
				required = _dots[cur_idx]["number"]
			if _dot_num_at[key] != required:
				continue
		nexts.append(n)

	if nexts.is_empty():
		return false

	# Warnsdorff: prefer cells with the fewest onward exits.
	nexts.sort_custom(func(a, b): return _exits(a, visited) < _exits(b, visited))

	for n in nexts:
		var key := "%d,%d" % [int(n.x), int(n.y)]
		var stepped_dot := _dot_num_at.has(key)
		var new_idx := cur_idx + (1 if stepped_dot else 0)

		if remaining == 1:
			# Last cell must be the final dot with all dots consumed.
			if n == _last_dot and new_idx >= _dots.size():
				result.append(n)
				return true
			continue

		visited[key] = true
		result.append(n)
		if _dfs(n, new_idx, remaining - 1, visited, result):
			return true
		result.pop_back()
		visited.erase(key)
		if _aborted:
			return false

	return false

func _exits(pos: Vector2, visited: Dictionary) -> int:
	var c := 0
	for d in DIRS:
		var n: Vector2 = pos + d
		if n.x < 0 or n.x >= _grid_size or n.y < 0 or n.y >= _grid_size:
			continue
		var key := "%d,%d" % [int(n.x), int(n.y)]
		if not visited.has(key) and not _blocked.has(key):
			c += 1
	return c

# When the player's head is a dead-end, find the cell nearest the head along
# their own path that still admits a full solution — the "rewind to here"
# target. Returns Vector2(-1, -1) if none (shouldn't happen on a solvable
# level, since the start is always solvable).
func find_rewind_target(player_path: Array, blocked: Dictionary, grid_size: int, dots: Array, budget_ms: int = 50) -> Vector2:
	var deadline := Time.get_ticks_msec() + budget_ms
	# Walk back from just-before-head toward the start; return the first
	# (deepest) prefix endpoint from which a solution exists.
	for i in range(player_path.size() - 2, 0, -1):
		if Time.get_ticks_msec() > deadline:
			break
		var visited := {}
		var nd := 0
		for j in range(i + 1):
			var cell = player_path[j]
			visited["%d,%d" % [cell[0], cell[1]]] = true
			if nd < dots.size() and dots[nd]["row"] == cell[0] and dots[nd]["col"] == cell[1]:
				nd += 1
		var head := Vector2(player_path[i][0], player_path[i][1])
		var remaining_budget: int = maxi(5, deadline - Time.get_ticks_msec())
		if not solve_from(head, visited, blocked, grid_size, dots, nd, remaining_budget).is_empty():
			return head
	return Vector2(-1, -1)
