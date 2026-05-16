## Расходуемый предмет: зелья, свитки и т.п.
## Стакабелен по умолчанию (до 99 штук).
## BUFF-эффекты применяются как временный StatModifier и снимаются по истечении duration.
## Если duration == 0.0 — BUFF считается бессрочным до снятия вручную.
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
## HEAL_HP — абсолютное кол-во; HEAL_PERCENT — доля 0.0–1.0; BUFF_* — бонус к стату.
@export var effect_value: float = 0.0
## Длительность BUFF-эффекта в секундах. 0.0 = бессрочный.
@export var duration: float = 0.0

func _init() -> void:
	is_stackable = true
	max_stack = 99

## Применяет эффект расходника к [param target].
## HEAL — мгновенный; BUFF — через StatModifier (снимается через [member duration] сек.).
func apply(target: Node) -> void:
	match effect_type:
		EffectType.HEAL_HP:
			if target.has_method("heal"):
				target.heal(int(effect_value))
		EffectType.HEAL_PERCENT:
			if target.has_method("heal") and "max_health" in target:
				target.heal(int(target.max_health * effect_value))
		EffectType.BUFF_STRENGTH, EffectType.BUFF_AGILITY, EffectType.BUFF_INTELLECT:
			_apply_buff(target)

func _apply_buff(target: Node) -> void:
	if not target.has_method("apply_modifier"):
		return
	var stat_name := _buff_stat_name()
	if stat_name.is_empty():
		return
	var mod := StatModifier.new()
	mod.stat = stat_name
	mod.op = StatModifier.Op.ADD
	mod.value = effect_value
	# Уникальный source_id позволяет нескольким зельям одного типа стакаться независимо.
	mod.source_id = "consumable_%s_%d" % [id, Time.get_ticks_msec()]
	target.apply_modifier(mod)
	if duration > 0.0 and target.is_inside_tree():
		var source_id_copy := mod.source_id
		target.get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if is_instance_valid(target):
					target.remove_modifiers_by_source(source_id_copy)
		)

func _buff_stat_name() -> String:
	match effect_type:
		EffectType.BUFF_STRENGTH:  return "strength"
		EffectType.BUFF_AGILITY:   return "agility"
		EffectType.BUFF_INTELLECT: return "intellect"
	return ""
