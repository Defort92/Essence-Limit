## Добавляет стартовых союзников в отряд при входе в сцену — сразу, без найма и платы.
## Идемпотентен: союзник с уже занятым именем не добавляется повторно (roster переживает
## смену сцены и сохранения, а также найм у вербовщика). Размещать в сцене после Player:
## добавление отложено на конец кадра, чтобы герой успел зарегистрироваться в PartySystem.
extends Node
class_name PartyStarter

@export var companions: Array[CompanionData] = []

func _ready() -> void:
	call_deferred("_add_companions")

func _add_companions() -> void:
	for data in companions:
		if data == null or PartySystem.has_member_named(data.display_name):
			continue
		PartySystem.add_companion(data)
