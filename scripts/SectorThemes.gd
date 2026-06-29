# SectorThemes.gd
# Per-sector visual palette. Every sector shares a DARK canvas (background +
# grid panel + block slabs) so the dark HUD/pause chrome always looks at home.
# Only the puzzle elements — ribbon, glow, numbered dots, target glow,
# particles, ripples, accent — vary by sector. This is the "side elements
# differ" rule: same dark stage, distinct world identity.
#
# Level -> pack mapping mirrors GameData.PACK_RANGES so the visual sector and
# the leaderboard pack agree (leaderboard IDs are already submitted to Play
# Games — these boundaries can't move).
#   First Pond  (1-30)    Spark      — friendly amber/gold opening
#   Reed Path   (31-80)   Glow       — orange sunset
#   Stone Bend  (81-130)  Ember      — volcanic red, molten-gold ribbon
#   Moon Pool   (131-200) Nova       — cosmic violet, ribbon hue rotates live
#   Garden      (201+)    Infinite   — pitch-black void, hue cycles per level
class_name SectorThemes
extends RefCounted

# User-facing pond names. Match GameData / Leaderboard / BoxSelect labels.
const PACK_NAMES := ["First Pond", "Reed Path", "Stone Bend", "Moon Pool", "Garden"]
# Internal theme keys. Used for music loop names and for the `name` field in
# the theme dict so HUD/Grid can branch on theme identity without strings.
const PACK_THEME_KEYS := ["spark", "glow", "ember", "nova", "infinite"]
# Last level included in each pack. Mirrors GameData.PACK_RANGES.
const PACK_LAST := [30, 80, 130, 200, 99999]

static func get_pack_index_for_level(level: int) -> int:
	for i in range(PACK_LAST.size()):
		if level <= PACK_LAST[i]:
			return i
	return PACK_LAST.size() - 1

static func get_pack_name(pack_index: int) -> String:
	return PACK_NAMES[clampi(pack_index, 0, PACK_NAMES.size() - 1)]

static func get_theme_for_level(level: int) -> Dictionary:
	return get_theme(get_pack_index_for_level(level), level)

static func get_theme(pack_index: int, level: int = 1) -> Dictionary:
	var idx := clampi(pack_index, 0, PACK_NAMES.size() - 1)
	match idx:
		0: return _spark()
		1: return _glow()
		2: return _ember()
		3: return _nova()
		_: return _infinite(level)

static func hsv_to_rgb_hex(h: float, s: float, v: float) -> String:
	var c := Color.from_hsv(fposmod(h, 1.0), clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0))
	return "#%02X%02X%02X" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]

# Shared dark canvas, slightly tinted toward the sector's mood. Sectors only
# override the entries they need to recolor (ribbon, dots, particles, etc.).
static func _base_dark(tint_top: Color, tint_grid_line: Color, tint_cell: Color, tint_block: Color, tint_block_border: Color) -> Dictionary:
	return {
		"bg_top": tint_top,
		"bg_bottom": Color("#050510"),
		"grid_line": tint_grid_line,
		"cell_empty": tint_cell,
		"block_fill": tint_block,
		"block_border": tint_block_border,
		"light_bg": false,
	}

# ---------------------------------------------------------------- packs ---

# Spark (1-10) — warm amber/gold. Dark canvas with subtle warm tint.
static func _spark() -> Dictionary:
	var t := _base_dark(
		Color("#100D1A"),
		Color("#2A2018"),
		Color("#15120A"),
		Color("#08060A"),
		Color("#3A2818"))
	t.merge({
		"name": "Spark",
		"ribbon": Color("#FFB800"),
		"glow": Color("#FFD680"),
		"dot_base": Color("#FF6E40"),
		"dot_pulse": Color("#FFB37A"),
		"target_glow": Color("#FFFFFF"),
		"particle": Color("#FFD23F"),
		"ripple": Color("#FFB800"),
		"accent": Color("#FFD680"),
		"music": "spark_loop",
		"dynamic_ribbon": "",
		"swatch": Color("#FFC04D"),
	})
	return t

# Glow (11-20) — orange sunset. Warmer, deeper, more saturated than Spark.
static func _glow() -> Dictionary:
	var t := _base_dark(
		Color("#1A0D0F"),
		Color("#3A1810"),
		Color("#180A08"),
		Color("#0F0606"),
		Color("#4A2818"))
	t.merge({
		"name": "Glow",
		"ribbon": Color("#FF6A1A"),
		"glow": Color("#FFA76B"),
		"dot_base": Color("#FFD600"),
		"dot_pulse": Color("#FFE680"),
		"target_glow": Color("#FFFFFF"),
		"particle": Color("#FFC472"),
		"ripple": Color("#FF6A1A"),
		"accent": Color("#FFA76B"),
		"music": "glow_loop",
		"dynamic_ribbon": "",
		"swatch": Color("#F97316"),
	})
	return t

# Ember (21-30) — volcanic. Dark red canvas with molten gold ribbon.
static func _ember() -> Dictionary:
	var t := _base_dark(
		Color("#150406"),
		Color("#3A1410"),
		Color("#1A0606"),
		Color("#100404"),
		Color("#5A1810"))
	t.merge({
		"name": "Ember",
		"ribbon": Color("#FFD600"),
		"glow": Color("#FFE680"),
		"dot_base": Color("#FF3D00"),
		"dot_pulse": Color("#FFB38F"),
		"target_glow": Color("#FFFFFF"),
		"particle": Color("#FFD600"),
		"ripple": Color("#FF3D00"),
		"accent": Color("#FFE680"),
		"music": "ember_loop",
		"dynamic_ribbon": "",
		"swatch": Color("#EF4444"),
	})
	return t

# Nova (31-40) — cosmic violet. Ribbon hue rotates 0..360 over ~4s (live).
static func _nova() -> Dictionary:
	var t := _base_dark(
		Color("#0E0A1F"),
		Color("#2A1A4A"),
		Color("#150F30"),
		Color("#080518"),
		Color("#4A2A8F"))
	t.merge({
		"name": "Nova",
		"ribbon": Color("#B388FF"),
		"glow": Color("#E1BFFF"),
		"dot_base": Color("#FF6E9C"),
		"dot_pulse": Color("#FFB3C8"),
		"target_glow": Color("#66FFB2"),
		"particle": Color("#B388FF"),
		"ripple": Color("#66FFB2"),
		"accent": Color("#E1BFFF"),
		"music": "nova_loop",
		"dynamic_ribbon": "nova",
		"swatch": Color("#8B5CF6"),
	})
	return t

# Infinite (41+) — pitch-black canvas with per-level hue cycle.
static func _infinite(level: int) -> Dictionary:
	var base_hue_deg := fposmod(float(level * 37), 360.0)
	var ribbon: Color = _hsv(base_hue_deg, 0.85, 1.0)
	var dot_pulse: Color = _hsv(base_hue_deg + 60.0, 0.85, 1.0)
	var target_glow: Color = _hsv(base_hue_deg + 180.0, 0.85, 1.0)
	var particle: Color = _hsv(base_hue_deg + 30.0, 0.85, 1.0)
	var ripple: Color = _hsv(base_hue_deg + 90.0, 0.85, 1.0)
	var accent: Color = _hsv(base_hue_deg + 180.0, 0.85, 1.0)
	var t := _base_dark(
		Color("#000000"),
		Color("#18181F"),
		Color("#0A0A14"),
		Color("#14141C"),
		Color("#2A2A36"))
	t["bg_bottom"] = Color("#050510")
	t.merge({
		"name": "Infinite",
		"ribbon": ribbon,
		"glow": ribbon.lightened(0.30),
		"dot_base": Color("#FFFFFF"),
		"dot_pulse": dot_pulse,
		"target_glow": target_glow,
		"particle": particle,
		"ripple": ripple,
		"accent": accent,
		"music": "infinite_loop",
		"dynamic_ribbon": "",
		"swatch": Color("#06D6A0"),
	})
	return t

static func _hsv(hue_deg: float, sat: float, val: float) -> Color:
	return Color.from_hsv(fposmod(hue_deg, 360.0) / 360.0, sat, val)
