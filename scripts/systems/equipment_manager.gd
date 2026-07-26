## Управляет надетым снаряжением персонажа.
## Слоты брони (HEAD, BODY, LEGS, GLOVES) — по одному. Аксессуаров — до MAX_ACCESSORIES.
## При экипировке нового предмета старый автоматически уходит в рюкзак.
## Сломанный предмет не даёт статов и помечается в UI как broken.
## Починка доступна у ремесленника в городе за золото.
## Компонент на каждого участника отряда — дочерний узел "Equipment" в player.tscn.
## У каждого персонажа своё снаряжение, доступ через Player.equipment.
## Снятое/надеваемое снаряжение уходит в рюкзак ТОГО ЖЕ персонажа (см. _inventory()) —
## рюкзаки у каждого свои, общего на отряд больше нет.
extends Node
class_name EquipmentManager

## Словарь: int(EquipmentData.Slot) → EquipmentData. Аксессуары хранятся отдельно.
var _equipped: Dictionary = {}
var _accessories: Array[EquipmentData] = []

## Сломанные слоты: int(EquipmentData.Slot) → true.
var _broken_slots: Dictionary = {}
## Параллельный массив статуса поломки для аксессуаров (индекс совпадает с _accessories).
var _broken_accessories: Array[bool] = []

signal item_equipped(slot: int, item: EquipmentData)
signal item_unequipped(slot: int, item: EquipmentData)
signal equipment_changed()
## Испускается при поломке предмета. UI должен показать предупреждение.
signal item_broke(slot: int, item: EquipmentData)

# ─── Экипировка ────────────────────────────────────────────────────────────

## Надевает [param item], предварительно удаляя его из рюкзака.
## Используй этот метод из UI — он атомарно делает remove из инвентаря и equip.
## Возвращает [code]false[/code] если предмета нет в рюкзаке или аксессуарный список полон.
func equip_from_inventory(item: EquipmentData) -> bool:
	if not _inventory().has_item(item.id):
		return false
	if not equip(item):
		return false
	_inventory().remove_item(item.id, 1)
	return true

## Надевает [param item] напрямую (без удаления из рюкзака).
## Используй equip_from_inventory() из UI; этот метод — для внутренней логики и загрузки.
## Двуручное оружие автоматически снимает предмет со слота WEAPON_OFF.
## Возвращает [code]false[/code] если аксессуарный список заполнен.
func equip(item: EquipmentData) -> bool:
	if item.slot == EquipmentData.Slot.ACCESSORY:
		if _accessories.size() >= EquipmentManagerConstants.MAX_ACCESSORIES:
			return false
		_accessories.append(item)
		_broken_accessories.append(false)
		item_equipped.emit(item.slot, item)
		equipment_changed.emit()
		return true

	if item.weapon_type == EquipmentData.WeaponType.MELEE_TWO_HAND:
		_displace_slot(EquipmentData.Slot.WEAPON_OFF)

	_displace_slot(item.slot)
	_equipped[item.slot] = item
	_broken_slots.erase(item.slot)
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
	if not _inventory().add_item(item):
		return false
	_equipped.erase(slot)
	_broken_slots.erase(slot)
	item_unequipped.emit(slot, item)
	equipment_changed.emit()
	return true

## Снимает аксессуар по его позиции [param index] в списке аксессуаров.
## Возвращает [code]false[/code] если индекс вне диапазона или рюкзак полон.
func unequip_accessory(index: int) -> bool:
	if index < 0 or index >= _accessories.size():
		return false
	var item: EquipmentData = _accessories[index]
	if not _inventory().add_item(item):
		return false
	_accessories.remove_at(index)
	_broken_accessories.remove_at(index)
	item_unequipped.emit(EquipmentData.Slot.ACCESSORY, item)
	equipment_changed.emit()
	return true

## Снимает предмет со слота [param slot] без возврата в чей-либо рюкзак — вызывающий сам
## решает, куда положить предмет. Нужно для лута с трупа: LootableCorpse кладёт снятое
## в рюкзак активного мародёра, а не автоматически обратно покойнику (unequip_slot всегда
## кладёт в рюкзак ВЛАДЕЛЬЦА этой экипировки — для мёртвого союзника это не то, что нужно).
## Возвращает [code]null[/code], если слот пуст или это ACCESSORY (см. take_accessory).
func take_from_slot(slot: EquipmentData.Slot) -> EquipmentData:
	if slot == EquipmentData.Slot.ACCESSORY or not _equipped.has(slot):
		return null
	var item: EquipmentData = _equipped[slot]
	_equipped.erase(slot)
	_broken_slots.erase(slot)
	item_unequipped.emit(slot, item)
	equipment_changed.emit()
	return item

## Снимает аксессуар по позиции [param index] без возврата в чей-либо рюкзак — см. take_from_slot.
func take_accessory(index: int) -> EquipmentData:
	if index < 0 or index >= _accessories.size():
		return null
	var item: EquipmentData = _accessories[index]
	_accessories.remove_at(index)
	_broken_accessories.remove_at(index)
	item_unequipped.emit(EquipmentData.Slot.ACCESSORY, item)
	equipment_changed.emit()
	return item

## Возвращает надетый предмет в слоте [param slot], или [code]null[/code] если слот пуст.
func get_equipped(slot: EquipmentData.Slot) -> EquipmentData:
	return _equipped.get(slot, null)

## Возвращает копию списка надетых аксессуаров.
func get_accessories() -> Array[EquipmentData]:
	return _accessories.duplicate()

## Возвращает [code]true[/code] если надет хотя бы один предмет (слот или аксессуар).
## Используется LootableCorpse, чтобы понять, есть ли что снять с павшего союзника.
func has_any_equipped() -> bool:
	return not _equipped.is_empty() or not _accessories.is_empty()

## Возвращает суммарный бонус стата [param stat] от всего надетого снаряжения.
## Сломанные предметы не учитываются.
func get_total_stat(stat: String) -> int:
	var total := 0
	for slot: int in _equipped:
		if _broken_slots.get(slot, false):
			continue
		var item: EquipmentData = _equipped[slot]
		if item and item.stat_bonuses.has(stat):
			total += item.stat_bonuses[stat]
	for idx in _accessories.size():
		if _broken_accessories[idx]:
			continue
		var item: EquipmentData = _accessories[idx]
		if item.stat_bonuses.has(stat):
			total += item.stat_bonuses[stat]
	return total

## Снимает всё снаряжение без возврата в рюкзак (например, при создании нового персонажа).
func clear() -> void:
	_equipped.clear()
	_accessories.clear()
	_broken_slots.clear()
	_broken_accessories.clear()
	equipment_changed.emit()

# ─── Поломка и починка ─────────────────────────────────────────────────────

## Ломает предмет в слоте [param slot] (вызывается из атаки босса/моба).
## Если слот пуст или предмет уже сломан — ничего не происходит.
func break_equipped_item(slot: EquipmentData.Slot) -> void:
	if slot == EquipmentData.Slot.ACCESSORY:
		return
	var item: EquipmentData = _equipped.get(slot, null)
	if item == null or _broken_slots.get(slot, false):
		return
	_broken_slots[slot] = true
	item_broke.emit(slot, item)
	equipment_changed.emit()

## Ломает аксессуар по его позиции [param index].
## Если индекс вне диапазона или уже сломан — ничего не происходит.
func break_accessory(index: int) -> void:
	if index < 0 or index >= _accessories.size():
		return
	if _broken_accessories[index]:
		return
	_broken_accessories[index] = true
	item_broke.emit(EquipmentData.Slot.ACCESSORY, _accessories[index])
	equipment_changed.emit()

## Возвращает [code]true[/code] если предмет в слоте [param slot] сломан.
func is_slot_broken(slot: EquipmentData.Slot) -> bool:
	if slot == EquipmentData.Slot.ACCESSORY:
		return false
	return _broken_slots.get(slot, false)

## Возвращает [code]true[/code] если аксессуар с индексом [param index] сломан.
func is_accessory_broken(index: int) -> bool:
	if index < 0 or index >= _broken_accessories.size():
		return false
	return _broken_accessories[index]

## Возвращает стоимость починки предмета в слоте [param slot] в золоте.
## Формула: buy_price / REPAIR_COST_DIVISOR, минимум 1.
func get_repair_cost(slot: EquipmentData.Slot) -> int:
	var item: EquipmentData = _equipped.get(slot, null)
	if item == null:
		return 0
	var repair_cost := int(
		float(item.buy_price) / float(EquipmentManagerConstants.REPAIR_COST_DIVISOR)
	)
	return maxi(1, repair_cost)

## Возвращает стоимость починки аксессуара с индексом [param index] в золоте.
func get_accessory_repair_cost(index: int) -> int:
	if index < 0 or index >= _accessories.size():
		return 0
	var repair_cost := int(
		float(_accessories[index].buy_price)
		/ float(EquipmentManagerConstants.REPAIR_COST_DIVISOR)
	)
	return maxi(1, repair_cost)

## Чинит предмет в слоте [param slot], списывая золото.
## Вызывать только в городе. Возвращает [code]false[/code] если слот пуст,
## предмет не сломан, или не хватает золота.
func repair_slot(slot: EquipmentData.Slot) -> bool:
	if slot == EquipmentData.Slot.ACCESSORY:
		return false
	if not _broken_slots.get(slot, false):
		return false
	var cost := get_repair_cost(slot)
	if not GameManager.spend_gold(cost):
		return false
	_broken_slots.erase(slot)
	equipment_changed.emit()
	return true

## Чинит аксессуар с индексом [param index], списывая золото.
## Возвращает [code]false[/code] если не сломан или не хватает золота.
func repair_accessory(index: int) -> bool:
	if index < 0 or index >= _accessories.size():
		return false
	if not _broken_accessories[index]:
		return false
	var cost := get_accessory_repair_cost(index)
	if not GameManager.spend_gold(cost):
		return false
	_broken_accessories[index] = false
	equipment_changed.emit()
	return true

# ─── Сериализация ──────────────────────────────────────────────────────────

## Сериализует состояние экипировки для сохранения в JSON.
func serialize() -> Dictionary:
	var equipped_data: Dictionary = {}
	for slot: int in _equipped:
		var item: EquipmentData = _equipped[slot]
		var item_path: Variant = null
		if item != null:
			item_path = item.resource_path
		equipped_data[str(slot)] = {
			"path": item_path,
			"broken": _broken_slots.get(slot, false),
		}
	var acc_data: Array = []
	for idx in _accessories.size():
		var item: EquipmentData = _accessories[idx]
		var item_path: Variant = null
		if item != null:
			item_path = item.resource_path
		acc_data.append({
			"path": item_path,
			"broken": _broken_accessories[idx] if idx < _broken_accessories.size() else false,
		})
	return { "equipped": equipped_data, "accessories": acc_data }

## Восстанавливает состояние экипировки из данных, сохранённых через [method serialize].
func deserialize(data: Dictionary) -> void:
	_equipped.clear()
	_accessories.clear()
	_broken_slots.clear()
	_broken_accessories.clear()

	for slot_str: String in data.get("equipped", {}):
		var entry = data.equipped[slot_str]
		var res_path: String = entry.get("path", "") if entry is Dictionary else str(entry)
		if res_path and ResourceLoader.exists(res_path):
			var item := load(res_path) as EquipmentData
			if item:
				var slot_key := slot_str.to_int()
				_equipped[slot_key] = item
				if entry is Dictionary and entry.get("broken", false):
					_broken_slots[slot_key] = true

	for entry in data.get("accessories", []):
		var res_path: String = entry.get("path", "") if entry is Dictionary else str(entry)
		if res_path and ResourceLoader.exists(res_path):
			var item := load(res_path) as EquipmentData
			if item:
				_accessories.append(item)
				_broken_accessories.append(entry.get("broken", false) if entry is Dictionary else false)

	equipment_changed.emit()

## Рюкзак владельца этого компонента (Equipment — всегда дочерний узел своего Player).
func _inventory() -> InventoryComponent:
	return (get_parent() as Player).inventory

# Снимает предмет из слота и кладёт в рюкзак без эмита equipment_changed.
func _displace_slot(slot: EquipmentData.Slot) -> void:
	if not _equipped.has(slot):
		return
	var old_item: EquipmentData = _equipped[slot]
	_equipped.erase(slot)
	_broken_slots.erase(slot)
	_inventory().add_item(old_item)
	item_unequipped.emit(slot, old_item)
