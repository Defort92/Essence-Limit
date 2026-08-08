## Paused developer panel for tuning the visual style in the active game scene.
extends Control
class_name DeveloperVisualSettings


var _controls: Dictionary = {}
var _value_labels: Dictionary = {}
var _syncing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	hide()


func open() -> void:
	_sync_controls()
	show()
	var first := _controls.get(&"show_grass") as Control
	if first != null:
		first.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.016, 0.012, 0.016, 0.86)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540.0, 0.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "НАСТРОЙКИ РАЗРАБОТЧИКА"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var hint := Label.new()
	hint.text = "Визуальные параметры применяются сразу и сохраняются автоматически"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.72, 0.69, 0.78)
	outer.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 560.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	_add_toggle(content, &"show_grass", "Показывать траву")
	_add_toggle(content, &"pixelation_enabled", "Пикселизация экрана")
	_add_slider(content, &"pixel_size", "Размер экранного пикселя", 1.0, 8.0, 1.0, "×%.0f")
	_add_toggle(content, &"palette_enabled", "Ограничить палитру")
	_add_slider(content, &"palette_levels", "Уровней на цветовой канал", 2.0, 32.0, 1.0, "%.0f")
	_add_separator(content)
	_add_toggle(content, &"outlines_enabled", "Экранные 3D-контуры")
	_add_slider(content, &"outline_thickness", "Толщина контуров", 1.0, 4.0, 0.25, "%.2f px")
	_add_slider(content, &"outline_strength", "Сила контуров", 0.0, 1.0, 0.05, "%.2f")
	_add_toggle(content, &"exclude_grass_outlines", "Исключать траву из контуров")
	_add_toggle(content, &"dark_edges_enabled", "Подсвечивать грани тёмных объектов")
	_add_slider(content, &"dark_surface_threshold", "Макс. яркость для светлой грани", 0.01, 0.30, 0.01, "%.2f")
	_add_slider(content, &"dark_edge_strength", "Яркость светлых граней", 0.0, 1.0, 0.05, "%.2f")
	_add_separator(content)
	_add_slider(content, &"toon_cuts", "Ступени toon-освещения", 1.0, 8.0, 1.0, "%.0f")
	_add_toggle(content, &"quantised_grass", "Ступенчатая анимация травы")
	_add_slider(content, &"grass_fps", "Частота анимации травы", 1.0, 20.0, 1.0, "%.0f fps")

	var reset := Button.new()
	reset.text = "Сбросить к параметрам по умолчанию"
	reset.pressed.connect(_on_reset_pressed)
	outer.add_child(reset)

	var close := Button.new()
	close.text = "Назад"
	close.pressed.connect(hide)
	outer.add_child(close)


func _add_toggle(parent: VBoxContainer, key: StringName, label_text: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.toggled.connect(func(value: bool) -> void: _on_value_changed(key, value))
	parent.add_child(toggle)
	_controls[key] = toggle


func _add_slider(
	parent: VBoxContainer,
	key: StringName,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	value_format: String
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 72.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(
		func(value: float) -> void:
			value_label.text = value_format % value
			_on_value_changed(key, value)
	)
	parent.add_child(slider)
	_controls[key] = slider
	_value_labels[key] = {"label": value_label, "format": value_format}


func _add_separator(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())


func _on_value_changed(key: StringName, value: Variant) -> void:
	if _syncing:
		return
	VisualSettings.set_setting(key, value)
	_update_availability()


func _on_reset_pressed() -> void:
	VisualSettings.reset_to_defaults()
	_sync_controls()


func _sync_controls() -> void:
	_syncing = true
	for key: StringName in _controls:
		var control := _controls[key] as Control
		var value: Variant = VisualSettings.get(key)
		if control is CheckButton:
			(control as CheckButton).set_pressed_no_signal(bool(value))
		elif control is HSlider:
			(control as HSlider).set_value_no_signal(float(value))
			var data: Dictionary = _value_labels[key]
			(data["label"] as Label).text = str(data["format"]) % float(value)
	_syncing = false
	_update_availability()


func _update_availability() -> void:
	_set_slider_editable(&"pixel_size", VisualSettings.pixelation_enabled)
	_set_slider_editable(&"palette_levels", VisualSettings.palette_enabled)
	_set_slider_editable(&"outline_thickness", VisualSettings.outlines_enabled)
	_set_slider_editable(&"outline_strength", VisualSettings.outlines_enabled)
	(_controls[&"exclude_grass_outlines"] as CheckButton).disabled = not VisualSettings.outlines_enabled
	(_controls[&"dark_edges_enabled"] as CheckButton).disabled = not VisualSettings.outlines_enabled
	var dark_controls_enabled := VisualSettings.outlines_enabled and VisualSettings.dark_edges_enabled
	_set_slider_editable(&"dark_surface_threshold", dark_controls_enabled)
	_set_slider_editable(&"dark_edge_strength", dark_controls_enabled)
	_set_slider_editable(&"grass_fps", VisualSettings.quantised_grass)


func _set_slider_editable(key: StringName, editable: bool) -> void:
	(_controls[key] as HSlider).editable = editable
