## Глобальное состояние персонажа: раса, имя, золото, базовые статы по расам.
## Является Autoload-синглтоном; регистрировать как "GameManager" в Project Settings.
extends Node

enum Race { HUMAN, BARBARIAN, ELF, DEMON, ANGEL }

var player_race: Race = Race.HUMAN
var player_name: String = ""
var gold: int = 0

## Временное хранилище HP для восстановления после загрузки сохранения.
## SaveSystem устанавливает это значение; Player читает его в _init_race_stats().
var saved_health: int = -1

signal gold_changed(new_amount: int)

## Начальные статы при создании персонажа.
## Ключи: "max_health", "strength", "agility", "intellect".
const RACE_BASE_STATS := {
	Race.HUMAN:     { "max_health": 100, "strength": 10, "agility": 10, "intellect": 10 },
	Race.BARBARIAN: { "max_health": 150, "strength": 14, "agility":  8, "intellect":  5 },
	Race.ELF:       { "max_health":  80, "strength":  7, "agility": 15, "intellect": 10 },
	Race.DEMON:     { "max_health": 100, "strength": 13, "agility": 12, "intellect":  7 },
	Race.ANGEL:     { "max_health":  90, "strength":  8, "agility": 10, "intellect": 15 },
}

## Прибавка к max_health за каждый уровень.
## Согласно дизайну (CLAUDE.md) уровень даёт только слот эссенции;
## небольшой прирост HP — единственный пассивный рост характеристик.
const RACE_LEVEL_HP_BONUS := {
	Race.HUMAN:     5,
	Race.BARBARIAN: 10,
	Race.ELF:       3,
	Race.DEMON:     5,
	Race.ANGEL:     4,
}

## Возвращает стартовые статы для [param race].
func get_race_base_stats(race: Race) -> Dictionary:
	return RACE_BASE_STATS.get(race, RACE_BASE_STATS[Race.HUMAN])

## Возвращает бонус за один уровень для [param race].
## Содержит только ключ "max_health".
func get_race_level_bonus(race: Race) -> Dictionary:
	return { "max_health": RACE_LEVEL_HP_BONUS.get(race, 5) }

## Добавляет [param amount] золота и испускает сигнал.
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

## Тратит [param amount] золота. Возвращает [code]false[/code] если золота не хватает.
func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

## Возвращает отображаемое имя расы на русском языке.
func get_race_name(race: Race) -> String:
	match race:
		Race.HUMAN:     return "Человек"
		Race.BARBARIAN: return "Варвар"
		Race.ELF:       return "Эльф"
		Race.DEMON:     return "Демон"
		Race.ANGEL:     return "Ангел"
	return ""
