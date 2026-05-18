## Базовый враг: состояния IDLE → CHASE → ATTACK, система модификаторов статов.
## Наследуй от этого класса для создания специальных врагов (боссы, уникальные).
## Виртуальные методы для переопределения: _on_attack, _on_die.
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
## Испускается при смерти. Сцена уровня слушает этот сигнал и спавнит ItemPickup-узлы.
signal loot_dropped(items: Array, gold: int, at_position: Vector3)

func _ready() -> void:
	add_to_group("enemies")
	LootSpawner.register_enemy(self)
	if data == null:
		push_error("Enemy '%s': EnemyData не назначен" % name)
		return
	health = get_stat_int("max_health")
	# Ищем Player в следующем кадре, чтобы он успел добавиться в группу.
	# Проверяем is_inside_tree() перед доступом — на случай если Enemy удалён до этого кадра.
	await get_tree().process_frame
	if not is_inside_tree():
		return
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

# ─── Стат-система ──────────────────────────────────────────────────────────

## Возвращает текущее значение стата [param stat_name] с учётом всех модификаторов.
func get_stat(stat_name: String) -> float:
	if data == null:
		return 0.0
	var base_value: float = _base_stat(stat_name)
	for modifier in _modifiers:
		if modifier.stat == stat_name and modifier.op == StatModifier.Op.ADD:
			base_value += modifier.value
	for modifier in _modifiers:
		if modifier.stat == stat_name and modifier.op == StatModifier.Op.MULTIPLY:
			base_value *= modifier.value
	return base_value

## Возвращает get_stat(), округлённый до int.
func get_stat_int(stat_name: String) -> int:
	return roundi(get_stat(stat_name))

## Добавляет модификатор стата (от ауры этажа или эффекта способности).
func apply_modifier(modifier: StatModifier) -> void:
	_modifiers.append(modifier)

## Удаляет все модификаторы с source_id == [param source_id].
func remove_modifiers_by_source(source_id: String) -> void:
	var filtered: Array[StatModifier] = []
	for modifier in _modifiers:
		if modifier.source_id != source_id:
			filtered.append(modifier)
	_modifiers = filtered

## Наносит урон с учётом защиты врага. Минимальный урон — 1.
func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	var actual_damage := max(1, amount - get_stat_int("defense"))
	health = max(0, health - actual_damage)
	health_changed.emit(health, get_stat_int("max_health"))
	if health == 0:
		_die()

func _base_stat(stat_name: String) -> float:
	match stat_name:
		"max_health":      return data.max_health
		"move_speed":      return data.move_speed
		"attack_damage":   return data.attack_damage
		"attack_range":    return data.attack_range
		"attack_cooldown": return data.attack_cooldown
		"detection_range": return data.detection_range
		"defense":         return data.defense
	return 0.0

# ─── Машина состояний ──────────────────────────────────────────────────────

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

func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	if data:
		XPSystem.try_award_kill_xp(data.mob_type_id, data.xp_reward)
		var gold_amount := randi_range(data.gold_drop_min, data.gold_drop_max)
		var loot_items: Array = []
		if data.loot_table:
			loot_items = data.loot_table.roll()
			gold_amount += data.loot_table.roll_gold()
		# Золото и предметы падают в мир как ItemPickup-узлы через LootSpawner.
		# GameManager.add_gold() не вызывается напрямую — игрок должен подобрать дроп.
		loot_dropped.emit(loot_items, gold_amount, global_position)
	_on_die()
	died.emit(self)
	queue_free()

## Переопределяй для кастомной атаки (дальний бой, AOE и т.д.).
func _on_attack(player: Player) -> void:
	player.take_damage(get_stat_int("attack_damage"))

## Переопределяй для эффектов при смерти (анимация, спавн сущностей).
func _on_die() -> void:
	pass

# ─── Утилиты поломки снаряжения ────────────────────────────────────────────

## Ломает случайный надетый предмет у [param player].
## Вызывай из _on_attack() боссов или уникальных мобов с особой атакой.
## Если всё снаряжение уже сломано или не надето — ничего не происходит.
func _break_random_equipment(player: Player) -> void:
	# Собираем список незломанных слотов + аксессуаров.
	var targets: Array = []
	for slot in EquipmentData.Slot.values():
		if slot == EquipmentData.Slot.ACCESSORY:
			continue
		if EquipmentManager.get_equipped(slot) != null and not EquipmentManager.is_slot_broken(slot):
			targets.append({"type": "slot", "key": slot})
	for idx in EquipmentManager.get_accessories().size():
		if not EquipmentManager.is_accessory_broken(idx):
			targets.append({"type": "acc", "key": idx})
	if targets.is_empty():
		return
	var chosen: Dictionary = targets[randi() % targets.size()]
	if chosen.type == "slot":
		EquipmentManager.break_equipped_item(chosen.key)
	else:
		EquipmentManager.break_accessory(chosen.key)
