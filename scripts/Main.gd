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
var SectorThemesScript = preload("res://scripts/SectorThemes.gd")
var PauseScene = preload("res://scenes/Pause.tscn")
var TutorialScene = preload("res://scenes/Tutorial.tscn")

var audio = null

# Level progression
var current_level: int = 1
var levels_per_pack: int = 40
var current_pack: int = 0  # 0=Tutorial, 1=Sunrise, 2=Nebula, etc.
var grid_sizes = [5, 5, 6, 7, 8, 9, 9]
var dot_counts = [6, 6, 7, 8, 9, 10, 12]

# Stuck detection (Feature 2D)
var _stuck_timer: float = 0.0
var _stuck_shown: bool = false
var _ad_playing: bool = false
const STUCK_SECONDS := 12.0

func _ready():
	level_gen = LevelGeneratorScript.new()
	game_state = GameStateScript.new()
	game_state.auto_locked.connect(_on_auto_locked)
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

	# Auto-lock everywhere except the tutorial (level 1), which teaches the
	# manual finger-lift completion flow.
	game_state.auto_lock_enabled = current_level != 1
	game_state.reset_hint_state()
	_stuck_timer = 0.0
	_stuck_shown = false

	# Per-sector theme: palette derived purely from pack index. For Infinite
	# the per-level hue uses current_level; Singularity's ribbon rotates live.
	var pack_index := SectorThemesScript.get_pack_index_for_level(current_level)
	current_pack = pack_index
	var theme := SectorThemesScript.get_theme(pack_index, current_level)
	grid.apply_theme(theme, current_level)
	# Music: crossfade to the sector's track key (silently falls back if the
	# key isn't recognized by the Music autoload).
	if Music and Music.has_method("play_key"):
		Music.play_key(theme.get("music", ""))

	# Update grid and HUD
	grid.setup(data)
	hud.update_for_level(current_level, data)
	hud.update_hint_badge(game_state.hints_used)

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
	t.setup(game_state, grid)

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
		# Silent no-ops (tap landed on a stable part of the line, or a finger
		# slip we don't want to nag about) skip the error feedback entirely.
		if result.get("silent", false):
			return
		# Show error feedback
		grid.show_error(row, col, result.get("message", ""))
		audio.play_error()
		_haptic(22)

func _haptic(ms: int):
	if GameData.haptics_on:
		Input.vibrate_handheld(ms)

# Feature 1: fired the moment the path auto-locks. Plays the lock snap (visual +
# short pluck + medium haptic) just before the win fanfare that follows in the
# completed branch of on_cell_tapped.
func _on_auto_locked(row: int, col: int):
	grid.play_lock_animation(row, col)
	audio.play_lock()
	_haptic(30)
	_play_win_zoom()

# Subtle camera punch on win — Grid scales up slightly then settles back. The
# position is offset to keep the visual centre fixed during the scale, so the
# whole playfield "breathes" toward the player rather than drifting top-left.
func _play_win_zoom():
	if grid == null:
		return
	var center: Vector2 = grid.grid_rect.position + grid.grid_rect.size * 0.5
	var orig_pos: Vector2 = grid.position
	var orig_scale: Vector2 = grid.scale
	var peak := Vector2(1.045, 1.045)
	# To keep center fixed: pos = original_pos + center * (1 - scale)
	var peak_pos: Vector2 = orig_pos + center * (1.0 - peak.x)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(grid, "scale", peak, 0.32).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(grid, "position", peak_pos, 0.32).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.chain()
	tw.tween_property(grid, "scale", orig_scale, 0.55).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(grid, "position", orig_pos, 0.55).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)

# Tutorial completion: finishing happens on finger-lift, not on append.
func on_touch_released():
	if game_state == null:
		return
	if game_state.finish_on_release():
		audio.play_win()
		_haptic(45)
		_on_level_complete()

# Stuck detection (Feature 2D). Timer is naturally frozen while the pause menu
# is up (the tree is paused) and is suppressed during ad playback.
func _process(delta):
	if _ad_playing or get_tree().paused:
		return
	if game_state == null or game_state.is_completed:
		return
	if game_state.player_path.is_empty() or game_state.has_legal_move():
		_stuck_timer = 0.0
		_stuck_shown = false
		return
	_stuck_timer += delta
	if _stuck_timer >= STUCK_SECONDS and not _stuck_shown:
		_stuck_shown = true
		hud.show_toast("Looks stuck — tap hint for help")

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
	if game_state.is_completed:
		return
	# The first GameData.free_hints_per_level hints each level are free; once
	# the quota is exhausted, further hints are gated behind a rewarded ad.
	# Both branches invoke the same grant callback so the trail still draws.
	if game_state.free_hints_used < GameData.free_hints_per_level:
		game_state.free_hints_used += 1
		_grant_hint()
	else:
		_ad_playing = true
		Ads.show_rewarded("hint", _grant_hint)

func _grant_hint():
	_ad_playing = false
	game_state.register_hint()
	# Every hint shows the dashed trail from the player's current head all
	# the way to the next un-reached number — same look the tutorial uses.
	# If there's no valid continuation from the head (the player is stuck in
	# a dead-end), fall back to a "rewind to here" arrow instead.
	var trail: Array = game_state.get_continuation_to_next_dot()
	if not trail.is_empty():
		grid.show_hint_trail(trail)
	else:
		var h = game_state.get_smart_hint()
		if h.get("type", "") == "rewind":
			grid.show_rewind_arrow(h["cell"])
		else:
			hud.show_toast("No hint available — try Undo")
	hud.update_hint_badge(game_state.hints_used)
	hud.update_stats(game_state)
	_haptic(12)
	# A granted hint clears the stuck nag.
	_stuck_timer = 0.0
	_stuck_shown = false

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

	grid.clear_hints()
	GameData.record_result(current_level, stars, game_state.hints_used)
	if current_level == 1:
		GameData.tutorial_done = true
		GameData.save_game()
	GameData.selected_level = current_level + 1

	emit_signal("level_completed", stars, time_val, moves_val)
	# Hold the popup until the win animations (lock snap 0.32s, completion
	# wave 0.9s, zoom punch ~0.87s) have finished — feels much more weighty
	# than the panel popping in over a still-animating playfield.
	_show_complete_after_win_anim(stars, time_val, moves_val)

func _show_complete_after_win_anim(stars: int, time_val: float, moves_val: int):
	await get_tree().create_timer(1.0).timeout
	# Player may have left the scene mid-animation (Home, level select, etc).
	if not is_instance_valid(hud) or not is_inside_tree():
		return
	hud.show_complete(stars, time_val, moves_val)

func on_next_level():
	# Interstitial every Nth completion (no-op in stub mode)
	Ads.notify_level_complete_then_interstitial()

	var prev_pack := SectorThemesScript.get_pack_index_for_level(current_level)
	current_level += 1
	# Check if we move to next pack
	if (current_level - 1) % levels_per_pack == 0 and current_level > 1:
		current_pack = mini(current_pack + 1, grid_sizes.size() - 1)

	# Sector warp: when the level advance crosses a pack boundary, play the
	# 0.6s radial wipe tinted to the NEW pack's accent before continuing.
	var new_pack := SectorThemesScript.get_pack_index_for_level(current_level)
	if new_pack != prev_pack and Transition and Transition.has_method("sector_warp"):
		var accent: Color = SectorThemesScript.get_theme(new_pack, current_level).get("accent", Color.WHITE)
		Transition.sector_warp(accent, 0.6)

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
