## Управляет достижениями: разблокировка, начисление наград, сериализация.
## Накопленные статовые награды сохраняются и переприменяются при каждой загрузке —
## Player вызывает apply_accumulated_to_player(self) в _ready(), чтобы они никогда не терялись.
## Является Autoload-синглтоном; регистрировать как "AchievementSystem" в Project Settings.
extends Node

## Словарь achievement_id → true для быстрой O(1) проверки.
var _unlocked: Dictionary = {}

## Накопленная сумма всех статовых наград от выполненных достижений.
## Ключи — имена статов, значения — суммарный float-бонус.
## Сериализуется отдельно, чтобы при загрузке можно было переприменить без списка ресурсов.
var _accumulated_stat_rewards: Dictionary = {}

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
		_accumulate_rewards(achievement.stat_rewards)
		var player := _find_player()
		if player:
			apply_accumulated_to_player(player)

	achievement_unlocked.emit(achievement)
	return true

## Возвращает [code]true[/code] если достижение уже разблокировано.
func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)

## Применяет накопленные статовые награды к [param player].
## Сначала снимает старые (source "achievement_rewards"), затем применяет актуальные.
## Вызывать из Player._ready() при каждом входе в сцену — это гарантирует персистентность.
func apply_accumulated_to_player(player: Node) -> void:
	if not player.has_method("apply_modifier") or not player.has_method("remove_modifiers_by_source"):
		return
	player.remove_modifiers_by_source("achievement_rewards")
	for stat_name in _accumulated_stat_rewards:
		var total: float = _accumulated_stat_rewards[stat_name]
		if total == 0.0:
			continue
		var mod := StatModifier.new()
		mod.stat = stat_name
		mod.op = StatModifier.Op.ADD
		mod.value = total
		mod.source_id = "achievement_rewards"
		player.apply_modifier(mod)

## Сбрасывает все достижения и накопленные награды — вызывать при создании нового персонажа.
func clear() -> void:
	_unlocked.clear()
	_accumulated_stat_rewards.clear()

func serialize() -> Dictionary:
	return {
		"unlocked": _unlocked.duplicate(),
		"accumulated_stats": _accumulated_stat_rewards.duplicate(),
	}

func deserialize(data: Dictionary) -> void:
	_unlocked = data.get("unlocked", {}).duplicate()
	_accumulated_stat_rewards = data.get("accumulated_stats", {}).duplicate()

func _accumulate_rewards(stat_rewards: Dictionary) -> void:
	for stat_name in stat_rewards:
		var current: float = _accumulated_stat_rewards.get(stat_name, 0.0)
		_accumulated_stat_rewards[stat_name] = current + float(stat_rewards[stat_name])

func _find_player() -> Node:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree:
		return scene_tree.get_first_node_in_group("player")
	return null
