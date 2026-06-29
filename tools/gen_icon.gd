extends SceneTree

const SIZE := 512

func _initialize():
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	# Background: deep-navy vertical gradient, full square (Play applies the mask)
	var top := Color("#0B0B16")
	var bot := Color("#13132A")
	for y in range(SIZE):
		var t := float(y) / float(SIZE - 1)
		var c := top.lerp(bot, t)
		for x in range(SIZE):
			img.set_pixel(x, y, c)

	# Soft inner radial glow
	var cx := SIZE / 2.0
	var cy := SIZE / 2.0
	for y in range(SIZE):
		for x in range(SIZE):
			var d := Vector2(x - cx, y - cy).length()
			var k := clampf(1.0 - d / (SIZE * 0.55), 0.0, 1.0)
			if k <= 0.0:
				continue
			var glow := Color("#F59E0B")
			glow.a = k * 0.16
			_blend(img, x, y, glow)

	# Three dots arranged like a "Z" with a thick warm gradient ribbon
	var c0 := Color("#FFC04D")   # amber
	var c1 := Color("#F97316")   # orange
	var c2 := Color("#EF4444")   # red
	var a := Vector2(150, 150)
	var b := Vector2(362, 256)
	var c := Vector2(150, 362)

	var ribbon_w := 56.0
	_draw_segment_glow(img, a, b, ribbon_w, c0, c1)
	_draw_segment_glow(img, b, c, ribbon_w, c1, c2)
	_draw_segment(img, a, b, ribbon_w, c0, c1)
	_draw_segment(img, b, c, ribbon_w, c1, c2)

	# Dot caps (filled disc + white inner)
	for d_def in [[a, c0], [b, c1], [c, c2]]:
		var p: Vector2 = d_def[0]
		var col: Color = d_def[1]
		var halo := col; halo.a = 0.35
		_disc(img, p, 78.0, halo)
		_disc(img, p, 56.0, col)
		_disc_ring(img, p, 56.0, 6.0, Color("#FFFFFF"))

	# Save
	img.save_png("res://assets/ui/icon.png")
	var img192 := img.duplicate()
	img192.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	img192.save_png("res://assets/ui/icon_192.png")
	print("icon: wrote assets/ui/icon.png (512) and assets/ui/icon_192.png (192)")
	quit()

func _blend(img: Image, x: int, y: int, src: Color):
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	var dst := img.get_pixel(x, y)
	var a := src.a
	var r := src.r * a + dst.r * (1.0 - a)
	var g := src.g * a + dst.g * (1.0 - a)
	var b := src.b * a + dst.b * (1.0 - a)
	img.set_pixel(x, y, Color(r, g, b, 1.0))

func _disc(img: Image, p: Vector2, r: float, color: Color):
	var minx := int(maxi(0, int(p.x - r - 1)))
	var maxx := int(mini(SIZE - 1, int(p.x + r + 1)))
	var miny := int(maxi(0, int(p.y - r - 1)))
	var maxy := int(mini(SIZE - 1, int(p.y + r + 1)))
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
	var outer := r
	var inner := r - w
	var minx := int(maxi(0, int(p.x - r - 1)))
	var maxx := int(mini(SIZE - 1, int(p.x + r + 1)))
	var miny := int(maxi(0, int(p.y - r - 1)))
	var maxy := int(mini(SIZE - 1, int(p.y + r + 1)))
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var d := Vector2(x - p.x, y - p.y).length()
			if d <= outer and d >= inner:
				_blend(img, x, y, color)

func _draw_segment(img: Image, a: Vector2, b: Vector2, w: float, ca: Color, cb: Color):
	# Distance-to-segment rasterization
	var minx := int(maxi(0, int(minf(a.x, b.x) - w - 2)))
	var maxx := int(mini(SIZE - 1, int(maxf(a.x, b.x) + w + 2)))
	var miny := int(maxi(0, int(minf(a.y, b.y) - w - 2)))
	var maxy := int(mini(SIZE - 1, int(maxf(a.y, b.y) + w + 2)))
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

func _draw_segment_glow(img: Image, a: Vector2, b: Vector2, w: float, ca: Color, cb: Color):
	# Wide soft underlay for the glow
	var glow_w := w * 2.3
	var minx := int(maxi(0, int(minf(a.x, b.x) - glow_w - 2)))
	var maxx := int(mini(SIZE - 1, int(maxf(a.x, b.x) + glow_w + 2)))
	var miny := int(maxi(0, int(minf(a.y, b.y) - glow_w - 2)))
	var maxy := int(mini(SIZE - 1, int(maxf(a.y, b.y) + glow_w + 2)))
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
			if d <= glow_w * 0.5:
				var col := ca.lerp(cb, t)
				col.a = (1.0 - d / (glow_w * 0.5)) * 0.22
				_blend(img, x, y, col)
