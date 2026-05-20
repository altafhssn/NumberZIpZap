extends SceneTree

const W := 1024
const H := 500

# 5x7 bitmap glyphs for the wordmark
const GLYPHS := {
	"Z": ["XXXXX",
		  "    X",
		  "   X ",
		  "  X  ",
		  " X   ",
		  "X    ",
		  "XXXXX"],
	"I": ["XXXXX",
		  "  X  ",
		  "  X  ",
		  "  X  ",
		  "  X  ",
		  "  X  ",
		  "XXXXX"],
	"P": ["XXXX ",
		  "X   X",
		  "X   X",
		  "XXXX ",
		  "X    ",
		  "X    ",
		  "X    "],
	"A": ["  X  ",
		  " X X ",
		  "X   X",
		  "X   X",
		  "XXXXX",
		  "X   X",
		  "X   X"],
	"T": ["XXXXX",
		  "  X  ",
		  "  X  ",
		  "  X  ",
		  "  X  ",
		  "  X  ",
		  "  X  "],
	"H": ["X   X",
		  "X   X",
		  "X   X",
		  "XXXXX",
		  "X   X",
		  "X   X",
		  "X   X"],
}

func _initialize():
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)

	# Diagonal navy gradient
	var c_tl := Color("#0A0A14")
	var c_br := Color("#181834")
	for y in range(H):
		for x in range(W):
			var t := (float(x) / float(W - 1) + float(y) / float(H - 1)) * 0.5
			img.set_pixel(x, y, c_tl.lerp(c_br, t))

	# Warm Ember radial glow from the left
	var gcx := 220.0
	var gcy := 250.0
	for y in range(H):
		for x in range(W):
			var d := Vector2(x - gcx, y - gcy).length()
			var k := clampf(1.0 - d / 360.0, 0.0, 1.0)
			if k <= 0.0:
				continue
			var g := Color("#F59E0B")
			g.a = k * 0.18
			_blend(img, x, y, g)

	# Three-dot Z ribbon on the left
	var c0 := Color("#FFC04D")
	var c1 := Color("#F97316")
	var c2 := Color("#EF4444")
	var a := Vector2(110, 130)
	var b := Vector2(320, 250)
	var c := Vector2(110, 370)
	var rw := 44.0
	_seg_glow(img, a, b, rw, c0, c1)
	_seg_glow(img, b, c, rw, c1, c2)
	_seg(img, a, b, rw, c0, c1)
	_seg(img, b, c, rw, c1, c2)
	for d_def in [[a, c0], [b, c1], [c, c2]]:
		var p: Vector2 = d_def[0]
		var col: Color = d_def[1]
		var halo := col; halo.a = 0.30
		_disc(img, p, 62.0, halo)
		_disc(img, p, 46.0, col)
		_disc_ring(img, p, 46.0, 5.0, Color("#FFFFFF"))

	# Wordmark "ZIPPATH" right side
	var scale := 14
	var text := "ZIPPATH"
	var letter_w := 5 * scale
	var letter_h := 7 * scale
	var gap := 12
	var total_w := text.length() * letter_w + (text.length() - 1) * gap
	var start_x := int(W - total_w) - 60
	var start_y := int((H - letter_h) / 2) - 6

	# Bright wordmark colour (warm white) and a soft amber halo behind it
	_draw_text_glow(img, text, start_x, start_y, scale, gap, Color("#F59E0B"), 6)
	_draw_text(img, text, start_x, start_y, scale, gap, Color("#FFFBE6"))

	# Tagline underline accent
	var ul_y := start_y + letter_h + 24
	var ul_x0 := start_x
	var ul_x1 := start_x + total_w
	_seg(img, Vector2(ul_x0, ul_y), Vector2(ul_x1, ul_y), 6.0, c0, c2)

	img.save_png("res://assets/ui/feature_graphic.png")
	print("feature graphic: assets/ui/feature_graphic.png (1024x500)")
	quit()


# --- glyph rendering -----------------------------------------------------

func _draw_text(img: Image, text: String, x: int, y: int, s: int, gap: int, col: Color):
	var cx := x
	for ch in text:
		_draw_glyph(img, ch, cx, y, s, col)
		cx += 5 * s + gap

func _draw_text_glow(img: Image, text: String, x: int, y: int, s: int, gap: int, col: Color, halo_radius: int):
	var cx := x
	for ch in text:
		_draw_glyph(img, ch, cx, y, s, col, halo_radius)
		cx += 5 * s + gap

func _draw_glyph(img: Image, ch: String, x: int, y: int, s: int, col: Color, halo_radius: int = 0):
	if not GLYPHS.has(ch):
		return
	var rows: Array = GLYPHS[ch]
	for row in range(rows.size()):
		var line: String = rows[row]
		for ccol in range(line.length()):
			if line[ccol] != "X":
				continue
			var px := x + ccol * s
			var py := y + row * s
			if halo_radius > 0:
				var hc := col
				hc.a = col.a * 0.30
				_fill_rect(img, px - halo_radius, py - halo_radius, s + halo_radius * 2, s + halo_radius * 2, hc)
			else:
				_fill_rect(img, px, py, s, s, col)


# --- drawing helpers (same as gen_icon.gd) -------------------------------

func _blend(img: Image, x: int, y: int, src: Color):
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	var dst := img.get_pixel(x, y)
	var a := src.a
	var r := src.r * a + dst.r * (1.0 - a)
	var g := src.g * a + dst.g * (1.0 - a)
	var b := src.b * a + dst.b * (1.0 - a)
	img.set_pixel(x, y, Color(r, g, b, 1.0))

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, col: Color):
	for yy in range(maxi(0, y), mini(H, y + h)):
		for xx in range(maxi(0, x), mini(W, x + w)):
			_blend(img, xx, yy, col)

func _disc(img: Image, p: Vector2, r: float, color: Color):
	var minx := maxi(0, int(p.x - r - 1))
	var maxx := mini(W - 1, int(p.x + r + 1))
	var miny := maxi(0, int(p.y - r - 1))
	var maxy := mini(H - 1, int(p.y + r + 1))
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var d := Vector2(x - p.x, y - p.y).length()
			if d <= r - 1.0:
				_blend(img, x, y, color)
			elif d <= r:
				var aa := color
				aa.a = color.a * (r - d)
				_blend(img, x, y, aa)

func _disc_ring(img: Image, p: Vector2, r: float, w: float, color: Color):
	var inner := r - w
	var minx := maxi(0, int(p.x - r - 1))
	var maxx := mini(W - 1, int(p.x + r + 1))
	var miny := maxi(0, int(p.y - r - 1))
	var maxy := mini(H - 1, int(p.y + r + 1))
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var d := Vector2(x - p.x, y - p.y).length()
			if d <= r and d >= inner:
				_blend(img, x, y, color)

func _seg(img: Image, a: Vector2, b: Vector2, w: float, ca: Color, cb: Color):
	var minx := maxi(0, int(minf(a.x, b.x) - w - 2))
	var maxx := mini(W - 1, int(maxf(a.x, b.x) + w + 2))
	var miny := maxi(0, int(minf(a.y, b.y) - w - 2))
	var maxy := mini(H - 1, int(maxf(a.y, b.y) + w + 2))
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1.0:
		return
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var p := Vector2(x, y) - a
			var t := clampf(p.dot(ab) / len2, 0.0, 1.0)
			var proj := a + ab * t
			var d := Vector2(x - proj.x, y - proj.y).length()
			if d <= w * 0.5 - 1.0:
				_blend(img, x, y, ca.lerp(cb, t))
			elif d <= w * 0.5:
				var col := ca.lerp(cb, t)
				col.a = w * 0.5 - d
				_blend(img, x, y, col)

func _seg_glow(img: Image, a: Vector2, b: Vector2, w: float, ca: Color, cb: Color):
	var gw := w * 2.3
	var minx := maxi(0, int(minf(a.x, b.x) - gw - 2))
	var maxx := mini(W - 1, int(maxf(a.x, b.x) + gw + 2))
	var miny := maxi(0, int(minf(a.y, b.y) - gw - 2))
	var maxy := mini(H - 1, int(maxf(a.y, b.y) + gw + 2))
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1.0:
		return
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var p := Vector2(x, y) - a
			var t := clampf(p.dot(ab) / len2, 0.0, 1.0)
			var proj := a + ab * t
			var d := Vector2(x - proj.x, y - proj.y).length()
			if d <= gw * 0.5:
				var col := ca.lerp(cb, t)
				col.a = (1.0 - d / (gw * 0.5)) * 0.22
				_blend(img, x, y, col)
