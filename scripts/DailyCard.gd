# DailyCard.gd
# The end-of-daily moment: a calm result card with a spoiler-free,
# copy-to-share summary (the Wordle-style return-and-recruit loop) and a
# gentle, never-punished streak. Built entirely in code — no .tscn needed.
extends CanvasLayer

signal home_requested

const MONTHS := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var _mood := "Dawn"
var _petals := 0
var _time_sec := 0.0
var _panel: Control

func _ready():
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(mood_name: String, petals: int, time_sec: float):
	_mood = mood_name
	_petals = clampi(petals, 0, 3)
	_time_sec = time_sec
	_build()

func _date_label() -> String:
	var d = Time.get_date_dict_from_system()
	var m: int = clampi(d.month, 1, 12)
	return "%s %d" % [MONTHS[m], d.day]

func _time_label() -> String:
	var mins := int(_time_sec) / 60
	var secs := int(_time_sec) % 60
	return "%d:%02d" % [mins, secs]

func _petals_glyphs() -> String:
	var out := ""
	for i in range(3):
		out += "🌸" if i < _petals else "⚪"
	return out

func _build():
	# Dim, input-blocking backdrop
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Full-rect center container reliably centers the card on any screen.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Card panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#16162C")
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 26
	sb.content_margin_bottom = 22
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 20
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color("#2A2A4E")
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	_panel = panel

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vb)

	vb.add_child(_label("Daily Pond", 26, Color("#FFFFFF"), 1))
	vb.add_child(_label("%s · %s" % [_date_label(), _mood], 16, Color("#9EA8DB"), 1))

	# Petals
	var petals := _label(_petals_glyphs(), 34, Color("#4361EE"), 1)
	petals.add_theme_constant_override("line_spacing", 0)
	vb.add_child(_spacer(4))
	vb.add_child(petals)

	# Streak
	var streak := GameData.daily_streak
	var streak_txt := ""
	if streak <= 0:
		streak_txt = "First pond tended."
	elif streak == 1:
		streak_txt = "🔥 1 day streak"
	else:
		streak_txt = "🔥 %d day streak" % streak
	vb.add_child(_label(streak_txt, 18, Color("#FFD166"), 1))
	if GameData.daily_best > streak and GameData.daily_best > 1:
		vb.add_child(_label("best %d" % GameData.daily_best, 13, Color("#9EA8DB"), 1))

	vb.add_child(_label("The pool blooms.", 14, Color("#9EA8DB"), 1))
	vb.add_child(_spacer(8))

	# Buttons
	var lb := _make_button("🏆  View Leaderboard", true)
	lb.pressed.connect(_on_leaderboard)
	vb.add_child(lb)

	var home := _make_button("Home", false)
	home.pressed.connect(_on_home)
	vb.add_child(home)

	# Pop-in (deferred one frame so the panel has a real size for its pivot)
	panel.modulate = Color(1, 1, 1, 0)
	panel.scale = Vector2(0.82, 0.82)
	_animate_in.call_deferred(dim, panel)

func _animate_in(dim: ColorRect, panel: Control):
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim, "color:a", 0.45, 0.25)
	tw.tween_property(panel, "modulate:a", 1.0, 0.28)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _label(text: String, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	# Stretch to fill the card width so horizontal_alignment actually centers
	# the text within the panel, not just within the label's own text width.
	# Without this, short labels ("Jul 2 · Dusk") sit left-flush in the VBox.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _make_button(text: String, accent: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if accent:
		sb.bg_color = Color("#4361EE")
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		sb.bg_color = Color("#0F0F22")
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color("#2A2A4E")
		b.add_theme_color_override("font_color", Color("#FFFFFF"))
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	return b

func _on_leaderboard():
	# Open the in-game leaderboard screen, defaulting to the Daily Pond board.
	GameData.selected_leaderboard_idx = 0
	Transition.goto("res://scenes/LeaderboardScreen.tscn")

func _on_home():
	emit_signal("home_requested")
