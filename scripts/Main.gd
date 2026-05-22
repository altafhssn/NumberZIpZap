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
var AudioScript = preload("res://scripts/Audio.gd")
var PauseScene = preload("res://scenes/Pause.tscn")
var TutorialScene = preload("res://scenes/Tutorial.tscn")

var audio = null

# Level progression
var current_level: int = 1
var levels_per_pack: int = 40
var current_pack: int = 0  # 0=Tutorial, 1=Sunrise, 2=Nebula, etc.
var grid_sizes = [5, 5, 6, 7, 8, 9, 9]
var dot_counts = [6, 6, 7, 8, 9, 10, 12]

func _ready():
	level_gen = LevelGeneratorScript.new()
	game_state = GameStateScript.new()
	audio = AudioScript.new()
	add_child(audio)

	# No banner during gameplay (avoid misclicks)
	Ads.hide_banner()

	# Resume from the level chosen on Home / Level Select
	current_level = maxi(1, GameData.selected_level)
	current_pack = mini((current_level - 1) / levels_per_pack, grid_sizes.size() - 1)

	_start_new_level()

func _start_new_level():
	# Difficulty scales with the absolute level (monotonic across packs):
	#  - grid size grows +1 every 10 levels (5x5 -> ... -> 9x9)
	#  - dot count grows +1 every 5 levels, capped to grid_size+2 so it
	#    stays solvable for the board.
	var lvl = current_level
	var gs = clampi(5 + (lvl - 1) / 10, 5, 9)
	var max_dots = mini(gs + 2, gs * gs - 1)
	var dc = clampi(6 + (lvl - 1) / 5, 6, max_dots)

	# From level 11+: random impassable blocks, +1 every 8 levels (cap gs).
	var blocks = 0
	if lvl > 10:
		blocks = clampi(1 + (lvl - 11) / 8, 1, gs)

	# Generate level
	var data = level_gen.generate(gs, dc, current_level * 1000 + Time.get_ticks_msec(), blocks)
	if data.is_empty():
		# Fallback
		data = level_gen.generate(5, 4, randi(), 0)
	
	game_state.load_level(data)
	
	# Update grid and HUD
	grid.setup(data)
	hud.update_for_level(current_level, data)

	# Tutorial on level 1: show if flag is off, or if the player still hasn't
	# unlocked anything past level 1 (safety net for a stuck flag).
	if current_level == 1 and (not GameData.tutorial_done or GameData.max_unlocked <= 1):
		_show_tutorial()

	emit_signal("level_loaded")

func _show_tutorial():
	if has_node("Tutorial"):
		return
	var t = TutorialScene.instantiate()
	t.name = "Tutorial"
	add_child(t)
	t.setup(game_state)

func on_cell_tapped(row: int, col: int):
	if game_state.is_completed:
		return
	
	var result = game_state.try_place_cell(row, col)
	if result.get("rewound", false):
		grid.refresh_from_state(game_state)
		hud.update_stats(game_state)
		_haptic(8)
	elif result.get("failed", false):
		# Grid filled but path did not end on the last number
		grid.add_path_cell(row, col, result.get("dot_reached", false))
		grid.show_error(row, col, result.get("message", "Failed"))
		hud.show_fail(result.get("message", "Failed"))
		audio.play_fail()
		_haptic(35)
	elif result.get("success", false):
		grid.add_path_cell(row, col, result.get("dot_reached", false))
		hud.update_stats(game_state)

		if result.get("dot_reached", false):
			grid.spawn_ripple(row, col)
			audio.play_dot()
			_haptic(15)
		else:
			audio.play_move()
			_haptic(8)

		if result.get("completed", false):
			audio.play_win()
			_haptic(45)
			_on_level_complete()
	else:
		# Show error feedback
		grid.show_error(row, col, result.get("message", ""))
		audio.play_error()
		_haptic(22)

func _haptic(ms: int):
	if GameData.haptics_on:
		Input.vibrate_handheld(ms)

func on_cell_drag(row: int, col: int):
	on_cell_tapped(row, col)

func on_undo():
	if game_state.undo():
		grid.refresh_from_state(game_state)
		hud.update_stats(game_state)
		_haptic(10)

func on_reset():
	game_state.full_reset()
	grid.refresh_from_state(game_state)
	hud.update_stats(game_state)
	_haptic(18)

func on_hint():
	# Hint is gated behind a rewarded ad (stub grants immediately)
	Ads.show_rewarded("hint", _grant_hint)

func _grant_hint():
	var hint = game_state.get_hint()
	if hint.size() == 2:
		grid.show_hint(hint[0], hint[1])
		hud.update_stats(game_state)
		_haptic(12)

func on_watch_continue():
	# Rewarded retry of the same level after a fail
	Ads.show_rewarded("continue", _continue_reward)

func _continue_reward():
	hud.hide_continue()
	on_replay()

func _on_level_complete():
	var stars = game_state.get_stars()
	var time_val = game_state.elapsed_time
	var moves_val = game_state.moves

	GameData.record_result(current_level, stars)
	if current_level == 1:
		GameData.tutorial_done = true
		GameData.save_game()
	GameData.selected_level = current_level + 1

	emit_signal("level_completed", stars, time_val, moves_val)
	hud.show_complete(stars, time_val, moves_val)

func on_next_level():
	# Interstitial every Nth completion (no-op in stub mode)
	Ads.notify_level_complete_then_interstitial()

	current_level += 1
	# Check if we move to next pack
	if (current_level - 1) % levels_per_pack == 0 and current_level > 1:
		current_pack = mini(current_pack + 1, grid_sizes.size() - 1)

	GameData.selected_level = current_level
	_start_new_level()

func on_replay():
	# Replay the exact same puzzle from scratch
	game_state.full_reset()
	grid.refresh_from_state(game_state)
	hud.update_for_level(current_level, game_state.level_data)
	hud.update_stats(game_state)

func on_pause():
	if has_node("Pause"):
		return
	get_tree().paused = true
	var p = PauseScene.instantiate()
	p.name = "Pause"
	p.resume_requested.connect(func(): get_tree().paused = false)
	p.restart_requested.connect(func(): get_tree().paused = false; on_reset())
	p.home_requested.connect(on_home)
	add_child(p)

func on_home():
	get_tree().paused = false
	Transition.goto("res://scenes/Home.tscn")

# Called from HUD via signals
func _on_hud_next():
	on_next_level()

func _on_hud_undo():
	on_undo()

func _on_hud_reset():
	on_reset()

func _on_hud_hint():
	on_hint()
