# Settings.gd
# Reusable settings overlay (instanced as a child). Emits `closed` when done.
extends CanvasLayer

signal closed

const PRIVACY_POLICY_URL := "https://altafhssn.github.io/NumberZIpZap/zippath_privacy.html"

@onready var sound_btn: Button = $Card/SoundBtn
@onready var haptics_btn: Button = $Card/HapticsBtn
@onready var tutorial_btn: Button = $Card/TutorialBtn
@onready var leaderboards_btn: Button = $Card/LeaderboardsBtn
@onready var premium_btn: Button = $Card/PremiumBtn
@onready var restore_btn: Button = $Card/RestoreBtn
@onready var account_btn: Button = $Card/AccountBtn
@onready var reset_btn: Button = $Card/ResetBtn
@onready var privacy_policy_btn: Button = $Card/PrivacyPolicyBtn
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
	account_btn.pressed.connect(_on_account)
	reset_btn.pressed.connect(_on_reset)
	privacy_policy_btn.pressed.connect(_on_privacy_policy)
	close_btn.pressed.connect(_on_close)
	_refresh_premium()
	IAP.purchase_completed.connect(_on_purchase_completed)
	FirebaseBackend.auth_changed.connect(_on_auth_changed)
	FirebaseBackend.backend_error.connect(_on_backend_error)
	_refresh_account()

func _refresh_account() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		account_btn.text = "Google Sign-In  ·  Mobile only"
		account_btn.disabled = true
		return
	account_btn.disabled = false
	if FirebaseBackend.is_signed_in():
		var name := str(FirebaseBackend.current_user.get("name", "Google account"))
		account_btn.text = "%s  ·  Sign out" % name
	else:
		account_btn.text = "Sign in with Google"

func _on_account() -> void:
	account_btn.disabled = true
	account_btn.text = "Please wait…"
	if FirebaseBackend.is_signed_in():
		FirebaseBackend.sign_out()
	else:
		FirebaseBackend.sign_in_with_google()

func _on_auth_changed(_signed_in: bool, _user: Dictionary) -> void:
	_refresh_account()

func _on_backend_error(message: String) -> void:
	push_warning("Firebase: %s" % message)
	account_btn.disabled = false
	account_btn.text = "Google Sign-In failed  ·  Retry"

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

func _on_privacy_policy():
	var error := OS.shell_open(PRIVACY_POLICY_URL)
	if error != OK:
		push_warning("Could not open Privacy Policy: %s" % error_string(error))

func _on_close():
	closed.emit()
	queue_free()
