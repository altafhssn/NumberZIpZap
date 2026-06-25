# Music.gd  (autoload singleton)
# Calm seamless ambient pad that plays continuously across all screens.
# Per-sector tracks (Tutorial = calm, Nova = energetic, etc.) are synthesised
# lazily and cached, then crossfaded between two AudioStreamPlayer instances.
extends Node

const RATE := 16000
const CROSSFADE_SEC := 0.8
const DEFAULT_KEY := "spark_loop"

# Per-key tuning. One entry per SectorThemes pack. Root note + LFO speed +
# spectral tilt all shift between sectors so each world sounds distinct
# without new audio assets. Missing keys silently fall back to the default.
const KEY_PRESETS := {
	"spark_loop":    { "root": 73.42,  "lfo_mult": 0.9, "tilt": 0.05 },  # Spark    — D2, calm-warm
	"glow_loop":     { "root": 65.41,  "lfo_mult": 0.8, "tilt": 0.10 },  # Glow     — C2, slower & brighter
	"ember_loop":    { "root": 49.00,  "lfo_mult": 1.8, "tilt": -0.05 }, # Ember    — G1, low/tense rumble
	"nova_loop":     { "root": 58.27,  "lfo_mult": 1.6, "tilt": -0.10 }, # Nova     — A#1, cosmic detune
	"infinite_loop": { "root": 82.41,  "lfo_mult": 1.3, "tilt": 0.05 },  # Infinite — E2, brighter digital
}

var _players: Array = []     # 2-element pool for crossfading
var _active := 0             # index of the currently audible player
var _streams: Dictionary = {} # key -> AudioStreamWAV (lazy cache)
var _current_key: String = ""
var _on := false
var _ready_built := false

func _ready():
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -7.0
		add_child(p)
		_players.append(p)
	# Build the (heavy) default buffer AFTER the first frame so app startup is
	# not blocked — a synchronous build here ANRs/crashes on Android at launch.
	_build_deferred.call_deferred()

func _build_deferred():
	await get_tree().process_frame
	var stream := _make_music(KEY_PRESETS[DEFAULT_KEY])
	_streams[DEFAULT_KEY] = stream
	_players[0].stream = stream
	_current_key = DEFAULT_KEY
	_ready_built = true
	_update()

func _process(_delta):
	if _ready_built and GameData.sound_on != _on:
		_update()

func _update():
	if not _ready_built:
		return
	_on = GameData.sound_on
	var p: AudioStreamPlayer = _players[_active]
	if _on:
		if not p.playing:
			p.play()
	else:
		for q in _players:
			q.stop()

# Switch to a different per-sector track. Unknown keys (or repeat calls with
# the same key) are silent no-ops, satisfying the "fall back to default" rule.
func play_key(key: String):
	if not _ready_built:
		# Pre-build the requested key once the default finishes building.
		_pending_key = key
		return
	if key == _current_key or key == "":
		return
	if not KEY_PRESETS.has(key):
		return  # unknown key, keep current track
	# Lazy-build the stream for this key, deferred so we never block a frame.
	if not _streams.has(key):
		_build_stream_deferred.call_deferred(key)
		_pending_key = key
		return
	_crossfade_to(key)

var _pending_key: String = ""

func _build_stream_deferred(key: String):
	await get_tree().process_frame
	if not _streams.has(key) and KEY_PRESETS.has(key):
		_streams[key] = _make_music(KEY_PRESETS[key])
	if _pending_key == key:
		_pending_key = ""
		if _on:
			_crossfade_to(key)
		else:
			# Sound off — just swap the assigned stream so it's ready later.
			_players[_active].stream = _streams[key]
			_current_key = key

func _crossfade_to(key: String):
	var from: AudioStreamPlayer = _players[_active]
	var to: AudioStreamPlayer = _players[1 - _active]
	to.stream = _streams[key]
	to.volume_db = -40.0
	to.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(to, "volume_db", -7.0, CROSSFADE_SEC)
	tw.tween_property(from, "volume_db", -40.0, CROSSFADE_SEC)
	tw.tween_callback(func():
		from.stop()
		from.volume_db = -7.0).set_delay(CROSSFADE_SEC)
	_active = 1 - _active
	_current_key = key

# All partial + LFO frequencies snapped to integer multiples of 1/L so the
# buffer is perfectly periodic — a click-free loop. `preset` shifts the root
# and tweaks LFO speed / spectral tilt so each sector sounds distinct without
# new asset files.
func _make_music(preset: Dictionary) -> AudioStreamWAV:
	var L := 12.0
	var count := int(RATE * L)
	var base := 1.0 / L
	# Minor-pad voicing relative to a root. Frequencies shown for D2 root and
	# scaled by (preset.root / 73.42) so the chord shape transposes cleanly.
	var root: float = float(preset.get("root", 73.42))
	var lfo_mult: float = float(preset.get("lfo_mult", 1.0))
	var tilt: float = float(preset.get("tilt", 0.0))
	var ratio := root / 73.42
	var partials := [
		[73.42,  0.22, 0.041, 0.45],
		[87.31,  0.18, 0.058, 0.55],
		[110.0,  0.14, 0.067, 0.55],
		[146.83, 0.13, 0.083, 0.60],
		[174.61, 0.10, 0.10,  0.65],
		[220.0,  0.07, 0.125, 0.70],
		[349.23, 0.05, 0.15,  0.80],
	]
	var tuned := []
	var norm := 0.0
	for i in range(partials.size()):
		var p = partials[i]
		# Tilt biases higher partials brighter/darker (positive = brighter).
		var weight: float = float(p[1]) * (1.0 + tilt * float(i))
		weight = maxf(0.01, weight)
		var f: float = maxf(base, round(float(p[0]) * ratio / base) * base)
		var lf: float = maxf(base, round(float(p[2]) * lfo_mult / base) * base)
		tuned.append([f, weight, lf, p[3]])
		norm += weight

	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(RATE)
		var s := 0.0
		for p in tuned:
			var depth: float = p[3]
			var lfo: float = 0.5 * (1.0 + sin(TAU * p[2] * t))
			var amp: float = p[1] * ((1.0 - depth) + depth * lfo)
			s += amp * sin(TAU * p[0] * t)
		var v := int(clampf((s / norm) * 0.85, -1.0, 1.0) * 32767.0)
		if v < 0:
			v += 65536
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF

	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = count
	return w
