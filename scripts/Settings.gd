# Settings.gd
# Reusable settings overlay (instanced as a child). Emits `closed` when done.
extends CanvasLayer

signal closed

@onready var sound_btn: Button = $Card/SoundBtn
@onready var reset_btn: Button = $Card/ResetBtn
@onready var close_btn: Button = $Card/CloseBtn

var _confirm_reset := false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_sound()
	sound_btn.pressed.connect(_on_sound)
	reset_btn.pressed.connect(_on_reset)
	close_btn.pressed.connect(_on_close)

func _refresh_sound():
	var on := GameData.sound_on
	sound_btn.text = "🔊  Sound: On" if on else "🔇  Sound: Off"

func _on_sound():
	GameData.sound_on = not GameData.sound_on
	GameData.save_game()
	_refresh_sound()

func _on_reset():
	if not _confirm_reset:
		_confirm_reset = true
		reset_btn.text = "Tap again to confirm"
		return
	GameData.reset_progress()
	_confirm_reset = false
	reset_btn.text = "✓  Progress reset"

func _on_close():
	closed.emit()
	queue_free()
