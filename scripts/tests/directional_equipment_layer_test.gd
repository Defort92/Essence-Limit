extends SceneTree

const BODY_FRAMES := "res://assets/sprites/characters/base/frames"
const SWORD_FRAMES := "res://assets/sprites/equipment/iron_sword/frames"
const EQUIPMENT_LAYER_SCRIPT := preload(
	"res://scripts/components/directional_equipment_layer.gd"
)
const DIRECTIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 1.0),
	Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, -1.0),
	Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, -1.0),
	Vector3(-1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 1.0),
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var body := DirectionalSprite3D.new()
	body.frames_dir = BODY_FRAMES
	root.add_child(body)

	var sword := EQUIPMENT_LAYER_SCRIPT.new()
	sword.source_sprite = body
	root.add_child(sword)
	sword.set_frames_dir(SWORD_FRAMES)
	await process_frame

	for sector in 8:
		if sword.get_animation_frame_count(sector, false) != 4:
			push_error("Sword idle frame count mismatch in sector %d." % sector)
			quit(1)
			return
		if sword.get_animation_frame_count(sector, true) != 8:
			push_error("Sword run frame count mismatch in sector %d." % sector)
			quit(1)
			return
		body.face_direction(DIRECTIONS[sector])
		body.set_moving(false)
		body.set_moving(true)
		body._process(0.0)
		sword._process(0.0)
		if sword.texture == null or not sword.visible:
			push_error("Sword layer is not visible in sector %d." % sector)
			quit(1)
			return
		if sword.flip_h != (sector >= 5):
			push_error("Sword mirror mismatch in sector %d." % sector)
			quit(1)
			return

	body.face_direction(DIRECTIONS[4])
	body.set_moving(false)
	body._process(
		body.get_idle_pause_remaining()
		+ body.idle_frame_duration * 5.0
		+ 0.001
	)
	sword._process(0.0)
	if not sword.texture.resource_path.ends_with("/back/idle/default/frame_04.png"):
		push_error("Sword idle phase did not scale from 6 body frames to 4 equipment frames.")
		quit(1)
		return

	sword.set_frames_dir("")
	if sword.visible or sword.texture != null:
		push_error("Sword layer did not clear after unequip.")
		quit(1)
		return

	print("[DirectionalEquipmentLayerTest] PASS: idle, run, mirror, unequip.")
	quit()
