# LevelSelect.gd
extends Control

const SectorThemesScript = preload("res://scripts/SectorThemes.gd")

const LEVELS_PER_PACK := 40
const PACK_NAMES := ["Tutorial", "Sunrise", "Nebula", "Void", "Nova", "Singularity", "Infinite"]

@onready var grid: GridContainer = $Scroll/Grid
@onready var pack_label: Label = $PackLabel
@onready var back_btn: Button = $BackBtn
@onready var prev_btn: Button = $PrevPack
@onready var next_btn: Button = $NextPack

var _pack := 0

func _ready():
	Ads.show_banner()
	back_btn.pressed.connect(func(): Transition.goto("res://scenes/Home.tscn"))
	prev_btn.pressed.connect(func(): _change_pack(-1))
	next_btn.pressed.connect(func(): _change_pack(1))
	# Open on the pack containing the furthest unlocked level
	_pack = (GameData.max_unlocked - 1) / LEVELS_PER_PACK
	_pack = clampi(_pack, 0, PACK_NAMES.size() - 1)
	_rebuild()

func _change_pack(dir: int):
	_pack = clampi(_pack + dir, 0, PACK_NAMES.size() - 1)
	_rebuild()

func _rebuild():
	# Tint the pack label and prepend a swatch glyph in the pack's ribbon
	# color so the player previews the world before entering. The swatch uses
	# a full BBCode block — we install a RichTextLabel-friendly format only
	# if the label supports it; otherwise we fall back to plain text.
	var theme: Dictionary = SectorThemesScript.get_theme(_pack, _pack * LEVELS_PER_PACK + 1)
	var ribbon: Color = theme.get("ribbon", Color.WHITE)
	var accent: Color = theme.get("accent", Color.WHITE)
	pack_label.text = "%s  (%d / %d)" % [PACK_NAMES[_pack], _pack + 1, PACK_NAMES.size()]
	pack_label.add_theme_color_override("font_color", accent)
	prev_btn.disabled = _pack == 0
	next_btn.disabled = _pack == PACK_NAMES.size() - 1
	for c in grid.get_children():
		c.queue_free()
	# Swatch row: one tile colored to the pack's ribbon + accent, sitting at
	# the top of the grid as a "you're entering this world" preview.
	grid.add_child(_make_swatch(ribbon, accent, PACK_NAMES[_pack]))
	for i in range(LEVELS_PER_PACK):
		var level := _pack * LEVELS_PER_PACK + i + 1
		grid.add_child(_make_tile(level))

func _make_tile(level: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(78, 78)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)

	var unlocked := GameData.is_unlocked(level)
	var stars := GameData.get_stars(level)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if unlocked:
		sb.bg_color = Color("#1C1C38") if stars == 0 else Color("#243a8a")
		sb.border_width_bottom = 1
		sb.border_width_top = 1
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_color = Color("#4361EE") if stars > 0 else Color("#2A2A4E")
		var star_str := ""
		for s in range(3):
			star_str += "★" if s < stars else "·"
		b.text = "%d\n%s" % [level, star_str]
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		b.pressed.connect(_on_pick.bind(level))
	else:
		sb.bg_color = Color(0.07, 0.07, 0.13, 0.7)
		b.text = "🔒"
		b.disabled = true
		b.add_theme_color_override("font_color_disabled", Color(0.4, 0.42, 0.55, 1))

	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)
	return b

# Read-only swatch tile shown at the top of the pack's grid. Picks up the
# pack's ribbon as the fill and accent as the border.
func _make_swatch(ribbon: Color, accent: Color, pack_name: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(78, 78)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = true
	b.text = pack_name.substr(0, 1)
	b.add_theme_color_override("font_color_disabled", Color(1, 1, 1, 0.95))
	b.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ribbon
	sb.set_corner_radius_all(14)
	sb.border_width_bottom = 2
	sb.border_width_top = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = accent
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("disabled", sb)
	return b

func _on_pick(level: int):
	GameData.selected_level = level
	Transition.goto("res://scenes/Main.tscn")
