# Audio.gd
# Procedural SFX — synthesizes short tones at runtime (no asset files).
extends Node

const RATE := 22050

var _players: Array = []
var _next := 0

# Cached streams
var _s_move: AudioStreamWAV
var _s_dot: AudioStreamWAV
var _s_error: AudioStreamWAV
var _s_win: AudioStreamWAV
var _s_fail: AudioStreamWAV

var _music_player: AudioStreamPlayer
var _music_on := false

func _ready():
	# Small pool so overlapping moves don't cut each other off
	for i in range(5):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	_s_move = _tone([{ "f": 520.0, "to": 600.0 }], 0.06, 0.28, "tri")
	_s_dot = _tone([{ "f": 740.0, "to": 990.0 }], 0.16, 0.40, "sine")
	_s_error = _tone([{ "f": 200.0, "to": 130.0 }], 0.20, 0.40, "square")
	_s_fail = _tone([{ "f": 440.0, "to": 110.0 }], 0.45, 0.42, "tri")
	_s_win = _arp([523.25, 659.25, 783.99, 1046.5], 0.12, 0.40)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.volume_db = -7.0
	_music_player.stream = _make_music()
	add_child(_music_player)
	_update_music()

func _process(_delta):
	# React to the sound setting being toggled from the Settings screen
	if GameData.sound_on != _music_on:
		_update_music()

func _update_music():
	_music_on = GameData.sound_on
	if _music_on:
		if not _music_player.playing:
			_music_player.play()
	else:
		_music_player.stop()

func play_move(): _play(_s_move)
func play_dot(): _play(_s_dot)
func play_error(): _play(_s_error)
func play_win(): _play(_s_win)
func play_fail(): _play(_s_fail)

func _play(stream: AudioStreamWAV):
	if stream == null:
		return
	if not GameData.sound_on:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.play()

# Build a tone with linear frequency sweep segments and an AD envelope.
func _tone(segments: Array, dur: float, vol: float, wave: String) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(count * 2)
	var seg = segments[0]
	var f0: float = seg["f"]
	var f1: float = seg.get("to", seg["f"])
	for i in range(count):
		var t := float(i) / float(RATE)
		var prog := t / dur
		var freq: float = lerp(f0, f1, prog)
		var phase := TAU * freq * t
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			"tri":
				s = asin(sin(phase)) * (2.0 / PI)
			_:
				s = sin(phase)
		# Envelope: 6ms attack, exponential decay
		var atk := minf(1.0, t / 0.006)
		var dec: float = pow(1.0 - prog, 1.6)
		var amp := s * atk * dec * vol
		_write_sample(data, i, amp)
	return _to_wav(data)

# Concatenate notes into a quick arpeggio (used for the win jingle).
func _arp(freqs: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var per := int(RATE * note_dur)
	var total := per * freqs.size()
	var data := PackedByteArray()
	data.resize(total * 2)
	for n in range(freqs.size()):
		var freq: float = freqs[n]
		for i in range(per):
			var t := float(i) / float(RATE)
			var prog := t / note_dur
			var s := sin(TAU * freq * t)
			var atk := minf(1.0, t / 0.005)
			var dec: float = pow(1.0 - prog, 1.2)
			var amp := s * atk * dec * vol
			_write_sample(data, n * per + i, amp)
	return _to_wav(data)

# Calm seamless ambient pad. All partial + LFO frequencies are snapped to
# integer multiples of 1/L so the buffer is perfectly periodic — no loop click.
func _make_music() -> AudioStreamWAV:
	var L := 16.0
	var count := int(RATE * L)
	var base := 1.0 / L
	# [freq, amp, lfo_rate, lfo_depth]  — A-major drone with shimmer
	var partials := [
		[110.0, 0.22, 0.05, 0.5],
		[164.81, 0.16, 0.07, 0.6],
		[220.0, 0.16, 0.06, 0.6],
		[277.18, 0.12, 0.083, 0.7],
		[329.63, 0.10, 0.11, 0.7],
		[440.0, 0.07, 0.13, 0.8],
		[554.37, 0.05, 0.17, 0.9],
	]
	var snapped := []
	var norm := 0.0
	for p in partials:
		var f: float = maxf(base, round(p[0] / base) * base)
		var lf: float = maxf(base, round(p[2] / base) * base)
		snapped.append([f, p[1], lf, p[3]])
		norm += p[1]

	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(RATE)
		var s := 0.0
		for p in snapped:
			var depth: float = p[3]
			var lfo: float = 0.5 * (1.0 + sin(TAU * p[2] * t))
			var amp: float = p[1] * ((1.0 - depth) + depth * lfo)
			s += amp * sin(TAU * p[0] * t)
		_write_sample(data, i, (s / norm) * 0.85)

	var w := _to_wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = count
	return w

func _write_sample(data: PackedByteArray, idx: int, amp: float):
	var v := int(clampf(amp, -1.0, 1.0) * 32767.0)
	if v < 0:
		v += 65536
	data[idx * 2] = v & 0xFF
	data[idx * 2 + 1] = (v >> 8) & 0xFF

func _to_wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
