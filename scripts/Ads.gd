# Ads.gd  (autoload singleton)
#
# Pass 1: stubs. Pass 2 swaps these bodies for real AdMob calls via the
# poing/godot-admob-android plugin (or equivalent).
#
# All formats are *gated by GameData.is_premium* — buying "Calm Forever" turns
# every banner and interstitial into a no-op while still allowing opt-in
# rewarded videos.
extends Node

# --- Placeholder unit IDs. Replace with real AdMob unit IDs in Pass 2.
const UNIT_BANNER       := "ca-app-pub-XXXXXXXXXXXX/XXXXXXXXX-banner"
const UNIT_INTERSTITIAL := "ca-app-pub-XXXXXXXXXXXX/XXXXXXXXX-inter"
const UNIT_REWARDED     := "ca-app-pub-XXXXXXXXXXXX/XXXXXXXXX-reward"

var _banner_shown: bool = false

func _is_android() -> bool:
	return OS.get_name() == "Android"

# --- Banner (bottom-anchored, adaptive size in Pass 2) ---

func show_banner() -> void:
	if GameData.is_premium:
		hide_banner()
		return
	if _banner_shown:
		return
	_banner_shown = true
	if not _is_android():
		print("[Ads] show_banner (stub)")
		return
	# TODO Pass 2:
	# AdMob.load_banner(UNIT_BANNER, "BOTTOM", "ADAPTIVE")
	# AdMob.show_banner()

func hide_banner() -> void:
	if not _banner_shown:
		return
	_banner_shown = false
	if not _is_android():
		print("[Ads] hide_banner (stub)")
		return
	# TODO Pass 2: AdMob.hide_banner()

# --- Interstitial (full-screen between levels) ---
# Skips the first 5 levels entirely and only fires every 3rd qualifying
# completion. Premium players never see one.
func notify_level_complete_then_interstitial(current_level: int, on_done: Callable = Callable()) -> void:
	if GameData.is_premium:
		_safe_call(on_done)
		return
	if current_level <= 5:
		# Early-game grace period: don't ad-bomb new players.
		_safe_call(on_done)
		return
	GameData.levels_since_interstitial += 1
	if GameData.levels_since_interstitial < 3:
		GameData.save_game()
		_safe_call(on_done)
		return
	GameData.levels_since_interstitial = 0
	GameData.save_game()
	_show_interstitial(on_done)

func _show_interstitial(on_done: Callable) -> void:
	if not _is_android():
		print("[Ads] show_interstitial (stub)")
		_safe_call(on_done)
		return
	# TODO Pass 2:
	# AdMob.load_interstitial(UNIT_INTERSTITIAL)
	# AdMob.connect("interstitial_closed", func(): _safe_call(on_done))
	# AdMob.show_interstitial()

# --- Rewarded (opt-in) ---
# Always available, even for premium players (they explicitly opted in).
# `kind` is just a tag for analytics ("hint" / "continue" / etc).
func show_rewarded(kind: String, on_reward: Callable) -> void:
	if not _is_android():
		print("[Ads] show_rewarded[%s] (stub) — auto-granting reward" % kind)
		_safe_call(on_reward)
		return
	# TODO Pass 2:
	# AdMob.load_rewarded(UNIT_REWARDED)
	# AdMob.connect("rewarded_user_earned_reward", func(_t, _a): _safe_call(on_reward))
	# AdMob.show_rewarded()

func _safe_call(c: Callable) -> void:
	if c.is_valid():
		c.call_deferred()
