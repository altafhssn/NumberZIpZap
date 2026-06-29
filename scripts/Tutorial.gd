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
	"Begin at the first stone.",
	"Trace gently to the next stone.",
	"Visit each stone in order.",
	"Fill the pool and rest on the last stone.",
]

func setup(game_state, grid_ref):
	_state = game_state
	_grid = grid_ref
	if _grid:
		_grid.show_solution_hint = true
	# First-impression protection: no banner during onboarding.
	Ads.hide_banner()
	_show(0)

func _process(_dt):
	if _state == null:
		return
	if _state.is_completed:
		_dismiss()
		return
	# Derive the target step from current next_dot_index every frame so the
	# card tracks the player's actual state — not a monotonic counter. Without
	# this, completing all dots and pressing Reset leaves the card stuck on
	# the "Fill the pool" message even though next_dot_index is back to 0.
	var nd: int = _state.next_dot_index
	var dots_total: int = _state.dots.size()
	var target_step: int
	if nd >= dots_total:
		target_step = 3  # all dots reached — just fill the rest
	elif nd >= 2:
		target_step = 2  # mid-puzzle, keep going
	elif nd >= 1:
		target_step = 1  # heading to second stone
	else:
		target_step = 0  # haven't touched first stone yet
	if target_step != _step:
		_show(target_step)

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
	# Banner returns once onboarding is done.
	Ads.show_banner()
	var t := create_tween()
	t.tween_property(card, "modulate:a", 0.0, 0.35)
	await t.finished
	queue_free()
