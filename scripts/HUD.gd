# HUD.gd
# UI overlay: level info, fill counter, undo/reset/hint buttons, completion
extends CanvasLayer

const SectorThemesScript = preload("res://scripts/SectorThemes.gd")
const StarBadgeScript = preload("res://scripts/StarBadge.gd")

@onready var main = get_parent()

# Track active completion-burst particle emitters so each show_complete can
# clean up the previous ones before spawning new ones (prevents accumulation
# when the player races through several levels).
var _active_burst_nodes: Array[Node] = []

# Big red ✗ overlay shown when the player has linked every numbered stone
# in order but the grid isn't fully filled — the puzzle is incomplete and
# they need to undo. Built on first use, kept around for the level's lifetime.
var _invalid_overlay: Control = null

# UI References
@onready var level_label = $LevelLabel
@onready var fill_label = $FillLabel
@onready var fill_bar: ProgressBar = $FillBar
@onready var undo_btn = $UndoBtn
@onready var reset_btn = $ResetBtn
@onready var hint_btn = $HintBtn
@onready var hint_count = $HintCount
@onready var pause_btn = $PauseBtn
@onready var continue_btn = $ContinueBtn
@onready var complete_panel = $CompletePanel
@onready var stars_label = $CompletePanel/StarsLabel
@onready var stats_label = $CompletePanel/StatsLabel
@onready var next_btn = $CompletePanel/NextBtn
@onready var replay_btn = $CompletePanel/ReplayBtn
@onready var home_btn = $CompletePanel/HomeBtn

func _ready():
	complete_panel.visible = false
	continue_btn.visible = false
	_connect_buttons()

func _connect_buttons():
	undo_btn.pressed.connect(_on_undo_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)
	hint_btn.pressed.connect(_on_hint_pressed)
	next_btn.pressed.connect(_on_next_pressed)
	replay_btn.pressed.connect(_on_replay_pressed)
	home_btn.pressed.connect(_on_home_pressed)
	pause_btn.pressed.connect(_on_pause_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)

func _on_continue_pressed():
	if main:
		main.on_watch_continue()

func show_continue():
	continue_btn.visible = true

func hide_continue():
	continue_btn.visible = false

func _on_replay_pressed():
	complete_panel.visible = false
	_clear_active_bursts()
	if main:
		main.on_replay()

func _on_pause_pressed():
	if main:
		main.on_pause()

func update_for_level(level_num: int, _level_data: Dictionary):
	var pack_name = _get_pack_name(level_num)
	# Tint the header label with the pack's sector swatch so the player feels
	# the world identity of the pond they're in (matches BoxSelect card border).
	var swatch: Color = SectorThemesScript.get_theme_for_level(level_num).get("swatch", Color(1, 1, 1, 1))
	level_label.add_theme_color_override("font_color", swatch)

	continue_btn.visible = false
	if fill_bar:
		fill_bar.value = 0
	Music.set_fill_ratio(0.0)
	level_label.text = "%s · Pool %d" % [pack_name, level_num]
	fill_label.text = "Begin at the first stone."

	# Pack mode: hint button is visible, shows wallet remaining.
	hint_btn.visible = true
	hint_count.visible = true
	refresh_hint_wallet()
	_hide_invalid_overlay()

func set_daily_banner(mood_name: String):
	level_label.text = "Daily Pond · %s" % mood_name
	fill_label.text = "Begin at the first stone."
	fill_label.add_theme_color_override("font_color", Color("#9EA8DB"))
	# Hints are available in the daily; the petal cost naturally demotes hint
	# users on the leaderboard (which ranks petals first, time second).
	hint_btn.visible = true
	hint_count.visible = true
	refresh_hint_wallet()

# Called by Main after a hint is spent or granted via rewarded ad. Premium
# players see a dot instead of a number.
func refresh_hint_wallet():
	if GameData.is_premium:
		hint_count.text = "∞"
	else:
		hint_count.text = "%d" % GameData.hint_wallet

func update_stats(state):
	continue_btn.visible = false
	var fill_pct = int(state.get_fill_pct())
	var next_dot = state.get_next_dot_number()
	if fill_bar:
		fill_bar.value = fill_pct
	Music.set_fill_ratio(float(fill_pct) / 100.0)

	if next_dot == -1 and fill_pct < 100:
		fill_label.text = "Every stone is awake. Let the tide fill the pool."
		fill_label.add_theme_color_override("font_color", Color("#FFD166"))
		# Big red ✗ so the player sees at-a-glance they've stranded cells.
		_show_invalid_overlay()
	else:
		if next_dot > 0:
			fill_label.text = "Find stone %d." % next_dot
		else:
			fill_label.text = "Let the water settle."
		fill_label.add_theme_color_override("font_color", Color("#9EA8DB"))
		_hide_invalid_overlay()

	# Refresh wallet display (covers ad-rewarded refills mid-level).
	refresh_hint_wallet()

func show_fail(message: String):
	fill_label.text = _soft_fail_message(message)
	fill_label.add_theme_color_override("font_color", Color("#EF4444"))
	continue_btn.visible = true
	# Hard-fail paths (grid full + ended off the last stone) also deserve
	# the bright ✗ — show it here too so any failure state looks consistent.
	_show_invalid_overlay()

# Big centered red ✗ rendered via a custom Control so the strokes are crisp
# regardless of font fallback. Sits behind the HUD's button row but above
# the grid; mouse-filter is IGNORE so it never eats taps. Includes a soft
# dark backdrop that dims the grid behind the X so the red strokes have
# something to "land" against.
func _ensure_invalid_overlay() -> void:
	if _invalid_overlay and is_instance_valid(_invalid_overlay):
		return
	# Full-screen wrapper so we can dim everything behind the X.
	var wrapper := Control.new()
	wrapper.name = "InvalidOverlay"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.modulate.a = 0.0
	add_child(wrapper)
	# Sit below the button row so Undo / Reset / Hint stay tappable.
	move_child(wrapper, 0)

	# Backdrop — slight darken pulled across the whole screen.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(scrim)

	# The X itself — larger now (360×360), positioned over the grid center.
	var x_node := Control.new()
	x_node.name = "X"
	x_node.set_anchors_preset(Control.PRESET_CENTER)
	x_node.custom_minimum_size = Vector2(360, 360)
	x_node.size = Vector2(360, 360)
	x_node.position = Vector2(-180, -180)
	x_node.pivot_offset = Vector2(180, 180)
	x_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	x_node.draw.connect(_draw_invalid_overlay.bind(x_node))
	wrapper.add_child(x_node)
	_invalid_overlay = wrapper

func _draw_invalid_overlay(node: Control) -> void:
	var s: Vector2 = node.size
	var pad: float = 50.0
	var width: float = 28.0
	# Triple-layered red: outer glow, mid stroke, inner highlight — makes the
	# strokes feel lit instead of flat.
	var glow := Color("#EF4444")
	glow.a = 0.30
	var solid := Color("#EF4444")
	var highlight := Color("#FFB4B4")  # near-white pink for sheen on the X
	# Glow strokes (wider, lower alpha)
	node.draw_line(Vector2(pad, pad), Vector2(s.x - pad, s.y - pad), glow, width + 20.0, true)
	node.draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y - pad), glow, width + 20.0, true)
	# Solid red strokes
	node.draw_line(Vector2(pad, pad), Vector2(s.x - pad, s.y - pad), solid, width, true)
	node.draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y - pad), solid, width, true)
	# Thin inner highlight strokes (gives the X a sheen down the middle)
	node.draw_line(Vector2(pad, pad), Vector2(s.x - pad, s.y - pad), highlight, width * 0.30, true)
	node.draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y - pad), highlight, width * 0.30, true)

func _show_invalid_overlay() -> void:
	_ensure_invalid_overlay()
	if _invalid_overlay.modulate.a > 0.5:
		return  # already visible — don't restart the fade
	# Pulse-in: scale the X from 0.55 → 1.0 with a back-ease for a stamp feel.
	var x_node: Control = _invalid_overlay.get_node_or_null("X")
	if x_node:
		x_node.scale = Vector2(0.55, 0.55)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_invalid_overlay, "modulate:a", 1.0, 0.18)
	if x_node:
		tw.tween_property(x_node, "scale", Vector2.ONE, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_invalid_overlay() -> void:
	if not _invalid_overlay or not is_instance_valid(_invalid_overlay):
		return
	if _invalid_overlay.modulate.a < 0.05:
		return  # already hidden
	var tw := create_tween()
	tw.tween_property(_invalid_overlay, "modulate:a", 0.0, 0.20)

func show_complete(stars: int, time_sec: float, moves: int):
	complete_panel.visible = true
	_hide_invalid_overlay()

	# Build the star badge row dynamically and overlay it on top of the
	# StarsLabel rect. Hiding the label keeps Main.tscn untouched; the
	# StarBadge nodes own their geometry, halo, and pulse — see StarBadge.gd.
	stars_label.text = ""
	_build_star_row(stars)
	# Stats: clock time + move count. Players want to see how they did, not a
	# flavor sentence — the stars + drops toast already carry the celebration.
	var mins: int = int(time_sec) / 60
	var secs: int = int(time_sec) % 60
	stats_label.text = "%d:%02d  ·  %d moves" % [mins, secs, moves]

	# Drops reward toast: small "💧 +N" floats in below the stats text so the
	# player sees what they earned for shop cosmetics.
	_show_drops_toast(stars * 10)
	
	# Panel pops in with a slight overshoot
	complete_panel.pivot_offset = complete_panel.size / 2.0
	complete_panel.modulate = Color(1, 1, 1, 0)
	complete_panel.scale = Vector2(0.7, 0.7)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(complete_panel, "modulate", Color(1, 1, 1, 1), 0.25)
	tw.tween_property(complete_panel, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Star pops are now driven by _build_star_row (per-badge stagger).

	if stars > 0:
		_burst(stars)

# Build a row of 3 StarBadge nodes centered over the StarsLabel rect. Each
# badge animates in with a back-overshoot scale + 0.20s stagger so the player
# feels the petals "earn in" one at a time.
func _build_star_row(stars: int) -> void:
	# Remove any leftover row from a previous completion so they don't stack.
	var existing = complete_panel.get_node_or_null("StarRowWrap")
	if existing:
		existing.queue_free()
	# Wrapper Control owns the absolute rect (matches StarsLabel + a little
	# vertical padding for badge halos). The HBoxContainer inside fills the
	# wrapper and centers the row of badges.
	var wrap := Control.new()
	wrap.name = "StarRowWrap"
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# StarsLabel is now 100px tall (70→170) so the wrap can sit flush — no
	# extra padding needed for the badge halos.
	wrap.offset_left = stars_label.offset_left
	wrap.offset_top = stars_label.offset_top
	wrap.offset_right = stars_label.offset_right
	wrap.offset_bottom = stars_label.offset_bottom
	complete_panel.add_child(wrap)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(row)

	for i in range(3):
		var b: Control = StarBadgeScript.new()
		b.custom_minimum_size = Vector2(88, 88)
		b.set_earned(i < stars)
		b.pivot_offset = Vector2(44, 44)
		b.scale = Vector2(0.10, 0.10)
		row.add_child(b)
		# Earned badges punch harder (1.55x overshoot); unearned settle at
		# 1.15x so they don't fight for attention.
		var peak: float = 1.55 if i < stars else 1.15
		var tw := create_tween()
		tw.tween_interval(0.25 + 0.20 * float(i))
		tw.tween_property(b, "scale", Vector2(peak, peak), 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _show_drops_toast(amount: int) -> void:
	if amount <= 0:
		return
	# Remove any leftover toast from a previous completion so they don't stack.
	var existing = complete_panel.get_node_or_null("DropsToast")
	if existing:
		existing.queue_free()

	var toast := Label.new()
	toast.name = "DropsToast"
	toast.text = "💧  +%d drops" % amount
	toast.add_theme_font_size_override("font_size", 15)
	toast.add_theme_color_override("font_color", Color(0.45, 0.85, 1, 1))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Slot it at the top of the panel — the old "THE POOL BLOOMS" header used
	# to live in this empty 28–58 band, so there's clean space here that
	# doesn't collide with the petal icons or the Next button row below.
	toast.anchor_left = 0.0
	toast.anchor_right = 1.0
	toast.offset_left = 0.0
	toast.offset_right = 0.0
	toast.offset_top = 30.0
	toast.offset_bottom = 56.0
	toast.modulate.a = 0.0
	complete_panel.add_child(toast)

	# Brief drift-down + fade-in so it feels like the reward "settles" in.
	# Starts 10px higher and slides down into its final slot.
	toast.offset_top = 20.0
	toast.offset_bottom = 46.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(toast, "modulate:a", 1.0, 0.35).set_delay(0.55)
	tw.tween_property(toast, "offset_top", 30.0, 0.40) \
		.set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast, "offset_bottom", 56.0, 0.40) \
		.set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _burst(stars: int):
	# Free any leftover emitters from a previous level's completion so we
	# never accumulate particles across runs (player tapping Next rapidly).
	_clear_active_bursts()

	# Use the equipped palette's start/end colors so the celebration feels
	# personalized — Sakura players get pink, Ocean players get blue, etc.
	# Falls back to the original pink/amber if GameData isn't loaded.
	var palette_a := Color(0.925, 0.282, 0.6, 1.0)   # petal pink default
	var palette_b := Color(1.0, 0.82, 0.4, 1.0)      # amber default
	if GameData.has_method("get_equipped_palette_colors"):
		var pal: Dictionary = GameData.get_equipped_palette_colors()
		palette_a = pal["start"]
		palette_b = pal["end"]

	# Layer 1 — soft palette-A petals raining down across the whole HUD,
	# drifting and rotating like real falling blossoms. This is the dominant
	# effect and lives on the HUD root so it isn't clipped by the panel rect.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var petals := CPUParticles2D.new()
	petals.position = Vector2(viewport_size.x * 0.5, -30.0)
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.emission_rect_extents = Vector2(viewport_size.x * 0.55, 10.0)
	petals.one_shot = false
	petals.amount = 24 + stars * 14
	petals.lifetime = 4.5
	petals.preprocess = 1.6  # already raining when the panel pops in
	petals.direction = Vector2(0, 1)
	petals.spread = 30.0
	petals.initial_velocity_min = 35.0
	petals.initial_velocity_max = 95.0
	petals.gravity = Vector2(0, 55.0)
	petals.angular_velocity_min = -90.0
	petals.angular_velocity_max = 90.0
	petals.angle_min = 0.0
	petals.angle_max = 360.0
	petals.scale_amount_min = 2.0
	petals.scale_amount_max = 4.5
	petals.color = palette_a
	# Fade in fast, hold, fade out — keeps the air full but never opaque.
	# Colors derived from the equipped palette's primary so each player gets a
	# slightly different "rain".
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	ramp.colors = PackedColorArray([
		Color(palette_a.r, palette_a.g, palette_a.b, 0.0),
		Color(palette_a.r, palette_a.g, palette_a.b, 0.95),
		Color(palette_a.r, palette_a.g, palette_a.b, 0.7),
		Color(palette_a.r * 0.85, palette_a.g * 0.85, palette_a.b * 0.85, 0.0),
	])
	petals.color_ramp = ramp
	add_child(petals)
	petals.emitting = true

	# Layer 2 — quick amber sparkle pop right over the petals icon on the
	# completion card. Adds a punch of celebration energy that fades fast.
	var sparkles := CPUParticles2D.new()
	sparkles.position = Vector2(complete_panel.size.x * 0.5, 80.0)
	sparkles.one_shot = true
	sparkles.explosiveness = 0.95
	sparkles.amount = 18 + stars * 10
	sparkles.lifetime = 1.3
	sparkles.direction = Vector2(0, -1)
	sparkles.spread = 75.0
	sparkles.initial_velocity_min = 140.0
	sparkles.initial_velocity_max = 280.0
	sparkles.gravity = Vector2(0, 260.0)
	sparkles.angular_velocity_min = -180.0
	sparkles.angular_velocity_max = 180.0
	sparkles.scale_amount_min = 1.4
	sparkles.scale_amount_max = 2.8
	sparkles.color = palette_b
	# Sparkles use palette_b (the gradient's end color) so the burst has
	# secondary contrast with the falling petals.
	var spark_ramp := Gradient.new()
	spark_ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	spark_ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),   # bright white flash at birth
		Color(palette_b.r, palette_b.g, palette_b.b, 0.9),
		Color(palette_b.r * 0.85, palette_b.g * 0.85, palette_b.b * 0.85, 0.0),
	])
	sparkles.color_ramp = spark_ramp
	complete_panel.add_child(sparkles)
	sparkles.emitting = true

	_active_burst_nodes.append(petals)
	_active_burst_nodes.append(sparkles)

	# Stop the rain after a few seconds and free both emitters. The panel
	# itself stays up until the player picks Next / Replay / Home.
	var stop_petal_timer := get_tree().create_timer(3.5)
	stop_petal_timer.timeout.connect(func():
		if is_instance_valid(petals):
			petals.emitting = false)
	var cleanup_timer := get_tree().create_timer(8.0)
	cleanup_timer.timeout.connect(_clear_active_bursts)

func _clear_active_bursts() -> void:
	for n in _active_burst_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_active_burst_nodes.clear()

func _on_undo_pressed():
	if main:
		main.on_undo()

func _on_reset_pressed():
	if main:
		main.on_reset()

func _on_hint_pressed():
	if main:
		main.on_hint()

func _on_next_pressed():
	complete_panel.visible = false
	_clear_active_bursts()
	if main:
		main.on_next_level()

func _on_home_pressed():
	complete_panel.visible = false
	_clear_active_bursts()
	if main:
		main.on_home()

func _get_pack_name(level_num: int) -> String:
	# Single source of truth — must agree with BoxSelect, Leaderboard, and the
	# already-submitted Play Games leaderboard IDs.
	return SectorThemesScript.get_pack_name(SectorThemesScript.get_pack_index_for_level(level_num))

func _soft_fail_message(message: String) -> String:
	if message.begins_with("Path must end"):
		return "The tide should rest on the last stone."
	if message.begins_with("Reach dot"):
		return message.replace("Reach dot", "Visit stone")
	match message:
		"Start at dot 1":
			return "Begin at the first stone."
		"Must be adjacent":
			return "The water moves one tile at a time."
		"Blocked":
			return "That stone bank is closed."
		_:
			return "The water refuses that path."
