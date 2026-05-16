## Система эссенций: хранит слоты, управляет установкой и удалением.
## Количество слотов = уровень персонажа + bonus_slots (расовые обряды Демона/Ангела).
## Статы и способности пересчитываются подписчиками сигналов (Player, AbilityManager).
## Является Autoload-синглтоном; регистрировать как "EssenceSystem" в Project Settings.
extends Node

## Массив слотов: индекс → EssenceData (null = пуст).
var slots: Array[EssenceData] = []
## Дополнительные слоты от расовых обрядов Демона/Ангела.
var bonus_slots: int = 0

signal essence_equipped(slot_index: int, essence: EssenceData)
signal essence_removed(slot_index: int)
signal slots_changed()

## Изменяет размер массива слотов под текущий уровень.
## Вызывается XPSystem при каждом повышении уровня.
func resize_to_level(level: int) -> void:
	var total_slots := level + bonus_slots
	slots.resize(total_slots)
	slots_changed.emit()

## Добавляет один дополнительный слот (расовый обряд Демона/Ангела).
func add_bonus_slot() -> void:
	bonus_slots += 1
	slots.resize(slots.size() + 1)
	slots_changed.emit()

## Вставляет [param essence] из рюкзака в первый свободный слот.
## Атомарно удаляет из инвентаря и устанавливает в слот.
## Используй этот метод из UI. Возвращает [code]false[/code] если предмета нет или нет слотов.
func equip_from_inventory(essence: EssenceData) -> bool:
	if not InventorySystem.has_item(essence.id):
		return false
	if not equip(essence):
		return false
	InventorySystem.remove_item(essence.id, 1)
	return true

## Вставляет [param essence] напрямую (без удаления из рюкзака).
## Используй equip_from_inventory() из UI; этот метод — для внутренней логики и загрузки.
## Возвращает [code]false[/code] если все слоты заняты.
func equip(essence: EssenceData) -> bool:
	for idx in slots.size():
		if slots[idx] == null:
			slots[idx] = essence
			essence_equipped.emit(idx, essence)
			return true
	return false

## Удаляет эссенцию из слота [param slot_index] за плату [member EssenceData.removal_cost].
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

## Возвращает суммарный бонус стата [param stat_name] от всех вставленных эссенций.
func get_total_stat(stat_name: String) -> int:
	var total := 0
	for essence in slots:
		if essence != null and essence.stat_bonuses.has(stat_name):
			total += essence.stat_bonuses[stat_name]
	return total
