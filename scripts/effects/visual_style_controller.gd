## Applies VisualSettings to one gameplay scene without affecting CanvasLayer UI.
extends Node


const PIXEL_SHADER := preload("res://assets/shaders/prototypes/pixel_preview.gdshader")
const OUTLINE_SHADER := preload(
	"res://assets/shaders/prototypes/screen_outline_preview.gdshader"
)
const GRASS_OUTLINE_EXCLUSION_MARKER := 0.123

@export var camera_path: NodePath
@export var grass_root_path: NodePath

var _camera: Camera3D
var _grass_root: Node3D
var _grass_material: ShaderMaterial
var _pixel_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _outline_mesh: MeshInstance3D


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_grass_root = get_node_or_null(grass_root_path) as Node3D
	if _camera == null:
		push_warning("VisualStyleController: camera_path does not point to Camera3D.")
		return
	_grass_material = _find_grass_material()
	_create_outline_pass()
	_create_pixel_pass()
	VisualSettings.settings_changed.connect(_apply_settings)
	_apply_settings()


func _create_outline_pass() -> void:
	_outline_mesh = MeshInstance3D.new()
	_outline_mesh.name = "VisualOutlinePass"
	_outline_mesh.extra_cull_margin = 16384.0
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_outline_mesh.mesh = quad
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_mesh.material_override = _outline_material
	_camera.add_child(_outline_mesh)


func _create_pixel_pass() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WorldPixelPass"
	# Gameplay CanvasLayers use the default layer 1, so layer 0 processes the
	# rendered world first and leaves HUD, menus and text crisp.
	layer.layer = 0
	add_child(layer)
	var preview := ColorRect.new()
	preview.name = "WorldPixelPreview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.color = Color.WHITE
	layer.add_child(preview)
	_pixel_material = ShaderMaterial.new()
	_pixel_material.shader = PIXEL_SHADER
	preview.material = _pixel_material


func _apply_settings() -> void:
	if _pixel_material == null or _outline_material == null:
		return
	_pixel_material.set_shader_parameter(
		"pixelation_enabled", VisualSettings.pixelation_enabled
	)
	_pixel_material.set_shader_parameter("pixel_size", VisualSettings.pixel_size)
	_pixel_material.set_shader_parameter("palette_enabled", VisualSettings.palette_enabled)
	_pixel_material.set_shader_parameter("palette_levels", VisualSettings.palette_levels)

	_outline_mesh.visible = VisualSettings.outlines_enabled
	_outline_material.set_shader_parameter("thickness", VisualSettings.outline_thickness)
	_outline_material.set_shader_parameter("outline_strength", VisualSettings.outline_strength)
	_outline_material.set_shader_parameter(
		"exclude_marked_surfaces", VisualSettings.exclude_grass_outlines
	)
	_outline_material.set_shader_parameter(
		"excluded_roughness_marker", GRASS_OUTLINE_EXCLUSION_MARKER
	)
	_outline_material.set_shader_parameter("dark_edges_enabled", VisualSettings.dark_edges_enabled)
	_outline_material.set_shader_parameter(
		"dark_surface_threshold", VisualSettings.dark_surface_threshold
	)
	_outline_material.set_shader_parameter(
		"dark_edge_strength", VisualSettings.dark_edge_strength
	)

	if _grass_root != null:
		_grass_root.visible = VisualSettings.show_grass
	if _grass_material != null:
		_grass_material.set_shader_parameter(
			"outline_exclusion_enabled", VisualSettings.exclude_grass_outlines
		)
		_grass_material.set_shader_parameter(
			"outline_exclusion_marker", GRASS_OUTLINE_EXCLUSION_MARKER
		)
		_grass_material.set_shader_parameter("cuts", roundi(VisualSettings.toon_cuts))
		_grass_material.set_shader_parameter("quantised", VisualSettings.quantised_grass)
		_grass_material.set_shader_parameter("framerate", VisualSettings.grass_fps)


func _find_grass_material() -> ShaderMaterial:
	if _grass_root == null:
		return null
	return _grass_root.get("grass_material") as ShaderMaterial
