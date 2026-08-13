extends SceneTree

const PROFILE_SCRIPT := preload("res://scripts/data/equipment_alignment_profile.gd")
const TEST_PATH := "user://equipment_alignment_profile_test.tres"


func _initialize() -> void:
	var profile := PROFILE_SCRIPT.new()
	profile.default_offset = Vector2(1.0, 2.0)
	profile.direction_offsets = {"front": Vector2(2.0, -1.0)}
	profile.animation_offsets = {"front/run": Vector2(-1.0, 3.0)}

	var inherited: Vector2 = profile.get_offset(&"front", &"run", 0)
	if inherited != Vector2(2.0, 4.0):
		_fail("Additive fallback returned %s." % inherited)
		return

	profile.set_frame_total_offset(&"front", &"run", 0, Vector2(7.0, -2.0))
	if profile.get_offset(&"front", &"run", 0) != Vector2(7.0, -2.0):
		_fail("Frame total offset was not preserved.")
		return
	if profile.get_offset(&"front", &"run", 0, true) != Vector2(-7.0, -2.0):
		_fail("Mirroring did not negate X only.")
		return
	if profile.get_offset(&"front", &"run", 1) != inherited:
		_fail("Frame fallback leaked into another frame.")
		return

	var save_error := ResourceSaver.save(profile, TEST_PATH)
	if save_error != OK:
		_fail("ResourceSaver failed with error %d." % save_error)
		return
	var loaded := ResourceLoader.load(TEST_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	if loaded == null or loaded.get_offset(&"front", &"run", 0) != Vector2(7.0, -2.0):
		_fail("Saved profile did not round-trip.")
		return

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("[EquipmentAlignmentProfileTest] PASS: fallback, frame override, mirror, save/load.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
