# Main.gd
# Main game controller for ZipPath
extends Node2D

signal level_loaded
signal level_completed(stars: int, time: float, moves: int)

@onready var hud = $HUD
@onready var grid = $Grid

var level_gen = null
var game_state = null

# Preloads
var LevelGeneratorScript = preload("res://scripts/LevelGenerator.gd")
var GameStateScript = preload("res://scripts/GameState.gd")

# Level progression
var current_level: int = 1
var levels_per_pack: int = 40
var current_pack: int = 0  # 0=Tutorial, 1=Sunrise, 2=Nebula, etc.
var grid_sizes = [5, 5, 6, 7, 8, 9, 9]
var dot_counts = [6, 6, 7, 8, 9, 10, 12]

func _ready():
	level_gen = LevelGeneratorScript.new()
	game_state = GameStateScript.new()
	
	_start_new_level()

func _start_new_level():
	# Determine grid size and dot count from progression
	var pack_idx = mini(current_pack, grid_sizes.size() - 1)
	var gs = grid_sizes[pack_idx]
	var dc = dot_counts[pack_idx]
	
	# Scale dot count with level within the pack
	var pack_level = (current_level - 1) % levels_per_pack
	var pack_progress = float(pack_level) / float(levels_per_pack)
	dc = clampi(int(dc + pack_progress * 3), 2, gs * 2)
	
	# Generate level
	var data = level_gen.generate(gs, dc, current_level * 1000 + Time.get_ticks_msec())
	if data.is_empty():
		# Fallback
		data = level_gen.generate(5, 4, randi())
	
	game_state.load_level(data)
	
	# Update grid and HUD
	grid.setup(data)
	hud.update_for_level(current_level, data)
	
	emit_signal("level_loaded")

func on_cell_tapped(row: int, col: int):
	if game_state.is_completed:
		return
	
	var result = game_state.try_place_cell(row, col)
	if result.get("rewound", false):
		grid.refresh_from_state(game_state)
		hud.update_stats(game_state)
	elif result.get("success", false):
		grid.add_path_cell(row, col, result.get("dot_reached", false))
		hud.update_stats(game_state)

		if result.get("completed", false):
			_on_level_complete()
	else:
		# Show error feedback
		grid.show_error(row, col, result.get("message", ""))

func on_cell_drag(row: int, col: int):
	on_cell_tapped(row, col)

func on_undo():
	if game_state.undo():
		grid.refresh_from_state(game_state)
		hud.update_stats(game_state)

func on_reset():
	game_state.full_reset()
	grid.refresh_from_state(game_state)
	hud.update_stats(game_state)

func on_hint():
	var hint = game_state.get_hint()
	if hint.size() == 2:
		grid.show_hint(hint[0], hint[1])
		hud.update_stats(game_state)

func _on_level_complete():
	var stars = game_state.get_stars()
	var time_val = game_state.elapsed_time
	var moves_val = game_state.moves
	
	emit_signal("level_completed", stars, time_val, moves_val)
	hud.show_complete(stars, time_val, moves_val)

func on_next_level():
	current_level += 1
	# Check if we move to next pack
	if (current_level - 1) % levels_per_pack == 0 and current_level > 1:
		current_pack = mini(current_pack + 1, grid_sizes.size() - 1)
	
	_start_new_level()

func on_home():
	# Return to pack select (goes to main menu state)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

# Called from HUD via signals
func _on_hud_next():
	on_next_level()

func _on_hud_undo():
	on_undo()

func _on_hud_reset():
	on_reset()

func _on_hud_hint():
	on_hint()
