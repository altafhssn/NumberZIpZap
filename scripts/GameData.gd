# GameData.gd  (autoload singleton)
# Persists progression (linear unlock), star ratings and settings to disk.
extends Node

const SAVE_PATH := "user://zippath_save.json"

var max_unlocked: int = 1          # highest level the player may enter
var stars: Dictionary = {}         # { level:int -> stars:int }
var best_times: Dictionary = {}    # { level:int -> seconds:float } (best per level)
var sound_on: bool = true
var haptics_on: bool = true
var tutorial_done: bool = false
var selected_level: int = 1        # level the gameplay scene should load
var selected_leaderboard_idx: int = 0  # runtime only — which board to land on in LeaderboardScreen

# --- Shop / cosmetics ---
const PalettesScript = preload("res://scripts/Palettes.gd")
var equipped_palette_id: String = PalettesScript.DEFAULT_ID
var unlocked_palette_ids: Array = []        # ids unlocked via drops
var seen_palette_popup_ids: Array = []      # ids whose "new palette!" popup was already shown
var drops: int = 0                          # soft currency, earned per level

# --- Monetization state ---
const HINT_WALLET_MAX := 5
var hint_wallet: int = HINT_WALLET_MAX
var hint_last_refill_date: String = ""    # YYYY-MM-DD — last day we credited a regen
var levels_since_interstitial: int = 0    # interstitial counter (every 3 levels, skip 1-5)
var is_premium: bool = false              # "Calm Forever" IAP purchased

# Pack groupings mirror BoxSelect.BOXES and Leaderboard.LB_PACKS.
# Keep them in sync.
const PACK_RANGES := [
	{"first": 1,   "last": 30},     # First Pond
	{"first": 31,  "last": 80},     # Reed Path
	{"first": 81,  "last": 130},    # Stone Bend
	{"first": 131, "last": 200},    # Moon Pool
	{"first": 201, "last": 9999},   # Garden (open-ended)
]

# --- Daily Pond (ritual + retention) ---
var daily_streak: int = 0          # consecutive days the daily was completed
var daily_best: int = 0            # best streak ever reached
var daily_last_date: String = ""   # last date (YYYY-MM-DD) a daily was completed
var daily_completed_at_unix: int = 0 # exact completion time for 24-hour lockout
var daily_results: Dictionary = {} # "YYYY-MM-DD" -> petals earned that day
var daily_mode: bool = false       # runtime only (not saved): are we playing the daily?

func _ready():
	load_game()
	regen_hints_if_needed()

# Credit one hint per calendar day the player has been away, capped at the max
# wallet. Called on app start and on app resume.
func regen_hints_if_needed():
	if is_premium:
		return  # Premium has effectively unlimited; wallet number is ignored.
	var today := today_key()
	if hint_last_refill_date == "":
		# First-ever load — seed the timer, don't credit.
		hint_last_refill_date = today
		save_game()
		return
	if hint_last_refill_date == today:
		return
	# Calendar days elapsed since last refill (1 day = 86400s).
	var prev_unix := _date_to_unix(hint_last_refill_date)
	var today_unix := _date_to_unix(today)
	if today_unix <= prev_unix:
		return
	var days_elapsed: int = int((today_unix - prev_unix) / 86400)
	if days_elapsed <= 0:
		return
	hint_wallet = mini(HINT_WALLET_MAX, hint_wallet + days_elapsed)
	hint_last_refill_date = today
	save_game()

# Parse "YYYY-MM-DD" into a Unix timestamp at midnight UTC.
func _date_to_unix(key: String) -> int:
	var parts := key.split("-")
	if parts.size() != 3:
		return 0
	var dict := {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 0,
		"minute": 0,
		"second": 0,
	}
	return int(Time.get_unix_time_from_datetime_dict(dict))

# Spend a hint from the wallet. Returns true if granted.
# Premium players always succeed without spending.
func spend_hint() -> bool:
	if is_premium:
		return true
	if hint_wallet <= 0:
		return false
	hint_wallet -= 1
	save_game()
	return true

# Add hints (e.g., after a rewarded ad). Capped at max for non-premium.
func grant_hints(n: int):
	if is_premium:
		return
	hint_wallet = mini(HINT_WALLET_MAX, hint_wallet + maxi(0, n))
	save_game()

func set_premium(on: bool):
	is_premium = on
	save_game()

# --- Shop / cosmetics ---

# Is this palette currently usable by the player?
func is_palette_unlocked(id: String) -> bool:
	var p: Dictionary = PalettesScript.get_palette(id)
	if PalettesScript.is_owned_by_default(p, is_premium, max_unlocked):
		return true
	return unlocked_palette_ids.has(id)

# Returns the list of palettes whose unlock_level was JUST reached on this
# level completion and whose celebratory popup hasn't been shown yet.
# Marks each one as seen as it returns, so we never pop the same one twice.
func consume_pending_palette_popups(level_just_completed: int) -> Array:
	# Threshold is "level_just_completed + 1" because max_unlocked moves up
	# after a successful level; an unlock_level of 10 should fire when the
	# player finishes level 9 (advancing max_unlocked from 9 to 10).
	var threshold := level_just_completed + 1
	var freshly: Array = PalettesScript.newly_unlocked_at(threshold)
	var ready: Array = []
	for p in freshly:
		var id := str(p["id"])
		if seen_palette_popup_ids.has(id):
			continue
		seen_palette_popup_ids.append(id)
		ready.append(p)
	if not ready.is_empty():
		save_game()
	return ready

# Attempt to spend drops to unlock a drops-tier palette. Returns true on success.
func try_unlock_palette(id: String) -> bool:
	var p: Dictionary = PalettesScript.get_palette(id)
	if str(p.get("source", "")) != "drops":
		return false
	if unlocked_palette_ids.has(id):
		return true
	var cost := int(p.get("cost", 0))
	if drops < cost:
		return false
	drops -= cost
	unlocked_palette_ids.append(id)
	save_game()
	return true

# Switch the active palette. Fails silently if not unlocked.
func equip_palette(id: String) -> bool:
	if not is_palette_unlocked(id):
		return false
	equipped_palette_id = id
	save_game()
	return true

# Credit drops earned at the end of a level.
func add_drops(n: int) -> void:
	if n <= 0:
		return
	drops += n
	save_game()

# Returns {"start": Color, "end": Color} for the currently-equipped palette.
func get_equipped_palette_colors() -> Dictionary:
	var p: Dictionary = PalettesScript.get_palette(equipped_palette_id)
	return {"start": p["start"], "end": p["end"]}

# Today's date as a stable key.
func today_key() -> String:
	var d = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

# Yesterday's key, for streak-continuity checks.
func _yesterday_key() -> String:
	var unix := Time.get_unix_time_from_system() - 86400.0
	var d = Time.get_date_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

# Deterministic seed so everyone gets the same daily pond.
func daily_seed() -> int:
	var d = Time.get_date_dict_from_system()
	return d.year * 10000 + d.month * 100 + d.day

func is_daily_done_today() -> bool:
	return daily_results.has(today_key())

func daily_lock_remaining_sec() -> int:
	if daily_completed_at_unix <= 0:
		return 0
	var elapsed := int(Time.get_unix_time_from_system()) - daily_completed_at_unix
	return maxi(0, 86400 - elapsed)

func is_daily_available() -> bool:
	return daily_lock_remaining_sec() <= 0

# Record a completed daily. Streak is generous and never punished:
# missing a day simply restarts the count at 1 on the next completion,
# while daily_best is preserved forever.
func record_daily(petals: int):
	var key := today_key()
	var capped := clampi(petals, 0, 3)
	if daily_results.has(key):
		# Already done today (a replay) — keep best petals, leave streak alone.
		if capped > int(daily_results[key]):
			daily_results[key] = capped
			save_game()
		if daily_completed_at_unix <= 0:
			daily_completed_at_unix = int(Time.get_unix_time_from_system())
			save_game()
		return
	if daily_last_date == _yesterday_key():
		daily_streak += 1
	else:
		daily_streak = 1
	daily_last_date = key
	daily_completed_at_unix = int(Time.get_unix_time_from_system())
	daily_results[key] = capped
	daily_best = maxi(daily_best, daily_streak)
	save_game()

func record_result(level: int, earned_stars: int, time_sec: float = 0.0):
	# High-water-mark: only stored stars can ever rise, never accumulate.
	# Replaying a level can improve the record but cannot double-reward.
	var capped := clampi(earned_stars, 0, 3)
	var prev = int(stars.get(level, 0))
	if capped > prev:
		stars[level] = capped
	# Best (lowest) time per level — only stored if the run was completed
	# successfully (time_sec > 0) and beats any prior time.
	if time_sec > 0.0:
		var prev_time = float(best_times.get(level, 0.0))
		if prev_time <= 0.0 or time_sec < prev_time:
			best_times[level] = time_sec
	if level + 1 > max_unlocked:
		max_unlocked = level + 1
	save_game()

# Which pack (0..4) does this level belong to?
func pack_index_for_level(level: int) -> int:
	for i in range(PACK_RANGES.size()):
		var r: Dictionary = PACK_RANGES[i]
		if level >= int(r["first"]) and level <= int(r["last"]):
			return i
	return PACK_RANGES.size() - 1

# Cumulative petals + best-time total across all completed levels in a pack.
# Returned as { "petals": int, "time": float, "completed": int }.
func get_pack_totals(pack_idx: int) -> Dictionary:
	if pack_idx < 0 or pack_idx >= PACK_RANGES.size():
		return {"petals": 0, "time": 0.0, "completed": 0}
	var r: Dictionary = PACK_RANGES[pack_idx]
	var first := int(r["first"])
	var last := int(r["last"])
	var petals := 0
	var total_time := 0.0
	var completed := 0
	for lvl in range(first, last + 1):
		petals += int(stars.get(lvl, 0))
		if best_times.has(lvl):
			total_time += float(best_times[lvl])
			completed += 1
	return {"petals": petals, "time": total_time, "completed": completed}

func get_stars(level: int) -> int:
	return int(stars.get(level, 0))

func is_unlocked(level: int) -> bool:
	return level <= max_unlocked

func reset_progress():
	max_unlocked = 1
	stars.clear()
	best_times.clear()
	selected_level = 1
	hint_wallet = HINT_WALLET_MAX
	hint_last_refill_date = today_key()
	levels_since_interstitial = 0
	# is_premium intentionally preserved — IAP entitlement survives a
	# progression reset, the same as on any platform store.
	save_game()

func save_game():
	var payload := {
		"max_unlocked": max_unlocked,
		"stars": stars,
		"best_times": best_times,
		"sound_on": sound_on,
		"haptics_on": haptics_on,
		"tutorial_done": tutorial_done,
		"daily_streak": daily_streak,
		"daily_best": daily_best,
		"daily_last_date": daily_last_date,
		"daily_completed_at_unix": daily_completed_at_unix,
		"daily_results": daily_results,
		"hint_wallet": hint_wallet,
		"hint_last_refill_date": hint_last_refill_date,
		"levels_since_interstitial": levels_since_interstitial,
		"is_premium": is_premium,
		"equipped_palette_id": equipped_palette_id,
		"unlocked_palette_ids": unlocked_palette_ids,
		"seen_palette_popup_ids": seen_palette_popup_ids,
		"drops": drops,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))
		f.close()

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	max_unlocked = int(data.get("max_unlocked", 1))
	sound_on = bool(data.get("sound_on", true))
	haptics_on = bool(data.get("haptics_on", true))
	tutorial_done = bool(data.get("tutorial_done", false))
	daily_streak = int(data.get("daily_streak", 0))
	daily_best = int(data.get("daily_best", 0))
	daily_last_date = str(data.get("daily_last_date", ""))
	daily_completed_at_unix = int(data.get("daily_completed_at_unix", 0))
	daily_results.clear()
	var dr = data.get("daily_results", {})
	if typeof(dr) == TYPE_DICTIONARY:
		for k in dr.keys():
			daily_results[str(k)] = int(dr[k])
	if daily_completed_at_unix <= 0 and is_daily_done_today():
		daily_completed_at_unix = int(Time.get_unix_time_from_system())
	stars.clear()
	var s = data.get("stars", {})
	if typeof(s) == TYPE_DICTIONARY:
		for k in s.keys():
			stars[int(k)] = int(s[k])
	best_times.clear()
	var bt = data.get("best_times", {})
	if typeof(bt) == TYPE_DICTIONARY:
		for k in bt.keys():
			best_times[int(k)] = float(bt[k])
	hint_wallet = clampi(int(data.get("hint_wallet", HINT_WALLET_MAX)), 0, HINT_WALLET_MAX)
	hint_last_refill_date = str(data.get("hint_last_refill_date", ""))
	levels_since_interstitial = int(data.get("levels_since_interstitial", 0))
	is_premium = bool(data.get("is_premium", false))
	equipped_palette_id = str(data.get("equipped_palette_id", PalettesScript.DEFAULT_ID))
	var saved_unlocks = data.get("unlocked_palette_ids", [])
	unlocked_palette_ids.clear()
	if typeof(saved_unlocks) == TYPE_ARRAY:
		for item in saved_unlocks:
			unlocked_palette_ids.append(str(item))
	var saved_seen = data.get("seen_palette_popup_ids", [])
	seen_palette_popup_ids.clear()
	if typeof(saved_seen) == TYPE_ARRAY:
		for item in saved_seen:
			seen_palette_popup_ids.append(str(item))
	drops = maxi(0, int(data.get("drops", 0)))
