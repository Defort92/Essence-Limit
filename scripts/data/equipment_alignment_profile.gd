## Non-destructive, per-frame placement corrections for an equipment sprite layer.
##
## Offsets are expressed in source-canvas pixels: +X moves right and +Y moves down.
## Corrections are additive from broad to specific:
## default -> direction -> animation -> frame.
@tool
extends Resource
class_name EquipmentAlignmentProfile


@export var default_offset: Vector2 = Vector2.ZERO
@export var direction_offsets: Dictionary = {}
@export var animation_offsets: Dictionary = {}
@export var frame_offsets: Dictionary = {}


func get_offset(
	direction: StringName,
	animation: StringName,
	frame_index: int,
	mirrored: bool = false
) -> Vector2:
	var result := get_inherited_offset(direction, animation)
	result += _as_vector2(frame_offsets.get(make_frame_key(direction, animation, frame_index)))
	if mirrored:
		result.x = -result.x
	return result


func get_inherited_offset(direction: StringName, animation: StringName) -> Vector2:
	var result := default_offset
	result += _as_vector2(direction_offsets.get(String(direction)))
	result += _as_vector2(animation_offsets.get(make_animation_key(direction, animation)))
	return result


## Stores the requested final offset as a frame-local correction over inherited values.
func set_frame_total_offset(
	direction: StringName,
	animation: StringName,
	frame_index: int,
	total_offset: Vector2
) -> void:
	var key := make_frame_key(direction, animation, frame_index)
	var correction := total_offset - get_inherited_offset(direction, animation)
	if correction.is_zero_approx():
		frame_offsets.erase(key)
	else:
		frame_offsets[key] = correction
	emit_changed()


func clear_frame_offset(direction: StringName, animation: StringName, frame_index: int) -> void:
	frame_offsets.erase(make_frame_key(direction, animation, frame_index))
	emit_changed()


func has_frame_offset(direction: StringName, animation: StringName, frame_index: int) -> bool:
	return frame_offsets.has(make_frame_key(direction, animation, frame_index))


static func make_animation_key(direction: StringName, animation: StringName) -> String:
	return "%s/%s" % [direction, animation]


static func make_frame_key(
	direction: StringName,
	animation: StringName,
	frame_index: int
) -> String:
	return "%s/frame_%02d" % [make_animation_key(direction, animation), frame_index + 1]


static func _as_vector2(value: Variant) -> Vector2:
	return value as Vector2 if value is Vector2 else Vector2.ZERO
