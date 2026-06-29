# Audio.gd
# Procedural musical feedback. The traced path plays a gentle pentatonic phrase.
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
var _s_lock: AudioStreamWAV
var _scale_up: Array[AudioStreamWAV] = []
var _scale_down: Array[AudioStreamWAV] = []

func _ready():
	# Small pool so overlapping moves don't cut each other off
	for i in range(5):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	var pentatonic := [293.66, 329.63, 392.0, 440.0, 493.88, 587.33, 659.25, 783.99]
	for f in pentatonic:
		_scale_up.append(_tone([{ "f": f, "to": f * 1.003 }], 0.105, 0.24, "mallet"))
		_scale_down.append(_tone([{ "f": f * 0.997, "to": f }], 0.075, 0.16, "mallet"))
	_s_move = _scale_up[0]
	_s_dot = _tone([{ "f": 587.33, "to": 880.0 }], 0.22, 0.34, "bell")
	_s_error = _tone([{ "f": 220.0, "to": 196.0 }], 0.18, 0.18, "sine")
	_s_fail = _tone([{ "f": 329.63, "to": 293.66 }], 0.35, 0.20, "mallet")
	_s_win = _arp([293.66, 392.0, 493.88, 587.33, 783.99], 0.16, 0.34)
	# Lock click: short bright pluck (~80ms) that lands the moment the puzzle
	# resolves. Slight upward bend gives it the "click into place" quality.
	_s_lock = _tone([{ "f": 988.0, "to": 1175.0 }], 0.08, 0.42, "mallet")

func play_move(step_index: int = 0):
	if _scale_up.is_empty():
		_play(_s_move)
		return
	_play(_scale_up[abs(step_index) % _scale_up.size()])

func play_dot(step_index: int = 0):
	if not _scale_up.is_empty():
		_play(_scale_up[(abs(step_index) + 2) % _scale_up.size()])
	_play(_s_dot)

func play_rewind(step_index: int = 0):
	if _scale_down.is_empty():
		_play(_s_fail)
		return
	_play(_scale_down[abs(step_index) % _scale_down.size()])

func play_error(): _play(_s_error)
func play_win(): _play(_s_win)
func play_fail(): _play(_s_fail)
func play_lock(): _play(_s_lock)

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
			"mallet":
				s = sin(phase) * 0.76 + sin(phase * 2.01) * 0.18 + sin(phase * 3.02) * 0.06
			"bell":
				s = sin(phase) * 0.70 + sin(phase * 2.4) * 0.20 + sin(phase * 3.01) * 0.10
			_:
				s = sin(phase)
		# Envelope: 6ms attack, exponential decay
		var atk := minf(1.0, t / 0.010)
		var dec: float = pow(1.0 - prog, 1.9)
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
