extends CharacterBody3D
class_name Enemy

@export var mob_type_id: String = "unknown"
@export var max_health: int = 50
@export var move_speed: float = 2.5
@export var attack_damage: int = 8
@export var attack_range: float = 1.5
@export var detection_range: float = 10.0
@export var xp_reward: int = 50
@export var is_unique: bool = false

var health: int = max_health

const GRAVITY: float = -20.0

enum State { IDLE, CHASE, ATTACK, DEAD }
var state: State = State.IDLE

var _player: Player = null
var _attack_cooldown: float = 0.0

signal died(enemy: Enemy)

func _ready() -> void:
	health = max_health
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	_attack_cooldown = max(0.0, _attack_cooldown - delta)

	match state:
		State.IDLE:
			_tick_idle()
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack()

	move_and_slide()

func _tick_idle() -> void:
	if _player and global_position.distance_to(_player.global_position) <= detection_range:
		state = State.CHASE

func _tick_chase(delta: float) -> void:
	if _player == null:
		state = State.IDLE
		return

	var dist := global_position.distance_to(_player.global_position)

	if dist <= attack_range:
		state = State.ATTACK
		velocity.x = 0.0
		velocity.z = 0.0
		return

	if dist > detection_range * 1.5:
		state = State.IDLE
		return

	var dir := (_player.global_position - global_position).normalized()
	dir.y = 0.0
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

func _tick_attack() -> void:
	if _player == null:
		state = State.IDLE
		return

	var dist := global_position.distance_to(_player.global_position)
	if dist > attack_range:
		state = State.CHASE
		return

	if _attack_cooldown <= 0.0:
		_attack_cooldown = 1.5
		_player.take_damage(attack_damage)

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health = max(0, health - amount)
	if health == 0:
		_die()

func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	XPSystem.try_award_kill_xp(mob_type_id, xp_reward)
	died.emit(self)
	queue_free()
