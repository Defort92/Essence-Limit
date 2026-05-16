## Таблица дропа: определяет какие предметы и с какой вероятностью выпадают из врага.
## Настраивается через .tres-ресурс, назначается на EnemyData.loot_table.
extends Resource
class_name LootTable

## Сколько раз крутить таблицу при каждом дропе.
@export var roll_count: int = 1
@export var gold_min: int = 0
@export var gold_max: int = 0

## Массив записей дропа. Каждая запись — словарь с ключами:
##   path: String     — res://-путь к ItemData-ресурсу
##   weight: float    — вес (относительная вероятность)
##   min_count: int
##   max_count: int
@export var entries: Array[Dictionary] = []

## Выполняет roll_count бросков по таблице.
## Возвращает Array[Dictionary] вида { item: ItemData, quantity: int }.
func roll() -> Array:
	var result := []

	var total_weight := 0.0
	for entry in entries:
		total_weight += float(entry.get("weight", 1.0))

	if total_weight <= 0.0:
		return result

	for _roll_idx in range(roll_count):
		var roll_value := randf() * total_weight
		var cumulative := 0.0
		for entry in entries:
			cumulative += float(entry.get("weight", 1.0))
			if roll_value <= cumulative:
				var res_path: String = entry.get("path", "")
				if res_path and ResourceLoader.exists(res_path):
					var item := load(res_path) as ItemData
					if item:
						var qty: int = randi_range(
							entry.get("min_count", 1),
							entry.get("max_count", 1)
						)
						result.append({ "item": item, "quantity": qty })
				break

	return result

## Возвращает случайное количество золота в диапазоне [gold_min, gold_max].
func roll_gold() -> int:
	return randi_range(gold_min, gold_max)
