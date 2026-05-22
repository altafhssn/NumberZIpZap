# Tutorial.gd
# First-time onboarding overlay. Shown on level 1 until the player completes it.
# Polls the game state and auto-advances through contextual hints — no taps to
# dismiss, no blocking input.
extends CanvasLayer

@onready var card: PanelContainer = $Card
@onready var label: Label = $Card/Label

var _state = null    # GameState ref
var _grid = null     # Grid ref (for the dotted hint trail)
var _step := -1

const STEPS := [
	"Tap dot ① to start. Follow the dotted trail.",
	"Drag through adjacent cells to reach dot ②.",
	"Hit every number in order — keep the highest for last.",
	"Fill every cell and end on the highest number to win!",
]

func setup(game_state, grid_ref):
	_state = game_state
	_grid = grid_ref
	if _grid:
		_grid.show_solution_hint = true
	_show(0)

func _process(_dt):
	if _state == null:
		return
	if _state.is_completed:
		_dismiss()
		return
	var nd: int = _state.next_dot_index
	var dots_total: int = _state.dots.size()
	# Auto-advance based on progress
	if _step == 0 and nd >= 1:
		_show(1)
	elif _step == 1 and nd >= 2:
		_show(2)
	elif _step == 2 and nd >= dots_total:
		_show(3)

func _show(i: int):
	if i == _step:
		return
	_step = i
	label.text = STEPS[i]
	card.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(card, "modulate:a", 1.0, 0.25)

func _dismiss():
	if not is_inside_tree():
		return
	_state = null
	if _grid:
		_grid.show_solution_hint = false
		_grid = null
	var t := create_tween()
	t.tween_property(card, "modulate:a", 0.0, 0.35)
	await t.finished
	queue_free()
