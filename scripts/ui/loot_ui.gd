## Экран обыска тела: список предметов павшего (врага или союзника) с кнопками «Взять».
## Открывается LootableCorpse через группу "loot_ui" по клавише "interact" (F).
## Каркас модалки (пауза, блюр, закрытие по клавише/крестику/фону/ESC) — в UIModalScreen.
## Один и тот же экран для врагов и союзников — источник (LootableCorpse) скрывает разницу.
extends UIModalScreen

@onready var _title_label: Label = $CenterContainer/Panel/Margin/VBoxContainer/HeaderRow/TitleLabel
@onready var _gold_label: Label = $CenterContainer/Panel/Margin/VBoxContainer/GoldLabel
@onready var _loot_list: VBoxContainer = $CenterContainer/Panel/Margin/VBoxContainer/ScrollContainer/LootList
@onready var _take_all_button: Button = $CenterContainer/Panel/Margin/VBoxContainer/TakeAllButton

var _source: LootableCorpse = null

func _ready() -> void:
	screen_group = "loot_ui"
	close_action = "interact"
	super._ready()
	# Взятие предмета меняет рюкзак; если он переполнился — обновляем доступность строк.
	InventorySystem.inventory_changed.connect(_on_inventory_changed)

## Открывает обыск тела [param source] и ставит игру на паузу.
func open(source: LootableCorpse) -> void:
	_source = source
	if not source.loot_changed.is_connected(_on_source_changed):
		source.loot_changed.connect(_on_source_changed)
	_title_label.text = source.corpse_name
	_refresh()
	_show_modal()

## Любое закрытие (клавиша, крестик, фон, ESC): отписка и удаление пустого тела
## (только контейнера — труп союзника остаётся в сцене).
func _before_close() -> void:
	if _source != null and is_instance_valid(_source):
		if _source.loot_changed.is_connected(_on_source_changed):
			_source.loot_changed.disconnect(_on_source_changed)
		if _source.is_empty():
			_source.despawn()
	_source = null

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
		_loot_list.add_child(UIListRow.create(
			"Золото: %d" % gold,
			[{"text": "Взять", "callback": func() -> void: _source.take_gold()}]
		))
	for entry: Dictionary in entries:
		# Копируем запись в замыкание: список пересобирается после каждого взятия.
		var captured := entry
		_loot_list.add_child(UIListRow.create(
			entry.text,
			[{"text": "Взять", "callback": func() -> void: _source.take_entry(captured)}]
		))

## «Взять всё»: забираем весь лут и сразу закрываем экран (пустое тело подчистит close()).
func _on_take_all_pressed() -> void:
	if _source != null and is_instance_valid(_source):
		_source.take_all()
	close()
