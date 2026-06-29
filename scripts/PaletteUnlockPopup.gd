# PaletteUnlockPopup.gd
# A celebratory modal that pops up when the player crosses a level-unlock
# threshold and earns a new path-color palette. Lives on its own CanvasLayer
# so it can overlay the level-complete card without being clipped by it.
extends CanvasLayer

signal closed
signal equip_requested(palette_id: String)

var _palette: Dictionary
var _panel: PanelContainer
var _gradient_strip: Control

func setup(palette: Dictionary) -> void:
	_palette = palette

func _ready() -> void:
	layer = 70  # above DailyCard (60) and the HUD complete panel
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _palette.is_empty():
		queue_free()
		return
	_build()

func _build() -> void:
	# Dim, input-blocking backdrop
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Centered container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Modal card
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#16162C")
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 28
	sb.content_margin_bottom = 24
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 22
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = _palette["start"]
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	_panel = panel

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	# Top accent line: small celebratory caption
	vb.add_child(_label("✨  NEW PALETTE  ✨", 13, Color(1, 0.82, 0.4, 1), 1))

	# Palette name (large)
	vb.add_child(_label(str(_palette["name"]), 30, Color(1, 1, 1, 1), 1))

	# Gradient preview strip (the actual line the player will draw)
	_gradient_strip = _make_gradient_strip(_palette["start"], _palette["end"])
	vb.add_child(_gradient_strip)

	vb.add_child(_label("Unlocked at level %d" % int(_palette.get("unlock_level", 0)),
		13, Color(0.62, 0.66, 0.86, 1), 1))

	vb.add_child(_spacer(8))

	# Buttons
	var equip_btn := _make_button("Equip Now", true)
	equip_btn.pressed.connect(_on_equip)
	vb.add_child(equip_btn)

	var later_btn := _make_button("Later", false)
	later_btn.pressed.connect(_on_close)
	vb.add_child(later_btn)

	# Pop-in animation
	panel.modulate = Color(1, 1, 1, 0)
	panel.scale = Vector2(0.82, 0.82)
	_animate_in.call_deferred(dim, panel)

func _animate_in(dim: ColorRect, panel: Control) -> void:
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim, "color:a", 0.55, 0.25)
	tw.tween_property(panel, "modulate:a", 1.0, 0.30)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _label(text: String, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _make_gradient_strip(c_start: Color, c_end: Color) -> Control:
	var strip := Control.new()
	strip.custom_minimum_size = Vector2(0, 38)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.set_meta("c_start", c_start)
	strip.set_meta("c_end", c_end)
	strip.draw.connect(_draw_strip.bind(strip))
	return strip

func _draw_strip(strip: Control) -> void:
	var w: float = strip.size.x
	var h: float = strip.size.y
	if w <= 0 or h <= 0:
		return
	var a: Color = strip.get_meta("c_start")
	var b: Color = strip.get_meta("c_end")
	var steps := 64
	var step_w: float = w / float(steps)
	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		strip.draw_rect(Rect2(i * step_w, 0, step_w + 1.0, h), a.lerp(b, t))
	# Soft white outline so the strip reads as a clean swatch.
	strip.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.10), false, 1.0)

func _make_button(text: String, accent: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if accent:
		# Use the palette's start color as the button bg so the CTA feels
		# rewarding and previews the palette one more time.
		sb.bg_color = _palette["start"]
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		sb.bg_color = Color("#0F0F22")
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color("#2A2A4E")
		b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	return b

func _on_equip() -> void:
	emit_signal("equip_requested", str(_palette["id"]))
	_dismiss()

func _on_close() -> void:
	_dismiss()

func _dismiss() -> void:
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.18)
	await tw.finished
	emit_signal("closed")
	queue_free()
