## Общая математика боя: расчёт шанса крита и применение критического множителя.
## Статические методы, вызываемые из Player/Enemy при атаке и лечении.
## Шанс крита складывается из бонусов АТАКУЮЩЕГО (get_attack_crit_chance) и
## ослаблений ЦЕЛИ (get_incoming_crit_bonus) — оба метода duck-typing, чтобы не
## завязываться на конкретный класс (Player, Enemy, будущие сущности).
class_name CombatMath

## Множитель урона/лечения при крите.
const CRIT_MULTIPLIER: float = 1.75
## Базовый шанс крита, если у атакующего нет метода get_attack_crit_chance.
const BASE_CRIT_CHANCE: float = 0.05
## Потолок итогового шанса крита (чтобы крит не стал гарантированным).
const MAX_CRIT_CHANCE: float = 0.95

## Итоговый шанс крита атакующего [param attacker] по цели [param target].
## Бонусы персонажа + уязвимость цели от наложенных ослаблений (дебаффов).
static func compute_crit_chance(attacker: Object, target: Object) -> float:
	var chance: float = BASE_CRIT_CHANCE
	if attacker != null and attacker.has_method("get_attack_crit_chance"):
		chance = attacker.get_attack_crit_chance()
	if target != null and target.has_method("get_incoming_crit_bonus"):
		chance += target.get_incoming_crit_bonus()
	return clampf(chance, 0.0, MAX_CRIT_CHANCE)

## Бросок на крит: true, если удар/лечение критическое.
static func roll_crit(attacker: Object, target: Object) -> bool:
	return randf() < compute_crit_chance(attacker, target)

## Применяет критический множитель к величине урона/лечения.
static func apply_crit(amount: int) -> int:
	return int(round(float(amount) * CRIT_MULTIPLIER))
