## Конфигурация одного достижения. Создавать как .tres в resources/achievements/.
extends Resource
class_name AchievementData

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var xp_reward: int = 0
## Постоянные бонусы к статам, начисляемые при выполнении.
## Ключи: "strength", "agility", "intellect", "max_health".
@export var stat_rewards: Dictionary = {}
