# HUD.gd
# UI overlay: level info, fill counter, undo/reset/hint buttons, completion
extends CanvasLayer

@onready var main = get_parent()

# UI References
@onready var level_label = $LevelLabel
@onready var fill_label = $FillLabel
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
	level_label.text = "%s – Level %d" % [pack_name, level_num]
	fill_label.text = "Connect 1→%d · fill every cell" % level_data.get("dots", []).size()
	
	# Update hint count
	if main and main.game_state:
		hint_count.text = "💡 %d" % main.game_state.hints_used

func update_stats(state):
	continue_btn.visible = false
	var fill_pct = int(state.get_fill_pct())
	var next_dot = state.get_next_dot_number()

	if next_dot == -1 and fill_pct < 100:
		# All dots linked but grid not full — this is the common confusion point
		fill_label.text = "All dots linked — now fill the rest! (%d%%)" % fill_pct
		fill_label.add_theme_color_override("font_color", Color(1, 0.82, 0.4, 1))
	else:
		fill_label.text = "%d%% filled" % fill_pct
		fill_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.78, 1))

	# Update hint count
	hint_count.text = "💡 %d" % state.hints_used

func show_fail(message: String):
	fill_label.text = "%s — Undo or Reset" % message
	fill_label.add_theme_color_override("font_color", Color(0.94, 0.27, 0.27, 1))
	continue_btn.visible = true

func show_complete(stars: int, time_sec: float, moves: int):
	complete_panel.visible = true
	
	var star_text = ""
	for i in range(3):
		if i < stars:
			star_text += "⭐"
		else:
			star_text += "☆"
	stars_label.text = star_text
	
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

	# Stars pop in one-by-one
	stars_label.pivot_offset = stars_label.size / 2.0
	stars_label.scale = Vector2(0.2, 0.2)
	var st = create_tween()
	st.tween_interval(0.25)
	st.tween_property(stars_label, "scale", Vector2(1.15, 1.15), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	st.tween_property(stars_label, "scale", Vector2.ONE, 0.12)

	if stars > 0:
		_burst(stars)

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
	var packs = ["Tutorial", "Sunrise", "Nebula", "Void", "Nova", "Singularity", "Infinite"]
	var idx = mini((level_num - 1) / 40, packs.size() - 1)
	return packs[idx]
