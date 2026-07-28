extends SceneTree

const FRAMES_DIR := "res://assets/sprites/characters/base/frames"
const DIRECTIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.0),
	Vector3(1.0, 0.0, 1.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(1.0, 0.0, -1.0),
	Vector3(0.0, 0.0, -1.0),
	Vector3(-1.0, 0.0, -1.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 1.0),
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var sprite := DirectionalSprite3D.new()
	sprite.frames_dir = FRAMES_DIR
	root.add_child(sprite)
	await process_frame

	for sector in 8:
		var walk_count := sprite.get_animation_frame_count(sector, true)
		var idle_count := sprite.get_animation_frame_count(sector, false)
		if walk_count != 8:
			push_error("Sector %d has %d walk frames instead of 8." % [sector, walk_count])
			quit(1)
			return
		if idle_count != 4:
			push_error("Sector %d has %d idle frames instead of 4." % [sector, idle_count])
			quit(1)
			return

		sprite.face_direction(DIRECTIONS[sector])
		sprite.set_moving(false)
		sprite.set_moving(true)
		sprite._process(0.0)
		var first_frame_path := sprite.texture.resource_path
		sprite._process(1.0 / sprite.walk_fps + 0.001)
		if sprite.texture.resource_path == first_frame_path:
			push_error("Sector %d did not advance its walk animation." % sector)
			quit(1)
			return

		var should_mirror := sector >= 5
		if sprite.flip_h != should_mirror:
			push_error(
				"Sector %d mirror mismatch: expected %s, got %s."
				% [sector, should_mirror, sprite.flip_h]
			)
			quit(1)
			return
		if sprite.is_animation_sector_mirrored(sector) != should_mirror:
			push_error("Sector %d reports an invalid mirror source." % sector)
			quit(1)
			return

	print("[DirectionalSpriteAnimationTest] PASS: 8 directions, mirrored left sectors.")
	quit()
