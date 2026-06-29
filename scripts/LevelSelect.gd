# LevelSelect.gd
# Per-pond level grid. Big numbered tiles + petal-row beneath, tinted with the
# pond's accent color. Cut-the-Rope-style scrollable grid.
extends Control

# Packs mirror BoxSelect.BOXES so navigation between the two screens stays
# consistent. If you add a pond to BoxSelect, add it here too.
const PACK_INFO := [
	{"name": "First Pond", "first": 1,   "last": 30},
	{"name": "Reed Path",  "first": 31,  "last": 80},
	{"name": "Stone Bend", "first": 81,  "last": 130},
	{"name": "Moon Pool",  "first": 131, "last": 200},
	{"name": "Garden",     "first": 201, "last": 9999},
]

const PACK_TINTS := [
	Color("#FFC04D"),  # amber  - First Pond
	Color("#F97316"),  # orange - Reed Path
	Color("#EF4444"),  # red    - Stone Bend
	Color("#8B5CF6"),  # violet - Moon Pool
	Color("#06D6A0"),  # teal   - Garden
]

# Garden has no real end (level 9999 is a sentinel). Cap how many tiles
# we actually render so the scroll list doesn't try to make 9000 buttons.
const GARDEN_VISIBLE_COUNT := 80

@onready var grid: GridContainer = $Scroll/Grid
@onready var pack_label: Label = $PackLabel
@onready var back_btn: Button = $BackBtn
@onready var prev_btn: Button = $PrevPack
@onready var next_btn: Button = $NextPack
@onready var title_label: Label = $TitleLabel
@onready var total_label: Label = $StatChip/TotalLabel
@onready var progress_bar: ProgressBar = $StatChip/ProgressBar

var _pack := 0

func _ready():
	Ads.show_banner()
	_make_static_chrome_touch_transparent()
	_make_nav_button_more_responsive(back_btn)
	_make_nav_button_more_responsive(prev_btn)
	_make_nav_button_more_responsive(next_btn)
	# Back returns to the pond carousel — the player came from there.
	back_btn.pressed.connect(func(): Transition.goto("res://scenes/BoxSelect.tscn"))
	prev_btn.pressed.connect(func(): _change_pack(-1))
	next_btn.pressed.connect(func(): _change_pack(1))
	# Open on whatever pond BoxSelect landed selected_level in.
	_pack = clampi(GameData.pack_index_for_level(GameData.selected_level), 0, PACK_INFO.size() - 1)
	title_label.text = "Pools"
	_rebuild()

func _make_static_chrome_touch_transparent() -> void:
	for node in [title_label, pack_label, total_label, progress_bar, $StatChip]:
		if node is Control:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _make_nav_button_more_responsive(button: BaseButton) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

func _change_pack(dir: int):
	_pack = clampi(_pack + dir, 0, PACK_INFO.size() - 1)
	_rebuild()

func _rebuild():
	var info: Dictionary = PACK_INFO[_pack]
	pack_label.text = "%s  (%d / %d)" % [info["name"], _pack + 1, PACK_INFO.size()]
	pack_label.add_theme_color_override("font_color", PACK_TINTS[_pack])
	prev_btn.disabled = _pack == 0
	next_btn.disabled = _pack == PACK_INFO.size() - 1
	# Update the pack's petal counter + progress bar so the header reflects
	# how much of the *current* pack the player has cleared.
	_refresh_progress(info)
	for c in grid.get_children():
		c.queue_free()
	var first: int = int(info["first"])
	var last: int = int(info["last"])
	# Cap the open-ended Garden pack to a sane window so we don't spawn
	# 9000 tiles. Players will scroll forever otherwise.
	if last - first + 1 > GARDEN_VISIBLE_COUNT:
		last = first + GARDEN_VISIBLE_COUNT - 1
	for level in range(first, last + 1):
		grid.add_child(_make_tile(level, _pack))

func _make_tile(level: int, pack_idx: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(80, 100)
	b.focus_mode = Control.FOCUS_NONE
	b.text = ""  # content composed as child controls

	var unlocked := GameData.is_unlocked(level)
	var stars := GameData.get_stars(level)
	var tint: Color = PACK_TINTS[pack_idx]

	# --- Tile background: neutral navy across all ponds; the tint only colors
	# the border and petals so each pond is identified by its accent edge
	# without painting the tile a muddy darkened version of its hue (the
	# darkened amber/orange looked like dirty mustard). Played levels get a
	# subtle blue lift so progress is still visible at a glance.
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(16)
	if unlocked:
		sb.bg_color = Color("#1E2748") if stars > 0 else Color("#16162C")
	else:
		sb.bg_color = Color("#0F0F22")
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = tint if unlocked else Color(tint.r, tint.g, tint.b, 0.18)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)

	# --- Content: VBox with number + petals row.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(margin)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	# Level number (or lock glyph)
	var num_label := Label.new()
	num_label.text = ("%d" % level) if unlocked else "🔒"
	num_label.add_theme_font_size_override("font_size", 28 if unlocked else 22)
	num_label.add_theme_color_override("font_color",
		Color(1, 1, 1, 1) if unlocked else Color(0.55, 0.60, 0.78, 1))
	num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(num_label)

	# Petals row
	var star_label := Label.new()
	if unlocked:
		var s := ""
		for i in range(3):
			s += "🌸" if i < stars else "⚪"
		star_label.text = s
	else:
		star_label.text = "— — —"
	star_label.add_theme_font_size_override("font_size", 13)
	star_label.add_theme_color_override("font_color",
		Color(1, 1, 1, 0.85) if unlocked else Color(0.4, 0.42, 0.55, 1))
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(star_label)

	if unlocked:
		b.pressed.connect(_on_pick.bind(level))
	else:
		b.disabled = true

	return b

func _on_pick(level: int):
	GameData.daily_mode = false
	GameData.selected_level = level
	Transition.goto("res://scenes/Main.tscn")

# Updates the petal counter ("🌸 N / M") and the thin bar under the title
# with stats scoped to the currently-active pack, matching BoxSelect's header.
func _refresh_progress(info: Dictionary) -> void:
	var first: int = int(info["first"])
	var last: int = int(info["last"])
	var visible_last: int = last
	# Cap Garden so the counter doesn't claim 9000-level max.
	if last - first + 1 > GARDEN_VISIBLE_COUNT:
		visible_last = first + GARDEN_VISIBLE_COUNT - 1
	var earned := 0
	for lvl in range(first, visible_last + 1):
		earned += int(GameData.stars.get(lvl, 0))
	var is_open_ended: bool = last >= 9999
	if is_open_ended:
		total_label.text = "🌸 %d earned" % earned
		progress_bar.value = 100.0
	else:
		var max_stars: int = (visible_last - first + 1) * 3
		total_label.text = "🌸 %d / %d" % [earned, max_stars]
		progress_bar.value = clampf(float(earned) / float(maxi(1, max_stars)), 0.0, 1.0) * 100.0
