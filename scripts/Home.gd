# Home.gd — title screen
extends Control

const SettingsScene = preload("res://scenes/Settings.tscn")

@onready var play_btn: Button = $PlayBtn
@onready var levels_btn: Button = $LevelsBtn
@onready var settings_btn: Button = $SettingsBtn
@onready var progress_label: Label = $ProgressLabel

func _ready():
	play_btn.pressed.connect(_on_play)
	levels_btn.pressed.connect(_on_levels)
	settings_btn.pressed.connect(_on_settings)
	var best = GameData.max_unlocked
	progress_label.text = "Continue · Level %d" % best if best > 1 else "Tap Play to start"

func _on_play():
	GameData.selected_level = GameData.max_unlocked
	Transition.goto("res://scenes/Main.tscn")

func _on_levels():
	Transition.goto("res://scenes/LevelSelect.tscn")

func _on_settings():
	if has_node("Settings"):
		return
	var s = SettingsScene.instantiate()
	s.name = "Settings"
	add_child(s)
