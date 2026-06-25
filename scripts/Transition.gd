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

# Sector warp: brief full-screen sweep in the new pack's accent color, used
# when a level advance crosses a pack boundary. Non-blocking — does not change
# scenes, just plays the visual flourish on top of the current scene.
func sector_warp(accent: Color, dur: float = 0.6):
	var sweep := ColorRect.new()
	sweep.color = accent
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.modulate.a = 0.0
	add_child(sweep)
	var tw := create_tween()
	# Quick flash in, slower fade out — feels like passing through a portal.
	tw.tween_property(sweep, "modulate:a", 0.65, dur * 0.30)
	tw.tween_property(sweep, "modulate:a", 0.0, dur * 0.70)
	await tw.finished
	sweep.queue_free()
