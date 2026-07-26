## Сохранение и загрузка игры в JSON-файлы (user://saves/slot_N.json).
## Поддерживает до MAX_SLOTS независимых слотов сохранения.
## Является Autoload-синглтоном; регистрировать как "SaveSystem" в Project Settings.
extends Node


signal game_saved(slot: int)
signal game_loaded(slot: int)

## Сохраняет текущее состояние игры в слот [param slot].
func save(slot: int) -> void:
	assert(slot >= 0 and slot < SaveSystemConstants.MAX_SLOTS, "Неверный номер слота сохранения")
	DirAccess.make_dir_recursive_absolute(SaveSystemConstants.SAVE_DIR)

	var save_data := {
		"version": 2,
		"player": {
			"race": int(GameManager.player_race),
			"player_name": GameManager.player_name,
			"gold": GameManager.gold,
		},
		"xp": {
			"current_xp": XPSystem.current_xp,
			"current_level": XPSystem.current_level,
			"killed_mob_types": XPSystem.killed_mob_types.duplicate(),
		},
		# Весь отряд: у каждого участника своя экипировка, эссенции, рюкзак (и золото в нём), HP, доверие.
		"party": PartySystem.serialize(),
		"stash": StashSystem.serialize(),
		"racial_passives": RacialPassiveSystem.serialize(),
		"achievements": AchievementSystem.serialize(),
	}

	var file := FileAccess.open(SaveSystemConstants.SAVE_DIR + "slot_%d.json" % slot, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		game_saved.emit(slot)

## Загружает сохранение из слота [param slot].
## Возвращает [code]false[/code] если слот пуст или файл повреждён.
func load_game(slot: int) -> bool:
	assert(slot >= 0 and slot < SaveSystemConstants.MAX_SLOTS, "Неверный номер слота сохранения")
	var file_path := SaveSystemConstants.SAVE_DIR + "slot_%d.json" % slot
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
	return FileAccess.file_exists(SaveSystemConstants.SAVE_DIR + "slot_%d.json" % slot)

## Удаляет файл сохранения из слота [param slot].
func delete_save(slot: int) -> void:
	var file_path := SaveSystemConstants.SAVE_DIR + "slot_%d.json" % slot
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)

## Возвращает краткую информацию о сохранении для превью экрана выбора слотов.
## Ключи: player_name, race, level, gold. Пустой словарь если слот пуст.
func get_save_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(SaveSystemConstants.SAVE_DIR + "slot_%d.json" % slot, FileAccess.READ)
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
	# Золото больше не отдельное поле — оно хранится как предмет в рюкзаке каждого
	# участника и восстанавливается вместе с ним через PartySystem.deserialize() ниже.

	var xp_data: Dictionary = save_data.get("xp", {})
	XPSystem.current_xp = xp_data.get("current_xp", 0)
	XPSystem.current_level = xp_data.get("current_level", 1)
	XPSystem.killed_mob_types = xp_data.get("killed_mob_types", {})

	StashSystem.deserialize(save_data.get("stash", []))
	RacialPassiveSystem.deserialize(save_data.get("racial_passives", []))
	AchievementSystem.deserialize(save_data.get("achievements", {}))

	# Пересчитать уровень на случай несогласованных данных в сохранении.
	XPSystem._check_level_up()

	# Состав отряда (HP, доверие, экипировка, эссенции каждого участника) восстанавливается
	# в PartySystem.roster; живые Player-узлы применят его через _init_from_roster()
	# при регистрации в следующей сцене. Загружать нужно ДО смены сцены.
	PartySystem.deserialize(save_data.get("party", {}))
