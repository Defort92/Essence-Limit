## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name CombatMathConstants
extends RefCounted

## Множитель урона/лечения при крите.
const CRIT_MULTIPLIER: float = 1.75

## Базовый шанс крита, если у атакующего нет метода get_attack_crit_chance.
const BASE_CRIT_CHANCE: float = 0.05

## Потолок итогового шанса крита (чтобы крит не стал гарантированным).
const MAX_CRIT_CHANCE: float = 0.95
