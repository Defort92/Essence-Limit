## Персонаж игрока: движение, уклонение, HP, применение урона/лечения.
## Статы = база (от расы) + EquipmentManager + EssenceSystem.
## Добавляется в группу "player" чтобы другие системы могли найти его через get_first_node_in_group.
extends CharacterBody3D
class_name Player

const MOVE_SPEED: float = 5.0
const GRAVITY: float = -20.0
const DODGE_SPEED: float = 12.0
const DODGE_DURATION: float = 0.25

enum State { IDLE, MOVE, DODGE, ATTACK, DEAD }
var state: State = State.IDLE

var _dodge_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _last_move_dir: Vector3 = Vector3.BACK

## Базовые статы (без учёта снаряжения и эссенций).
## Инициализируются из RACE_BASE_STATS и растут при повышении уровня.
var max_health: int = 100
var health: int = 100
var base_strength: int = 10
var base_agility: int = 10
var base_intellect: int = 10

var is_in_town: bool = true

signal health_changed(current: int, maximum: int)
signal died()

func _ready() -> void:
	add_to_group("player")
	_init_race_stats()
	EssenceSystem.resize_to_level(XPSystem.current_level)
	DungeonPortal.portal_closed.connect(_on_portal_closed)
	XPSystem.level_up.connect(_on_level_up)
	EquipmentManager.equipment_changed.connect(_on_equipment_changed)

## Применяет [param amount] урона. Если HP доходит до 0 — переходит в State.DEAD и испускает died.
func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	if health == 0:
		state = State.DEAD
		died.emit()

## Восстанавливает [param amount] HP, не превышая max_health.
func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	health_changed.emit(health, max_health)

## Возвращает итоговое значение стата [param stat_name] с учётом снаряжения и эссенций.
func get_total_stat(stat_name: String) -> int:
	var total := 0
	match stat_name:
		"strength":   total += base_strength
		"agility":    total += base_agility
		"intellect":  total += base_intellect
		"max_health": total += max_health
	total += EquipmentManager.get_total_stat(stat_name)
	total += EssenceSystem.get_total_stat(stat_name)
	return total

func _physics_process(delta: float) -> void:
	match state:
		State.IDLE, State.MOVE:
			_handle_movement(delta)
			_handle_dodge_input()
		State.DODGE:
			_tick_dodge(delta)
		State.DEAD:
			pass

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	move_and_slide()

func _init_race_stats() -> void:
	var stats := GameManager.get_race_base_stats(GameManager.player_race)
	max_health     = stats.get("max_health", 100)
	base_strength  = stats.get("strength", 10)
	base_agility   = stats.get("agility", 10)
	base_intellect = stats.get("intellect", 10)

	# SaveSystem заранее записывает saved_health если это загрузка, иначе -1.
	health = GameManager.saved_health if GameManager.saved_health > 0 else max_health
	health = min(health, max_health)
	GameManager.saved_health = -1

	health_changed.emit(health, max_health)

func _on_level_up(new_level: int) -> void:
	var bonus := GameManager.get_race_level_bonus(GameManager.player_race)
	var hp_gain: int = bonus.get("max_health", 0)
	max_health += hp_gain
	# При повышении уровня HP растёт вместе с максимумом, но не сверх нового максимума.
	health = min(health + hp_gain, max_health)
	health_changed.emit(health, max_health)

func _on_equipment_changed() -> void:
	pass

func _handle_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input.x, 0.0, input.y)

	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		_last_move_dir = direction
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.z * MOVE_SPEED
		state = State.MOVE
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)
		state = State.IDLE

func _handle_dodge_input() -> void:
	if Input.is_action_just_pressed("dodge"):
		state = State.DODGE
		_dodge_timer = DODGE_DURATION
		_dodge_direction = _last_move_dir

func _tick_dodge(delta: float) -> void:
	_dodge_timer -= delta
	velocity.x = _dodge_direction.x * DODGE_SPEED
	velocity.z = _dodge_direction.z * DODGE_SPEED
	if _dodge_timer <= 0.0:
		state = State.IDLE

func _on_portal_closed() -> void:
	is_in_town = true
