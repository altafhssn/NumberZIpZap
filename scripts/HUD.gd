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
@onready var complete_panel = $CompletePanel
@onready var stars_label = $CompletePanel/StarsLabel
@onready var stats_label = $CompletePanel/StatsLabel
@onready var next_btn = $CompletePanel/NextBtn
@onready var home_btn = $CompletePanel/HomeBtn

func _ready():
	complete_panel.visible = false
	_connect_buttons()

func _connect_buttons():
	undo_btn.pressed.connect(_on_undo_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)
	hint_btn.pressed.connect(_on_hint_pressed)
	next_btn.pressed.connect(_on_next_pressed)
	home_btn.pressed.connect(_on_home_pressed)

func update_for_level(level_num: int, level_data: Dictionary):
	var grid_size = level_data.get("grid_size", 5)
	var diff = level_data.get("difficulty", 0)
	var pack_name = _get_pack_name(level_num)
	
	level_label.text = "%s – Level %d" % [pack_name, level_num]
	fill_label.text = "Connect 1→%d · fill every cell" % level_data.get("dots", []).size()
	
	# Update hint count
	if main and main.game_state:
		hint_count.text = "💡 %d" % main.game_state.hints_used

func update_stats(state):
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
	
	# Animate in
	var tween = create_tween()
	complete_panel.modulate = Color(1, 1, 1, 0)
	tween.tween_property(complete_panel, "modulate", Color(1, 1, 1, 1), 0.5)

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
