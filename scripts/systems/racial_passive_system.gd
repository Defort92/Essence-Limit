## Хранит расовые пассивки, разблокированные персонажем через взаимодействие с расовыми NPC.
## Примеры пассивок: "barbarian_tattoo_1", "elf_spirit_bond", "demon_soul_rite_1".
## Является Autoload-синглтоном; регистрировать как "RacialPassiveSystem" в Project Settings.
extends Node

var _unlocked: Array[String] = []

signal passive_unlocked(passive_id: String)

## Разблокирует пассивку [param passive_id] если она ещё не получена.
func unlock_passive(passive_id: String) -> void:
	if has_passive(passive_id):
		return
	_unlocked.append(passive_id)
	passive_unlocked.emit(passive_id)

## Возвращает [code]true[/code] если пассивка уже разблокирована.
func has_passive(passive_id: String) -> bool:
	return passive_id in _unlocked

## Возвращает копию списка всех разблокированных пассивок.
func get_unlocked() -> Array[String]:
	return _unlocked.duplicate()

## Сбрасывает все пассивки — вызывать при создании нового персонажа.
func clear() -> void:
	_unlocked.clear()

func serialize() -> Array:
	return _unlocked.duplicate()

func deserialize(data: Array) -> void:
	_unlocked = data.duplicate()
