## Экран обыска тела: список предметов павшего (врага или союзника) с кнопками «Взять».
## Открывается LootableCorpse через группу "loot_ui" по клавише "interact" (F).
## Ставит игру на паузу (process_mode = WHEN_PAUSED позволяет панели реагировать на ввод).
## Один и тот же экран для врагов и союзников — источник (LootableCorpse) скрывает разницу.
extends CanvasLayer

@onready var _title_label: Label = $Dim/CenterContainer/Panel/Margin/VBoxContainer/HeaderRow/TitleLabel
@onready var _gold_label: Label = $Dim/CenterContainer/Panel/Margin/VBoxContainer/GoldLabel
@onready var _loot_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ScrollContainer/LootList
@onready var _take_all_button: Button = $Dim/CenterContainer/Panel/Margin/VBoxContainer/TakeAllButton

var _source: LootableCorpse = null
var _row_style_normal: StyleBoxFlat
var _row_style_hover: StyleBoxFlat

func _ready() -> void:
	add_to_group("loot_ui")
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_row_styles()
	hide()
	# Взятие предмета меняет рюкзак; если он переполнился — обновляем доступность строк.
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	# ESC снимает паузу через PauseManager напрямую — синхронизируемся, чтобы панель
	# не осталась висеть поверх разблокированного мира.
	PauseManager.unpaused.connect(_on_unpaused)

## F закрывает открытый экран (симметрично открытию). Экран работает при паузе,
## поэтому обрабатывает ввод, пока LootableCorpse (в паузе неактивен) — нет.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()

## Открывает обыск тела [param source] и ставит игру на паузу.
func open(source: LootableCorpse) -> void:
	_source = source
	if not source.loot_changed.is_connected(_on_source_changed):
		source.loot_changed.connect(_on_source_changed)
	_title_label.text = source.corpse_name
	_refresh()
	show()
	PauseManager.pause()

## Закрывает экран, снимает паузу и удаляет пустое тело (только контейнер, не труп союзника).
func close() -> void:
	if _source != null and is_instance_valid(_source):
		if _source.loot_changed.is_connected(_on_source_changed):
			_source.loot_changed.disconnect(_on_source_changed)
		if _source.is_empty():
			_source.despawn()
	_source = null
	hide()
	PauseManager.unpause()

func _on_unpaused() -> void:
	# Пауза снята извне (ESC) — прячемся, но так же подчищаем пустое тело.
	if _source != null and is_instance_valid(_source):
		if _source.loot_changed.is_connected(_on_source_changed):
			_source.loot_changed.disconnect(_on_source_changed)
		if _source.is_empty():
			_source.despawn()
	_source = null
	hide()

func _on_source_changed() -> void:
	_refresh()

func _on_inventory_changed() -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	if _source == null or not is_instance_valid(_source):
		close()
		return

	# Золото показываем отдельной строкой списка (ниже), верхний лейбл не используем.
	_gold_label.visible = false
	var gold: int = _source.get_loot_gold()

	for child in _loot_list.get_children():
		child.queue_free()

	var entries: Array = _source.get_loot_entries()
	if entries.is_empty() and gold == 0:
		var empty_label := Label.new()
		empty_label.text = "Пусто"
		empty_label.add_theme_color_override("font_color", Color(0.58, 0.53, 0.5, 1))
		_loot_list.add_child(empty_label)
		_take_all_button.disabled = true
		return

	_take_all_button.disabled = false
	if gold > 0:
		_loot_list.add_child(_make_row(
			"Золото: %d" % gold, "Взять",
			func() -> void: _source.take_gold()
		))
	for entry: Dictionary in entries:
		# Копируем запись в замыкание: список пересобирается после каждого взятия.
		var captured := entry
		_loot_list.add_child(_make_row(
			entry.text, "Взять",
			func() -> void: _source.take_entry(captured)
		))

func _on_take_all_pressed() -> void:
	if _source != null and is_instance_valid(_source):
		_source.take_all()

func _make_row(label_text: String, button_text: String, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.78, 0.71, 0.6, 1))
	row.add_child(label)

	var button := Button.new()
	button.text = button_text
	button.add_theme_stylebox_override("normal", _row_style_normal)
	button.add_theme_stylebox_override("hover", _row_style_hover)
	button.add_theme_color_override("font_color", Color(0.78, 0.71, 0.6, 1))
	button.add_theme_color_override("font_hover_color", Color(0.95, 0.83, 0.45, 1))
	button.pressed.connect(callback)
	row.add_child(button)

	return row

func _build_row_styles() -> void:
	_row_style_normal = StyleBoxFlat.new()
	_row_style_normal.bg_color = Color(0.039, 0.031, 0.035, 0.85)
	_row_style_normal.border_width_left = 1
	_row_style_normal.border_width_top = 1
	_row_style_normal.border_width_right = 1
	_row_style_normal.border_width_bottom = 1
	_row_style_normal.border_color = Color(0.471, 0.376, 0.212, 0.4)
	_row_style_normal.content_margin_left = 12
	_row_style_normal.content_margin_top = 4
	_row_style_normal.content_margin_right = 12
	_row_style_normal.content_margin_bottom = 4

	_row_style_hover = _row_style_normal.duplicate() as StyleBoxFlat
	_row_style_hover.bg_color = Color(0.588, 0.275, 0.141, 0.2)
	_row_style_hover.border_color = Color(0.55, 0.44, 0.25, 0.55)

func _on_close_pressed() -> void:
	close()
