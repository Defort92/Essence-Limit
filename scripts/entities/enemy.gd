extends CharacterBody3D
class_name Enemy

@export var data: EnemyData

var health: int
var _modifiers: Array[StatModifier] = []

const GRAVITY: float = -20.0

enum State { IDLE, CHASE, ATTACK, DEAD }
var state: State = State.IDLE

var _player: Player = null
var _attack_cooldown: float = 0.0

signal died(enemy: Enemy)
signal health_changed(current: int, maximum: int)

func _ready() -> void:
	if data == null:
		push_error("Enemy '%s': EnemyData not set" % name)
		return
	health = get_stat_int("max_health")
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Player

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	_attack_cooldown = max(0.0, _attack_cooldown - delta)

	match state:
		State.IDLE:   _tick_idle()
		State.CHASE:  _tick_chase(delta)
		State.ATTACK: _tick_attack()

	move_and_slide()

# --- Stat system ---

func get_stat(stat_name: String) -> float:
	if data == null:
		return 0.0
	var base: float = _base_stat(stat_name)
	for mod in _modifiers:
		if mod.stat == stat_name and mod.op == StatModifier.Op.ADD:
			base += mod.value
	for mod in _modifiers:
		if mod.stat == stat_name and mod.op == StatModifier.Op.MULTIPLY:
			base *= mod.value
	return base

func get_stat_int(stat_name: String) -> int:
	return roundi(get_stat(stat_name))

func apply_modifier(mod: StatModifier) -> void:
	_modifiers.append(mod)

func remove_modifiers_by_source(source_id: String) -> void:
	var result: Array[StatModifier] = []
	for m in _modifiers:
		if m.source_id != source_id:
			result.append(m)
	_modifiers = result

func _base_stat(stat_name: String) -> float:
	match stat_name:
		"max_health": return data.max_health
		"move_speed": return data.move_speed
		"attack_damage": return data.attack_damage
		"attack_range": return data.attack_range
		"attack_cooldown": return data.attack_cooldown
		"detection_range": return data.detection_range
	return 0.0

# --- State machine ---

func _tick_idle() -> void:
	if _player and global_position.distance_to(_player.global_position) <= get_stat("detection_range"):
		state = State.CHASE

func _tick_chase(_delta: float) -> void:
	if _player == null:
		state = State.IDLE
		return

	var dist := global_position.distance_to(_player.global_position)

	if dist <= get_stat("attack_range"):
		velocity.x = 0.0
		velocity.z = 0.0
		state = State.ATTACK
		return

	if dist > get_stat("detection_range") * 1.5:
		state = State.IDLE
		return

	var dir := (_player.global_position - global_position).normalized()
	dir.y = 0.0
	velocity.x = dir.x * get_stat("move_speed")
	velocity.z = dir.z * get_stat("move_speed")

func _tick_attack() -> void:
	if _player == null:
		state = State.IDLE
		return

	if global_position.distance_to(_player.global_position) > get_stat("attack_range"):
		state = State.CHASE
		return

	if _attack_cooldown <= 0.0:
		_attack_cooldown = get_stat("attack_cooldown")
		_on_attack(_player)

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health = max(0, health - amount)
	health_changed.emit(health, get_stat_int("max_health"))
	if health == 0:
		_die()

func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	if data:
		XPSystem.try_award_kill_xp(data.mob_type_id, data.xp_reward)
		var gold := randi_range(data.gold_drop_min, data.gold_drop_max)
		if gold > 0:
			GameManager.add_gold(gold)
	_on_die()
	died.emit(self)
	queue_free()

# --- Virtual hooks ---

func _on_attack(player: Player) -> void:
	player.take_damage(get_stat_int("attack_damage"))

func _on_die() -> void:
	pass
