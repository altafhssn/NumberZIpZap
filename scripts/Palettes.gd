# Palettes.gd
# Catalog of path-color cosmetics for the Shop. Each entry defines the gradient
# the player's drawn line uses during gameplay (start → end).
#
# Source values:
#   "free"          — pre-unlocked from day one, no cost
#   "level_unlock"  — auto-unlocks when max_unlocked >= unlock_level
#   "drops"         — unlock by spending the soft drops currency
#   "premium"       — IAP-locked; granted by buying Calm Forever
extends RefCounted

const DEFAULT_ID := "sunset"

# Order matters — this is the display order in the shop grid.
const PALETTES := [
	# ----- Free starter palettes (always available) -----
	{"id": "sunset",   "name": "Sunset",   "start": Color("#FF9D6C"), "end": Color("#EC4899"), "source": "free"},
	{"id": "ocean",    "name": "Ocean",    "start": Color("#00B4D8"), "end": Color("#0077B6"), "source": "free"},

	# ----- Level-unlock milestones (gifted on progression) -----
	{"id": "forest",      "name": "Forest",      "start": Color("#06D6A0"), "end": Color("#1B998B"), "source": "level_unlock", "unlock_level": 10},
	{"id": "ash",         "name": "Ash",         "start": Color("#C5C7D1"), "end": Color("#7A7E8B"), "source": "level_unlock", "unlock_level": 25},
	{"id": "twilight",    "name": "Twilight",    "start": Color("#4361EE"), "end": Color("#7B2D8B"), "source": "level_unlock", "unlock_level": 50},
	{"id": "candy_cane",  "name": "Candy Cane 🎄", "start": Color("#FFFFFF"), "end": Color("#DC2626"), "source": "level_unlock", "unlock_level": 100},

	# ----- Drops-unlock tier (earn by playing) -----
	{"id": "ember",     "name": "Ember",     "start": Color("#F59E0B"), "end": Color("#EF4444"), "source": "drops", "cost": 50},
	{"id": "coral",     "name": "Coral",     "start": Color("#FB7185"), "end": Color("#F97316"), "source": "drops", "cost": 120},
	{"id": "aurora",    "name": "Aurora",    "start": Color("#8B5CF6"), "end": Color("#06D6A0"), "source": "drops", "cost": 200},
	{"id": "midnight",  "name": "Midnight",  "start": Color("#1E1B4B"), "end": Color("#7B2D8B"), "source": "drops", "cost": 350},
	{"id": "mint",      "name": "Mint",      "start": Color("#A7F3D0"), "end": Color("#EEF7F2"), "source": "drops", "cost": 500},
	{"id": "rose_gold", "name": "Rose Gold", "start": Color("#FECDD3"), "end": Color("#D4A15F"), "source": "drops", "cost": 750},
	{"id": "cosmic",    "name": "Cosmic",    "start": Color("#7B2D8B"), "end": Color("#EC4899"), "source": "drops", "cost": 1000},

	# ----- Premium tier (granted by Calm Forever IAP) -----
	{"id": "sakura",  "name": "Sakura",  "start": Color("#FECDD3"), "end": Color("#EC4899"), "source": "premium"},
	{"id": "neon",    "name": "Neon",    "start": Color("#22D3EE"), "end": Color("#F472B6"), "source": "premium"},
	{"id": "galaxy",  "name": "Galaxy",  "start": Color("#312E81"), "end": Color("#EC4899"), "source": "premium"},
]

static func get_palette(id: String) -> Dictionary:
	for p in PALETTES:
		if str(p["id"]) == id:
			return p
	# Fall back to the very first entry if the saved id is unknown
	# (e.g., a palette was removed between updates).
	return PALETTES[0]

# Drops earned at the end of a level, scaled by petals achieved.
# 3 petals = 30 drops, 2 = 20, 1 = 10, 0 = 0.
static func drops_for_petals(petals: int) -> int:
	return clampi(petals, 0, 3) * 10

# Convenience: is this palette automatically owned given the player's state?
# (free / premium-with-CF / level threshold reached).
static func is_owned_by_default(p: Dictionary, is_premium: bool, max_unlocked_level: int = 1) -> bool:
	var source := str(p.get("source", "free"))
	if source == "free":
		return true
	if source == "premium" and is_premium:
		return true
	if source == "level_unlock" and max_unlocked_level >= int(p.get("unlock_level", 999)):
		return true
	return false

# Returns the array of palettes that should reveal their popup the moment the
# player crosses a given level boundary (i.e., their unlock_level == level).
static func newly_unlocked_at(level: int) -> Array:
	var out: Array = []
	for p in PALETTES:
		if str(p.get("source", "")) == "level_unlock" and int(p.get("unlock_level", -1)) == level:
			out.append(p)
	return out
