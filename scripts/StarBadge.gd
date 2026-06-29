# StarBadge.gd
# Despite the historical name, this draws a 5-petal CHERRY BLOSSOM, not a
# star. ZipPath's reward currency is petals (🌸), so flowers are the
# consistent visual language across the shop, leaderboard, HUD, and the
# level-complete panel. Earned blossoms get a pink halo + bright pink petals
# + a yellow stamen-dotted center. Unearned ones are outline-only and dim.
# (File name kept as StarBadge.gd to avoid churning every caller's preload.)
extends Control

var earned: bool = false
var _t: float = 0.0

# Petal colors — three-stop pink gradient applied via concentric draw_circle
# calls per petal so each blossom petal reads as a soft rounded shape.
const PETAL_OUTER  := Color("#D81B60")  # deep magenta rim
const PETAL_MID    := Color("#FF6B9D")  # signature petal pink
const PETAL_INNER  := Color("#FFD0DE")  # near-white pink for the petal core
# Stamen / center
const CENTER_OUTER := Color("#FFB300")  # amber edge of the flower's core
const CENTER_INNER := Color("#FFF2A8")  # bright yellow heart
const STAMEN_DOT   := Color("#E65100")  # tiny orange specks
# Halo + highlights
const HALO         := Color("#FF6B9D")
const HIGHLIGHT    := Color(1.0, 1.0, 1.0, 0.92)
# Empty (unearned) blossom — same shape, dimmer fill + outline.
const EMPTY_FILL   := Color(0.18, 0.20, 0.28, 0.55)
const EMPTY_STROKE := Color(0.42, 0.44, 0.55, 0.85)

func _ready():
	# Bounding box has to be larger than the visible flower so the halo +
	# petal tips stay inside it. 88px matches the layout the HUD reserves.
	custom_minimum_size = Vector2(88, 88)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta):
	# Only earned blossoms need a continuous redraw for the breathing halo
	# pulse — unearned ones are static.
	if earned:
		_t += delta
		queue_redraw()

func set_earned(v: bool):
	earned = v
	queue_redraw()

# Petal center positions: 5 petals evenly spaced, starting from 12 o'clock
# so the blossom sits upright. Each petal sits at `petal_dist` from the
# flower center along its angle.
func _petal_centers(center: Vector2, petal_dist: float) -> Array:
	var centers: Array = []
	for i in range(5):
		var angle: float = (float(i) / 5.0) * TAU - PI * 0.5
		centers.append({
			"pos": center + Vector2(cos(angle), sin(angle)) * petal_dist,
			"angle": angle,
		})
	return centers

func _draw():
	var center: Vector2 = size * 0.5
	# Flower geometry. outer_r is the bounding radius (tip of a petal). Petal
	# centers sit closer in at 0.55× so the petals overlap nicely at the heart.
	var outer_r: float = min(size.x, size.y) * 0.40
	var petal_dist: float = outer_r * 0.55
	var petal_r: float = outer_r * 0.42

	if earned:
		# Pulsing pink halo. Two stacked circles, the outer slightly larger,
		# breathing at ~0.35 Hz so the bloom feels alive without throbbing.
		var pulse: float = 0.5 + 0.5 * sin(_t * 2.2)
		var halo := HALO
		halo.a = lerpf(0.16, 0.30, pulse)
		draw_circle(center, outer_r * 1.30, halo)
		halo.a = lerpf(0.26, 0.46, pulse)
		draw_circle(center, outer_r * 1.05, halo)

		var centers: Array = _petal_centers(center, petal_dist)

		# Drop shadow under every petal — soft offset down-right so the
		# blossom feels lifted off the panel.
		for p_data in centers:
			var shadow_pos: Vector2 = p_data["pos"] + Vector2(0, petal_r * 0.10)
			draw_circle(shadow_pos, petal_r * 1.02, Color(0, 0, 0, 0.32))

		# Petal layers — outer rim → mid pink → bright inner. The concentric
		# draw_circle stack reads as a soft gradient, no shader needed.
		for p_data in centers:
			var p: Vector2 = p_data["pos"]
			draw_circle(p, petal_r, PETAL_OUTER)
			draw_circle(p, petal_r * 0.86, PETAL_MID)
			draw_circle(p, petal_r * 0.55, PETAL_INNER)

		# Per-petal highlight — small white pinprick on the side facing the
		# light source (upper-left). Reads as a glossy sheen on each petal.
		for p_data in centers:
			var p: Vector2 = p_data["pos"]
			var angle: float = float(p_data["angle"])
			# Position the shine slightly inward from each petal toward the
			# upper-left of the flower for consistent lighting.
			var shine_dir: Vector2 = Vector2(-0.55, -0.55).normalized()
			var shine_pos: Vector2 = p + shine_dir * petal_r * 0.30
			var shine_col: Color = HIGHLIGHT
			shine_col.a = 0.55
			draw_circle(shine_pos, petal_r * 0.16, shine_col)

		# Flower center — amber→yellow gradient with tiny stamen specks.
		# Drawn LAST so it sits cleanly on top of the petals where they meet.
		var center_r: float = petal_r * 0.62
		draw_circle(center, center_r, CENTER_OUTER)
		draw_circle(center, center_r * 0.70, CENTER_INNER)
		# Stamen dots — 6 small orange specks ringed around the heart.
		for i in range(6):
			var a: float = (float(i) / 6.0) * TAU + PI * 0.08
			var d_pos: Vector2 = center + Vector2(cos(a), sin(a)) * center_r * 0.55
			draw_circle(d_pos, center_r * 0.12, STAMEN_DOT)
		# Tiny bright center pip — completes the "blooming" look.
		draw_circle(center, center_r * 0.22, Color("#FFFFFF"))
	else:
		# Unearned — outline-only blossom, same silhouette but dim. Keeps the
		# row visually balanced (3 flower shapes) even when some aren't earned.
		var centers: Array = _petal_centers(center, petal_dist)
		for p_data in centers:
			var p: Vector2 = p_data["pos"]
			draw_circle(p, petal_r, EMPTY_FILL)
			draw_circle(p, petal_r, EMPTY_STROKE, false, 2.0, true)
		# Empty center — same disc shape, just dim.
		var center_r: float = petal_r * 0.62
		draw_circle(center, center_r, EMPTY_FILL)
		draw_circle(center, center_r, EMPTY_STROKE, false, 1.5, true)
