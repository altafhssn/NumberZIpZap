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
	# Step is DERIVED from current progress every frame, not monotonically
	# advanced. Without this, pressing Reset (or Undo past a dot) leaves the
	# card stuck on whatever the highest-ever step was — e.g. you reach all
	# six dots, hit Reset, and the card still preaches "Fill every cell" on
	# an empty grid. Re-derive so it tracks state both forward AND backward.
	var nd: int = _state.next_dot_index
	var dots_total: int = _state.dots.size()
	var desired := 0
	if nd >= 1:
		desired = 1
	if nd >= 2:
		desired = 2
	if nd >= dots_total:
		desired = 3
	if desired != _step:
		_show(desired)

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
