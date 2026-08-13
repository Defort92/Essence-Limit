## Видимый физический снаряд. Движется через move_and_collide(), поэтому даже быстрая
## стрела использует swept collision и не пролетает сквозь тонкие капсулы между кадрами.
extends CharacterBody3D
class_name CombatProjectile

enum Kind { ARROW, FIREBALL }

const ARROW_SPEED: float = 30.0
const FIREBALL_SPEED: float = 13.0
var _source: Node3D = null
var _source_faction: Faction.Kind = Faction.Kind.NEUTRAL
var _damage: int = 1
var _direction: Vector3 = Vector3.FORWARD
var _speed: float = ARROW_SPEED
var _remaining_distance: float = 10.0
var _kind: Kind = Kind.ARROW
var _configured: bool = false

func configure(
	source: Node3D,
	damage: int,
	direction: Vector3,
	speed: float,
	max_distance: float,
	kind: Kind
) -> void:
	_source = source
	_source_faction = source.faction if source != null and "faction" in source else Faction.Kind.NEUTRAL
	_damage = maxi(1, damage)
	_direction = direction.normalized()
	_speed = maxf(0.1, speed)
	_remaining_distance = maxf(0.1, max_distance)
	_kind = kind
	_configured = true
	# Игрок/союзники стреляют только во врагов, враги — только в отряд. Земля
	# присутствует в обеих масках и останавливает любой снаряд.
	collision_mask = 5 if _source_faction == Faction.Kind.PLAYER else 3
	if source is CollisionObject3D:
		add_collision_exception_with(source as CollisionObject3D)

func _ready() -> void:
	if not _configured:
		push_error("CombatProjectile создан без configure()")
		queue_free()
		return
	_build_collision()
	_build_visual()
	look_at(global_position + _direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	var travel := minf(_speed * delta, _remaining_distance)
	if travel <= 0.0:
		queue_free()
		return
	var collision := move_and_collide(_direction * travel)
	_remaining_distance -= travel
	if collision != null:
		_hit(collision.get_collider())
		return
	if _remaining_distance <= 0.0:
		queue_free()

func _hit(body: Object) -> void:
	if (
		body != null
		and body.has_method("take_damage")
		and "faction" in body
		and Faction.is_hostile(_source_faction, body.faction)
	):
		var is_crit := CombatMath.roll_crit(_source, body)
		body.take_damage(CombatMath.apply_crit(_damage) if is_crit else _damage, is_crit)
	queue_free()

func _build_collision() -> void:
	var collision_shape := CollisionShape3D.new()
	if _kind == Kind.FIREBALL:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.22
		collision_shape.shape = sphere
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.055
		capsule.height = 0.7
		collision_shape.shape = capsule
		collision_shape.rotation_degrees.x = 90.0
	add_child(collision_shape)

func _build_visual() -> void:
	if _kind == Kind.FIREBALL:
		_build_fireball_visual()
	else:
		_build_arrow_visual()

func _build_arrow_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.22, 0.09)
	material.roughness = 0.8
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.025
	shaft_mesh.bottom_radius = 0.025
	shaft_mesh.height = 0.65
	shaft_mesh.material = material
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees.x = 90.0
	add_child(shaft)

	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.07
	tip_mesh.height = 0.16
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.72, 0.74, 0.78)
	metal.metallic = 0.75
	tip_mesh.material = metal
	tip.mesh = tip_mesh
	tip.position.z = -0.4
	tip.rotation_degrees.x = -90.0
	add_child(tip)

func _build_fireball_visual() -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.22, 0.02)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.08, 0.005)
	material.emission_energy_multiplier = 4.0
	sphere.material = material
	orb.mesh = sphere
	add_child(orb)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.24, 0.04)
	light.light_energy = 2.2
	light.omni_range = 2.5
	light.shadow_enabled = false
	add_child(light)
