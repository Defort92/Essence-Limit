## Система опыта и уровней. Уровень общий на весь отряд (первое убийство типа моба
## засчитывается всем), но слот эссенции открывается у каждого участника отдельно.
## XP начисляется только за первое убийство каждого типа моба (killed_mob_types).
## Уровень открывает новый слот эссенции через essence.resize_to_level() каждого участника.
## Является Autoload-синглтоном; регистрировать как "XPSystem" в Project Settings.
extends Node

const MAX_LEVEL := 100
const MIN_LEVEL := 1

var current_xp: int = 0
var current_level: int = 1

## Словарь mob_type_id → true. Хранится на всё время жизни персонажа.
var killed_mob_types: Dictionary = {}
## Словарь floor_id → true. Сбрасывается при каждом новом забеге.
var bosses_killed_this_run: Dictionary = {}

signal xp_gained(amount: int, total: int)
signal level_up(new_level: int)
signal level_down(new_level: int)

## Начисляет XP за убийство моба [param mob_type_id], если этот тип ещё не был убит.
func try_award_kill_xp(mob_type_id: String, xp_reward: int) -> void:
	if killed_mob_types.has(mob_type_id):
		return
	killed_mob_types[mob_type_id] = true
	_add_xp(xp_reward)

## Начисляет XP за достижение без проверки дублей.
func award_achievement_xp(xp_reward: int) -> void:
	_add_xp(xp_reward)

## Начисляет XP за убийство босса на этаже [param floor_id], максимум один раз за забег.
func try_award_boss_kill_xp(floor_id: int, xp_reward: int) -> void:
	if bosses_killed_this_run.has(floor_id):
		return
	bosses_killed_this_run[floor_id] = true
	_add_xp(xp_reward)

## Временно снижает уровень на [param amount] (способность монстра, аура этажа).
## Сохраняет XP нетронутым — при снятии эффекта уровень восстанавливается через restore_level().
## Слоты эссенций блокируются, но не уничтожаются.
func reduce_level(amount: int) -> void:
	var new_level: int = max(MIN_LEVEL, current_level - amount)
	if new_level == current_level:
		return
	current_level = new_level
	_resize_all_essences()
	level_down.emit(current_level)

## Восстанавливает уровень после временного снижения.
## Пересчитывает фактический уровень по накопленному XP — никаких дублей слотов не будет,
## потому что essence.resize_to_level не создаёт лишних слотов если они уже есть.
func restore_level() -> void:
	var correct_level := _calculate_level_from_xp()
	if correct_level == current_level:
		return
	current_level = correct_level
	_resize_all_essences()
	level_up.emit(current_level)

## Сбрасывает счётчик убийств боссов. Вызывать при каждом открытии портала.
func on_run_started() -> void:
	bosses_killed_this_run.clear()

## Возвращает количество XP, недостающих до следующего уровня.
func xp_to_next_level() -> int:
	if current_level >= MAX_LEVEL:
		return 0
	return _xp_for_level(current_level + 1) - current_xp

func _add_xp(amount: int) -> void:
	if current_level >= MAX_LEVEL:
		return
	current_xp += amount
	xp_gained.emit(amount, current_xp)
	_check_level_up()

func _check_level_up() -> void:
	while current_level < MAX_LEVEL and current_xp >= _xp_for_level(current_level + 1):
		current_level += 1
		_resize_all_essences()
		level_up.emit(current_level)

## Применяет текущий уровень к слотам эссенций каждого участника отряда — у каждого
## своя essence-компонента, общего EssenceSystem больше нет.
func _resize_all_essences() -> void:
	for member in PartySystem.members:
		member.essence.resize_to_level(current_level)

## Вычисляет фактический уровень по накопленному XP без изменения состояния.
func _calculate_level_from_xp() -> int:
	var level := MIN_LEVEL
	while level < MAX_LEVEL and current_xp >= _xp_for_level(level + 1):
		level += 1
	return level

func _xp_for_level(level: int) -> int:
	return level * level * 100
