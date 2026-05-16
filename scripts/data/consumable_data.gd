## Расходуемый предмет: зелья, свитки и т.п.
## Стакабелен по умолчанию (до 99 штук).
extends ItemData
class_name ConsumableData

enum EffectType {
	HEAL_HP,
	HEAL_PERCENT,
	BUFF_STRENGTH,
	BUFF_AGILITY,
	BUFF_INTELLECT,
}

@export var effect_type: EffectType = EffectType.HEAL_HP
## Для HEAL_HP — абсолютное значение; для HEAL_PERCENT — доля (0.0–1.0); для BUFF_* — целое число.
@export var effect_value: float = 0.0

func _init() -> void:
	is_stackable = true
	max_stack = 99

## Применяет эффект к [param target]. Целевой узел должен содержать нужные поля и методы.
func apply(target: Node) -> void:
	match effect_type:
		EffectType.HEAL_HP:
			if target.has_method("heal"):
				target.heal(int(effect_value))
		EffectType.HEAL_PERCENT:
			if target.has_method("heal") and "max_health" in target:
				target.heal(int(target.max_health * effect_value))
		EffectType.BUFF_STRENGTH:
			if "base_strength" in target:
				target.base_strength += int(effect_value)
		EffectType.BUFF_AGILITY:
			if "base_agility" in target:
				target.base_agility += int(effect_value)
		EffectType.BUFF_INTELLECT:
			if "base_intellect" in target:
				target.base_intellect += int(effect_value)
