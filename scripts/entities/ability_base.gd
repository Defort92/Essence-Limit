## Базовый класс для активной способности, получаемой через эссенцию.
## Добавляется как дочерний узел к владельцу: к Player — через AbilityManager,
## к Enemy — через EnemyAbilityController. Наследуй, переопределяй [method activate].
extends Node
class_name AbilityBase

@export var ability_name: String = ""
@export var description: String = ""
@export var cooldown_duration: float = 5.0

## Владелец способности: Player или Enemy. У обоих есть faction, heal(),
## apply_timed_modifier() — при таргетинге фильтруй цели через Faction.is_hostile().
var caster: CharacterBody3D = null
var current_cooldown: float = 0.0

signal activated(ability: AbilityBase)
signal cooldown_finished(ability: AbilityBase)

func _process(delta: float) -> void:
	if current_cooldown > 0.0:
		current_cooldown -= delta
		if current_cooldown <= 0.0:
			current_cooldown = 0.0
			cooldown_finished.emit(self)

## Пытается активировать способность.
## Возвращает [code]false[/code] если способность ещё на кулдауне.
func try_activate() -> bool:
	if current_cooldown > 0.0:
		return false
	current_cooldown = cooldown_duration
	activate()
	activated.emit(self)
	return true

## Возвращает прогресс кулдауна: 0.0 = готова, 1.0 = только что использована.
func get_cooldown_progress() -> float:
	if cooldown_duration <= 0.0:
		return 0.0
	return current_cooldown / cooldown_duration

## Реализуй эффект способности в подклассе. Вызывается автоматически через try_activate().
func activate() -> void:
	pass
