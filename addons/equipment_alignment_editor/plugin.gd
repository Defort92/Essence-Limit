@tool
extends EditorPlugin

const AlignmentDock := preload("res://addons/equipment_alignment_editor/alignment_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = AlignmentDock.new()
	_dock.setup(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
