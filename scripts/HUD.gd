# HUD.gd
# UI overlay: level info, fill counter, undo/reset/hint buttons, completion
extends CanvasLayer

const SectorThemesScript = preload("res://scripts/SectorThemes.gd")
const StarBadgeScript = preload("res://scripts/StarBadge.gd")

@onready var main = get_parent()

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
	if main:
		main.on_replay()

func _on_pause_pressed():
	if main:
		main.on_pause()

func update_for_level(level_num: int, level_data: Dictionary):
	var grid_size = level_data.get("grid_size", 5)
	var diff = level_data.get("difficulty", 0)
	var pack_name = _get_pack_name(level_num)
	
	continue_btn.visible = false
	if fill_bar:
		fill_bar.value = 0
	level_label.text = "%s – Level %d" % [pack_name, level_num]
	fill_label.text = "Connect 1→%d · fill every cell" % level_data.get("dots", []).size()
	
	# Update hint count
	if main and main.game_state:
		hint_count.text = "💡 %d" % main.game_state.hints_used

func update_stats(state):
	continue_btn.visible = false
	var fill_pct = int(state.get_fill_pct())
	var next_dot = state.get_next_dot_number()
	if fill_bar:
		fill_bar.value = fill_pct

	if next_dot == -1 and fill_pct < 100:
		# All dots linked but grid not full — this is the common confusion point
		fill_label.text = "All dots linked — now fill the rest! (%d%%)" % fill_pct
		fill_label.add_theme_color_override("font_color", Color(1, 0.82, 0.4, 1))
	else:
		fill_label.text = "%d%% filled" % fill_pct
		fill_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.78, 1))

	# Update hint count
	hint_count.text = "💡 %d" % state.hints_used

# Hint counter badge — hints used this level (resets at level start).
func update_hint_badge(count: int):
	if hint_count:
		hint_count.text = "💡 %d" % count

# Non-blocking toast that fades in/out near the bottom of the screen.
var _toast: Label = null
func show_toast(text: String):
	if _toast == null or not is_instance_valid(_toast):
		_toast = Label.new()
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast.anchor_left = 0.0
		_toast.anchor_right = 1.0
		_toast.anchor_top = 0.86
		_toast.anchor_bottom = 0.92
		_toast.add_theme_color_override("font_color", Color(1, 0.92, 0.7, 1))
		_toast.add_theme_font_size_override("font_size", 18)
		add_child(_toast)
	_toast.text = text
	_toast.modulate = Color(1, 1, 1, 0)
	var tw = create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)

func show_fail(message: String):
	fill_label.text = "%s — Undo or Reset" % message
	fill_label.add_theme_color_override("font_color", Color(0.94, 0.27, 0.27, 1))
	continue_btn.visible = true

func show_complete(stars: int, time_sec: float, moves: int):
	complete_panel.visible = true

	var mins = int(time_sec) / 60
	var secs = int(time_sec) % 60
	stats_label.text = "Time: %d:%02d  |  Moves: %d" % [mins, secs, moves]

	# Panel pops in with a slight overshoot
	complete_panel.pivot_offset = complete_panel.size / 2.0
	complete_panel.modulate = Color(1, 1, 1, 0)
	complete_panel.scale = Vector2(0.7, 0.7)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(complete_panel, "modulate", Color(1, 1, 1, 1), 0.25)
	tw.tween_property(complete_panel, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Stars: replace the text-based ⭐⭐☆ with three individually animated
	# Labels so each star pops in with overshoot scale and stagger — much
	# more rewarding than scaling the whole row at once.
	_show_animated_stars(stars)

	if stars > 0:
		_burst(stars)

func _show_animated_stars(stars: int):
	# Clear any previous animated stars (e.g. on level replay).
	for c in stars_label.get_children():
		c.queue_free()
	stars_label.text = ""

	# HBox centres the three star badges across the StarsLabel rect.
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars_label.add_child(hbox)

	var badges: Array = []
	for i in range(3):
		var b: Control = StarBadgeScript.new()
		b.earned = i < stars
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(b)
		badges.append(b)

	# Wait one frame so HBoxContainer assigns sizes, then animate each star
	# with overshoot scale → settle. Staggered so they land in sequence and
	# unearned stars get a smaller, gentler "miss" animation.
	await get_tree().process_frame
	for i in range(badges.size()):
		var b: Control = badges[i]
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(0.1, 0.1)
		var peak: Vector2 = Vector2(1.55, 1.55) if b.earned else Vector2(1.15, 1.15)
		var t := create_tween()
		t.tween_interval(0.20 + float(i) * 0.20)
		t.tween_property(b, "scale", peak, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _burst(stars: int):
	var p := CPUParticles2D.new()
	p.position = Vector2(complete_panel.size.x / 2.0, 70.0)
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 14 + stars * 10
	p.lifetime = 1.1
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 480)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color(1, 0.82, 0.4, 1)
	complete_panel.add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())

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
	if main:
		main.on_next_level()

func _on_home_pressed():
	complete_panel.visible = false
	if main:
		main.on_home()

func _get_pack_name(level_num: int) -> String:
	return SectorThemesScript.get_pack_name(SectorThemesScript.get_pack_index_for_level(level_num))
