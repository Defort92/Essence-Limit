## Конфигурация врага — задаётся через .tres-ресурс и назначается на сцену Enemy.
extends Resource
class_name EnemyData

@export var mob_type_id: String = "unknown"
@export var display_name: String = "Враг"

@export_group("Combat")
@export var max_health: int = 50
@export var attack_damage: int = 8
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.5
## Снижает входящий урон от игрока. Итоговый урон: max(1, damage - defense).
@export var defense: int = 0
## Базовый шанс крита атак врага (0.0–1.0). Увеличивается модификаторами "crit_chance"
## и уязвимостью цели ("crit_vulnerability"). См. CombatMath.
@export var crit_chance: float = 0.05

@export_group("Movement")
@export var move_speed: float = 2.5
@export var detection_range: float = 10.0

@export_group("Gear")
## Фиксированное оружие врага: stat_bonuses ("damage", "range") добавляются к атаке.
## Враги не переодеваются — это статичная часть их статов, не EquipmentManager.
@export var equipped_weapon: EquipmentData
## Расходник самолечения (обычно зелье). null = враг не лечится.
@export var self_heal_consumable: ConsumableData
## Порог HP (доля 0.0–1.0), ниже которого враг использует self_heal_consumable.
@export var self_heal_threshold: float = 0.3
## Кулдаун самолечения в секундах (чтобы враг не спамил зелья каждый кадр).
@export var self_heal_cooldown: float = 8.0

## Статус-эффект (обычно недуг), накладываемый на цель при удачной атаке этого врага.
## null = обычная атака без статуса. См. Enemy._on_attack.
@export var attack_status: StatusEffectData

@export_group("Abilities")
## Сцены AbilityBase (те же, что у эссенций в EssenceData.ability_scene).
## Кастуются автоматически через EnemyAbilityController на сцене врага.
@export var ability_scenes: Array[PackedScene] = []

@export_group("Rewards")
@export var xp_reward: int = 50
@export var gold_drop_min: int = 0
@export var gold_drop_max: int = 5
## Если null — предметы не выпадают; золото всё равно начисляется через gold_drop_min/max.
@export var loot_table: LootTable

@export_group("Flags")
@export var is_unique: bool = false
## MONSTER враждебен PLAYER/ALLY. ALLY/HOSTILE_NPC — задел под будущих "проходимцев".
@export var faction: Faction.Kind = Faction.Kind.MONSTER

@export_group("Visual")
## Заглушка вместо уникального спрайта: базовый гуманоид перекрашивается в этот цвет.
## Заменить на свой набор текстур в сцене (Sprite3D → tex_*), когда появится арт монстра.
@export var sprite_tint: Color = Color.WHITE
