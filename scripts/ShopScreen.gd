# ShopScreen.gd
# Path-color cosmetics shop. Renders a 2-column grid of palette tiles.
# Each tile shows the gradient + name + status: Equipped / Equip / Buy / Locked.
extends Control

const PalettesScript = preload("res://scripts/Palettes.gd")

@onready var back_btn: Button = $BackBtn
@onready var drops_label: Label = $DropsChip/DropsLabel
@onready var grid: GridContainer = $Scroll/Grid

func _ready() -> void:
	Ads.show_banner()
	back_btn.pressed.connect(func(): Transition.goto("res://scenes/Home.tscn"))
	_refresh()

func _refresh() -> void:
	drops_label.text = "💧 %d drops" % GameData.drops
	for c in grid.get_children():
		c.queue_free()
	for p in PalettesScript.PALETTES:
		grid.add_child(_make_tile(p))

func _make_tile(p: Dictionary) -> Control:
	var id := str(p["id"])
	var unlocked: bool = GameData.is_palette_unlocked(id)
	var equipped: bool = unlocked and GameData.equipped_palette_id == id
	var source := str(p.get("source", "free"))

	# --- The whole tile is one Button so the entire surface is tappable ---
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 140)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.text = ""

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(16)
	sb.bg_color = Color("#16162C") if unlocked else Color("#0F0F22")
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	# Equipped gets a bright border in the palette's own start color.
	if equipped:
		sb.border_color = p["start"]
	elif unlocked:
		sb.border_color = Color("#2A2A4E")
	else:
		sb.border_color = Color("#1F1F38")
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(margin)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	# Name
	var name_label := Label.new()
	name_label.text = str(p["name"])
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color",
		Color(1, 1, 1, 1) if unlocked else Color(0.62, 0.66, 0.86, 1))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_label)

	# Gradient preview — a small rounded strip drawn via custom Control.
	var preview := _make_gradient_strip(p["start"], p["end"], unlocked)
	vb.add_child(preview)

	# Status footer: Equipped / Equip / Buy 💧X / Premium
	var footer_text: String
	var footer_color: Color
	if equipped:
		footer_text = "Equipped"
		footer_color = p["start"]
	elif unlocked:
		footer_text = "Tap to equip"
		footer_color = Color(0.62, 0.85, 1, 1)
	elif source == "drops":
		footer_text = "💧 %d" % int(p.get("cost", 0))
		footer_color = Color(0.45, 0.85, 1, 1) if GameData.drops >= int(p["cost"]) else Color(0.62, 0.66, 0.86, 1)
	elif source == "premium":
		# IAP not yet enabled — show "Coming soon" until the Play Billing
		# plugin is wired in. The palettes still appear in the shop so
		# players can see what's planned for the next update.
		footer_text = "Coming soon"
		footer_color = Color(0.62, 0.66, 0.86, 1)
	elif source == "level_unlock":
		# Tell the player *how* to unlock, not just that it's locked.
		footer_text = "Unlocks at L%d" % int(p.get("unlock_level", 0))
		footer_color = Color(0.62, 0.66, 0.86, 1)
	else:
		footer_text = "Locked"
		footer_color = Color(0.62, 0.66, 0.86, 1)

	var footer := Label.new()
	footer.text = footer_text
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", footer_color)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(footer)

	# Tap behavior
	b.pressed.connect(_on_tile_pressed.bind(p))
	return b

# A small rounded gradient swatch (~180×16) drawn via a Control's _draw.
# We render it from code so each palette gets a perfectly tuned mini-preview
# without needing 15 hand-made textures.
func _make_gradient_strip(c_start: Color, c_end: Color, unlocked: bool) -> Control:
	var strip := Control.new()
	strip.custom_minimum_size = Vector2(0, 30)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_meta("c_start", c_start if unlocked else Color(c_start.r, c_start.g, c_start.b, 0.45))
	strip.set_meta("c_end",   c_end   if unlocked else Color(c_end.r,   c_end.g,   c_end.b,   0.45))
	strip.draw.connect(_draw_strip.bind(strip))
	return strip

func _draw_strip(strip: Control) -> void:
	var w: float = strip.size.x
	var h: float = strip.size.y
	if w <= 0 or h <= 0:
		return
	var a: Color = strip.get_meta("c_start")
	var b: Color = strip.get_meta("c_end")
	# Manual gradient: 64 vertical slices interpolated between a and b.
	var steps := 64
	var step_w: float = w / float(steps)
	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		var col := a.lerp(b, t)
		strip.draw_rect(Rect2(i * step_w, 0, step_w + 1.0, h), col)
	# Subtle rounded "frame" overlay so the strip reads as a pill.
	strip.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.08), false, 1.0)

func _on_tile_pressed(p: Dictionary) -> void:
	var id := str(p["id"])
	var source := str(p.get("source", "free"))
	if GameData.is_palette_unlocked(id):
		GameData.equip_palette(id)
		_refresh()
		return
	if source == "drops":
		var cost := int(p.get("cost", 0))
		if GameData.drops >= cost:
			if GameData.try_unlock_palette(id):
				GameData.equip_palette(id)
		_refresh()
		return
	if source == "premium":
		# IAP is not live in v1.0 — taps on premium tiles do nothing for
		# now so we don't fire a non-functional purchase dialog. The Pass-2
		# plugin integration will restore: IAP.purchase(PRODUCT_CALM_FOREVER).
		return
