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

var DailyCardScript = preload("res://scripts/DailyCard.gd")
var PaletteUnlockPopupScript = preload("res://scripts/PaletteUnlockPopup.gd")
var PalettesScript = preload("res://scripts/Palettes.gd")
var SectorThemesScript = preload("res://scripts/SectorThemes.gd")
var _daily_mood_name: String = "Dawn"

# Level progression
var current_level: int = 1
var levels_per_pack: int = 40
var current_pack: int = 0  # Dawn/Day/Dusk/Night journey index.
var grid_sizes = [5, 5, 6, 7, 8, 9, 9]
var dot_counts = [6, 6, 7, 8, 9, 10, 12]

# Double-tap shortcut — tracks the previous tap's cell and timestamp so a
# second tap on the same numbered stone within DOUBLE_TAP_WINDOW seconds
# rewinds the path back to that stone. Bypasses the stable-line rule.
const DOUBLE_TAP_WINDOW := 0.35
var _last_tap_cell: Vector2i = Vector2i(-1, -1)
var _last_tap_time: float = 0.0

func _ready():
	level_gen = LevelGeneratorScript.new()
	game_state = GameStateScript.new()
	# Auto-lock: GameState fires this the instant the last cell completes the
	# puzzle. We use it for the snap feedback so the lock-in is felt before the
	# completion card animates in (see _on_auto_locked + deferred timer below).
	game_state.auto_locked.connect(_on_auto_locked)
	audio = AudioScript.new()
	add_child(audio)

	Ads.show_banner()

	current_level = maxi(1, GameData.selected_level)
	current_pack = mini((current_level - 1) / levels_per_pack, grid_sizes.size() - 1)

	GameData.regen_hints_if_needed()

	if GameData.daily_mode:
		if not GameData.is_daily_available():
			GameData.daily_mode = false
			Transition.goto("res://scenes/Home.tscn")
			return
		_start_daily_level()
	else:
		_start_new_level()

# The Daily Pond: one deterministic puzzle per calendar day, identical for
# every player, in that day's mood. No tutorial, no progression — just the
# ritual. Completion shows a shareable card instead of the next-level flow.
func _start_daily_level():
	var s := GameData.daily_seed()
	var gs := 5 + (s % 3)                       # 5..7, varies by day
	var max_dots := mini(gs + 2, gs * gs - 1)
	var dc := clampi(6 + (s / 7) % 4, 6, max_dots)
	var blocks := 0
	if gs >= 6:
		blocks = (s / 13) % 3                   # 0..2, deterministic

	var data = level_gen.generate(gs, dc, s, blocks)
	if data.is_empty():
		data = level_gen.generate(5, 6, s, 0)

	game_state.load_level(data)

	# Mood is chosen by the date, not by difficulty, so the daily cycles
	# through Dawn/Day/Dusk/Night over time.
	var themes = game_state.THEMES
	var mood_idx = s % themes.size()
	var theme = themes[mood_idx]
	game_state.path_color_start = theme["start"]
	game_state.path_color_end = theme["end"]
	_daily_mood_name = theme["name"]

	grid.setup(data)
	# Apply the sector theme (background, particles, ambient) before the
	# equipped palette so the palette can override the path colors on top.
	# Daily uses Pool 1's theme so the visuals stay consistent across the day.
	grid.apply_theme(SectorThemesScript.get_theme_for_level(1), 1)
	_apply_equipped_palette()
	hud.update_for_level(1, data)
	hud.set_daily_banner(_daily_mood_name)

	emit_signal("level_loaded")

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

	# From level 121+: blocks must be scattered (no two adjacent). The carved-
	# cluster look becomes unpleasant at higher levels and felt unfair to
	# players past the Stone Bend pack.
	var scatter_blocks: bool = lvl > 120

	# Scatter mode can't sustain many blocks — a Hamiltonian path through a
	# 9x9 grid with 9 scattered obstacles is borderline infeasible. Cap it.
	if scatter_blocks:
		blocks = mini(blocks, maxi(2, gs - 4))

	# Generate level
	var data = level_gen.generate(gs, dc, current_level * 1000 + Time.get_ticks_msec(), blocks, scatter_blocks)
	if data.is_empty():
		# Fallback
		data = level_gen.generate(5, 4, randi(), 0)

	game_state.load_level(data)

	# Update grid and HUD
	grid.setup(data)
	# Apply the sector theme first so the background, ribbon, and particles
	# align with the current pack. _apply_equipped_palette then overrides the
	# path colors with the player's cosmetic choice (if any).
	grid.apply_theme(SectorThemesScript.get_theme_for_level(current_level), current_level)
	_apply_equipped_palette()
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
	t.setup(game_state, grid)

func on_cell_tapped(row: int, col: int, from_drag: bool = false):
	if game_state.is_completed:
		return

	# Double-tap on a numbered stone that's already in the path → rewind to
	# that stone. Provides a fast checkpoint shortcut without forcing the
	# player to drag back through every intermediate cell. Only counts genuine
	# taps (press events) — drag movements don't bump the tap timer.
	if not from_drag:
		var now: float = float(Time.get_ticks_msec()) / 1000.0
		var same_cell: bool = _last_tap_cell == Vector2i(row, col)
		var in_window: bool = (now - _last_tap_time) < DOUBLE_TAP_WINDOW
		_last_tap_cell = Vector2i(row, col)
		_last_tap_time = now
		if same_cell and in_window:
			if game_state.try_rewind_to_dot(row, col):
				grid.refresh_from_state(game_state)
				hud.update_stats(game_state)
				audio.play_rewind(game_state.player_path.size())
				_haptic(15)
				# Reset so a third tap doesn't fire something weird.
				_last_tap_cell = Vector2i(-1, -1)
				_last_tap_time = 0.0
				return

	var result = game_state.try_place_cell(row, col)
	if result.get("rewound", false):
		grid.refresh_from_state(game_state)
		hud.update_stats(game_state)
		audio.play_rewind(game_state.player_path.size())
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

		# Soft-fail detection: player just landed on the FINAL numbered
		# stone but the grid isn't fully visited — every dot is linked,
		# every cell isn't. Bad attempt — fire fail feedback and auto-
		# rewind back to the previous numbered stone after a short pause
		# so the player can see the ✗ before the path snaps back.
		var soft_fail: bool = (
			result.get("dot_reached", false)
			and game_state.next_dot_index >= game_state.dots.size()
			and not result.get("completed", false)
			and game_state.get_fill_pct() < 100.0
		)

		# On completion: skip dot SFX + extra haptic so they don't muddy the
		# lock click + zoom that _on_auto_locked already fired this frame.
		# Auto-lock owns the entire feedback for the closing cell.
		var is_completing_now: bool = result.get("completed", false)
		if soft_fail:
			audio.play_fail()
			_haptic(45)
			get_tree().create_timer(1.1).timeout.connect(_rewind_after_soft_fail)
		elif result.get("dot_reached", false) and not is_completing_now:
			grid.spawn_ripple(row, col)
			audio.play_dot(game_state.player_path.size())
			_haptic(15)
		elif not is_completing_now:
			audio.play_move(game_state.player_path.size())
			_haptic(8)

		if result.get("completed", false):
			# The lock snap (audio + haptic + ripple) is handled by
			# _on_auto_locked, which fires from GameState the same frame. The
			# completion card is deferred so the lock click → win zoom → 1.2s
			# back-then-forward path retrace can all play out before the
			# panel covers the grid. Total beat: ~1.4s.
			get_tree().create_timer(1.4).timeout.connect(_on_level_complete)
	elif result.get("silent", false):
		# Intentional no-op: tap landed on a committed cell (before the last
		# touched stone). No feedback so the player can graze the line freely.
		pass
	else:
		# Show error feedback
		grid.show_error(row, col, result.get("message", ""))
		audio.play_error()
		_haptic(22)

func _haptic(ms: int):
	if GameData.haptics_on:
		Input.vibrate_handheld(ms)

# Fired synchronously by GameState the instant the player's last appended cell
# completes the puzzle (before try_place_cell returns and before grid actually
# draws the final cell). We play the "lock" audio + haptic and kick off the
# grid lock animation + win zoom here so the satisfying click lands the same
# frame the path resolves. The cell's own ripple is left to the dot_reached
# branch in on_cell_tapped — by the time that runs, grid.add_path_cell has
# already drawn the final cell.
func _on_auto_locked(row: int, col: int) -> void:
	audio.play_lock()
	# Win SFX layered ~120ms later — the pluck reads as "click" first, then
	# the arpeggio celebrates. Stacking them at once muddies both.
	get_tree().create_timer(0.12).timeout.connect(audio.play_win)
	_haptic(60)
	# Pop a fresh ripple at the closing cell so the visual lands the same frame
	# as the lock click; the dot_reached branch hasn't reached add_path_cell
	# yet, so an earlier spawn_ripple here would render over an empty cell.
	# Instead we drive the dedicated lock animation, which carries its own
	# disc + ring and doesn't depend on the cell being drawn first.
	grid.play_lock_animation(row, col)
	_play_win_zoom()

# Brief 1.0 → 1.08 → 1.0 zoom on the grid that gives the resolution moment a
# subtle "earned" punch. Position is compensated so the visual center stays
# fixed instead of drifting toward the bottom-right corner (Node2D scales
# from its own position). Total duration kept inside the 1.0s popup delay
# (0.30 + 0.55 = 0.85s) so the grid is settled by the time the panel slides
# in. Scale bumped from 1.045 to 1.08 — the brief's 1.045 was too subtle on
# device to actually notice.
func _play_win_zoom() -> void:
	if grid == null:
		return
	var base_pos: Vector2 = grid.position
	var rect_size: Vector2 = grid.grid_rect.size
	var peak_scale := 1.08
	var off: Vector2 = -rect_size * (peak_scale - 1.0) * 0.5
	# Phase 1 — scale up + offset run in parallel (0.30s).
	var tw := create_tween().set_parallel(true)
	tw.tween_property(grid, "scale", Vector2(peak_scale, peak_scale), 0.30) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(grid, "position", base_pos + off, 0.30) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	# Phase 2 — chain, then re-enable parallel so the release scale and
	# position tweens also run together (0.55s). Without re-enabling, chain
	# resets to sequential and the total bloats past the popup deferral.
	tw.chain().set_parallel(true)
	tw.tween_property(grid, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(grid, "position", base_pos, 0.55) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)

# Auto-revert the player's path back to the previous numbered stone after
# a soft-fail (all dots linked but cells remain). Called via a 1.1s timer
# so the player sees the big ✗ overlay flash before the path snaps back.
# Guards against firing after the player already pressed Reset / Replay.
func _rewind_after_soft_fail() -> void:
	if game_state == null or game_state.is_completed:
		return
	if game_state.player_path.is_empty():
		return
	game_state.rewind_to_previous_dot()
	grid.refresh_from_state(game_state)
	hud.update_stats(game_state)
	audio.play_move(game_state.player_path.size())
	_haptic(12)

func on_cell_drag(row: int, col: int):
	# from_drag=true so double-tap timer isn't bumped by passing-finger cells.
	on_cell_tapped(row, col, true)

func on_undo():
	if game_state.undo():
		grid.refresh_from_state(game_state)
		hud.update_stats(game_state)
		audio.play_rewind(game_state.player_path.size())
		_haptic(10)

func on_reset():
	game_state.full_reset()
	grid.refresh_from_state(game_state)
	hud.update_stats(game_state)
	_haptic(18)

func on_hint():
	request_hint()

func _grant_hint():
	# Show the FULL path from the head to the next un-reached numbered dot —
	# same trail the tutorial uses. Lets the player see exactly which cells
	# bridge them to the next stone instead of a 3-cell teaser. Falls back to
	# the old single-cell solution lookup when the solver can't find a
	# continuation (rare; usually only on dead-ended states).
	var trail: Array = game_state.get_continuation_to_next_dot()
	if trail.size() > 0:
		game_state.hints_used += 1
		grid.show_hint_trail(trail)
		hud.update_stats(game_state)
		_haptic(12)
		return
	var hint = game_state.get_hint()
	if hint.size() == 2:
		grid.show_hint(hint[0], hint[1])
		hud.update_stats(game_state)
		_haptic(12)

# Called by HUD when the player taps the Hint button.
# Both daily and pack mode: spend from wallet; if empty, offer a rewarded ad.
# In daily mode, the petal cost still applies — leaderboard ranks petals first
# so hint users naturally fall below clean runs without being locked out.
func request_hint():
	if GameData.spend_hint():
		_grant_hint()
		hud.refresh_hint_wallet()
		return
	# Out of hints — offer the rewarded ad path.
	Ads.show_rewarded("hint", _on_hint_ad_reward)

# Reward callback for the rewarded-ad refill flow. Extracted into a named
# method so the call site doesn't need a multi-line lambda (which can confuse
# the GDScript parser when the closing ')' lands in an indented position).
func _on_hint_ad_reward() -> void:
	GameData.grant_hints(1)
	hud.refresh_hint_wallet()
	# Auto-spend the freshly-granted hint so the player gets immediate
	# feedback for the ad they just watched.
	if GameData.spend_hint():
		_grant_hint()

func on_watch_continue():
	_continue_reward()

func _continue_reward():
	hud.hide_continue()
	on_replay()

func _on_level_complete():
	var stars = game_state.get_stars()
	var time_val = game_state.elapsed_time
	var moves_val = game_state.moves

	# Daily Pond completes into a shareable card, not the progression flow.
	if GameData.daily_mode:
		GameData.record_daily(stars)
		# Daily players still feed the shop economy — same drops formula as
		# regular levels so the daily ritual is as rewarding as a pack level.
		GameData.add_drops(PalettesScript.drops_for_petals(stars))
		Leaderboard.submit_daily(stars, time_val)
		_show_daily_card(stars, time_val)
		return

	GameData.record_result(current_level, stars, time_val)
	# Reward the player with shop currency, scaled by petals earned.
	GameData.add_drops(PalettesScript.drops_for_petals(stars))
	# Check if completing this level just crossed a palette-unlock threshold.
	# Queued for after the level-complete card animates in.
	var fresh_palettes: Array = GameData.consume_pending_palette_popups(current_level)
	if not fresh_palettes.is_empty():
		_queue_palette_popup(fresh_palettes[0])
	if current_level == 1:
		GameData.tutorial_done = true
		GameData.save_game()
	GameData.selected_level = current_level + 1

	# Submit cumulative pack totals to the per-pack leaderboard.
	# Play Games only retains the player's best score, so resubmitting on
	# every completion is the correct pattern.
	var pack_idx := GameData.pack_index_for_level(current_level)
	var totals: Dictionary = GameData.get_pack_totals(pack_idx)
	Leaderboard.submit_pack(pack_idx, int(totals["petals"]), float(totals["time"]))

	# Interstitial cadence (every 3 levels, skip 1-5, never premium).
	# Ads.notify_level_complete_then_interstitial manages the counter +
	# skip rules; the callback is empty because the completion panel can
	# stay up while the ad shows in the background.
	Ads.notify_level_complete_then_interstitial(current_level)

	emit_signal("level_completed", stars, time_val, moves_val)
	hud.show_complete(stars, time_val, moves_val)

func on_next_level():
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
	if GameData.daily_mode:
		hud.set_daily_banner(_daily_mood_name)
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

# Override game_state's path colors with whatever palette the player has
# equipped in the shop. Called after every level/daily load so cosmetics
# always apply — including to the daily mood gradients.
func _apply_equipped_palette() -> void:
	var colors: Dictionary = GameData.get_equipped_palette_colors()
	game_state.path_color_start = colors["start"]
	game_state.path_color_end = colors["end"]

# Show the "new palette unlocked!" celebration card. Deferred slightly so the
# level-complete card pops in first; the popup then slides on top.
func _queue_palette_popup(palette: Dictionary) -> void:
	var timer := get_tree().create_timer(1.6)
	timer.timeout.connect(func():
		if has_node("PaletteUnlockPopup"):
			return
		var popup = PaletteUnlockPopupScript.new()
		popup.name = "PaletteUnlockPopup"
		popup.setup(palette)
		add_child(popup)
		popup.equip_requested.connect(func(id: String):
			GameData.equip_palette(id)
			_apply_equipped_palette()))

func _show_daily_card(petals: int, time_sec: float):
	if has_node("DailyCard"):
		return
	var card = DailyCardScript.new()
	card.name = "DailyCard"
	add_child(card)
	card.setup(_daily_mood_name, petals, time_sec)
	card.home_requested.connect(on_home)

func on_home():
	get_tree().paused = false
	GameData.daily_mode = false
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
