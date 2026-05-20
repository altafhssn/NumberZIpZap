# GameData.gd  (autoload singleton)
# Persists progression (linear unlock), star ratings and settings to disk.
extends Node

const SAVE_PATH := "user://zippath_save.json"

var max_unlocked: int = 1          # highest level the player may enter
var stars: Dictionary = {}         # { level:int -> stars:int }
var sound_on: bool = true
var haptics_on: bool = true
var tutorial_done: bool = false
var selected_level: int = 1        # level the gameplay scene should load

func _ready():
	load_game()

func record_result(level: int, earned_stars: int):
	var prev = int(stars.get(level, 0))
	if earned_stars > prev:
		stars[level] = earned_stars
	if level + 1 > max_unlocked:
		max_unlocked = level + 1
	save_game()

func get_stars(level: int) -> int:
	return int(stars.get(level, 0))

func is_unlocked(level: int) -> bool:
	return level <= max_unlocked

func reset_progress():
	max_unlocked = 1
	stars.clear()
	selected_level = 1
	save_game()

func save_game():
	var payload := {
		"max_unlocked": max_unlocked,
		"stars": stars,
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
