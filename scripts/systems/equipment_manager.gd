## Управляет надетым снаряжением персонажа.
## Слоты брони (HEAD, BODY, LEGS, GLOVES) — по одному. Аксессуаров — до MAX_ACCESSORIES.
## При экипировке нового предмета старый автоматически уходит в рюкзак.
## Является Autoload-синглтоном; регистрировать как "EquipmentManager" в Project Settings.
extends Node

const MAX_ACCESSORIES: int = 3

## Словарь: int(EquipmentData.Slot) → EquipmentData. Аксессуары хранятся отдельно.
var _equipped: Dictionary = {}
var _accessories: Array[EquipmentData] = []

signal item_equipped(slot: int, item: EquipmentData)
signal item_unequipped(slot: int, item: EquipmentData)
signal equipment_changed()

## Надевает [param item] из рюкзака.
## Двуручное оружие автоматически снимает предмет со слота WEAPON_OFF.
## Возвращает [code]false[/code] если аксессуарный список заполнен.
func equip(item: EquipmentData) -> bool:
	if item.slot == EquipmentData.Slot.ACCESSORY:
		if _accessories.size() >= MAX_ACCESSORIES:
			return false
		_accessories.append(item)
		item_equipped.emit(item.slot, item)
		equipment_changed.emit()
		return true

	if item.weapon_type == EquipmentData.WeaponType.MELEE_TWO_HAND:
		_displace_slot(EquipmentData.Slot.WEAPON_OFF)

	_displace_slot(item.slot)
	_equipped[item.slot] = item
	item_equipped.emit(item.slot, item)
	equipment_changed.emit()
	return true

## Снимает предмет из слота [param slot] обратно в рюкзак.
## Для аксессуаров используй [method unequip_accessory].
## Возвращает [code]false[/code] если слот пуст или рюкзак полон.
func unequip_slot(slot: EquipmentData.Slot) -> bool:
	if slot == EquipmentData.Slot.ACCESSORY:
		return false
	if not _equipped.has(slot):
		return false
	var item: EquipmentData = _equipped[slot]
	if not InventorySystem.add_item(item):
		return false
	_equipped.erase(slot)
	item_unequipped.emit(slot, item)
	equipment_changed.emit()
	return true

## Снимает аксессуар по его позиции [param index] в списке аксессуаров.
## Возвращает [code]false[/code] если индекс вне диапазона или рюкзак полон.
func unequip_accessory(index: int) -> bool:
	if index < 0 or index >= _accessories.size():
		return false
	var item: EquipmentData = _accessories[index]
	if not InventorySystem.add_item(item):
		return false
	_accessories.remove_at(index)
	item_unequipped.emit(EquipmentData.Slot.ACCESSORY, item)
	equipment_changed.emit()
	return true

## Возвращает надетый предмет в слоте [param slot], или [code]null[/code] если слот пуст.
func get_equipped(slot: EquipmentData.Slot) -> EquipmentData:
	return _equipped.get(slot, null)

## Возвращает копию списка надетых аксессуаров.
func get_accessories() -> Array[EquipmentData]:
	return _accessories.duplicate()

## Возвращает суммарный бонус стата [param stat] от всего надетого снаряжения.
func get_total_stat(stat: String) -> int:
	var total := 0
	for item: EquipmentData in _equipped.values():
		if item and item.stat_bonuses.has(stat):
			total += item.stat_bonuses[stat]
	for item: EquipmentData in _accessories:
		if item.stat_bonuses.has(stat):
			total += item.stat_bonuses[stat]
	return total

## Снимает всё снаряжение без возврата в рюкзак (например, при смерти или создании нового персонажа).
func clear() -> void:
	_equipped.clear()
	_accessories.clear()
	equipment_changed.emit()

## Сериализует состояние экипировки для сохранения в JSON.
func serialize() -> Dictionary:
	var equipped_data: Dictionary = {}
	for slot: int in _equipped:
		var item: EquipmentData = _equipped[slot]
		equipped_data[str(slot)] = item.resource_path if item else null
	var acc_data: Array = []
	for item: EquipmentData in _accessories:
		acc_data.append(item.resource_path if item else null)
	return { "equipped": equipped_data, "accessories": acc_data }

## Восстанавливает состояние экипировки из данных, сохранённых через [method serialize].
func deserialize(data: Dictionary) -> void:
	_equipped.clear()
	_accessories.clear()
	for slot_str: String in data.get("equipped", {}):
		var res_path = data.equipped[slot_str]
		if res_path and ResourceLoader.exists(res_path):
			var item := load(res_path) as EquipmentData
			if item:
				_equipped[slot_str.to_int()] = item
	for res_path in data.get("accessories", []):
		if res_path and ResourceLoader.exists(res_path):
			var item := load(res_path) as EquipmentData
			if item:
				_accessories.append(item)
	equipment_changed.emit()

# Снимает предмет из слота и кладёт в рюкзак без эмита equipment_changed.
# Используется внутри equip() чтобы освободить слот перед надеванием нового предмета.
func _displace_slot(slot: EquipmentData.Slot) -> void:
	if not _equipped.has(slot):
		return
	var old_item: EquipmentData = _equipped[slot]
	_equipped.erase(slot)
	InventorySystem.add_item(old_item)
	item_unequipped.emit(slot, old_item)
