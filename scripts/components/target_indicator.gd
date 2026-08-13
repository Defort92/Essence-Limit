## Программно нарисованная метка текущей цели. Узел остаётся дочерним Player,
## но top_level позволяет держать его в мировой позиции выбранного противника.
extends MeshInstance3D
class_name TargetIndicator

const RADIUS: float = 0.68
const SEGMENTS: int = 32
const HEIGHT_ABOVE_GROUND: float = 0.06

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_mesh()
	hide()

func show_target(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		hide()
		return
	global_position = target.global_position + Vector3.UP * HEIGHT_ABOVE_GROUND
	show()

func clear_target() -> void:
	hide()

func _build_mesh() -> void:
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.2, 0.08, 0.95)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.08, 0.02)
	material.emission_energy_multiplier = 1.8
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in SEGMENTS:
		var angle_a := TAU * float(index) / float(SEGMENTS)
		var angle_b := TAU * float(index + 1) / float(SEGMENTS)
		immediate.surface_add_vertex(Vector3(cos(angle_a) * RADIUS, 0.0, sin(angle_a) * RADIUS))
		immediate.surface_add_vertex(Vector3(cos(angle_b) * RADIUS, 0.0, sin(angle_b) * RADIUS))
	# Короткие угловые засечки делают метку читаемой даже на близком плане.
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		immediate.surface_add_vertex(direction * (RADIUS - 0.16))
		immediate.surface_add_vertex(direction * (RADIUS + 0.16))
	immediate.surface_end()
	mesh = immediate
