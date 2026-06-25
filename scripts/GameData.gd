# GameData.gd  (autoload singleton)
# Persists progression (linear unlock), star ratings and settings to disk.
extends Node

const SAVE_PATH := "user://zippath_save.json"

var max_unlocked: int = 1          # highest level the player may enter
var stars: Dictionary = {}         # { level:int -> stars:int }
var hints: Dictionary = {}         # { level:int -> hints_used:int } (best/last attempt)
var sound_on: bool = true
var haptics_on: bool = true
var tutorial_done: bool = false
var selected_level: int = 1        # level the gameplay scene should load
var free_hints_per_level: int = 15  # first N hints each level are free (no ad)

func _ready():
	load_game()
	# DEV: all levels unlocked for testing. Remove this line before shipping
	# (and bump it back to the saved value if you want to honour real progress).
	max_unlocked = 999

func record_result(level: int, earned_stars: int, hints_used: int = 0):
	# High-water-mark: only stored stars can ever rise, never accumulate.
	# Replaying a level can improve the record but cannot double-reward.
	var capped := clampi(earned_stars, 0, 3)
	var prev = int(stars.get(level, 0))
	if capped > prev:
		stars[level] = capped
	# Persist the hint count of this completed attempt so the star calc and UI
	# stay consistent across replays (a fresh attempt overwrites with its own).
	hints[level] = maxi(0, hints_used)
	if level + 1 > max_unlocked:
		max_unlocked = level + 1
	save_game()

func get_stars(level: int) -> int:
	return int(stars.get(level, 0))

func get_hints_used(level: int) -> int:
	return int(hints.get(level, 0))

func is_unlocked(level: int) -> bool:
	return level <= max_unlocked

func reset_progress():
	max_unlocked = 1
	stars.clear()
	hints.clear()
	selected_level = 1
	save_game()

func save_game():
	var payload := {
		"max_unlocked": max_unlocked,
		"stars": stars,
		"hints": hints,
		"sound_on": sound_on,
		"haptics_on": haptics_on,
		"tutorial_done": tutorial_done,
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
	stars.clear()
	var s = data.get("stars", {})
	if typeof(s) == TYPE_DICTIONARY:
		for k in s.keys():
			stars[int(k)] = int(s[k])
	# Backward-compatible: older saves have no "hints" key.
	hints.clear()
	var h = data.get("hints", {})
	if typeof(h) == TYPE_DICTIONARY:
		for k in h.keys():
			hints[int(k)] = int(h[k])
