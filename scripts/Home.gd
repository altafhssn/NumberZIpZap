# Home.gd - title screen
extends Control

const SettingsScene = preload("res://scenes/Settings.tscn")

@onready var play_btn: Button = $PlayBtn
@onready var daily_btn: Button = $DailyBtn
@onready var levels_btn: Button = $LevelsBtn
@onready var shop_btn: Button = $ShopBtn
@onready var settings_btn: Button = $SettingsBtn
@onready var progress_label: Label = $ProgressLabel

func _ready():
	Ads.show_banner()
	play_btn.pressed.connect(_on_play)
	daily_btn.pressed.connect(_on_daily)
	levels_btn.pressed.connect(_on_levels)
	shop_btn.pressed.connect(_on_shop)
	settings_btn.pressed.connect(_on_settings)
	var best = GameData.max_unlocked
	progress_label.text = "Continue - Level %d" % best if best > 1 else "Tap Play to start"
	_refresh_daily_button()

func _refresh_daily_button():
	var streak: int = GameData.daily_streak
	if not GameData.is_daily_available():
		daily_btn.text = "Daily Pond - %s" % _format_daily_wait(GameData.daily_lock_remaining_sec())
		daily_btn.disabled = true
	elif streak > 0:
		daily_btn.text = "Daily Pond - Streak %d" % streak
		daily_btn.disabled = false
	else:
		daily_btn.text = "Daily Pond"
		daily_btn.disabled = false

func _on_play():
	GameData.daily_mode = false
	GameData.selected_level = GameData.max_unlocked
	Transition.goto("res://scenes/Main.tscn")

func _on_daily():
	if not GameData.is_daily_available():
		_refresh_daily_button()
		return
	GameData.daily_mode = true
	Transition.goto("res://scenes/Main.tscn")

func _on_levels():
	GameData.daily_mode = false
	Transition.goto("res://scenes/BoxSelect.tscn")

func _on_shop():
	GameData.daily_mode = false
	Transition.goto("res://scenes/ShopScreen.tscn")

func _on_settings():
	if has_node("Settings"):
		return
	var s = SettingsScene.instantiate()
	s.name = "Settings"
	add_child(s)

func _format_daily_wait(seconds: int) -> String:
	var hours := int(ceil(float(seconds) / 3600.0))
	if hours > 1:
		return "%dh left" % hours
	return "1h left"
