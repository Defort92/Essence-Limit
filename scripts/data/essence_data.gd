extends Resource
class_name EssenceData

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

# Фиксированные бонусы к характеристикам
@export var stat_bonuses: Dictionary = {
	# "max_health": 0, "strength": 0, "agility": 0, "intellect": 0
}

# Активная способность (ссылка на скрипт или PackedScene)
@export var ability_scene: PackedScene

# Цена удаления в городе
@export var removal_cost: int = 100
