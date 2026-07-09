## Глобальное состояние персонажа: раса, имя, золото, базовые статы по расам.
## Содержит new_game() — единственную точку сброса всех систем при старте новой игры.
## Является Autoload-синглтоном; регистрировать как "GameManager" в Project Settings.
extends Node

enum Race { HUMAN, BARBARIAN, ELF, DEMON, ANGEL }

## Золото — обычный (стакающийся) предмет в личном рюкзаке персонажа, а не общий счётчик:
## у каждого участника отряда своя пачка золота-предмета в InventoryComponent.
## GameManager.gold — сумма по всему отряду, только для отображения (лавка, HUD этажа).
const GOLD_ITEM: ItemData = preload("res://resources/items/gold.tres")

var player_race: Race = Race.HUMAN
var player_name: String = ""

## Сумма золота-предмета по рюкзакам всех живых участников отряда.
var gold: int:
	get:
		return _total_gold()

signal gold_changed(new_amount: int)
signal new_game_started(race: Race, player_name: String)
signal player_died()

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

## Сбрасывает все игровые системы и запускает новую игру с выбранной расой и именем.
## Вызывать из экрана создания персонажа перед сменой сцены.
func new_game(race: Race, name: String) -> void:
	player_race = race
	player_name = name
	gold_changed.emit(gold)

	XPSystem.current_xp = 0
	XPSystem.current_level = 1
	XPSystem.killed_mob_types.clear()
	XPSystem.bosses_killed_this_run.clear()

	# Состав отряда (включая экипировку/эссенции/рюкзак каждого участника) живёт в
	# PartySystem.roster. Запись героя (и её пустой рюкзак) создастся заново при регистрации
	# первого Player в новой сцене — отдельно очищать инвентарь не нужно.
	PartySystem.reset()

	StashSystem.clear()
	RacialPassiveSystem.clear()
	AchievementSystem.clear()

	new_game_started.emit(race, name)

## Обрабатывает вайп отряда: закрывает портал, испускает сигнал и открывает экран смерти.
## Вызывается PartySystem, когда погибли все участники. HP восстановится через roster:
## павшие получают health = -1 (полное HP) при выходе из сцены.
func on_player_died() -> void:
	DungeonPortal.close_portal()
	player_died.emit()
	SceneManager.go_to_death_screen()

## Возвращает стартовые статы для [param race].
func get_race_base_stats(race: Race) -> Dictionary:
	return RACE_BASE_STATS.get(race, RACE_BASE_STATS[Race.HUMAN])

## Возвращает бонус HP за один уровень для [param race].
func get_race_level_bonus(race: Race) -> Dictionary:
	return { "max_health": RACE_LEVEL_HP_BONUS.get(race, 5) }

## Добавляет [param amount] золота в рюкзак активного участника отряда и испускает сигнал.
func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	var inv := PartySystem.get_active_inventory()
	if inv == null:
		push_warning("GameManager.add_gold: нет активного участника отряда, золото потеряно")
		return
	inv.add_item(GOLD_ITEM, amount)
	gold_changed.emit(gold)

## Тратит [param amount] золота. Списывается сперва у активного персонажа, затем —
## у остальных участников отряда (первый попавшийся с ненулевым запасом).
## Возвращает [code]false[/code] если суммарно золота на отряд не хватает — тогда
## ничего не списывается.
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if _total_gold() < amount:
		return false
	var remaining := amount
	for member in _spend_order():
		if remaining <= 0:
			break
		var have := member.inventory.get_item_count(GOLD_ITEM.id)
		if have <= 0:
			continue
		var take: int = min(have, remaining)
		member.inventory.remove_item(GOLD_ITEM.id, take)
		remaining -= take
	gold_changed.emit(gold)
	return true

func _total_gold() -> int:
	var total := 0
	for member in PartySystem.members:
		if is_instance_valid(member):
			total += member.inventory.get_item_count(GOLD_ITEM.id)
	return total

## Порядок списания золота: активный участник первым, затем остальные живые участники.
func _spend_order() -> Array[Player]:
	var order: Array[Player] = []
	var active := PartySystem.get_active_member()
	if active != null:
		order.append(active)
	for member in PartySystem.members:
		if member != active and is_instance_valid(member):
			order.append(member)
	return order

## Возвращает отображаемое имя расы на русском языке.
func get_race_name(race: Race) -> String:
	match race:
		Race.HUMAN:     return "Человек"
		Race.BARBARIAN: return "Варвар"
		Race.ELF:       return "Эльф"
		Race.DEMON:     return "Демон"
		Race.ANGEL:     return "Ангел"
	return ""
