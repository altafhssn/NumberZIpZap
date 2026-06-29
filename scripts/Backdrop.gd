# Backdrop.gd
# Reusable calm background: paper gradient + fixed grain.
# Attach to a full-rect Control placed behind screen content.
extends Control

var top := Color("#0B0B16")
var bottom := Color("#13132A")
var grain_a := Color(0.263, 0.380, 0.933, 0.10)
var grain_b := Color(0.482, 0.176, 0.545, 0.10)

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw():
	var s := size
	# Gradient fill
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)
	# Fixed paper grain. It should feel made, not animated.
	for i in range(90):
		var x := fmod(float(i * 73 + 19), maxf(1.0, s.x))
		var y := fmod(float(i * 41 + 31), maxf(1.0, s.y))
		var r := 0.8 + fmod(float(i * 17), 13.0) / 13.0
		draw_circle(Vector2(x, y), r, grain_a if i % 2 == 0 else grain_b)
