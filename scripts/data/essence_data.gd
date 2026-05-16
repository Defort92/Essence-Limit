## Эссенция — вставляется в слот персонажа, даёт пассивные статы и активную способность.
## Слотов у персонажа ровно столько, сколько его уровень (+ расовые бонусы для Демонов/Ангелов).
## Удалить эссенцию можно только в городе за removal_cost золота.
extends ItemData
class_name EssenceData

## Ключи — названия статов: "strength", "agility", "intellect", "max_health".
@export var stat_bonuses: Dictionary = {}
@export var ability_scene: PackedScene
@export var removal_cost: int = 100
