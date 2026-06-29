# BoxSelect.gd
# Picks a grid-size "box" to play. Each box gates a level range and
# requires a minimum total petals to unlock.
extends Control

const SectorThemesScript = preload("res://scripts/SectorThemes.gd")

const BOXES := [
	{"name": "First Pond", "grid": 7, "first": 1,   "last": 30,   "stars": 0,   "icon": "res://assets/ui/leaderboard/lb_first_pond.png"},
	{"name": "Reed Path",  "grid": 9, "first": 31,  "last": 80,   "stars": 50,  "icon": "res://assets/ui/leaderboard/lb_reed_path.png"},
	{"name": "Stone Bend", "grid": 9, "first": 81,  "last": 130,  "stars": 130, "icon": "res://assets/ui/leaderboard/lb_stone_bend.png"},
	{"name": "Moon Pool",  "grid": 9, "first": 131, "last": 200,  "stars": 250, "icon": "res://assets/ui/leaderboard/lb_moon_pool.png"},
	{"name": "Garden",     "grid": 9, "first": 201, "last": 9999, "stars": 400, "icon": "res://assets/ui/leaderboard/lb_garden.png"},
]

# Tint source: SectorThemes.swatch — keeps BoxSelect, HUD header, and the
# in-puzzle theming all reading from the same per-pack palette.
static func _box_tint(idx: int) -> Color:
	return SectorThemesScript.get_theme(idx).get("swatch", Color(1, 1, 1, 1))

@onready var grid: HBoxContainer = $Scroll/List
@onready var back_btn: Button = $BackBtn
@onready var total_label: Label = $StatChip/TotalLabel
@onready var progress_bar: ProgressBar = $StatChip/ProgressBar

# Card sized like a deck-pack tile (Cut-the-Rope / Toon Blast style):
# fixed compact size, the BOX badge is the visual anchor — no vertical stretch.
# ~280×460 fits one full card + meaningful peek of the next on a 480-wide phone.
const CARD_WIDTH := 280.0
const CARD_HEIGHT := 460.0
const SIDE_PADDING := 20.0  # matches HBoxContainer separation for symmetry

func _ready():
	Ads.show_banner()
	back_btn.pressed.connect(func(): Transition.goto("res://scenes/Home.tscn"))
	_update_total()
	_build()

func _update_total():
	var total = _total_stars()
	var next_thr := -1
	for box in BOXES:
		if total < int(box["stars"]):
			next_thr = int(box["stars"])
			break
	if next_thr > 0:
		# Compact: "🌸 21 / 40" with the bar tracking 21/40 of the way to the
		# next unlock. Reads as progress, not as a sentence.
		total_label.text = "🌸  %d  /  %d" % [total, next_thr]
		progress_bar.value = clampf(float(total) / float(next_thr), 0.0, 1.0) * 100.0
	else:
		total_label.text = "🌸  %d  ·  all ponds open" % total
		progress_bar.value = 100.0

func _total_stars() -> int:
	var s := 0
	for k in GameData.stars.keys():
		s += int(GameData.stars[k])
	return s

func _build():
	for c in grid.get_children():
		c.queue_free()
	var total := _total_stars()
	# Left spacer so the first card starts with breathing room from the edge.
	var lead := Control.new()
	lead.custom_minimum_size = Vector2(SIDE_PADDING, 0)
	grid.add_child(lead)
	for i in range(BOXES.size()):
		var box: Dictionary = BOXES[i]
		grid.add_child(_make_tile(box, i, total))
	# Trailing spacer so the last card can scroll fully into view.
	var trail := Control.new()
	trail.custom_minimum_size = Vector2(SIDE_PADDING, 0)
	grid.add_child(trail)

func _make_tile(box: Dictionary, idx: int, total_stars: int) -> Control:
	var b := Button.new()
	# Fixed size — no vertical stretch. SHRINK_CENTER centers the card inside
	# the scroll viewport so empty space sits *around* the card, not inside it.
	b.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.text = ""  # all content is composed as child controls

	var unlocked: bool = total_stars >= int(box["stars"])
	var tint: Color = _box_tint(idx)

	# --- Card background ---
	# Neutral navy bg across all ponds; tint only colors the border and the
	# preview path inside. Avoids the muddy-mustard look that the darkened
	# warm tints (amber/orange) produced. Mirrors LevelSelect's treatment.
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(22)
	sb.bg_color = Color("#16162C") if unlocked else Color("#0F0F22")
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = (tint if unlocked else Color(tint.r, tint.g, tint.b, 0.20))
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 12
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)

	# --- Content layout: MarginContainer > VBoxContainer ---
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(margin)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	# --- Pond preview: NxN grid + sample path. THIS is the visual identity:
	# each pond looks unique (different grid size + bespoke path), and the
	# tint colors the path so the box's accent reads even from peek view.
	# A lock glyph stacks on top for locked ponds. ---
	var preview_size := Vector2(180, 180)
	var preview_wrap := Control.new()
	preview_wrap.custom_minimum_size = preview_size
	preview_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(preview_wrap)

	# Each pack's visual identity is now the leaderboard PNG (same file used by
	# Play Console, the in-game leaderboard screen, and this BoxSelect card).
	# Falls back to a flat tint panel if the icon file is missing.
	var icon_path: String = str(box.get("icon", ""))
	var icon_rect: TextureRect = null
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_rect = TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.texture = load(icon_path)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			# Dim + slight desaturation for locked packs so the lock stamp pops.
			icon_rect.modulate = Color(0.45, 0.48, 0.55, 0.85)
		preview_wrap.add_child(icon_rect)

	# Subtle press feedback: pulse the icon's brightness on tap-and-hold.
	if unlocked and icon_rect != null:
		b.button_down.connect(func():
			icon_rect.modulate = Color(1.15, 1.15, 1.15, 1.0))
		b.button_up.connect(func():
			icon_rect.modulate = Color(1, 1, 1, 1))

	if not unlocked:
		var lock_label := Label.new()
		lock_label.text = "🔒"
		lock_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_label.add_theme_font_size_override("font_size", 72)
		lock_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_wrap.add_child(lock_label)

	vb.add_child(_spacer(14))

	# --- Title ---
	var title_color: Color = Color(1, 1, 1, 1) if unlocked else Color(0.72, 0.76, 0.92, 1)
	vb.add_child(_card_label(str(box["name"]), 26, title_color))

	# --- Meta: grid size + level range ---
	var meta_color: Color = Color(1, 1, 1, 0.70) if unlocked else Color(0.55, 0.60, 0.78, 1)
	var range_text: String
	if int(box["last"]) >= 9999:
		range_text = "Pools %d+" % int(box["first"])
	else:
		range_text = "Pools %d–%d" % [int(box["first"]), int(box["last"])]
	vb.add_child(_card_label("%d×%d  ·  %s" % [
		int(box["grid"]), int(box["grid"]), range_text
	], 14, meta_color))

	vb.add_child(_spacer(18))

	# --- Bottom: petal count (or unlock requirement) ---
	var earned := 0
	for lvl in range(int(box["first"]), int(box["last"]) + 1):
		earned += int(GameData.stars.get(lvl, 0))
	# Garden (and any open-ended pack) reports just the earned count instead
	# of a misleading "X / 29397" denominator.
	var is_open_ended: bool = int(box["last"]) >= 9999
	var max_stars: int = (int(box["last"]) - int(box["first"]) + 1) * 3
	var bar_ratio := 0.0

	# Stat panel: petal count chip + progress bar, grouped into a single
	# rounded surface so the bottom of the card feels intentional instead of
	# two stray text labels.
	var stat_panel := PanelContainer.new()
	var stat_sb := StyleBoxFlat.new()
	stat_sb.set_corner_radius_all(14)
	stat_sb.bg_color = Color(0.04, 0.04, 0.09, 0.55)
	stat_sb.border_width_left = 1
	stat_sb.border_width_top = 1
	stat_sb.border_width_right = 1
	stat_sb.border_width_bottom = 1
	stat_sb.border_color = Color(tint.r, tint.g, tint.b, 0.35) if unlocked else Color(0.18, 0.18, 0.30, 1)
	stat_sb.content_margin_left = 16
	stat_sb.content_margin_right = 16
	stat_sb.content_margin_top = 14
	stat_sb.content_margin_bottom = 14
	stat_panel.add_theme_stylebox_override("panel", stat_sb)
	stat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(stat_panel)

	var stat_vb := VBoxContainer.new()
	stat_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_vb.add_theme_constant_override("separation", 10)
	stat_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_panel.add_child(stat_vb)

	if unlocked:
		if is_open_ended:
			stat_vb.add_child(_card_label("🌸  %d earned" % earned, 26, Color(1, 0.82, 0.4, 1)))
			bar_ratio = 1.0  # full bar for the endless pack
		else:
			stat_vb.add_child(_card_label("🌸  %d / %d" % [earned, max_stars], 26, Color(1, 0.82, 0.4, 1)))
			bar_ratio = float(earned) / float(maxi(1, max_stars))
		b.pressed.connect(_on_pick.bind(box))
	else:
		var to_go: int = int(box["stars"]) - total_stars
		stat_vb.add_child(_card_label("Need 🌸 %d" % int(box["stars"]), 22, Color(0.85, 0.88, 1, 1)))
		stat_vb.add_child(_card_label("%d more petals" % to_go, 13, Color(0.62, 0.66, 0.86, 1)))
		b.disabled = true
		bar_ratio = float(total_stars) / float(maxi(1, int(box["stars"])))

	# --- Progress bar inside the stat panel ---
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = clampf(bar_ratio, 0.0, 1.0) * 100.0
	bar.custom_minimum_size = Vector2(0, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.10, 0.10, 0.18, 1)
	bar_bg.set_corner_radius_all(6)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = (tint if unlocked else Color(tint.r, tint.g, tint.b, 0.55))
	bar_fg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fg)
	stat_vb.add_child(bar)

	return b

# Convenience: centered label with a single style change point.
func _card_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _on_pick(box: Dictionary):
	# Land LevelSelect on the furthest unlocked level inside this pond.
	# selected_level is used by LevelSelect to choose which pack to open on.
	var start: int = int(box["first"])
	var last_level: int = int(box["last"])
	var target := start
	for lvl in range(start, last_level + 1):
		if GameData.is_unlocked(lvl):
			target = lvl
		else:
			break
	GameData.daily_mode = false
	GameData.selected_level = target
	Transition.goto("res://scenes/LevelSelect.tscn")
