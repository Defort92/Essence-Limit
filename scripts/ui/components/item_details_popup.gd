## Модальная карточка предмета поверх экрана персонажа.
## Показывает крупную иконку, описание и характеристики любого ItemData.
extends Control
class_name ItemDetailsPopup


@onready var _name_label: Label = $Backdrop/CenterContainer/Panel/Margin/VBoxContainer/HeaderRow/NameLabel
@onready var _rarity_label: Label = $Backdrop/CenterContainer/Panel/Margin/VBoxContainer/ContentRow/IconColumn/RarityLabel
@onready var _icon_rect: TextureRect = $Backdrop/CenterContainer/Panel/Margin/VBoxContainer/ContentRow/IconColumn/IconRect
@onready var _description_label: Label = $Backdrop/CenterContainer/Panel/Margin/VBoxContainer/ContentRow/InfoColumn/DescriptionLabel
@onready var _stats_label: Label = $Backdrop/CenterContainer/Panel/Margin/VBoxContainer/ContentRow/InfoColumn/StatsLabel

var current_item: ItemData = null


func _ready() -> void:
	_icon_rect.custom_minimum_size = ItemDetailsPopupConstants.LARGE_ICON_SIZE
	hide()


func show_item(item: ItemData) -> void:
	if item == null:
		return
	current_item = item
	_name_label.text = item.display_name
	_icon_rect.texture = item.icon
	_description_label.text = item.description if not item.description.is_empty() else "Описание отсутствует."
	_set_rarity(item.rarity)
	_stats_label.text = "\n".join(_build_characteristics(item))
	show()


func close() -> void:
	current_item = null
	hide()


func _set_rarity(rarity: int) -> void:
	var safe_index: int = clampi(rarity, 0, ItemDetailsPopupConstants.RARITY_NAMES.size() - 1)
	_rarity_label.text = ItemDetailsPopupConstants.RARITY_NAMES[safe_index]
	_rarity_label.add_theme_color_override("font_color", ItemDetailsPopupConstants.RARITY_COLORS[safe_index])


func _build_characteristics(item: ItemData) -> PackedStringArray:
	var lines := PackedStringArray()
	if item is EquipmentData:
		var equipment := item as EquipmentData
		lines.append("Тип: %s" % ItemDetailsPopupConstants.WEAPON_TYPE_NAMES.get(equipment.weapon_type, "Снаряжение"))
		var slot_name: String = "Руки" if equipment.weapon_type != EquipmentData.WeaponType.NONE else ItemDetailsPopupConstants.SLOT_NAMES.get(equipment.slot, "Не указан")
		lines.append("Слот: %s" % slot_name)
		_append_stat_bonuses(lines, equipment.stat_bonuses)
	elif item is EssenceData:
		var essence := item as EssenceData
		lines.append("Тип: Эссенция")
		_append_stat_bonuses(lines, essence.stat_bonuses)
		lines.append("Удаление: %d зол." % essence.removal_cost)
	elif item is ConsumableData:
		_append_consumable_effect(lines, item as ConsumableData)
	else:
		lines.append("Тип: Предмет")

	if item.buy_price > 0:
		lines.append("Цена покупки: %d зол." % item.buy_price)
	if item.sell_price > 0:
		lines.append("Цена продажи: %d зол." % item.sell_price)
	return lines


func _append_stat_bonuses(lines: PackedStringArray, bonuses: Dictionary) -> void:
	for stat_key: Variant in bonuses:
		var stat_name: String = str(stat_key)
		var display_name: String = ItemDetailsPopupConstants.STAT_NAMES.get(stat_name, stat_name.capitalize())
		var value: Variant = bonuses[stat_key]
		var prefix := "+" if (value is int or value is float) and value >= 0 else ""
		lines.append("%s: %s%s" % [display_name, prefix, str(value)])


func _append_consumable_effect(lines: PackedStringArray, consumable: ConsumableData) -> void:
	lines.append("Тип: Расходуемый предмет")
	var effect_name: String = ItemDetailsPopupConstants.EFFECT_NAMES.get(consumable.effect_type, "Эффект")
	var value_text := str(consumable.effect_value)
	if consumable.effect_type == ConsumableData.EffectType.HEAL_PERCENT:
		value_text = "%d%%" % roundi(consumable.effect_value * 100.0)
	lines.append("%s: %s" % [effect_name, value_text])
	if consumable.duration > 0.0:
		lines.append("Длительность: %s сек." % str(consumable.duration))


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	close()
