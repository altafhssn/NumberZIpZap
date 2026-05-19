# Ui.gd  (autoload singleton)
# Global UI feedback: a soft tap sound + light haptic on every button press.
# Auto-wires itself to any BaseButton added anywhere in the scene tree.
extends Node

const RATE := 22050

var _player: AudioStreamPlayer
var _click: AudioStreamWAV

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = -6.0
	add_child(_player)
	_click = _make_click()
	get_tree().node_added.connect(_on_node_added)
	# Hook buttons that already exist in the first scene
	_scan(get_tree().root)

func _scan(n: Node):
	_on_node_added(n)
	for c in n.get_children():
		_scan(c)

func _on_node_added(n: Node):
	if n is BaseButton and not n.is_connected("pressed", _on_pressed):
		n.pressed.connect(_on_pressed)

func _on_pressed():
	if GameData.sound_on:
		_player.stream = _click
		_player.play()
	if GameData.haptics_on:
		Input.vibrate_handheld(10)

func _make_click() -> AudioStreamWAV:
	var dur := 0.045
	var count := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(RATE)
		var prog := t / dur
		var freq := lerp(880.0, 1040.0, prog)
		var s := sin(TAU * freq * t)
		var atk := minf(1.0, t / 0.003)
		var dec: float = pow(1.0 - prog, 1.8)
		var v := int(clampf(s * atk * dec * 0.30, -1.0, 1.0) * 32767.0)
		if v < 0:
			v += 65536
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
