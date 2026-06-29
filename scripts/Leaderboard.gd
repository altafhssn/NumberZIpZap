# Leaderboard.gd  (autoload singleton)
#
# Wraps Google Play Games Services leaderboards through the installed
# GodotPlayGameServices addon.
extends Node

const LB_DAILY := "CgkIIYy7_pASEAIQAQ"
const LB_PACKS := [
	"CgkIIYy7_pASEAIQAg",  # First Pond  (levels 1-30)
	"CgkIIYy7_pASEAIQAw",  # Reed Path   (levels 31-80)
	"CgkIIYy7_pASEAIQBA",  # Stone Bend  (levels 81-130)
	"CgkIIYy7_pASEAIQBQ",  # Moon Pool   (levels 131-200)
	"CgkIIYy7_pASEAIQBg",  # Garden      (levels 201+)
]

signal scores_loaded(leaderboard_id: String, scores: Array)

var signed_in: bool = false
var _initialized: bool = false
var _sign_in_client: PlayGamesSignInClient
var _leaderboards_client: PlayGamesLeaderboardsClient
var _pending_scores: Array[Dictionary] = []
# Loads queued while we wait for sign-in. Each entry is { id, max }. Flushed
# in _on_user_authenticated when the player completes the Play Games sign-in.
var _pending_loads: Array[Dictionary] = []

func _ready() -> void:
	_initialize_play_games()
	sign_in()

func _is_android() -> bool:
	return OS.get_name() == "Android"

func _initialize_play_games() -> bool:
	if _initialized:
		return true
	if not _is_android():
		signed_in = true
		return false

	var result = GodotPlayGameServices.initialize()
	if result != GodotPlayGameServices.PlayGamesPluginError.OK:
		push_warning("[Leaderboard] Play Games plugin is unavailable.")
		return false

	_sign_in_client = PlayGamesSignInClient.new()
	add_child(_sign_in_client)
	_sign_in_client.user_authenticated.connect(_on_user_authenticated)

	_leaderboards_client = PlayGamesLeaderboardsClient.new()
	add_child(_leaderboards_client)
	_leaderboards_client.score_submitted.connect(_on_score_submitted)
	_leaderboards_client.top_scores_loaded.connect(_on_top_scores_loaded)

	_initialized = true
	return true

func _encode(petals: int, time_sec: float) -> int:
	var ms := int(maxf(0.0, time_sec) * 1000.0)
	return petals * 1000000 - ms

func sign_in() -> void:
	if not _is_android():
		print("[Leaderboard] sign_in (editor stub)")
		signed_in = true
		return
	if not _initialize_play_games():
		return
	_sign_in_client.sign_in()

func submit_daily(petals: int, time_sec: float) -> void:
	_submit_score(LB_DAILY, _encode(petals, time_sec))

func submit_pack(pack_idx: int, total_petals: int, total_time_sec: float) -> void:
	if pack_idx < 0 or pack_idx >= LB_PACKS.size():
		push_warning("[Leaderboard] submit_pack: invalid pack_idx %d" % pack_idx)
		return
	var lb_id := str(LB_PACKS[pack_idx])
	if lb_id == "":
		if not _is_android():
			print("[Leaderboard] submit_pack skipped: missing leaderboard id for pack %d" % pack_idx)
		return
	_submit_score(lb_id, _encode(total_petals, total_time_sec))

func show_daily() -> void:
	_show_leaderboard(LB_DAILY)

func show_pack(pack_idx: int) -> void:
	if pack_idx < 0 or pack_idx >= LB_PACKS.size():
		return
	var lb_id := str(LB_PACKS[pack_idx])
	if lb_id == "":
		show_all()
		return
	_show_leaderboard(lb_id)

func show_all() -> void:
	if not _is_android():
		print("[Leaderboard] show_all (editor stub)")
		return
	if not _initialize_play_games():
		return
	_leaderboards_client.show_all_leaderboards()

func _submit_score(leaderboard_id: String, score: int) -> void:
	if leaderboard_id == "":
		return
	if not _is_android():
		print("[Leaderboard] submit_score[%s] score=%d (editor stub)" % [leaderboard_id, score])
		return
	if not _initialize_play_games():
		return
	if not signed_in:
		_pending_scores.append({"leaderboard_id": leaderboard_id, "score": score})
		_sign_in_client.sign_in()
		return
	_leaderboards_client.submit_score(leaderboard_id, score)

func _show_leaderboard(leaderboard_id: String) -> void:
	if leaderboard_id == "":
		return
	if not _is_android():
		print("[Leaderboard] show_leaderboard[%s] (editor stub)" % leaderboard_id)
		return
	if not _initialize_play_games():
		return
	_leaderboards_client.show_leaderboard(leaderboard_id)

func _on_user_authenticated(is_authenticated: bool) -> void:
	signed_in = is_authenticated
	if not signed_in:
		# Sign-in failed — drain any queued loads with an empty result so the
		# screen can show "No scores yet" instead of staying at "Loading...".
		for q in _pending_loads:
			emit_signal("scores_loaded", str(q["id"]), [])
		_pending_loads.clear()
		return
	# Flush any in-memory pending submissions captured during this session.
	var queued := _pending_scores.duplicate()
	_pending_scores.clear()
	for item in queued:
		_leaderboards_client.submit_score(str(item["leaderboard_id"]), int(item["score"]))
	# Backfill: every pack's CURRENT cumulative score is resubmitted on every
	# successful sign-in. This fixes the case where the player completed
	# levels in earlier sessions but sign-in failed/was delayed and the
	# in-memory queue was lost when the app closed. Play Games only keeps
	# the player's best score per leaderboard, so resubmitting their current
	# totals is safe and idempotent.
	for i in range(GameData.PACK_RANGES.size()):
		if i >= LB_PACKS.size():
			break
		var totals: Dictionary = GameData.get_pack_totals(i)
		if int(totals.get("completed", 0)) <= 0:
			continue
		var score := _encode(int(totals["petals"]), float(totals["time"]))
		_leaderboards_client.submit_score(str(LB_PACKS[i]), score)
	# Now flush any pending leaderboard reads.
	var queued_loads := _pending_loads.duplicate()
	_pending_loads.clear()
	for q in queued_loads:
		_leaderboards_client.load_top_scores(
			str(q["id"]),
			PlayGamesLeaderboardVariant.TimeSpan.TIME_SPAN_ALL_TIME,
			PlayGamesLeaderboardVariant.Collection.COLLECTION_PUBLIC,
			int(q["max"]),
			true
		)

func _on_score_submitted(is_submitted: bool, leaderboard_id: String) -> void:
	if not is_submitted:
		push_warning("[Leaderboard] score submit failed for %s" % leaderboard_id)

# --- Score fetching (for the in-game leaderboard screen) -----------------
# Loads the top entries on a board and emits `scores_loaded` with a clean
# decoded array each entry shaped like:
#   { "rank": int, "name": String, "petals": int, "time_sec": float,
#     "raw_score": int, "icon_uri": String, "is_self": bool }
# In editor we synthesise a small sample so the UI can be developed offline.
func load_top(leaderboard_id: String, max_results: int = 25) -> void:
	if leaderboard_id == "":
		emit_signal("scores_loaded", "", [])
		return
	if not _is_android():
		print("[Leaderboard] load_top[%s] (editor stub)" % leaderboard_id)
		var fake := [
			{"rank": 1, "name": "Alice",   "petals": 3, "time_sec": 42.5,  "raw_score": 2999957500, "icon_uri": "", "is_self": false},
			{"rank": 2, "name": "Bo",      "petals": 3, "time_sec": 51.0,  "raw_score": 2999949000, "icon_uri": "", "is_self": false},
			{"rank": 3, "name": "You",     "petals": 2, "time_sec": 38.2,  "raw_score": 1999961800, "icon_uri": "", "is_self": true},
			{"rank": 4, "name": "Charlie", "petals": 2, "time_sec": 78.0,  "raw_score": 1999922000, "icon_uri": "", "is_self": false},
			{"rank": 5, "name": "Dee",     "petals": 1, "time_sec": 30.1,  "raw_score": 999969900,  "icon_uri": "", "is_self": false},
		]
		call_deferred("emit_signal", "scores_loaded", leaderboard_id, fake)
		return
	if not _initialize_play_games():
		emit_signal("scores_loaded", leaderboard_id, [])
		return
	# If sign-in hasn't completed yet, queue the load and kick off sign-in.
	# When `user_authenticated` fires, we flush the queue.
	if not signed_in:
		_pending_loads.append({"id": leaderboard_id, "max": clampi(max_results, 1, 25)})
		_sign_in_client.sign_in()
		return
	_leaderboards_client.load_top_scores(
		leaderboard_id,
		PlayGamesLeaderboardVariant.TimeSpan.TIME_SPAN_ALL_TIME,
		PlayGamesLeaderboardVariant.Collection.COLLECTION_PUBLIC,
		clampi(max_results, 1, 25),
		true
	)

func _on_top_scores_loaded(leaderboard_id: String, leaderboard_scores) -> void:
	var rows: Array = []
	if leaderboard_scores != null and leaderboard_scores.scores != null:
		for s in leaderboard_scores.scores:
			var raw: int = int(s.raw_score)
			# raw_score = petals*1_000_000 - elapsed_ms. Decode back to display.
			var petals: int = int(floor(float(raw) / 1_000_000.0))
			var ms: int = petals * 1_000_000 - raw
			rows.append({
				"rank": int(s.rank),
				"name": str(s.score_holder_display_name),
				"petals": petals,
				"time_sec": float(ms) / 1000.0,
				"raw_score": raw,
				"icon_uri": str(s.score_holder_icon_image_uri),
				"is_self": false, # plugin doesn't flag this; UI can compare names if needed
			})
	emit_signal("scores_loaded", leaderboard_id, rows)
