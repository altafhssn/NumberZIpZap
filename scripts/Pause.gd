# Pause.gd — in-game pause overlay (instanced as a child of Main)
extends CanvasLayer

signal resume_requested
signal restart_requested
signal home_requested

const SettingsScene = preload("res://scenes/Settings.tscn")

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Card/ResumeBtn.pressed.connect(_on_resume)
	$Card/RestartBtn.pressed.connect(func(): restart_requested.emit(); _close())
	$Card/SettingsBtn.pressed.connect(_on_settings)
	$Card/HomeBtn.pressed.connect(func(): home_requested.emit())

func _on_resume():
	resume_requested.emit()
	_close()

func _on_settings():
	if has_node("Settings"):
		return
	var s = SettingsScene.instantiate()
	s.name = "Settings"
	add_child(s)

func _close():
	queue_free()
