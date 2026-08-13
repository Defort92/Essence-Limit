extends Node3D

## Runtime controls for comparing the prototype's original hybrid 2.5D look
## against optional pixelation, palette reduction and screen-space outlines.
## All effects are preview-only and leave source textures and animations intact.

const PIXEL_PREVIEW_SHADER := preload(
	"res://assets/shaders/prototypes/pixel_preview.gdshader"
)
const OUTLINE_PREVIEW_SHADER := preload(
	"res://assets/shaders/prototypes/screen_outline_preview.gdshader"
)

const DEFAULT_PIXEL_SIZE := 2.0
const DEFAULT_PALETTE_LEVELS := 19.0
const DEFAULT_OUTLINE_THICKNESS := 1.0
const DEFAULT_OUTLINE_STRENGTH := 0.50
const DEFAULT_DARK_EDGE_THRESHOLD := 0.02
const DEFAULT_DARK_EDGE_STRENGTH := 0.05
const DEFAULT_TOON_CUTS := 3.0
const DEFAULT_GRASS_FPS := 5.0
const GRASS_OUTLINE_EXCLUSION_MARKER := 0.123

@onready var _camera := $World/OrthographicCamera as Camera3D
@onready var _grass_root := $World/VegetationChunks as Node3D
@onready var _grass_chunk := $World/VegetationChunks/GrassChunk as MultiMeshInstance3D
@onready var _ground := $World/EnvironmentGeometry/Ground as MeshInstance3D
@onready var _stone := $World/EnvironmentGeometry/StoneBlocks/StoneBlockLarge as MeshInstance3D

var _pixel_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _outline_mesh: MeshInstance3D
var _settings_panel: PanelContainer

var _grass_toggle: CheckButton
var _pixel_toggle: CheckButton
var _pixel_slider: HSlider
var _palette_toggle: CheckButton
var _palette_slider: HSlider
var _outline_toggle: CheckButton
var _outline_slider: HSlider
var _outline_strength_slider: HSlider
var _grass_outline_exclusion_toggle: CheckButton
var _dark_edges_toggle: CheckButton
var _dark_edge_threshold_slider: HSlider
var _dark_edge_strength_slider: HSlider
var _toon_slider: HSlider
var _grass_animation_toggle: CheckButton
var _grass_fps_slider: HSlider
var _status_label: Label


func _ready() -> void:
	_create_outline_preview()
	_create_pixel_preview()
	_create_settings_panel()
	_reset_controls()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_settings_panel.visible = not _settings_panel.visible
			get_viewport().set_input_as_handled()


func _create_pixel_preview() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PixelPreviewLayer"
	layer.layer = 50
	add_child(layer)

	var preview := ColorRect.new()
	preview.name = "PixelPreview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.color = Color.WHITE
	layer.add_child(preview)

	_pixel_material = ShaderMaterial.new()
	_pixel_material.shader = PIXEL_PREVIEW_SHADER
	preview.material = _pixel_material


func _create_outline_preview() -> void:
	_outline_mesh = MeshInstance3D.new()
	_outline_mesh.name = "OutlinePreview"
	_outline_mesh.extra_cull_margin = 16384.0

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_outline_mesh.mesh = quad

	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_PREVIEW_SHADER
	_outline_mesh.material_override = _outline_material
	_camera.add_child(_outline_mesh)


func _create_settings_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VisualSettingsLayer"
	layer.layer = 100
	add_child(layer)

	_settings_panel = PanelContainer.new()
	_settings_panel.name = "VisualSettingsPanel"
	_settings_panel.position = Vector2(16.0, 16.0)
	_settings_panel.custom_minimum_size = Vector2(380.0, 0.0)
	layer.add_child(_settings_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.03, 0.045, 0.94)
	panel_style.border_color = Color(0.34, 0.29, 0.42, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	_settings_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_settings_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Лаборатория визуального стиля"
	title.add_theme_font_size_override("font_size", 20)
	content.add_child(title)

	var help := Label.new()
	help.text = "WASD — движение   ·   F1 — скрыть панель"
	help.modulate = Color(0.72, 0.69, 0.78)
	content.add_child(help)

	content.add_child(HSeparator.new())

	_grass_toggle = _add_toggle(content, "Показывать траву", _on_grass_toggled)
	_pixel_toggle = _add_toggle(content, "Пикселизация экрана", _on_pixel_toggled)
	_pixel_slider = _add_slider(
		content,
		"Размер экранного пикселя",
		1.0,
		8.0,
		1.0,
		_on_pixel_size_changed,
		"×%.0f"
	)

	_palette_toggle = _add_toggle(content, "Ограничить палитру", _on_palette_toggled)
	_palette_slider = _add_slider(
		content,
		"Уровней на цветовой канал",
		2.0,
		32.0,
		1.0,
		_on_palette_levels_changed,
		"%.0f"
	)

	_outline_toggle = _add_toggle(content, "Экранные 3D-контуры", _on_outline_toggled)
	_outline_slider = _add_slider(
		content,
		"Толщина контуров",
		1.0,
		4.0,
		0.25,
		_on_outline_thickness_changed,
		"%.2f px"
	)
	_outline_strength_slider = _add_slider(
		content,
		"Сила контуров",
		0.0,
		1.0,
		0.05,
		_on_outline_strength_changed,
		"%.2f"
	)
	_grass_outline_exclusion_toggle = _add_toggle(
		content,
		"Исключать траву из контуров",
		_on_grass_outline_exclusion_toggled
	)
	_dark_edges_toggle = _add_toggle(
		content,
		"Подсвечивать грани тёмных объектов",
		_on_dark_edges_toggled
	)
	_dark_edge_threshold_slider = _add_slider(
		content,
		"Макс. яркость для светлой грани",
		0.01,
		0.30,
		0.01,
		_on_dark_edge_threshold_changed,
		"%.2f"
	)
	_dark_edge_strength_slider = _add_slider(
		content,
		"Яркость светлых граней",
		0.0,
		1.0,
		0.05,
		_on_dark_edge_strength_changed,
		"%.2f"
	)

	content.add_child(HSeparator.new())

	_toon_slider = _add_slider(
		content,
		"Ступени toon-освещения",
		1.0,
		8.0,
		1.0,
		_on_toon_cuts_changed,
		"%.0f"
	)
	_grass_animation_toggle = _add_toggle(
		content,
		"Ступенчатая анимация травы",
		_on_grass_animation_toggled
	)
	_grass_fps_slider = _add_slider(
		content,
		"Частота анимации травы",
		1.0,
		20.0,
		1.0,
		_on_grass_fps_changed,
		"%.0f fps"
	)

	var reset_button := Button.new()
	reset_button.text = "Сбросить настройки"
	reset_button.pressed.connect(_reset_controls)
	content.add_child(reset_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.modulate = Color(0.78, 0.75, 0.84)
	content.add_child(_status_label)


func _add_toggle(parent: VBoxContainer, label_text: String, callback: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.toggled.connect(callback)
	parent.add_child(toggle)
	return toggle


func _add_slider(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	callback: Callable,
	value_format: String
) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value_label := Label.new()
	value_label.custom_minimum_size.x = 62.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slider)
	slider.value_changed.connect(
		func(value: float) -> void:
			value_label.text = value_format % value
			callback.call(value)
	)
	return slider


func _reset_controls() -> void:
	_grass_toggle.button_pressed = true
	_pixel_toggle.button_pressed = true
	_pixel_slider.value = DEFAULT_PIXEL_SIZE
	_palette_toggle.button_pressed = false
	_palette_slider.value = DEFAULT_PALETTE_LEVELS
	_outline_toggle.button_pressed = true
	_outline_slider.value = DEFAULT_OUTLINE_THICKNESS
	_outline_strength_slider.value = DEFAULT_OUTLINE_STRENGTH
	_grass_outline_exclusion_toggle.button_pressed = true
	_dark_edges_toggle.button_pressed = true
	_dark_edge_threshold_slider.value = DEFAULT_DARK_EDGE_THRESHOLD
	_dark_edge_strength_slider.value = DEFAULT_DARK_EDGE_STRENGTH
	_toon_slider.value = DEFAULT_TOON_CUTS
	_grass_animation_toggle.button_pressed = true
	_grass_fps_slider.value = DEFAULT_GRASS_FPS
	# Apply every default explicitly. Assigning the same button value does not
	# emit `toggled`, which matters for the initially visible outline quad.
	_on_grass_toggled(true)
	_on_pixel_toggled(true)
	_on_pixel_size_changed(DEFAULT_PIXEL_SIZE)
	_on_palette_toggled(false)
	_on_palette_levels_changed(DEFAULT_PALETTE_LEVELS)
	_on_outline_toggled(true)
	_on_outline_thickness_changed(DEFAULT_OUTLINE_THICKNESS)
	_on_outline_strength_changed(DEFAULT_OUTLINE_STRENGTH)
	_on_grass_outline_exclusion_toggled(true)
	_on_dark_edges_toggled(true)
	_on_dark_edge_threshold_changed(DEFAULT_DARK_EDGE_THRESHOLD)
	_on_dark_edge_strength_changed(DEFAULT_DARK_EDGE_STRENGTH)
	_on_toon_cuts_changed(DEFAULT_TOON_CUTS)
	_on_grass_animation_toggled(true)
	_on_grass_fps_changed(DEFAULT_GRASS_FPS)
	_update_control_availability()
	_update_status()


func _on_grass_toggled(enabled: bool) -> void:
	_grass_root.visible = enabled
	_update_status()


func _on_pixel_toggled(enabled: bool) -> void:
	_pixel_material.set_shader_parameter("pixelation_enabled", enabled)
	_update_control_availability()
	_update_status()


func _on_pixel_size_changed(value: float) -> void:
	_pixel_material.set_shader_parameter("pixel_size", value)
	_update_status()


func _on_palette_toggled(enabled: bool) -> void:
	_pixel_material.set_shader_parameter("palette_enabled", enabled)
	_update_control_availability()
	_update_status()


func _on_palette_levels_changed(value: float) -> void:
	_pixel_material.set_shader_parameter("palette_levels", value)
	_update_status()


func _on_outline_toggled(enabled: bool) -> void:
	_outline_mesh.visible = enabled
	_update_control_availability()
	_update_status()


func _on_outline_thickness_changed(value: float) -> void:
	_outline_material.set_shader_parameter("thickness", value)
	_update_status()


func _on_outline_strength_changed(value: float) -> void:
	_outline_material.set_shader_parameter("outline_strength", value)
	_update_status()


func _on_grass_outline_exclusion_toggled(enabled: bool) -> void:
	_outline_material.set_shader_parameter("exclude_marked_surfaces", enabled)
	_outline_material.set_shader_parameter(
		"excluded_roughness_marker",
		GRASS_OUTLINE_EXCLUSION_MARKER
	)
	var grass_material := _grass_chunk.material_override as ShaderMaterial
	if grass_material != null:
		grass_material.set_shader_parameter("outline_exclusion_enabled", enabled)
		grass_material.set_shader_parameter(
			"outline_exclusion_marker",
			GRASS_OUTLINE_EXCLUSION_MARKER
		)
	_update_status()


func _on_dark_edges_toggled(enabled: bool) -> void:
	_outline_material.set_shader_parameter("dark_edges_enabled", enabled)
	_update_control_availability()
	_update_status()


func _on_dark_edge_threshold_changed(value: float) -> void:
	_outline_material.set_shader_parameter("dark_surface_threshold", value)
	_update_status()


func _on_dark_edge_strength_changed(value: float) -> void:
	_outline_material.set_shader_parameter("dark_edge_strength", value)
	_update_status()


func _on_toon_cuts_changed(value: float) -> void:
	var cuts := roundi(value)
	_set_material_parameter(_ground, "cuts", cuts)
	_set_material_parameter(_stone, "cuts", cuts)
	var grass_material := _grass_chunk.material_override as ShaderMaterial
	if grass_material != null:
		grass_material.set_shader_parameter("cuts", cuts)
	_update_status()


func _on_grass_animation_toggled(enabled: bool) -> void:
	var grass_material := _grass_chunk.material_override as ShaderMaterial
	if grass_material != null:
		grass_material.set_shader_parameter("quantised", enabled)
	_update_control_availability()
	_update_status()


func _on_grass_fps_changed(value: float) -> void:
	var grass_material := _grass_chunk.material_override as ShaderMaterial
	if grass_material != null:
		grass_material.set_shader_parameter("framerate", value)
	_update_status()


func _set_material_parameter(mesh: MeshInstance3D, parameter: StringName, value: Variant) -> void:
	var material := mesh.get_active_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter(parameter, value)


func _update_control_availability() -> void:
	_pixel_slider.editable = _pixel_toggle.button_pressed
	_palette_slider.editable = _palette_toggle.button_pressed
	_outline_slider.editable = _outline_toggle.button_pressed
	_outline_strength_slider.editable = _outline_toggle.button_pressed
	_grass_outline_exclusion_toggle.disabled = not _outline_toggle.button_pressed
	_dark_edges_toggle.disabled = not _outline_toggle.button_pressed
	_dark_edge_threshold_slider.editable = (
		_outline_toggle.button_pressed and _dark_edges_toggle.button_pressed
	)
	_dark_edge_strength_slider.editable = (
		_outline_toggle.button_pressed and _dark_edges_toggle.button_pressed
	)
	_grass_fps_slider.editable = _grass_animation_toggle.button_pressed


func _update_status() -> void:
	if _status_label == null:
		return
	var active: Array[String] = []
	if not _grass_toggle.button_pressed:
		active.append("без травы")
	if _pixel_toggle.button_pressed:
		active.append("пиксель ×%.0f" % _pixel_slider.value)
	if _palette_toggle.button_pressed:
		active.append("палитра %.0f" % _palette_slider.value)
	if _outline_toggle.button_pressed:
		active.append("контуры %.2f px" % _outline_slider.value)
		if _grass_outline_exclusion_toggle.button_pressed:
			active.append("трава без контуров")
		if _dark_edges_toggle.button_pressed:
			active.append("светлые тёмные грани")
	if active.is_empty():
		_status_label.text = "Исходный вид: экранные фильтры выключены."
	else:
		_status_label.text = "Активно: %s" % ", ".join(active)
	_status_label.tooltip_text = (
		"Экранная пикселизация предназначена для визуального сравнения и не "
		+ "заменяет настоящий низкоразрешённый SubViewport."
	)
