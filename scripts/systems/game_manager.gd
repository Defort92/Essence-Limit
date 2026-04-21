extends Node

enum Race { HUMAN, BARBARIAN, ELF, DEMON, ANGEL }

var player_race: Race = Race.HUMAN
var player_name: String = ""
var gold: int = 0

signal gold_changed(new_amount: int)

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

func get_race_name(race: Race) -> String:
	match race:
		Race.HUMAN: return "Человек"
		Race.BARBARIAN: return "Варвар"
		Race.ELF: return "Эльф"
		Race.DEMON: return "Демон"
		Race.ANGEL: return "Ангел"
	return ""
