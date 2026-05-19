# Ads.gd  (autoload singleton)
# IAA layer — AdMob-shaped API with a safe stub fallback.
#
# The game is fully "ad ready": all placement hooks call through here.
# When no native AdMob plugin is present (editor, or before the plugin is
# installed) every call is a safe no-op, EXCEPT rewarded ads which resolve
# immediately so the reward UX is testable. To go live:
#   1. Add the Godot AdMob Android plugin to android/plugins.
#   2. Put your real AdMob App ID in the Android manifest and the unit IDs
#      below (these are Google's official TEST ids — safe placeholders).
#   3. Replace the bodies in the "PLUGIN INTEGRATION POINTS" region with the
#      plugin's actual calls. Nothing else in the game needs to change.
extends Node

# --- AdMob unit IDs (Google official TEST ids — replace for production) ---
const APP_ID            := "ca-app-pub-3940256099942544~3347511713"
const BANNER_ID         := "ca-app-pub-3940256099942544/6300978111"
const INTERSTITIAL_ID   := "ca-app-pub-3940256099942544/1033173712"
const REWARDED_ID       := "ca-app-pub-3940256099942544/5224354917"

# Show an interstitial every Nth level completion
const INTERSTITIAL_EVERY := 3

var _plugin = null            # native AdMob singleton when available
var _banner_visible := false

func _ready():
	# Detect the native plugin (name depends on the chosen AdMob plugin build)
	for n in ["AdMob", "GodotAdMob", "PoingGodotAdMob"]:
		if Engine.has_singleton(n):
			_plugin = Engine.get_singleton(n)
			break
	if _plugin:
		_init_plugin()
	else:
		print("[Ads] No AdMob plugin — running in stub mode (no-op ads).")

# ----------------------------- public API --------------------------------

func show_banner():
	_banner_visible = true
	if _plugin == null:
		return
	# PLUGIN INTEGRATION POINT: load + show banner (BANNER_ID)

func hide_banner():
	_banner_visible = false
	if _plugin == null:
		return
	# PLUGIN INTEGRATION POINT: hide/destroy banner

# Counts completions and only actually shows every INTERSTITIAL_EVERY-th call.
var _completions := 0
func notify_level_complete_then_interstitial():
	_completions += 1
	if _completions % INTERSTITIAL_EVERY == 0:
		show_interstitial()

func show_interstitial():
	if _plugin == null:
		print("[Ads] (stub) interstitial")
		return
	# PLUGIN INTEGRATION POINT: show a loaded interstitial (INTERSTITIAL_ID),
	# preload the next one on close.

# kind is just a tag for analytics ("hint" / "continue").
# on_reward is called ONLY when the user earns the reward.
func show_rewarded(kind: String, on_reward: Callable):
	if _plugin == null:
		# Stub: grant immediately so the reward flow is fully testable.
		print("[Ads] (stub) rewarded '%s' -> granting" % kind)
		on_reward.call_deferred()
		return
	# PLUGIN INTEGRATION POINT: show rewarded (REWARDED_ID); on the plugin's
	# "user_earned_reward" signal call on_reward.call(); preload the next.

func _init_plugin():
	if _plugin == null:
		return
	# PLUGIN INTEGRATION POINT: initialize(APP_ID), set test devices,
	# preload interstitial + rewarded, connect plugin signals.
	print("[Ads] AdMob plugin detected and initialized.")
