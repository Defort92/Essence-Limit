extends Node

var current_xp: int = 0
var current_level: int = 1

# Отслеживание первых убийств: mob_type_id → true
# Сбрасывается только при создании нового персонажа, НЕ при каждом забеге
var killed_mob_types: Dictionary = {}

# Отслеживание убийств боссов за текущий забег: floor_id → true
var bosses_killed_this_run: Dictionary = {}

signal xp_gained(amount: int, total: int)
signal level_up(new_level: int)

func try_award_kill_xp(mob_type_id: String, xp_reward: int) -> void:
	if killed_mob_types.has(mob_type_id):
		return
	killed_mob_types[mob_type_id] = true
	_add_xp(xp_reward)

func award_achievement_xp(xp_reward: int) -> void:
	_add_xp(xp_reward)

func try_award_boss_kill_xp(floor_id: int, xp_reward: int) -> void:
	if bosses_killed_this_run.has(floor_id):
		return
	bosses_killed_this_run[floor_id] = true
	_add_xp(xp_reward)

func on_run_started() -> void:
	bosses_killed_this_run.clear()

func _add_xp(amount: int) -> void:
	current_xp += amount
	xp_gained.emit(amount, current_xp)
	_check_level_up()

func _check_level_up() -> void:
	var xp_needed = _xp_for_level(current_level + 1)
	while current_xp >= xp_needed:
		current_level += 1
		EssenceSystem.resize_to_level(current_level)
		level_up.emit(current_level)
		xp_needed = _xp_for_level(current_level + 1)

func _xp_for_level(level: int) -> int:
	# Простая формула, можно заменить таблицей
	return level * level * 100
