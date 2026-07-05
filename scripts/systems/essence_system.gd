## Система эссенций: хранит слоты, управляет установкой и удалением.
## Количество слотов = уровень персонажа + bonus_slots (расовые обряды Демона/Ангела).
## При понижении уровня лишние слоты становятся заблокированными —
## эссенции в них не теряются, но и не дают статов. UI отображает их как locked.
## Компонент на каждого участника отряда — дочерний узел "Essence" в player.tscn.
## У каждого персонажа свои слоты эссенций, доступ через Player.essence.
extends Node
class_name EssenceSystem

## Массив слотов: индекс → EssenceData (null = пуст).
## Размер массива может быть больше _active_slot_count при понижении уровня.
var slots: Array[EssenceData] = []
## Дополнительные слоты от расовых обрядов Демона/Ангела.
var bonus_slots: int = 0
## Количество активных слотов (level + bonus_slots). Слоты с индексом >= этого значения заблокированы.
var _active_slot_count: int = 0

signal essence_equipped(slot_index: int, essence: EssenceData)
signal essence_removed(slot_index: int)
signal slots_changed()

## Обновляет количество активных слотов.
## Если level уменьшился — лишние слоты блокируются, но эссенции в них не теряются.
## Если level вырос — новые слоты добавляются и становятся доступными.
func resize_to_level(level: int) -> void:
	_active_slot_count = level + bonus_slots
	if _active_slot_count > slots.size():
		slots.resize(_active_slot_count)
	slots_changed.emit()

## Добавляет один дополнительный слот (расовый обряд Демона/Ангела).
func add_bonus_slot() -> void:
	bonus_slots += 1
	_active_slot_count += 1
	if _active_slot_count > slots.size():
		slots.resize(_active_slot_count)
	slots_changed.emit()

## Возвращает количество активных (незаблокированных) слотов.
func get_active_slot_count() -> int:
	return _active_slot_count

## Возвращает [code]true[/code] если слот [param slot_index] заблокирован из-за понижения уровня.
func is_slot_locked(slot_index: int) -> bool:
	return slot_index >= _active_slot_count

## Вставляет [param essence] из рюкзака в первый свободный активный слот.
## Атомарно удаляет из инвентаря и устанавливает в слот.
## Возвращает [code]false[/code] если предмета нет или все активные слоты заняты.
func equip_from_inventory(essence: EssenceData) -> bool:
	if not InventorySystem.has_item(essence.id):
		return false
	if not equip(essence):
		return false
	InventorySystem.remove_item(essence.id, 1)
	return true

## Вставляет [param essence] напрямую (без удаления из рюкзака).
## Используй equip_from_inventory() из UI; этот метод — для внутренней логики и загрузки.
## Устанавливает только в активные слоты. Возвращает [code]false[/code] если все заняты.
func equip(essence: EssenceData) -> bool:
	for idx in _active_slot_count:
		if idx >= slots.size():
			break
		if slots[idx] == null:
			slots[idx] = essence
			essence_equipped.emit(idx, essence)
			return true
	return false

## Удаляет эссенцию из слота [param slot_index] за плату [member EssenceData.removal_cost].
## Эссенция уничтожается — в инвентарь не возвращается.
## Вызывать только в городе (player.is_in_town == true).
## Возвращает [code]false[/code] если слот пуст или не хватает золота.
func remove(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var essence: EssenceData = slots[slot_index]
	if essence == null:
		return false
	if not GameManager.spend_gold(essence.removal_cost):
		return false
	slots[slot_index] = null
	essence_removed.emit(slot_index)
	return true

## Возвращает суммарный бонус стата [param stat_name] только от эссенций в активных слотах.
## Заблокированные слоты (индекс >= _active_slot_count) не учитываются.
func get_total_stat(stat_name: String) -> int:
	var total := 0
	for idx in _active_slot_count:
		if idx >= slots.size():
			break
		var essence: EssenceData = slots[idx]
		if essence != null and essence.stat_bonuses.has(stat_name):
			total += essence.stat_bonuses[stat_name]
	return total
