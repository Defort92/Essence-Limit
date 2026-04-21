extends Node

# Слоты эссенций: индекс → EssenceData (null = пусто)
var slots: Array[EssenceData] = []
var bonus_slots: int = 0  # Дополнительные слоты (Демон/Ангел через обряды)

signal essence_equipped(slot_index: int, essence: EssenceData)
signal essence_removed(slot_index: int)
signal slots_changed()

func resize_to_level(level: int) -> void:
	var total = level + bonus_slots
	slots.resize(total)
	slots_changed.emit()

func add_bonus_slot() -> void:
	bonus_slots += 1
	slots.resize(slots.size() + 1)
	slots_changed.emit()

func equip(essence: EssenceData) -> bool:
	for i in slots.size():
		if slots[i] == null:
			slots[i] = essence
			essence_equipped.emit(i, essence)
			_apply_stats(essence, 1)
			return true
	return false

# Удаление только в городе — вызывать только при is_in_town() == true
func remove(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var essence = slots[slot_index]
	if essence == null:
		return false
	if not GameManager.spend_gold(essence.removal_cost):
		return false
	_apply_stats(essence, -1)
	slots[slot_index] = null
	essence_removed.emit(slot_index)
	return true

func get_total_stat(stat: String) -> int:
	var total = 0
	for essence in slots:
		if essence != null and essence.stat_bonuses.has(stat):
			total += essence.stat_bonuses[stat]
	return total

func _apply_stats(essence: EssenceData, multiplier: int) -> void:
	# Персонаж подписывается на сигналы и пересчитывает свои статы
	pass
