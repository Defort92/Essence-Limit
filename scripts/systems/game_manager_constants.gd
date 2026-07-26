## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name GameManagerConstants
extends RefCounted

## Значения должны совпадать с GameManager.Race: словари ниже индексируются этой нумерацией.
enum Race { HUMAN, BARBARIAN, ELF, DEMON, ANGEL }

## Золото — обычный (стакающийся) предмет в личном рюкзаке персонажа, а не общий счётчик:
## у каждого участника отряда своя пачка золота-предмета в InventoryComponent.
## GameManager.gold — сумма по всему отряду, только для отображения (лавка, HUD этажа).
const GOLD_ITEM: ItemData = preload("res://resources/items/gold.tres")

## Начальные статы при создании персонажа.
const RACE_BASE_STATS := {
	Race.HUMAN:     { "max_health": 100, "strength": 10, "agility": 10, "intellect": 10 },
	Race.BARBARIAN: { "max_health": 150, "strength": 14, "agility":  8, "intellect":  5 },
	Race.ELF:       { "max_health":  80, "strength":  7, "agility": 15, "intellect": 10 },
	Race.DEMON:     { "max_health": 100, "strength": 13, "agility": 12, "intellect":  7 },
	Race.ANGEL:     { "max_health":  90, "strength":  8, "agility": 10, "intellect": 15 },
}

## Прибавка к max_health за каждый уровень.
const RACE_LEVEL_HP_BONUS := {
	Race.HUMAN:     5,
	Race.BARBARIAN: 10,
	Race.ELF:       3,
	Race.DEMON:     5,
	Race.ANGEL:     4,
}
