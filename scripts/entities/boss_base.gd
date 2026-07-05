## Базовый класс для боссов этажей. Расширяет Enemy системой фаз.
## При достижении порогового % HP автоматически переходит в следующую фазу.
## Переопределяй [method _on_phase_changed] для смены паттернов атак и поведения.
extends Enemy
class_name BossBase

## Пороги HP (0.0–1.0) для смены фаз, в порядке убывания.
## Пример: [0.7, 0.4, 0.1] → 4 фазы, переходы при 70%, 40%, 10% HP.
@export var phase_thresholds: Array[float] = [0.7, 0.4]

var current_phase: int = 0

signal phase_changed(new_phase: int)

func take_damage(amount: int, is_crit: bool = false) -> void:
	super.take_damage(amount, is_crit)
	_check_phase_transition()

func _check_phase_transition() -> void:
	if current_phase >= phase_thresholds.size():
		return
	var hp_percent := float(health) / float(get_stat_int("max_health"))
	if hp_percent <= phase_thresholds[current_phase]:
		current_phase += 1
		_on_phase_changed(current_phase)
		phase_changed.emit(current_phase)

## Переопределяй для смены поведения при входе в фазу [param new_phase] (начиная с 1).
## Типичное применение: apply_modifier() для усиления статов, смена паттерна атаки.
func _on_phase_changed(new_phase: int) -> void:
	pass
