# LeaderboardScreen.gd
# In-game ranking view styled to match the rest of ZipPath. Acts as a thin
# presentation layer over Leaderboard.gd — the autoload handles the actual
# Play Games calls and emits a clean `scores_loaded` signal.
#
# Use Leaderboard.show_in_game(initial_idx) (added on the autoload) or call
# Transition.goto(... ) with selected_board_idx set, depending on how the
# caller wants to land here.
extends Control

# Boards must match Leaderboard.LB_DAILY + Leaderboard.LB_PACKS order:
#   0 = Daily Pond,  1..5 = First Pond / Reed Path / Stone Bend / Moon Pool / Garden
const BOARDS := [
	{"name": "Daily Pond", "tint": Color("#EC4899"), "icon": "res://assets/ui/leaderboard/lb_daily.png"},
	{"name": "First Pond", "tint": Color("#FFC04D"), "icon": "res://assets/ui/leaderboard/lb_first_pond.png"},
	{"name": "Reed Path",  "tint": Color("#F97316"), "icon": "res://assets/ui/leaderboard/lb_reed_path.png"},
	{"name": "Stone Bend", "tint": Color("#EF4444"), "icon": "res://assets/ui/leaderboard/lb_stone_bend.png"},
	{"name": "Moon Pool",  "tint": Color("#8B5CF6"), "icon": "res://assets/ui/leaderboard/lb_moon_pool.png"},
	{"name": "Garden",     "tint": Color("#06D6A0"), "icon": "res://assets/ui/leaderboard/lb_garden.png"},
]

@onready var back_btn: Button = $BackBtn
@onready var prev_btn: Button = $PrevBtn
@onready var next_btn: Button = $NextBtn
@onready var board_label: Label = $BoardLabel
@onready var board_icon: TextureRect = $BoardIcon
@onready var status_label: Label = $StatusLabel
@onready var refresh_btn: Button = $RefreshBtn
@onready var list: VBoxContainer = $Scroll/List

var _idx: int = 0
# Where to go on Back. Caller can override before _ready by setting `return_to`.
var return_to: String = "res://scenes/Home.tscn"
# Token bumped on every load request; the timeout closure checks it to decide
# whether its scheduled "couldn't load" message is still relevant.
var _load_token: int = 0

func _ready() -> void:
	Ads.show_banner()
	# Honour an "initial board" choice the caller may have stashed on GameData.
	_idx = clampi(GameData.selected_leaderboard_idx, 0, BOARDS.size() - 1)
	back_btn.pressed.connect(_on_back)
	prev_btn.pressed.connect(func(): _change(-1))
	next_btn.pressed.connect(func(): _change(1))
	refresh_btn.pressed.connect(func():
		# Re-kick sign-in (which backfills all pack totals) and re-fetch.
		Leaderboard.sign_in()
		_refresh())
	if not Leaderboard.scores_loaded.is_connected(_on_scores_loaded):
		Leaderboard.scores_loaded.connect(_on_scores_loaded)
	_refresh()

func _change(dir: int) -> void:
	var new_idx := clampi(_idx + dir, 0, BOARDS.size() - 1)
	if new_idx == _idx:
		return
	_idx = new_idx
	_refresh()

func _refresh() -> void:
	var info: Dictionary = BOARDS[_idx]
	# Sign-in status is rendered into the title line so the player can see at
	# a glance whether Play Games is connected. Without this it's impossible
	# to tell "no scores yet" from "we never reached Google in the first place".
	var sign_in_tag := ""
	if OS.get_name() == "Android":
		sign_in_tag = "   ✓" if Leaderboard.signed_in else "   ⚠"
	board_label.text = "%s  (%d / %d)%s" % [info["name"], _idx + 1, BOARDS.size(), sign_in_tag]
	board_label.add_theme_color_override("font_color", info["tint"])
	# Swap the board's icon. ResourceLoader.exists guards against typos / missing
	# files so the screen still renders if an icon is absent.
	var icon_path: String = str(info.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		board_icon.texture = load(icon_path)
		board_icon.visible = true
	else:
		board_icon.texture = null
		board_icon.visible = false
	prev_btn.disabled = _idx == 0
	next_btn.disabled = _idx == BOARDS.size() - 1
	for c in list.get_children():
		c.queue_free()
	status_label.text = "Loading..."
	status_label.visible = true
	_load_token += 1
	var my_token: int = _load_token
	Leaderboard.load_top(_id_for_idx(_idx), 25)
	# Failsafe: if the plugin never fires `scores_loaded` (no network, sign-in
	# pending, or empty board on Android with no submissions yet), at least
	# the screen tells the player what happened instead of staying blank.
	get_tree().create_timer(6.0).timeout.connect(func():
		# Stale timeout — newer load already started or already resolved.
		if my_token != _load_token:
			return
		# Scores already rendered.
		if list.get_child_count() > 0:
			return
		# Tailor the message based on what we actually know about the state.
		if OS.get_name() == "Android" and not Leaderboard.signed_in:
			status_label.text = "Not signed in to Google Play Games.\nTap ↻ Refresh to retry."
		else:
			status_label.text = "Couldn't load this board.\nCheck your connection, or try another."
		status_label.visible = true)

func _id_for_idx(i: int) -> String:
	if i == 0:
		return Leaderboard.LB_DAILY
	if i - 1 < Leaderboard.LB_PACKS.size():
		return str(Leaderboard.LB_PACKS[i - 1])
	return ""

func _on_scores_loaded(leaderboard_id: String, scores: Array) -> void:
	# Ignore stale results from boards the player has since scrolled past.
	if leaderboard_id != _id_for_idx(_idx):
		return
	# Invalidate any pending "Couldn't load" timeout for this load.
	_load_token += 1
	for c in list.get_children():
		c.queue_free()
	if scores.is_empty():
		status_label.text = "No scores yet — be the first!"
		status_label.visible = true
		return
	status_label.visible = false
	var tint: Color = BOARDS[_idx]["tint"]
	for row in scores:
		list.add_child(_make_row(row, tint))

func _make_row(row: Dictionary, tint: Color) -> Control:
	# Single horizontal panel: rank circle | name | score
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	# Self row gets a brighter slab + tint border so the player spots it fast.
	var is_self: bool = bool(row.get("is_self", false))
	sb.bg_color = Color("#1E2748") if is_self else Color("#16162C")
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = tint if is_self else Color("#2A2A4E")
	panel.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Rank "badge" — small tinted square with the rank number. Top-3 use
	# medal-ish colors for a tiny dopamine hit.
	var rank_panel := PanelContainer.new()
	rank_panel.custom_minimum_size = Vector2(44, 44)
	var rsb := StyleBoxFlat.new()
	rsb.set_corner_radius_all(10)
	rsb.bg_color = _rank_color(int(row["rank"]))
	rank_panel.add_theme_stylebox_override("panel", rsb)
	var rank_label := Label.new()
	rank_label.text = "%d" % int(row["rank"])
	rank_label.add_theme_font_size_override("font_size", 18)
	rank_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_panel.add_child(rank_label)
	hbox.add_child(rank_panel)

	# Name (left-aligned, expands)
	var name_label := Label.new()
	name_label.text = str(row["name"]) if str(row["name"]) != "" else "Anonymous"
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1) if is_self else Color(0.88, 0.92, 1, 1))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_label)

	# Score (petals + time)
	var score_label := Label.new()
	score_label.text = _format_score(int(row.get("petals", 0)), float(row.get("time_sec", 0.0)))
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color(1, 0.82, 0.4, 1))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(score_label)

	return panel

func _rank_color(rank: int) -> Color:
	match rank:
		1: return Color("#FFD166")  # gold
		2: return Color("#C0C0C0")  # silver
		3: return Color("#CD7F32")  # bronze
		_: return Color("#1A1A30")  # neutral

func _format_score(petals: int, time_sec: float) -> String:
	# "🌸 3 · 0:42" — petals dominate, time as tiebreak.
	var mins: int = int(time_sec) / 60
	var secs: int = int(time_sec) % 60
	return "🌸 %d  ·  %d:%02d" % [petals, mins, secs]

func _on_back() -> void:
	Transition.goto(return_to)
