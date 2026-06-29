# Settings.gd
# Reusable settings overlay (instanced as a child). Emits `closed` when done.
extends CanvasLayer

signal closed

@onready var sound_btn: Button = $Card/SoundBtn
@onready var haptics_btn: Button = $Card/HapticsBtn
@onready var tutorial_btn: Button = $Card/TutorialBtn
@onready var leaderboards_btn: Button = $Card/LeaderboardsBtn
@onready var premium_btn: Button = $Card/PremiumBtn
@onready var restore_btn: Button = $Card/RestoreBtn
@onready var reset_btn: Button = $Card/ResetBtn
@onready var close_btn: Button = $Card/CloseBtn

var _confirm_reset := false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_sound()
	_refresh_haptics()
	sound_btn.pressed.connect(_on_sound)
	haptics_btn.pressed.connect(_on_haptics)
	tutorial_btn.pressed.connect(_on_tutorial)
	leaderboards_btn.pressed.connect(_on_leaderboards)
	premium_btn.pressed.connect(_on_premium)
	restore_btn.pressed.connect(_on_restore)
	reset_btn.pressed.connect(_on_reset)
	close_btn.pressed.connect(_on_close)
	_refresh_premium()
	IAP.purchase_completed.connect(_on_purchase_completed)

func _on_leaderboards():
	# Open ZipPath's in-game leaderboard screen instead of Google's native
	# overlay so the experience stays inside the game's aesthetic.
	GameData.selected_leaderboard_idx = 0  # land on Daily Pond
	closed.emit()
	Transition.goto("res://scenes/LeaderboardScreen.tscn")
	queue_free()

func _refresh_premium():
	if GameData.is_premium:
		premium_btn.text = "Calm Forever  ·  Owned ✓"
		premium_btn.disabled = true
		restore_btn.visible = true
	else:
		# IAP not wired yet — show "Coming soon" disabled state until v1.1
		# release. Hide the Restore link too since it has nothing to restore.
		premium_btn.text = "Calm Forever  ·  Coming soon"
		premium_btn.disabled = true
		restore_btn.visible = false

func _on_premium():
	IAP.purchase(IAP.PRODUCT_CALM_FOREVER)

func _on_restore():
	IAP.restore_purchases()
	restore_btn.text = "Restoring…"
	# Give the platform a moment, then refresh.
	await get_tree().create_timer(1.0).timeout
	_refresh_premium()
	restore_btn.text = "Restore purchases"

func _on_purchase_completed(_product_id: String):
	_refresh_premium()

func _on_tutorial():
	GameData.tutorial_done = false
	GameData.selected_level = 1
	GameData.save_game()
	get_tree().paused = false
	Transition.goto("res://scenes/Main.tscn")
	queue_free()

func _refresh_sound():
	var on := GameData.sound_on
	sound_btn.text = "Sound: On" if on else "Sound: Off"

func _refresh_haptics():
	var on := GameData.haptics_on
	haptics_btn.text = "Haptics: On" if on else "Haptics: Off"

func _on_sound():
	GameData.sound_on = not GameData.sound_on
	GameData.save_game()
	_refresh_sound()

func _on_haptics():
	GameData.haptics_on = not GameData.haptics_on
	GameData.save_game()
	_refresh_haptics()
	if GameData.haptics_on:
		Input.vibrate_handheld(15)

func _on_reset():
	if not _confirm_reset:
		_confirm_reset = true
		reset_btn.text = "Tap again to confirm"
		return
	GameData.reset_progress()
	_confirm_reset = false
	reset_btn.text = "Progress reset"

func _on_close():
	closed.emit()
	queue_free()
