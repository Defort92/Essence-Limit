extends SceneTree

const BODY_FRAMES := "res://assets/sprites/characters/base/frames"
const WEAPON_FRAMES := {
	"Sword": "res://assets/sprites/equipment/iron_sword/frames",
	"Bow": "res://assets/sprites/equipment/training_bow/frames",
	"Staff": "res://assets/sprites/equipment/apprentice_staff/frames",
}
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

	var layer := EQUIPMENT_LAYER_SCRIPT.new()
	layer.source_sprite = body
	root.add_child(layer)
	await process_frame

	for weapon_name: String in WEAPON_FRAMES:
		layer.set_frames_dir(WEAPON_FRAMES[weapon_name])
		for sector in 8:
			if layer.get_animation_frame_count(sector, false) != 4:
				push_error("%s idle frame count mismatch in sector %d." % [weapon_name, sector])
				quit(1)
				return
			if layer.get_animation_frame_count(sector, true) != 8:
				push_error("%s run frame count mismatch in sector %d." % [weapon_name, sector])
				quit(1)
				return
			body.face_direction(DIRECTIONS[sector])
			body.set_moving(false)
			body.set_moving(true)
			body._process(0.0)
			layer._process(0.0)
			if layer.texture == null or not layer.visible:
				push_error("%s layer is not visible in sector %d." % [weapon_name, sector])
				quit(1)
				return
			if layer.flip_h != (sector >= 5):
				push_error("%s mirror mismatch in sector %d." % [weapon_name, sector])
				quit(1)
				return

	layer.set_frames_dir(WEAPON_FRAMES["Sword"])

	body.face_direction(DIRECTIONS[4])
	body.set_moving(false)
	body._process(
		body.get_idle_pause_remaining()
		+ body.idle_frame_duration * 5.0
		+ 0.001
	)
	layer._process(0.0)
	if (
		layer.texture == null
		or not layer.texture.resource_path.ends_with("/back/idle/default/frame_04.png")
	):
		push_error("Sword idle phase did not scale from 6 body frames to 4 equipment frames.")
		quit(1)
		return

	layer.set_frames_dir("")
	if layer.visible or layer.texture != null:
		push_error("Sword layer did not clear after unequip.")
		quit(1)
		return

	print("[DirectionalEquipmentLayerTest] PASS: 3 weapons, idle, run, mirror, unequip.")
	quit()
