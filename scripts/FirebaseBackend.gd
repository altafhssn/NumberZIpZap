extends Node

signal auth_changed(signed_in: bool, user: Dictionary)
signal backend_error(message: String)

var current_user: Dictionary = {}
var _firebase: Node

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	if OS.has_feature("ios"):
		_firebase = get_node_or_null("/root/FirebaseIOS")
	else:
		_firebase = get_node_or_null("/root/Firebase")
	if _firebase == null:
		if not OS.has_feature("editor"):
			backend_error.emit("Firebase Android plugin is unavailable.")
		return
	_firebase.auth.auth_success.connect(_on_auth_success)
	_firebase.auth.auth_failure.connect(_on_auth_failure)
	_firebase.auth.sign_out_success.connect(_on_sign_out)
	_firebase.firestore.write_task_completed.connect(_on_profile_write)
	if _firebase.auth.is_signed_in():
		_on_auth_success(_firebase.auth.get_current_user_data())

func is_available() -> bool:
	return _firebase != null and (OS.has_feature("android") or OS.has_feature("ios"))

func is_signed_in() -> bool:
	return not current_user.is_empty()

func sign_in_with_google() -> void:
	if not is_available():
		backend_error.emit("Google Sign-In is available in Android builds.")
		return
	_firebase.auth.sign_in_with_google()

func sign_out() -> void:
	if _firebase != null:
		_firebase.auth.sign_out()

func _on_auth_success(user: Dictionary) -> void:
	current_user = _normalize_user(user)
	auth_changed.emit(true, current_user)
	_write_user_profile()

func _normalize_user(user: Dictionary) -> Dictionary:
	return {
		"uid": str(user.get("uid", "")),
		"name": str(user.get("name", user.get("displayName", ""))),
		"email": str(user.get("email", "")),
		"photoUrl": str(user.get("photoUrl", user.get("photoURL", ""))),
		"emailVerified": bool(user.get("emailVerified", user.get("isEmailVerified", false))),
	}

func _on_auth_failure(message: String) -> void:
	backend_error.emit(message)

func _on_sign_out(success: bool) -> void:
	if not success:
		return
	current_user.clear()
	auth_changed.emit(false, {})

func _write_user_profile() -> void:
	var uid := str(current_user.get("uid", ""))
	if uid.is_empty():
		backend_error.emit("Firebase returned a user without a uid.")
		return
	var profile := {
		"uid": uid,
		"display_name": str(current_user.get("name", "")),
		"email": str(current_user.get("email", "")),
		"photo_url": str(current_user.get("photoUrl", "")),
		"updated_at_unix": int(Time.get_unix_time_from_system()),
	}
	_firebase.firestore.set_document("users", uid, profile, true)

func _on_profile_write(result: Dictionary) -> void:
	if not bool(result.get("status", false)):
		backend_error.emit(str(result.get("error", "Could not update the Firebase profile.")))
