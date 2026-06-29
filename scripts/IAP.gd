# IAP.gd  (autoload singleton)
#
# Pass 1: stubs. Pass 2 swaps for the Google Play Billing plugin
# (godot-google-play-billing or equivalent).
#
# Single product: "Calm Forever" — one-time non-consumable that flips
# GameData.is_premium = true. Removes banner + interstitial ads forever and
# grants unlimited hints.
extends Node

signal purchase_completed(product_id: String)
signal purchase_failed(product_id: String, reason: String)

const PRODUCT_CALM_FOREVER := "calm_forever"

# Local fallback for editor builds and pre-Play-Console testing. The Play
# Console will return the real localized price string in Pass 2.
const PRICE_FALLBACK := "$1.99"

func _is_android() -> bool:
	return OS.get_name() == "Android"

func _ready() -> void:
	# Pass 2: connect to billing plugin signals and call refresh_purchases()
	# at boot so reinstalls restore "Calm Forever" automatically.
	pass

# Returns the localized display price, or PRICE_FALLBACK in the editor.
func get_price(_product_id: String) -> String:
	if not _is_android():
		return PRICE_FALLBACK
	# TODO Pass 2:
	# return GooglePlayBilling.get_price(product_id)
	return PRICE_FALLBACK

# Kick off the purchase flow. Emits purchase_completed on success.
func purchase(product_id: String) -> void:
	if not _is_android():
		print("[IAP] purchase %s (stub) — auto-granting" % product_id)
		_grant(product_id)
		return
	# TODO Pass 2:
	# GooglePlayBilling.purchase(product_id)

# Replay previous non-consumable purchases (called from Settings).
func restore_purchases() -> void:
	if not _is_android():
		print("[IAP] restore_purchases (stub)")
		return
	# TODO Pass 2:
	# GooglePlayBilling.query_purchases()

func _grant(product_id: String) -> void:
	if product_id == PRODUCT_CALM_FOREVER:
		GameData.set_premium(true)
		Ads.hide_banner()
		emit_signal("purchase_completed", product_id)
