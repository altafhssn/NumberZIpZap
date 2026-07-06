# Ads.gd (autoload singleton)
#
# Android AdMob integration via poingstudios/godot-admob-plugin. The IDs below
# are Google's official test IDs; replace all four before publishing.
extends Node

const UNIT_BANNER := "ca-app-pub-9716577681904769/3753716208"
const UNIT_INTERSTITIAL := "ca-app-pub-9716577681904769/2843160451"
const UNIT_REWARDED := "ca-app-pub-9716577681904769/2651588760"

var _initialized := false
var _banner_shown := false
var _banner: AdView
var _banner_listener := AdListener.new()
var _interstitial: InterstitialAd
var _interstitial_load_callback := InterstitialAdLoadCallback.new()
var _interstitial_content_callback := FullScreenContentCallback.new()
var _interstitial_done := Callable()
var _rewarded: RewardedAd
var _rewarded_load_callback := RewardedAdLoadCallback.new()
var _rewarded_content_callback := FullScreenContentCallback.new()
var _reward_listener := OnUserEarnedRewardListener.new()
var _pending_reward := Callable()


func _ready() -> void:
	if not _is_android():
		return
	_configure_callbacks()
	_request_consent()


func _is_android() -> bool:
	return OS.get_name() == "Android"


func _configure_callbacks() -> void:
	_banner_listener.on_ad_loaded = _on_banner_loaded
	_banner_listener.on_ad_failed_to_load = _on_banner_failed_to_load

	_interstitial_load_callback.on_ad_loaded = _on_interstitial_loaded
	_interstitial_load_callback.on_ad_failed_to_load = _on_interstitial_failed_to_load
	_interstitial_content_callback.on_ad_dismissed_full_screen_content = _on_interstitial_closed
	_interstitial_content_callback.on_ad_failed_to_show_full_screen_content = _on_interstitial_failed_to_show

	_rewarded_load_callback.on_ad_loaded = _on_rewarded_loaded
	_rewarded_load_callback.on_ad_failed_to_load = _on_rewarded_failed_to_load
	_rewarded_content_callback.on_ad_dismissed_full_screen_content = _on_rewarded_closed
	_rewarded_content_callback.on_ad_failed_to_show_full_screen_content = _on_rewarded_failed_to_show
	_reward_listener.on_user_earned_reward = _on_reward_earned


# UMP presents Google's consent form only where it is required. If consent
# cannot be refreshed (for example while offline), the SDK still initializes
# and decides whether a limited ad can be served.
func _request_consent() -> void:
	UserMessagingPlatform.consent_information.update(
		ConsentRequestParameters.new(),
		_on_consent_updated,
		_on_consent_update_failed
	)


func _on_consent_updated() -> void:
	if not UserMessagingPlatform.consent_information.get_is_consent_form_available():
		_initialize_ads()
		return
	UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_form_failed)


func _on_consent_form_loaded(form: ConsentForm) -> void:
	var status := UserMessagingPlatform.consent_information.get_consent_status()
	if status == ConsentInformation.ConsentStatus.REQUIRED:
		form.show(_on_consent_form_dismissed)
	else:
		_initialize_ads()


func _on_consent_form_dismissed(error: FormError) -> void:
	if error:
		push_warning("[Ads] Consent form: %s" % error.message)
	_initialize_ads()


func _on_consent_update_failed(error: FormError) -> void:
	push_warning("[Ads] Consent update: %s" % error.message)
	_initialize_ads()


func _on_consent_form_failed(error: FormError) -> void:
	push_warning("[Ads] Consent form load: %s" % error.message)
	_initialize_ads()


func _initialize_ads() -> void:
	if _initialized:
		return
	_initialized = true
	MobileAds.initialize()
	_load_interstitial()
	_load_rewarded()
	if _banner_shown:
		_create_banner()


# --- Banner: bottom-anchored adaptive width ---

func show_banner() -> void:
	if GameData.is_premium:
		hide_banner()
		return
	_banner_shown = true
	if not _is_android():
		return
	if _banner:
		_banner.show()
	elif _initialized:
		_create_banner()


func hide_banner() -> void:
	_banner_shown = false
	if _banner:
		_banner.hide()


func _create_banner() -> void:
	if _banner:
		return
	var size := AdSize.get_current_orientation_anchored_adaptive_banner_ad_size(AdSize.FULL_WIDTH)
	_banner = AdView.new(UNIT_BANNER, size, AdPosition.Values.BOTTOM)
	_banner.ad_listener = _banner_listener
	_banner.load_ad(AdRequest.new())


func _on_banner_loaded() -> void:
	if _banner and not _banner_shown:
		_banner.hide()


func _on_banner_failed_to_load(error: LoadAdError) -> void:
	push_warning("[Ads] Banner failed to load: %s" % error.message)
	if _banner:
		_banner.destroy()
		_banner = null


# --- Interstitial: after the first five levels, then every third completion ---

func notify_level_complete_then_interstitial(current_level: int, on_done: Callable = Callable()) -> void:
	if GameData.is_premium or current_level <= 5:
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


func _load_interstitial() -> void:
	if not _initialized or _interstitial:
		return
	InterstitialAdLoader.new().load(UNIT_INTERSTITIAL, AdRequest.new(), _interstitial_load_callback)


func _on_interstitial_loaded(ad: InterstitialAd) -> void:
	_interstitial = ad
	_interstitial.full_screen_content_callback = _interstitial_content_callback


func _on_interstitial_failed_to_load(error: LoadAdError) -> void:
	push_warning("[Ads] Interstitial failed to load: %s" % error.message)


func _show_interstitial(on_done: Callable) -> void:
	if not _is_android() or not _interstitial:
		_safe_call(on_done)
		_load_interstitial()
		return
	_interstitial_done = on_done
	_interstitial.show()


func _on_interstitial_closed() -> void:
	_finish_interstitial()


func _on_interstitial_failed_to_show(error: AdError) -> void:
	push_warning("[Ads] Interstitial failed to show: %s" % error.message)
	_finish_interstitial()


func _finish_interstitial() -> void:
	if _interstitial:
		_interstitial.destroy()
		_interstitial = null
	_safe_call(_interstitial_done)
	_interstitial_done = Callable()
	_load_interstitial()


# --- Rewarded: opt-in and available even for premium players ---

func _load_rewarded() -> void:
	if not _initialized or _rewarded:
		return
	RewardedAdLoader.new().load(UNIT_REWARDED, AdRequest.new(), _rewarded_load_callback)


func _on_rewarded_loaded(ad: RewardedAd) -> void:
	_rewarded = ad
	_rewarded.full_screen_content_callback = _rewarded_content_callback
	if _pending_reward.is_valid():
		_rewarded.show(_reward_listener)


func _on_rewarded_failed_to_load(error: LoadAdError) -> void:
	push_warning("[Ads] Rewarded ad failed to load: %s" % error.message)
	_pending_reward = Callable()


func show_rewarded(kind: String, on_reward: Callable) -> void:
	if not _is_android():
		print("[Ads] show_rewarded[%s] (editor preview)" % kind)
		_safe_call(on_reward)
		return
	_pending_reward = on_reward
	if _rewarded:
		_rewarded.show(_reward_listener)
	else:
		_load_rewarded()


func _on_reward_earned(_item: RewardedItem) -> void:
	_safe_call(_pending_reward)
	_pending_reward = Callable()


func _on_rewarded_closed() -> void:
	_finish_rewarded()


func _on_rewarded_failed_to_show(error: AdError) -> void:
	push_warning("[Ads] Rewarded ad failed to show: %s" % error.message)
	_pending_reward = Callable()
	_finish_rewarded()


func _finish_rewarded() -> void:
	if _rewarded:
		_rewarded.destroy()
		_rewarded = null
	_pending_reward = Callable()
	_load_rewarded()


func _safe_call(callback: Callable) -> void:
	if callback.is_valid():
		callback.call_deferred()
