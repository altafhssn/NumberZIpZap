# BoxSelect.gd
# Picks a grid-size "box" to play. Each box gates a level range and
# requires a minimum total stars to unlock.
extends Control

const BOXES := [
	{"name": "Spark",    "grid": 5, "first": 1,  "last": 10, "stars": 0},
	{"name": "Glow",     "grid": 6, "first": 11, "last": 20, "stars": 18},
	{"name": "Ember",    "grid": 7, "first": 21, "last": 30, "stars": 40},
	{"name": "Nova",     "grid": 8, "first": 31, "last": 40, "stars": 65},
	{"name": "Infinite", "grid": 9, "first": 41, "last": 80, "stars": 95},
]

const BOX_TINTS := [
	Color("#FFC04D"),  # amber
	Color("#F97316"),  # orange
	Color("#EF4444"),  # red
	Color("#8B5CF6"),  # violet
	Color("#06D6A0"),  # teal
]

@onready var grid: VBoxContainer = $Scroll/List
@onready var back_btn: Button = $BackBtn
@onready var total_label: Label = $TotalLabel

func _ready():
	Ads.show_banner()
	back_btn.pressed.connect(func(): Transition.goto("res://scenes/Home.tscn"))
	total_label.text = "★ %d  total stars" % _total_stars()
	_build()

func _total_stars() -> int:
	var s := 0
	for k in GameData.stars.keys():
		s += int(GameData.stars[k])
	return s

func _build():
	for c in grid.get_children():
		c.queue_free()
	var total := _total_stars()
	for i in range(BOXES.size()):
		var box: Dictionary = BOXES[i]
		grid.add_child(_make_tile(box, i, total))

func _make_tile(box: Dictionary, idx: int, total_stars: int) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 120)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)

	var unlocked: bool = total_stars >= int(box["stars"])
	var tint: Color = BOX_TINTS[idx]
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.bg_color = (tint.darkened(0.7) if unlocked else Color("#11112A"))
	sb.border_width_bottom = 2
	sb.border_width_top = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = (tint if unlocked else Color("#2A2A4E"))
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)

	# Per-box progress
	var earned := 0
	for lvl in range(int(box["first"]), int(box["last"]) + 1):
		earned += int(GameData.stars.get(lvl, 0))
	var max_stars: int = (int(box["last"]) - int(box["first"]) + 1) * 3

	if unlocked:
		b.text = "%d.  %s  ·  %d×%d\nLv %d–%d        ★ %d / %d" % [
			idx + 1, box["name"], box["grid"], box["grid"],
			box["first"], box["last"], earned, max_stars
		]
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		b.pressed.connect(_on_pick.bind(box))
	else:
		b.text = "🔒  %s  ·  %d×%d\nNeed ★ %d to unlock" % [
			box["name"], box["grid"], box["grid"], int(box["stars"])
		]
		b.disabled = true
		b.add_theme_color_override("font_color_disabled", Color(0.55, 0.58, 0.78, 1))
	return b

func _on_pick(box: Dictionary):
	# Pick the furthest unlocked level inside this box, or the first level
	var start: int = int(box["first"])
	var last_level: int = int(box["last"])
	var target := start
	for lvl in range(start, last_level + 1):
		if GameData.is_unlocked(lvl):
			target = lvl
		else:
			break
	GameData.selected_level = target
	Transition.goto("res://scenes/Main.tscn")
