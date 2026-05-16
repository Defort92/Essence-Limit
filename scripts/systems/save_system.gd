## Сохранение и загрузка игры в JSON-файлы (user://saves/slot_N.json).
## Поддерживает до MAX_SLOTS независимых слотов сохранения.
## Является Autoload-синглтоном; регистрировать как "SaveSystem" в Project Settings.
extends Node

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 3

signal game_saved(slot: int)
signal game_loaded(slot: int)

## Сохраняет текущее состояние игры в слот [param slot].
func save(slot: int) -> void:
	assert(slot >= 0 and slot < MAX_SLOTS, "Неверный номер слота сохранения")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var save_data := {
		"version": 1,
		"player": {
			"race": int(GameManager.player_race),
			"player_name": GameManager.player_name,
			"gold": GameManager.gold,
			"health": _get_player_health(),
		},
		"xp": {
			"current_xp": XPSystem.current_xp,
			"current_level": XPSystem.current_level,
			"killed_mob_types": XPSystem.killed_mob_types.duplicate(),
		},
		"essence_bonus_slots": EssenceSystem.bonus_slots,
		"essences": _serialize_essences(),
		"inventory": InventorySystem.serialize(),
		"stash": StashSystem.serialize(),
		"equipment": EquipmentManager.serialize(),
	}

	var file := FileAccess.open(SAVE_DIR + "slot_%d.json" % slot, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		game_saved.emit(slot)

## Загружает сохранение из слота [param slot].
## Возвращает [code]false[/code] если слот пуст или файл повреждён.
func load_game(slot: int) -> bool:
	assert(slot >= 0 and slot < MAX_SLOTS, "Неверный номер слота сохранения")
	var file_path := SAVE_DIR + "slot_%d.json" % slot
	if not FileAccess.file_exists(file_path):
		return false

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	var json_text := file.get_as_text()
	file.close()

	var save_data = JSON.parse_string(json_text)
	if save_data == null or not save_data is Dictionary:
		return false

	_apply_save(save_data)
	game_loaded.emit(slot)
	return true

## Возвращает [code]true[/code] если в слоте [param slot] есть сохранение.
func has_save(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_DIR + "slot_%d.json" % slot)

## Удаляет файл сохранения из слота [param slot].
func delete_save(slot: int) -> void:
	var file_path := SAVE_DIR + "slot_%d.json" % slot
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)

## Возвращает краткую информацию о сохранении для превью на экране выбора слота.
## Ключи: player_name, race, level, gold. Пустой словарь если слот пуст.
func get_save_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(SAVE_DIR + "slot_%d.json" % slot, FileAccess.READ)
	if not file:
		return {}
	var save_data = JSON.parse_string(file.get_as_text())
	file.close()
	if save_data == null:
		return {}
	var player_data: Dictionary = save_data.get("player", {})
	var xp_data: Dictionary = save_data.get("xp", {})
	return {
		"player_name": player_data.get("player_name", ""),
		"race": player_data.get("race", 0),
		"level": xp_data.get("current_level", 1),
		"gold": player_data.get("gold", 0),
	}

func _apply_save(save_data: Dictionary) -> void:
	var player_data: Dictionary = save_data.get("player", {})
	GameManager.player_race = player_data.get("race", 0) as GameManager.Race
	GameManager.player_name = player_data.get("player_name", "")
	GameManager.gold = player_data.get("gold", 0)
	GameManager.gold_changed.emit(GameManager.gold)

	var xp_data: Dictionary = save_data.get("xp", {})
	XPSystem.current_xp = xp_data.get("current_xp", 0)
	XPSystem.current_level = xp_data.get("current_level", 1)
	XPSystem.killed_mob_types = xp_data.get("killed_mob_types", {})

	EssenceSystem.bonus_slots = save_data.get("essence_bonus_slots", 0)
	EssenceSystem.resize_to_level(XPSystem.current_level)
	_deserialize_essences(save_data.get("essences", []))

	InventorySystem.deserialize(save_data.get("inventory", []))
	StashSystem.deserialize(save_data.get("stash", []))
	EquipmentManager.deserialize(save_data.get("equipment", {}))

	# Player._init_race_stats() читает это значение при старте, если оно > 0.
	GameManager.saved_health = player_data.get("health", -1)

func _get_player_health() -> int:
	var player := _find_player()
	if player and "health" in player:
		return player.health
	return -1

func _serialize_essences() -> Array:
	var result := []
	for essence in EssenceSystem.slots:
		result.append(essence.resource_path if essence else null)
	return result

func _deserialize_essences(data: Array) -> void:
	for idx in range(min(data.size(), EssenceSystem.slots.size())):
		var res_path = data[idx]
		if res_path and ResourceLoader.exists(res_path):
			EssenceSystem.slots[idx] = load(res_path) as EssenceData
		else:
			EssenceSystem.slots[idx] = null
	EssenceSystem.slots_changed.emit()

func _find_player() -> Node:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree:
		return scene_tree.get_first_node_in_group("player")
	return null
