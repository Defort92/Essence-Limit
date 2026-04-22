extends Resource
class_name EnemyData

@export var mob_type_id: String = "unknown"
@export var display_name: String = "Враг"

@export_group("Combat")
@export var max_health: int = 50
@export var attack_damage: int = 8
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.5

@export_group("Movement")
@export var move_speed: float = 2.5
@export var detection_range: float = 10.0

@export_group("Rewards")
@export var xp_reward: int = 50
@export var gold_drop_min: int = 0
@export var gold_drop_max: int = 5

@export_group("Flags")
@export var is_unique: bool = false
