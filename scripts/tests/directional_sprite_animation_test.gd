extends SceneTree

const FRAMES_DIR := "res://assets/sprites/characters/base/frames"
const RUN_FRAME_COUNTS: PackedInt32Array = [8, 8, 8, 8, 8, 8, 8, 8]
const IDLE_FRAME_COUNTS: PackedInt32Array = [4, 4, 4, 4, 6, 4, 4, 4]
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
		if walk_count != RUN_FRAME_COUNTS[sector]:
			push_error(
				"Sector %d has %d run frames instead of %d."
				% [sector, walk_count, RUN_FRAME_COUNTS[sector]]
			)
			quit(1)
			return
		if idle_count != IDLE_FRAME_COUNTS[sector]:
			push_error(
				"Sector %d has %d idle frames instead of %d."
				% [sector, idle_count, IDLE_FRAME_COUNTS[sector]]
			)
			quit(1)
			return

		sprite.face_direction(DIRECTIONS[sector])
		sprite.set_moving(false)
		sprite.set_moving(true)
		sprite._process(0.0)
		var first_frame_path := sprite.texture.resource_path
		var expected_run_dir := FRAMES_DIR.path_join(
			DirectionalSpriteConstants.DIR_FOLDERS[sector if sector < 5 else 8 - sector]
		).path_join("run").path_join("default")
		if not first_frame_path.begins_with(expected_run_dir):
			push_error("Sector %d did not load its run animation." % sector)
			quit(1)
			return
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
		if sprite.get_current_animation_state() != &"run":
			push_error("Movement did not select the run/default clip.")
			quit(1)
			return

	sprite.face_direction(DIRECTIONS[4])
	sprite.set_moving(false)
	sprite._process(0.0)
	if not sprite.is_idle_animation_paused():
		push_error("Idle animation did not start with a pause.")
		quit(1)
		return
	var first_idle_path := sprite.texture.resource_path
	var initial_pause := sprite.get_idle_pause_remaining()
	if initial_pause < sprite.idle_pause_min or initial_pause > sprite.idle_pause_max:
		push_error("Initial idle pause is outside the configured range: %f." % initial_pause)
		quit(1)
		return
	var first_step := sprite.idle_frame_duration + 0.001
	sprite._process(initial_pause + first_step)
	if sprite.is_idle_animation_paused() or sprite.texture.resource_path == first_idle_path:
		push_error("Back idle animation did not advance after its pause.")
		quit(1)
		return
	sprite._process(sprite.idle_frame_duration * 6.0 - first_step + 0.0001)
	if not sprite.is_idle_animation_paused() or sprite.get_current_animation_frame() != 0:
		push_error("Back idle animation did not return to its paused first frame.")
		quit(1)
		return
	var next_pause := sprite.get_idle_pause_remaining()
	if next_pause < sprite.idle_pause_min - 0.001 or next_pause > sprite.idle_pause_max:
		push_error("Next idle pause is outside the configured range: %f." % next_pause)
		quit(1)
		return

	print("[DirectionalSpriteAnimationTest] PASS: 8 directions, mirrored left sectors, interval idle.")
	quit()
