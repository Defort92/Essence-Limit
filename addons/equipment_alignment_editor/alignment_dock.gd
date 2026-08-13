@tool
extends VBoxContainer

const AlignmentPreview := preload(
	"res://addons/equipment_alignment_editor/alignment_preview.gd"
)
const BODY_FRAMES_DEFAULT := "res://assets/sprites/characters/base/frames"
const SOURCE_DIRECTIONS := [
	"front", "front-right", "full-right", "rear-right", "back",
]
const ANIMATIONS := ["idle", "run"]

var _editor_interface: EditorInterface
var _equipment_options: OptionButton
var _body_path: LineEdit
var _direction_options: OptionButton
var _animation_options: OptionButton
var _frame_spin: SpinBox
var _x_spin: SpinBox
var _y_spin: SpinBox
var _preview: Control
var _status: Label
var _save_button: Button

var _equipment_entries: Array[EquipmentData] = []
var _equipment: EquipmentData
var _profile: EquipmentAlignmentProfile
var _body_frames: Array[Texture2D] = []
var _equipment_frames: Array[Texture2D] = []
var _updating_controls := false
var _dirty := false


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	name = "Привязка экипировки"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_scan_equipment()


func _build_ui() -> void:
	var title := Label.new()
	title.text = "Редактор привязки экипировки"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	var help := Label.new()
	help.text = "Перетаскивайте предмет или задавайте X/Y. Исходные PNG не изменяются."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)

	_equipment_options = OptionButton.new()
	_equipment_options.tooltip_text = "Ресурсы EquipmentData из res://resources/equipment"
	_equipment_options.item_selected.connect(_on_equipment_selected)
	add_child(_labeled_control("Предмет", _equipment_options))

	_body_path = LineEdit.new()
	_body_path.text = BODY_FRAMES_DEFAULT
	_body_path.text_submitted.connect(func(_value: String) -> void: _reload_frames())
	add_child(_labeled_control("Кадры тела", _body_path))

	var selectors := HBoxContainer.new()
	_direction_options = OptionButton.new()
	for direction in SOURCE_DIRECTIONS:
		_direction_options.add_item(direction)
	_direction_options.item_selected.connect(func(_index: int) -> void: _reload_frames())
	selectors.add_child(_labeled_control("Направление", _direction_options, true))
	_animation_options = OptionButton.new()
	for animation in ANIMATIONS:
		_animation_options.add_item(animation)
	_animation_options.item_selected.connect(func(_index: int) -> void: _reload_frames())
	selectors.add_child(_labeled_control("Анимация", _animation_options, true))
	add_child(selectors)

	var frame_row := HBoxContainer.new()
	var previous := Button.new()
	previous.text = "<"
	previous.pressed.connect(func() -> void: _step_frame(-1))
	frame_row.add_child(previous)
	_frame_spin = SpinBox.new()
	_frame_spin.min_value = 1.0
	_frame_spin.max_value = 1.0
	_frame_spin.step = 1.0
	_frame_spin.allow_greater = false
	_frame_spin.value_changed.connect(func(_value: float) -> void: _refresh_preview())
	frame_row.add_child(_labeled_control("Кадр тела", _frame_spin, true))
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(func() -> void: _step_frame(1))
	frame_row.add_child(next)
	add_child(frame_row)

	_preview = AlignmentPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.offset_dragged.connect(_set_current_offset)
	add_child(_preview)

	var offset_row := HBoxContainer.new()
	_x_spin = _make_offset_spin()
	_y_spin = _make_offset_spin()
	_x_spin.value_changed.connect(func(_value: float) -> void: _on_offset_spin_changed())
	_y_spin.value_changed.connect(func(_value: float) -> void: _on_offset_spin_changed())
	offset_row.add_child(_labeled_control("X", _x_spin, true))
	offset_row.add_child(_labeled_control("Y", _y_spin, true))
	var reset := Button.new()
	reset.text = "Сбросить кадр"
	reset.pressed.connect(_reset_current_frame)
	offset_row.add_child(reset)
	add_child(offset_row)

	_save_button = Button.new()
	_save_button.text = "Сохранить профиль"
	_save_button.disabled = true
	_save_button.pressed.connect(_save_profile)
	add_child(_save_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _labeled_control(label_text: String, control: Control, expand := false) -> Control:
	var box := VBoxContainer.new()
	if expand:
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	box.add_child(control)
	return box


func _make_offset_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -256.0
	spin.max_value = 256.0
	spin.step = 1.0
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _scan_equipment() -> void:
	_equipment_entries.clear()
	_equipment_options.clear()
	var directory := DirAccess.open("res://resources/equipment")
	if directory == null:
		_set_status("Каталог ресурсов экипировки не найден.", true)
		return
	var files := directory.get_files()
	files.sort()
	for file_name in files:
		if file_name.get_extension() != "tres" or file_name.ends_with("_alignment.tres"):
			continue
		var resource := load("res://resources/equipment".path_join(file_name))
		if resource is EquipmentData and not resource.sprite_frames_dir.is_empty():
			_equipment_entries.append(resource)
			_equipment_options.add_item(resource.display_name + "  (" + resource.id + ")")
	if _equipment_entries.is_empty():
		_set_status("Не найдено EquipmentData с заполненным sprite_frames_dir.", true)
		return
	_on_equipment_selected(0)


func _on_equipment_selected(index: int) -> void:
	if index < 0 or index >= _equipment_entries.size():
		return
	_equipment = _equipment_entries[index]
	_profile = _equipment.alignment_profile
	if _profile == null:
		_profile = EquipmentAlignmentProfile.new()
	_dirty = false
	_save_button.disabled = false
	_reload_frames()


func _reload_frames() -> void:
	if _equipment == null:
		return
	var direction := _current_direction()
	var animation := _current_animation()
	_body_frames = _load_body_series(_body_path.text.strip_edges(), direction, animation)
	_equipment_frames = _load_equipment_series(
		_equipment.sprite_frames_dir,
		direction,
		animation
	)
	var frame_count := maxi(_body_frames.size(), 1)
	_updating_controls = true
	_frame_spin.max_value = frame_count
	_frame_spin.value = clampi(int(_frame_spin.value), 1, frame_count)
	_updating_controls = false
	_refresh_preview()
	if _body_frames.is_empty() or _equipment_frames.is_empty():
		_set_status(
			"Не найдены кадры: тело=%d, предмет=%d" % [
				_body_frames.size(), _equipment_frames.size()
			],
			true
		)
	else:
		_set_status(
			"Загружено кадров: тело=%d, предмет=%d." % [
				_body_frames.size(), _equipment_frames.size()
			]
		)


func _refresh_preview() -> void:
	if _updating_controls or _profile == null:
		return
	var frame_index := _current_frame_index()
	var body: Texture2D = null
	var equipment_frame: Texture2D = null
	if not _body_frames.is_empty():
		body = _body_frames[frame_index % _body_frames.size()]
	if not _equipment_frames.is_empty():
		equipment_frame = _equipment_frames[frame_index % _equipment_frames.size()]
	var value := _profile.get_offset(
		_current_direction(), _current_animation(), frame_index
	)
	_updating_controls = true
	_x_spin.value = value.x
	_y_spin.value = value.y
	_updating_controls = false
	_preview.set_preview(body, equipment_frame, value)


func _set_current_offset(value: Vector2) -> void:
	if _profile == null:
		return
	value = value.round()
	_profile.set_frame_total_offset(
		_current_direction(), _current_animation(), _current_frame_index(), value
	)
	_dirty = true
	_updating_controls = true
	_x_spin.value = value.x
	_y_spin.value = value.y
	_updating_controls = false
	_preview.set_equipment_offset(value)
	_set_status("Несохранённое смещение кадра: (%d, %d)" % [int(value.x), int(value.y)])


func _on_offset_spin_changed() -> void:
	if _updating_controls:
		return
	_set_current_offset(Vector2(_x_spin.value, _y_spin.value))


func _reset_current_frame() -> void:
	if _profile == null:
		return
	_profile.clear_frame_offset(
		_current_direction(), _current_animation(), _current_frame_index()
	)
	_dirty = true
	_refresh_preview()
	_set_status("Покадровая поправка сброшена к общему смещению.")


func _step_frame(amount: int) -> void:
	var frame_count := maxi(int(_frame_spin.max_value), 1)
	var next_value := posmod(_current_frame_index() + amount, frame_count) + 1
	_frame_spin.value = next_value


func _save_profile() -> void:
	if _equipment == null or _profile == null:
		return
	var profile_path := _profile.resource_path
	if profile_path.is_empty():
		profile_path = _equipment.resource_path.get_basename() + "_alignment.tres"
	var profile_error := ResourceSaver.save(_profile, profile_path)
	if profile_error != OK:
		_set_status("Не удалось сохранить профиль: ошибка %d" % profile_error, true)
		return
	_equipment.alignment_profile = _profile
	var equipment_error := ResourceSaver.save(_equipment, _equipment.resource_path)
	if equipment_error != OK:
		_set_status("Профиль сохранён, но EquipmentData не обновлён: ошибка %d" % equipment_error, true)
		return
	_dirty = false
	_editor_interface.get_resource_filesystem().scan_sources()
	_set_status("Сохранено: " + profile_path)


func _load_body_series(base_dir: String, direction: String, animation: String) -> Array[Texture2D]:
	var direction_dir := base_dir.path_join(direction)
	var candidates: Array[PackedStringArray] = []
	candidates.append(PackedStringArray([
		direction_dir.path_join(animation).path_join("default"), "frame"
	]))
	if animation == "idle":
		candidates.append(PackedStringArray([direction_dir, "idle"]))
	else:
		if direction == "front":
			candidates.append(PackedStringArray([
				direction_dir.path_join("run_v10_source_exact"), "run"
			]))
		candidates.append(PackedStringArray([direction_dir.path_join("run_v1"), "run"]))
		candidates.append(PackedStringArray([direction_dir, "walk"]))
		candidates.append(PackedStringArray([direction_dir, "run"]))
	return _load_first_series(candidates)


func _load_equipment_series(base_dir: String, direction: String, animation: String) -> Array[Texture2D]:
	var direction_dir := base_dir.path_join(direction)
	return _load_first_series([
		PackedStringArray([
			direction_dir.path_join(animation).path_join("default"), "frame"
		]),
		PackedStringArray([direction_dir, animation]),
	])


func _load_first_series(candidates: Array) -> Array[Texture2D]:
	for candidate: PackedStringArray in candidates:
		var frames := _load_series(candidate[0], candidate[1])
		if not frames.is_empty():
			return frames
	return []


func _load_series(directory: String, prefix: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var index := 1
	while true:
		var path := "%s/%s_%02d.png" % [directory, prefix, index]
		if not ResourceLoader.exists(path):
			break
		var texture := load(path) as Texture2D
		if texture == null:
			break
		frames.append(texture)
		index += 1
	return frames


func _current_direction() -> StringName:
	return StringName(SOURCE_DIRECTIONS[_direction_options.selected])


func _current_animation() -> StringName:
	return StringName(ANIMATIONS[_animation_options.selected])


func _current_frame_index() -> int:
	return maxi(int(_frame_spin.value) - 1, 0)


func _set_status(message: String, is_error := false) -> void:
	_status.text = message
	_status.modulate = Color("ff817c") if is_error else Color("b8d7a3")
