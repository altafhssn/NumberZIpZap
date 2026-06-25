# StarBadge.gd
# Custom-drawn 5-point star with proper geometry, gold gradient, soft halo
# glow, white highlight pinprick, and a subtle continuous pulse for earned
# stars. Replaces flat emoji ⭐/☆ in the level-complete popup.
extends Control

var earned: bool = false
var _t: float = 0.0

const GOLD_OUTER   := Color("#E8A500")
const GOLD_MID     := Color("#FFC83A")
const GOLD_INNER   := Color("#FFE680")
const HALO         := Color("#FFD23F")
const EMPTY_FILL   := Color(0.18, 0.20, 0.28, 0.55)
const EMPTY_STROKE := Color(0.42, 0.44, 0.55, 0.85)
const HIGHLIGHT    := Color(1.0, 1.0, 1.0, 0.92)

func _ready():
	# Bounding box has to be larger than the visible star so the halo fits
	# inside it — otherwise HBoxContainer separation can't pull adjacent
	# badges apart visually and the halos bleed into stats below.
	custom_minimum_size = Vector2(88, 88)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta):
	# Only earned stars need a continuous redraw for the pulse — unearned ones
	# are static.
	if earned:
		_t += delta
		queue_redraw()

func set_earned(v: bool):
	earned = v
	queue_redraw()

# Build the 10-vertex star polygon scaled by `scale_factor`. Outer points sit
# on `outer_r`, inner points on `outer_r * inner_ratio`. The first point is
# at 12 o'clock so the star is upright.
func _star_polygon(center: Vector2, outer_r: float, inner_ratio: float, scale_factor: float = 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var inner_r: float = outer_r * inner_ratio
	for i in range(10):
		var angle: float = (float(i) / 10.0) * TAU - PI * 0.5
		var r: float = (outer_r if i % 2 == 0 else inner_r) * scale_factor
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	return pts

func _draw():
	var center: Vector2 = size * 0.5
	# Outer radius shrunk so the star + halo together stay inside the
	# bounding box (otherwise the halo bleeds into neighbouring stars and
	# the stats label below).
	var outer_r: float = min(size.x, size.y) * 0.36
	var inner_ratio: float = 0.42

	if earned:
		# Pulsing outer halo — gentle golden bloom that breathes. Radii kept
		# under 1.30× so the halo lands within the 88-pixel badge.
		var pulse: float = 0.5 + 0.5 * sin(_t * 2.2)
		var halo := HALO
		halo.a = lerpf(0.18, 0.32, pulse)
		draw_circle(center, outer_r * 1.28, halo)
		halo.a = lerpf(0.28, 0.50, pulse)
		draw_circle(center, outer_r * 1.02, halo)

		# Drop shadow — slight dark offset down-right for depth.
		var shadow_pts := _star_polygon(center + Vector2(0, outer_r * 0.07), outer_r, inner_ratio)
		var shadow_cols := PackedColorArray()
		for i in range(shadow_pts.size()):
			shadow_cols.append(Color(0, 0, 0, 0.30))
		draw_polygon(shadow_pts, shadow_cols)

		# Outer star — darker gold rim. Per-vertex coloring gives a faux
		# radial gradient: outer points are MID, inner points are INNER.
		var outer_pts := _star_polygon(center, outer_r, inner_ratio)
		var outer_cols := PackedColorArray()
		for i in range(outer_pts.size()):
			outer_cols.append(GOLD_OUTER if i % 2 == 0 else GOLD_MID)
		draw_polygon(outer_pts, outer_cols)

		# Inner star — slightly smaller bright fill so the rim shows.
		var inner_pts := _star_polygon(center, outer_r * 0.82, inner_ratio)
		var inner_cols := PackedColorArray()
		for i in range(inner_pts.size()):
			inner_cols.append(GOLD_MID if i % 2 == 0 else GOLD_INNER)
		draw_polygon(inner_pts, inner_cols)

		# Bright white shine pinprick at upper-left — gives the star a "lit"
		# look.
		var shine_pos := center + Vector2(-outer_r * 0.28, -outer_r * 0.30)
		var shine_col := HIGHLIGHT
		shine_col.a = 0.9
		draw_circle(shine_pos, outer_r * 0.13, shine_col)
		shine_col.a = 0.6
		draw_circle(shine_pos + Vector2(outer_r * 0.04, outer_r * 0.05),
			outer_r * 0.07, shine_col)

		# Crisp 1px outline of the outer star — keeps the silhouette sharp
		# against the panel background.
		var outline := PackedVector2Array()
		for p in outer_pts:
			outline.append(p)
		outline.append(outer_pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.45), 1.5, true)
	else:
		# Unearned — outline-only star, elegantly understated.
		var pts := _star_polygon(center, outer_r, inner_ratio)
		var fill_cols := PackedColorArray()
		for i in range(pts.size()):
			fill_cols.append(EMPTY_FILL)
		draw_polygon(pts, fill_cols)
		var stroke := PackedVector2Array()
		for p in pts:
			stroke.append(p)
		stroke.append(pts[0])
		draw_polyline(stroke, EMPTY_STROKE, 2.0, true)
