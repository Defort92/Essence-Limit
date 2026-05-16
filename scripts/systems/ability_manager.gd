## Управляет активными способностями игрока, полученными через эссенции.
## Слушает EssenceSystem.essence_equipped/removed и автоматически спавнит/удаляет AbilityBase-узлы.
## Input Actions ability_1..ability_4 биндятся на первые 4 слота эссенций.
## Является Autoload-синглтоном; регистрировать как "AbilityManager" в Project Settings.
extends Node

## Маппинг Input Action → индекс слота эссенции.
## Добавь ability_1..ability_4 в Project Settings → Input Map (клавиши Q/E/R/F).
const DEFAULT_BINDINGS: Dictionary = {
	"ability_1": 0,
	"ability_2": 1,
	"ability_3": 2,
	"ability_4": 3,
}

var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()

## Словарь: slot_index (int) → AbilityBase.
var _active_abilities: Dictionary = {}

signal ability_added(slot_index: int, ability: AbilityBase)
signal ability_removed(slot_index: int)
signal ability_activated(slot_index: int)

func _ready() -> void:
	EssenceSystem.essence_equipped.connect(_on_essence_equipped)
	EssenceSystem.essence_removed.connect(_on_essence_removed)

func _unhandled_input(event: InputEvent) -> void:
	for action in bindings:
		if event.is_action_just_pressed(action):
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

## Перестраивает все способности из текущего состояния EssenceSystem.slots.
## Вызывается SaveSystem после загрузки сохранения.
func rebuild_from_slots() -> void:
	_clear_all()
	for idx in EssenceSystem.slots.size():
		var essence: EssenceData = EssenceSystem.slots[idx]
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
	var player := _find_player()
	if player == null:
		# Player ещё не в дереве — отложить до следующего кадра.
		call_deferred("_spawn_ability", slot_index, essence)
		return

	var ability := essence.ability_scene.instantiate() as AbilityBase
	if ability == null:
		push_error("AbilityManager: сцена '%s' не содержит AbilityBase" % essence.ability_scene.resource_path)
		return

	ability.caster = player
	player.add_child(ability)
	_active_abilities[slot_index] = ability
	ability_added.emit(slot_index, ability)

func _clear_all() -> void:
	for ability in _active_abilities.values():
		if is_instance_valid(ability):
			ability.queue_free()
	_active_abilities.clear()

func _find_player() -> Player:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree:
		return scene_tree.get_first_node_in_group("player") as Player
	return null
