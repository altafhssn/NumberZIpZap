# Transition.gd  (autoload singleton)
# Smooth fade-to-black scene changes.
extends CanvasLayer

var _rect: ColorRect
var _busy := false

func _ready():
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.043, 0.043, 0.086, 1.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	_rect.visible = false
	add_child(_rect)

func goto(path: String, dur: float = 0.28):
	if _busy:
		return
	_busy = true
	_rect.visible = true
	_rect.modulate.a = 0.0

	var t1 := create_tween()
	t1.tween_property(_rect, "modulate:a", 1.0, dur)
	await t1.finished

	get_tree().change_scene_to_file(path)
	# Let the new scene initialize before fading back in
	await get_tree().process_frame
	await get_tree().process_frame

	var t2 := create_tween()
	t2.tween_property(_rect, "modulate:a", 0.0, dur)
	await t2.finished

	_rect.visible = false
	_busy = false
