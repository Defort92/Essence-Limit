## Полоска здоровья врага над головой: красная заливка на тёмном фоне, без чисел.
## Показывает только долю оставшегося HP, чтобы видеть, насколько просело здоровье.
## Строится из двух билборд-квадов (фон + заливка), заливка сжимается влево по доле HP.
## Камера в игре фиксирована, поэтому billboard FIXED_Y стабильно держит полоску к экрану.
extends Node3D
class_name EnemyHealthBar


var _fill: MeshInstance3D = null
var _fill_mesh: QuadMesh = null
var _ratio: float = 1.0

func _ready() -> void:
	var bg: MeshInstance3D = _make_quad(EnemyHealthBarConstants.BG_COLOR, 0)
	add_child(bg)
	_fill = _make_quad(EnemyHealthBarConstants.FILL_COLOR, 1)
	_fill_mesh = _fill.mesh as QuadMesh
	add_child(_fill)
	_apply_ratio()

func _make_quad(color: Color, priority: int) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(EnemyHealthBarConstants.BAR_WIDTH, EnemyHealthBarConstants.BAR_HEIGHT)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = priority
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

## Обновляет полоску по текущему и максимальному HP.
func set_values(current: int, maximum: int) -> void:
	_ratio = 0.0 if maximum <= 0 else float(current) / float(maximum)
	_apply_ratio()

## Сжимает заливку влево по доле HP: ширина = BAR_WIDTH * ratio, левый край на месте.
## Меняем сам QuadMesh (size + center_offset), а не transform узла: billboard-материал
## игнорирует масштаб узла, а смещение позиции идёт в мировых осях — полоска бы просто ездила.
func _apply_ratio() -> void:
	if _fill_mesh == null:
		return
	var r: float = clampf(_ratio, 0.0, 1.0)
	var w: float = maxf(EnemyHealthBarConstants.BAR_WIDTH * r, 0.001)
	_fill_mesh.size = Vector2(w, EnemyHealthBarConstants.BAR_HEIGHT)
	_fill_mesh.center_offset = Vector3(-(EnemyHealthBarConstants.BAR_WIDTH - w) * 0.5, 0.0, 0.0)
	_fill.visible = r > 0.0
