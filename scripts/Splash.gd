# Splash.gd
# Publisher logo splash shown once at app launch, then -> Home.
extends Control

const HOLD := 1.4
const FADE := 0.45

@onready var logo: TextureRect = $Logo

func _ready():
	# Skip the splash on tap (instant continue)
	gui_input.connect(_on_tap)
	logo.modulate.a = 0.0
	_run.call_deferred()

func _run():
	var t1 := create_tween()
	t1.tween_property(logo, "modulate:a", 1.0, FADE)
	await t1.finished
	await get_tree().create_timer(HOLD).timeout
	var t2 := create_tween()
	t2.tween_property(logo, "modulate:a", 0.0, FADE)
	await t2.finished
	_go_home()

func _on_tap(event: InputEvent):
	if event is InputEventScreenTouch and event.pressed:
		_go_home()
	elif event is InputEventMouseButton and event.pressed:
		_go_home()

func _go_home():
	if not is_inside_tree():
		return
	Transition.goto("res://scenes/Home.tscn")
