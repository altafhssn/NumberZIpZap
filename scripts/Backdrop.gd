# Backdrop.gd
# Reusable animated background: vertical gradient + drifting neon dots.
# Attach to a full-rect Control placed behind screen content.
extends Control

var top := Color("#0B0B16")
var bottom := Color("#13132A")
var accent_a := Color("#4361EE")
var accent_b := Color("#7B2D8B")

var _dots: Array = []   # [{ p: Vector2(0..1,0..1), r: float, spd: float, hue: float }]
var _t := 0.0

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	randomize()
	for i in range(26):
		_dots.append({
			"p": Vector2(randf(), randf()),
			"r": randf_range(1.5, 4.0),
			"spd": randf_range(0.004, 0.018),
			"hue": randf(),
		})

func _process(delta):
	_t += delta
	for d in _dots:
		d["p"].y -= d["spd"] * delta * 60.0 / 60.0
		if d["p"].y < -0.02:
			d["p"].y = 1.02
			d["p"].x = randf()
	queue_redraw()

func _draw():
	var s := size
	# Gradient fill
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)
	# Drifting dots
	for d in _dots:
		var pos := Vector2(d["p"].x * s.x, d["p"].y * s.y)
		var col: Color = accent_a.lerp(accent_b, d["hue"])
		var twinkle: float = 0.10 + 0.10 * sin(_t * 2.0 + d["hue"] * 6.28)
		col.a = twinkle
		draw_circle(pos, d["r"] * 2.4, col)
		col.a = twinkle * 2.2
		draw_circle(pos, d["r"], col)
