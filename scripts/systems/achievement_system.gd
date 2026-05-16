## Управляет достижениями: разблокировка, начисление наград, сериализация.
## Награды (XP + постоянные статы) применяются один раз при первой разблокировке.
## Является Autoload-синглтоном; регистрировать как "AchievementSystem" в Project Settings.
extends Node

## Словарь achievement_id → true для быстрой O(1) проверки.
var _unlocked: Dictionary = {}

signal achievement_unlocked(achievement: AchievementData)

## Пытается разблокировать [param achievement].
## Возвращает [code]false[/code] если оно уже выполнено.
func try_unlock(achievement: AchievementData) -> bool:
	if is_unlocked(achievement.id):
		return false

	_unlocked[achievement.id] = true

	if achievement.xp_reward > 0:
		XPSystem.award_achievement_xp(achievement.xp_reward)

	if not achievement.stat_rewards.is_empty():
		_apply_stat_rewards(achievement.stat_rewards)

	achievement_unlocked.emit(achievement)
	return true

## Возвращает [code]true[/code] если достижение уже разблокировано.
func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)

## Сбрасывает все достижения — вызывать при создании нового персонажа.
func clear() -> void:
	_unlocked.clear()

func serialize() -> Dictionary:
	return _unlocked.duplicate()

func deserialize(data: Dictionary) -> void:
	_unlocked = data.duplicate()

func _apply_stat_rewards(stat_rewards: Dictionary) -> void:
	var player := _find_player()
	if player == null:
		push_warning("AchievementSystem: Player не найден, статы за достижение не применены")
		return
	for stat_name in stat_rewards:
		var mod := StatModifier.new()
		mod.stat = stat_name
		mod.op = StatModifier.Op.ADD
		mod.value = float(stat_rewards[stat_name])
		mod.source_id = "achievement"
		player.apply_modifier(mod)

func _find_player() -> Player:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree:
		return scene_tree.get_first_node_in_group("player") as Player
	return null
