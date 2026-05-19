# Music.gd  (autoload singleton)
# Calm seamless ambient pad that plays continuously across all screens.
extends Node

const RATE := 16000

var _player: AudioStreamPlayer
var _on := false
var _ready_built := false

func _ready():
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = -7.0
	add_child(_player)
	# Build the (heavy) buffer AFTER the first frame so app startup is not
	# blocked — a synchronous build here ANRs/crashes on Android at launch.
	_build_deferred.call_deferred()

func _build_deferred():
	await get_tree().process_frame
	_player.stream = _make_music()
	_ready_built = true
	_update()

func _process(_delta):
	if _ready_built and GameData.sound_on != _on:
		_update()

func _update():
	if not _ready_built:
		return
	_on = GameData.sound_on
	if _on:
		if not _player.playing:
			_player.play()
	else:
		_player.stop()

# All partial + LFO frequencies snapped to integer multiples of 1/L so the
# buffer is perfectly periodic — a click-free loop.
func _make_music() -> AudioStreamWAV:
	var L := 10.0
	var count := int(RATE * L)
	var base := 1.0 / L
	var partials := [
		[110.0, 0.24, 0.05, 0.5],
		[164.81, 0.18, 0.07, 0.6],
		[220.0, 0.16, 0.06, 0.6],
		[277.18, 0.12, 0.083, 0.7],
		[329.63, 0.09, 0.11, 0.7],
	]
	var tuned := []
	var norm := 0.0
	for p in partials:
		var f: float = maxf(base, round(p[0] / base) * base)
		var lf: float = maxf(base, round(p[2] / base) * base)
		tuned.append([f, p[1], lf, p[3]])
		norm += p[1]

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
