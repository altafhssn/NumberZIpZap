# LevelGenerator.gd
# Generates ZipPath levels using Hamiltonian path + Warnsdorff heuristic
# Each level: N×N grid, K numbered dots, path visits every cell exactly once
extends RefCounted

# Generation budget — scoped to a single _find_hamiltonian_with_blocks call.
# _dfs decrements _gen_steps against _gen_budget on every recursive entry, and
# trips _gen_aborted when blown so the backtracking unwinds the whole stack
# instead of grinding away on a pathological seed. Without this, a bad seed
# on level 11+ (first blocked level) could hang the game.
var _gen_budget: int = 0
var _gen_steps: int = 0
var _gen_aborted: bool = false

# Generate a complete level
# Returns Dictionary with: grid_size, dots, solution, difficulty
#
# scatter_blocks: when true, block placement is constrained so no two blocked
# cells are 4-adjacent (Manhattan distance >= 2). Diagonals are still allowed.
# Used by higher-level packs where the carved-cluster style stops feeling
# fair. Falls back to the carved layout if scattered placement can't find a
# Hamiltonian path in a reasonable number of attempts.
func generate(grid_size: int, dot_count: int, seed_val: int = -1, block_count: int = 0, scatter_blocks: bool = false) -> Dictionary:
	if seed_val >= 0:
		seed(seed_val)
	else:
		randomize()

	# Step 1: Choose blocks and find a Hamiltonian path over the remaining
	# cells. Prefer scattered blocks, but keep a tight time budget so mobile
	# never freezes while building the next level.
	var blocked: Array = []
	var path: Array = []
	var b: int = block_count
	if b > 0:
		var max_b := grid_size * grid_size - maxi(dot_count, 2) - 1
		b = clampi(b, 0, max_b)
		if scatter_blocks:
			# Try the scattered-placement strategy first (no two adjacent blocks).
			# Capped at 3 attempts — each Hamiltonian solve is expensive, so we
			# fail fast and fall back to the cluster layout if scattering won't
			# fit a solvable path. Prevents the editor from hanging on hard
			# seeds at higher level numbers.
			for _attempt in range(3):
				var candidate_blocks := _pick_scattered_blocks(grid_size, b)
				if candidate_blocks.size() < b:
					continue
				var candidate_path := _find_hamiltonian_with_blocks(grid_size, candidate_blocks)
				if not candidate_path.is_empty():
					blocked = candidate_blocks
					path = candidate_path
					break
		if path.is_empty():
			# Scattered failed (or wasn't requested) — fall back to the carved
			# block layout. Levels remain solvable but blocks may cluster.
			var carved := _find_carved_block_layout(grid_size, b)
			blocked = carved["blocked"]
			path = carved["path"]
	else:
		path = _find_hamiltonian_path(grid_size)
	if path.is_empty():
		push_error("LevelGenerator: Failed to generate path for grid ", grid_size)
		return {}

	# Step 3: Place dots along the (non-blocked) solution path
	var dots = _place_dots(path, dot_count, grid_size)
	if dots.is_empty():
		push_error("LevelGenerator: Failed to place dots")
		return {}

	# Step 4: Difficulty + level data
	var difficulty = _calculate_difficulty(grid_size, dots, path)
	var level_data = {
		"id": "lvl_gen_%d" % randi(),
		"grid_size": grid_size,
		"dots": dots,
		"solution": _path_to_cell_list(path),
		"blocked": _path_to_cell_list(blocked),
		"difficulty": difficulty,
		"seed": seed_val if seed_val >= 0 else randi()
	}

	return level_data


# Find a Hamiltonian path covering every cell.
# Start from a guaranteed-valid boustrophedon (snake) path, then randomise it
# with "backbite" moves. This is O(cells) per move, never backtracks and
# always succeeds in milliseconds — the old randomized-DFS could take
# several seconds on some seeds and ANR/crash on mobile.
func _find_hamiltonian_path(grid_size: int) -> Array:
	var path: Array = []
	for r in range(grid_size):
		if r % 2 == 0:
			for c in range(grid_size):
				path.append(Vector2(r, c))
		else:
			for c in range(grid_size - 1, -1, -1):
				path.append(Vector2(r, c))

	# Index lookup: "x,y" -> position in path
	var idx := {}
	for i in range(path.size()):
		idx["%d,%d" % [path[i].x, path[i].y]] = i

	var moves = path.size() * 12
	for _m in range(moves):
		# Pick an endpoint (0 = head, 1 = tail)
		var at_tail = randi() % 2 == 1
		var end_pos: Vector2 = path[-1] if at_tail else path[0]
		var nbrs = _get_neighbors(end_pos, grid_size)
		var nb = nbrs[randi() % nbrs.size()]
		var j: int = idx["%d,%d" % [nb.x, nb.y]]

		if at_tail:
			# Neighbour already adjacent to the tail in the path → no-op
			if j >= path.size() - 2:
				continue
			# Reverse the segment after nb up to the tail
			var lo := j + 1
			var hi := path.size() - 1
			while lo < hi:
				var tmp = path[lo]
				path[lo] = path[hi]
				path[hi] = tmp
				idx["%d,%d" % [path[lo].x, path[lo].y]] = lo
				idx["%d,%d" % [path[hi].x, path[hi].y]] = hi
				lo += 1
				hi -= 1
		else:
			if j <= 1:
				continue
			var lo2 := 0
			var hi2 := j - 1
			while lo2 < hi2:
				var tmp2 = path[lo2]
				path[lo2] = path[hi2]
				path[hi2] = tmp2
				idx["%d,%d" % [path[lo2].x, path[lo2].y]] = lo2
				idx["%d,%d" % [path[hi2].x, path[hi2].y]] = hi2
				lo2 += 1
				hi2 -= 1

	return path

func _find_split_endpoint_blocks(grid_size: int, count: int) -> Dictionary:
	var best := {}
	var best_cluster := 999
	for _attempt in range(16):
		var full = _find_hamiltonian_path(grid_size)
		var head_blocks := count / 2
		var tail_blocks := count - head_blocks
		var candidate_blocked: Array = full.slice(0, head_blocks)
		candidate_blocked.append_array(full.slice(full.size() - tail_blocks, full.size()))
		var largest := _largest_block_cluster(candidate_blocked)
		if largest < best_cluster:
			best_cluster = largest
			best = {
				"blocked": candidate_blocked,
				"path": full.slice(head_blocks, full.size() - tail_blocks)
			}
		if largest <= maxi(head_blocks, tail_blocks):
			return best
	return best

func _find_carved_block_layout(grid_size: int, count: int) -> Dictionary:
	for _attempt in range(4):
		var full = _find_hamiltonian_path(grid_size)
		var carved := _carve_removable_intervals(full, count)
		if not carved.is_empty():
			return carved
	return _find_split_endpoint_blocks(grid_size, count)

func _carve_removable_intervals(full: Array, count: int) -> Dictionary:
	var candidates := _find_removable_intervals(full, mini(5, count))
	candidates.shuffle()

	var intervals: Array = []
	var remaining := count
	for cand in candidates:
		if int(cand["count"]) > remaining:
			continue
		if not _interval_fits(cand, intervals):
			continue
		intervals.append(cand)
		remaining -= int(cand["count"])
		if remaining == 0:
			break

	if remaining != 0:
		return {}

	var skip := {}
	var blocked: Array = []
	for interval in intervals:
		for idx in range(int(interval["start"]), int(interval["end"]) + 1):
			skip[idx] = true
			blocked.append(full[idx])

	var path: Array = []
	for i in range(full.size()):
		if not skip.has(i):
			path.append(full[i])
	if not _path_is_adjacent(path):
		return {}
	return {"blocked": blocked, "path": path}

func _find_removable_intervals(path: Array, max_remove: int) -> Array:
	var candidates: Array = []
	for i in range(path.size() - 2):
		var upper = mini(path.size(), i + max_remove + 2)
		for j in range(i + 2, upper):
			var remove_count := j - i - 1
			if remove_count <= 0 or remove_count > max_remove:
				continue
			if _are_adjacent(path[i], path[j]):
				candidates.append({
					"start": i + 1,
					"end": j - 1,
					"count": remove_count
				})
	return candidates

func _interval_fits(candidate: Dictionary, intervals: Array) -> bool:
	var c_start := int(candidate["start"])
	var c_end := int(candidate["end"])
	for interval in intervals:
		var i_start := int(interval["start"])
		var i_end := int(interval["end"])
		if c_start <= i_end + 2 and c_end >= i_start - 2:
			return false
	return true

func _path_is_adjacent(path: Array) -> bool:
	for i in range(1, path.size()):
		if not _are_adjacent(path[i - 1], path[i]):
			return false
	return true

func _are_adjacent(a: Vector2, b: Vector2) -> bool:
	return abs(int(a.x) - int(b.x)) + abs(int(a.y) - int(b.y)) == 1

func _largest_block_cluster(blocks: Array) -> int:
	var remaining := {}
	for b in blocks:
		remaining["%d,%d" % [int(b.x), int(b.y)]] = b
	var largest := 0
	while not remaining.is_empty():
		var stack := [remaining.keys()[0]]
		var size := 0
		while not stack.is_empty():
			var key: String = stack.pop_back()
			if not remaining.has(key):
				continue
			var b = remaining[key]
			remaining.erase(key)
			size += 1
			for other_key in remaining.keys():
				var other = remaining[other_key]
				if abs(int(b.x) - int(other.x)) + abs(int(b.y) - int(other.y)) <= 1:
					stack.append(other_key)
		largest = maxi(largest, size)
	return largest


# Pick `count` cells that are at least 2 Manhattan steps apart from each other.
func _pick_scattered_blocks(grid_size: int, count: int) -> Array:
	var blocks: Array = []
	var attempts := 0
	while blocks.size() < count and attempts < 500:
		attempts += 1
		var c := Vector2(randi() % grid_size, randi() % grid_size)
		var ok := true
		for b in blocks:
			if abs(c.x - b.x) + abs(c.y - b.y) <= 1:
				ok = false
				break
		if ok:
			blocks.append(c)
	return blocks

# Hamiltonian path over (grid \ blocks) via Warnsdorff DFS, multi-restart.
# Pre-marks blocked cells as visited so the DFS treats them as obstacles.
func _find_hamiltonian_with_blocks(grid_size: int, blocked: Array) -> Array:
	var target := grid_size * grid_size - blocked.size()
	if target <= 0:
		return []
	var blocked_dict := {}
	for bb in blocked:
		blocked_dict[bb] = true
	# Step budget per attempt: cells * 25 is empirically enough for the
	# typical Warnsdorff path but caps the worst case so a bad seed can't
	# hang the game (the level-11 freeze). Floor 1000 keeps small boards
	# fluid. Outer attempts dropped 25 → 12 since the budget catches
	# pathological seeds quickly; the tail-trim fallback handles the rest.
	_gen_budget = maxi(1000, target * 25)
	var attempts := 0
	while attempts < 12:
		attempts += 1
		var start := Vector2(randi() % grid_size, randi() % grid_size)
		if blocked_dict.has(start):
			continue
		_gen_aborted = false
		_gen_steps = 0
		var visited: Dictionary = blocked_dict.duplicate()
		var path: Array = []
		if _dfs(start, grid_size, visited, path, target):
			return path
		# Budget blown — try a different start, don't grind the same seed.
	return []

# DFS with Warnsdorff heuristic
func _dfs(pos: Vector2, grid_size: int, visited: Dictionary, path: Array, total_cells: int) -> bool:
	# Budget check: bail immediately if this attempt has already exceeded the
	# generation budget. Every recursion entry counts as one step, so deep
	# backtracking shows up as budget consumption.
	_gen_steps += 1
	if _gen_steps > _gen_budget:
		_gen_aborted = true
		return false

	visited[pos] = true
	path.append(pos)

	if path.size() == total_cells:
		return true  # All cells visited

	# Get unvisited neighbors
	var neighbors = _get_neighbors(pos, grid_size)
	var unvisited = []
	for n in neighbors:
		if not visited.has(n):
			unvisited.append(n)

	if unvisited.is_empty():
		# Dead end — backtrack
		visited.erase(pos)
		path.pop_back()
		return false

	# Warnsdorff heuristic: sort by fewest onward exits
	unvisited.sort_custom(func(a, b):
		return _warnsdorff_score(a, visited, grid_size) < _warnsdorff_score(b, visited, grid_size))

	# Randomize in case of ties (within same score group)
	# Fisher-Yates shuffle on subgroups with equal scores
	var shuffled = []
	var i = 0
	while i < unvisited.size():
		var score = _warnsdorff_score(unvisited[i], visited, grid_size)
		var group = [unvisited[i]]
		var j = i + 1
		while j < unvisited.size() and _warnsdorff_score(unvisited[j], visited, grid_size) == score:
			group.append(unvisited[j])
			j += 1
		# Shuffle this tie group
		group.shuffle()
		shuffled.append_array(group)
		i = j

	for nbr in shuffled:
		if _dfs(nbr, grid_size, visited, path, total_cells):
			return true
		# Abort propagates up the recursion so we don't try further siblings
		# under a doomed branch.
		if _gen_aborted:
			break

	# Backtrack
	visited.erase(pos)
	path.pop_back()
	return false


# Warnsdorff score: number of unvisited neighbors
# Lower = better (fewer onward exits = explore this first)
func _warnsdorff_score(pos: Vector2, visited: Dictionary, grid_size: int) -> int:
	var count = 0
	for n in _get_neighbors(pos, grid_size):
		if not visited.has(n):
			count += 1
	return count


# Get orthogonal neighbors within bounds
func _get_neighbors(pos: Vector2, grid_size: int) -> Array:
	var neighbors = []
	var dirs = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	for d in dirs:
		var n = pos + d
		if n.x >= 0 and n.x < grid_size and n.y >= 0 and n.y < grid_size:
			neighbors.append(n)
	return neighbors


# Place K dots along the Hamiltonian path with constraints
func _place_dots(path: Array, dot_count: int, grid_size: int) -> Array:
	if dot_count < 2:
		dot_count = 2
	if dot_count > path.size():
		dot_count = path.size()
	
	var min_seg = maxi(2, grid_size / 2)
	var max_seg = 2 * grid_size
	
	var dots = []
	var path_len = path.size()
	
	# Dot 1 is always the first cell of the path
	var first_dot_idx = 0
	dots.append({
		"number": 1,
		"row": int(path[first_dot_idx].x),
		"col": int(path[first_dot_idx].y),
		"index": first_dot_idx
	})
	
	# Try to place remaining dots
	var remaining = dot_count - 1
	var last_idx = first_dot_idx
	var segment_lengths = []
	
	# First pass: distribute evenly
	var ideal_seg = (path_len - first_dot_idx) / remaining
	var attempts = 0
	
	for n in range(2, dot_count + 1):
		var min_idx = last_idx + min_seg
		var max_idx = last_idx + max_seg
		var target_idx = last_idx + maxi(min_seg, mini(ideal_seg, max_seg))
		
		# Ensure room for remaining dots
		var dots_left = dot_count - n
		if dots_left > 0:
			var max_allowed = path_len - (dots_left * min_seg) - 1
			target_idx = mini(target_idx, max_allowed)
		
		# Find the best index near target that includes a turn
		var best_idx = -1
		var best_turns = -1
		
		for offset in range(0, maxi(1, ideal_seg / 2)):
			for sign_dir in [1, -1]:
				var candidate = target_idx + (offset * sign_dir)
				if candidate > last_idx + min_seg and candidate < path_len - (dots_left * min_seg + 1):
					var turns = _count_turns(path, last_idx, candidate)
					if turns > best_turns:
						best_turns = turns
						best_idx = candidate
		
		if best_idx < 0:
			best_idx = mini(last_idx + min_seg, path_len - 1)
		
		dots.append({
			"number": n,
			"row": int(path[best_idx].x),
			"col": int(path[best_idx].y),
			"index": best_idx
		})
		segment_lengths.append(best_idx - last_idx)
		last_idx = best_idx

		# The highest-numbered dot is always the final cell of the path,
		# so completing the fill ends exactly on the last number.
		if n == dot_count:
			dots[-1]["index"] = path_len - 1
			dots[-1]["row"] = int(path[path_len - 1].x)
			dots[-1]["col"] = int(path[path_len - 1].y)

	return dots


# Count 90° turns in a path segment
func _count_turns(path: Array, from_idx: int, to_idx: int) -> int:
	if to_idx - from_idx < 2:
		return 0
	var turns = 0
	for i in range(from_idx + 1, to_idx):
		var prev = path[i - 1]
		var curr = path[i]
		var next = path[i + 1]
		var d1 = curr - prev
		var d2 = next - curr
		if d1 != d2:
			turns += 1
	return turns


# Calculate difficulty score D ∈ [0, 100]
func _calculate_difficulty(grid_size: int, dots: Array, path: Array) -> float:
	var K = float(dots.size())
	var Kmax = float(maxi(8, grid_size))
	var w1 = 0.20  # Dot density
	var w2 = 0.35  # Turn ratio
	var w3 = 0.30  # Branch factor
	var w4 = 0.15  # Grid size
	
	var total_cells = path.size()
	var total_turns = 0
	var total_branch = 0
	
	for i in range(1, path.size()):
		var prev = path[i - 1]
		var curr = path[i]
		var next_pos = path[i + 1] if i + 1 < path.size() else curr
		var d1 = curr - prev
		var d2 = next_pos - curr
		if d1 != d2:
			total_turns += 1
		# Branch factor at this cell
		var nbrs = 0
		for n in _get_neighbors(curr, grid_size):
			nbrs += 1
		if nbrs > 2:
			total_branch += (nbrs - 2)
	
	var turn_ratio = total_turns / float(maxi(1, total_cells))
	var branch_factor = total_branch / float(maxi(1, total_cells))
	
	var D = (w1 * (K / Kmax) + w2 * (turn_ratio * 10) + w3 * (branch_factor * 5) + w4 * (grid_size / 10.0)) * 100.0
	D = clampf(D, 0.0, 100.0)
	
	return round(D * 10.0) / 10.0


# Convert Vector2 path to cell coordinate array [[row, col], ...]
func _path_to_cell_list(path: Array) -> Array:
	var cells = []
	for p in path:
		cells.append([int(p.x), int(p.y)])
	return cells
