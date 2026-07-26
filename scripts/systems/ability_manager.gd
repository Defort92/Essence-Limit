## Управляет активными способностями участника отряда, полученными через эссенции.
## Слушает Essence.essence_equipped/removed своего владельца и автоматически спавнит/удаляет
## AbilityBase-узлы. Input Actions ability_1..ability_4 реагируют только если владелец сейчас
## под управлением игрока (control_mode == HUMAN) — у ИИ-союзников свой способ вызова способностей.
## Компонент на каждого участника отряда — дочерний узел "Abilities" в player.tscn.
extends Node
class_name AbilityManager


var bindings: Dictionary = AbilityManagerConstants.DEFAULT_BINDINGS.duplicate()

## Словарь: slot_index (int) → AbilityBase.
var _active_abilities: Dictionary = {}

## Владелец-персонаж (родительский узел в player.tscn) и его слоты эссенций.
@onready var _owner_player: Player = get_parent() as Player
@onready var _essence: EssenceSystem = get_parent().get_node("Essence") as EssenceSystem

signal ability_added(slot_index: int, ability: AbilityBase)
signal ability_removed(slot_index: int)
signal ability_activated(slot_index: int)

func _ready() -> void:
	_essence.essence_equipped.connect(_on_essence_equipped)
	_essence.essence_removed.connect(_on_essence_removed)

func _unhandled_input(event: InputEvent) -> void:
	if _owner_player.control_mode != Player.ControlMode.HUMAN:
		return
	for action in bindings:
		if event.is_action_pressed(action):
			activate_ability(bindings[action])

## Активирует способность в слоте [param slot_index].
## Возвращает [code]false[/code] если слот пуст или способность на кулдауне.
func activate_ability(slot_index: int) -> bool:
	if not _active_abilities.has(slot_index):
		return false
	var result: bool = _active_abilities[slot_index].try_activate()
	if result:
		ability_activated.emit(slot_index)
	return result

## Возвращает экземпляр способности в слоте, или [code]null[/code] если слот пуст.
func get_ability(slot_index: int) -> AbilityBase:
	return _active_abilities.get(slot_index, null)

## Возвращает словарь всех активных способностей (копию).
func get_all_abilities() -> Dictionary:
	return _active_abilities.duplicate()

## Перестраивает все способности из текущего состояния слотов эссенций владельца.
## Вызывается SaveSystem после загрузки сохранения.
func rebuild_from_slots() -> void:
	_clear_all()
	for idx in _essence.slots.size():
		var essence: EssenceData = _essence.slots[idx]
		if essence != null and essence.ability_scene != null:
			_spawn_ability(idx, essence)

## Удаляет все активные способности без сигналов.
func clear() -> void:
	_clear_all()

func _on_essence_equipped(slot_index: int, essence: EssenceData) -> void:
	if essence.ability_scene == null:
		return
	_spawn_ability(slot_index, essence)

func _on_essence_removed(slot_index: int) -> void:
	if not _active_abilities.has(slot_index):
		return
	_active_abilities[slot_index].queue_free()
	_active_abilities.erase(slot_index)
	ability_removed.emit(slot_index)

func _spawn_ability(slot_index: int, essence: EssenceData) -> void:
	var ability := essence.ability_scene.instantiate() as AbilityBase
	if ability == null:
		push_error("AbilityManager: сцена '%s' не содержит AbilityBase" % essence.ability_scene.resource_path)
		return

	ability.caster = _owner_player
	_owner_player.add_child(ability)
	_active_abilities[slot_index] = ability
	ability_added.emit(slot_index, ability)

func _clear_all() -> void:
	for ability in _active_abilities.values():
		if is_instance_valid(ability):
			ability.queue_free()
	_active_abilities.clear()
