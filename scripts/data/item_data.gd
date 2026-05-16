## Базовый класс для всех предметов в игре.
## EquipmentData, EssenceData и ConsumableData наследуют от него.
extends Resource
class_name ItemData

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var rarity: Rarity = Rarity.COMMON
@export var buy_price: int = 0
@export var sell_price: int = 0
@export var is_stackable: bool = false
@export var max_stack: int = 1
