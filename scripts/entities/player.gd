## Персонаж игрока: движение, уклонение, атака, блок, HP, статы с модификаторами.
## Статы = base (раса + уровень) + EquipmentManager + EssenceSystem + _modifiers.
## Добавляется в группу "player" для поиска через get_first_node_in_group.
extends CharacterBody3D
class_name Player

# --- Константы движения ---
const MOVE_SPEED: float = 5.0
const GRAVITY: float = -20.0
const DODGE_SPEED: float = 12.0
const DODGE_DURATION: float = 0.25

# --- Константы боя ---
## Длительность состояния ATTACK (окно блокировки повторного удара).
const ATTACK_STATE_DURATION: float = 0.3
## Снижение урона при активном блоке щитом (0.0–1.0).
const BLOCK_DAMAGE_REDUCTION: float = 0.5
const UNARMED_COOLDOWN: float = 0.6
const UNARMED_DAMAGE_BASE: int = 3
const UNARMED_RANGE: float = 1.2

enum State { IDLE, MOVE, DODGE, ATTACK, DEAD }
var state: State = State.IDLE

var _dodge_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _last_move_dir: Vector3 = Vector3.BACK
var _attack_timer: float = 0.0
var _attack_state_timer: float = 0.0

## true во время уклонения — игрок не получает урон (i-frames).
var _is_invincible: bool = false
var is_blocking: bool = false

# --- Статы ---
## База HP (раса + уровень). Не включает бонусы снаряжения/эссенций.
var base_max_health: int = 100
## Итоговый максимум HP. Пересчитывается через _recalculate_derived_stats().
var max_health: int = 100
var health: int = 100
var base_strength: int = 10
var base_agility: int = 10
var base_intellect: int = 10

## Временные модификаторы от аур, расходников, достижений.
var _modifiers: Array[StatModifier] = []

## Быстрые слоты расходников (item_id). Назначаются из UI, используются клавишами 1–4.
var quick_slots: Array[String] = ["", "", "", ""]

var is_in_town: bool = true

signal health_changed(current: int, maximum: int)
signal died()

func _ready() -> void:
	add_to_group("player")
	_init_race_stats()
	AchievementSystem.apply_accumulated_to_player(self)
	EssenceSystem.resize_to_level(XPSystem.current_level)
	DungeonPortal.portal_closed.connect(_on_portal_closed)
	XPSystem.level_up.connect(_on_level_up)
	EssenceSystem.essence_equipped.connect(_on_essence_changed)
	EssenceSystem.essence_removed.connect(_on_essence_slot_cleared)
	EquipmentManager.equipment_changed.connect(_on_equipment_changed)
	died.connect(GameManager.on_player_died)

func _physics_process(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta

	match state:
		State.IDLE, State.MOVE:
			_handle_movement(delta)
			_handle_attack_input()
			_handle_block_input()
			_handle_dodge_input()
			_handle_consumable_input()
		State.ATTACK:
			_handle_movement(delta)
			_handle_block_input()
			_tick_attack_state(delta)
		State.DODGE:
			_tick_dodge(delta)
		State.DEAD:
			pass

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	move_and_slide()

# ─── Здоровье ──────────────────────────────────────────────────────────────

## Применяет урон с учётом защиты, блока и i-frames.
func take_damage(amount: int) -> void:
	if state == State.DEAD or _is_invincible:
		return
	var defense := get_total_stat("defense")
	var actual_damage := max(1, amount - defense)
	if is_blocking and _has_shield():
		# Щит поглощает часть урона. int() отбрасывает дробную часть:
		# 10 урона × (1 - 0.5) = 5.0 → игрок получает 5
		#  1 урона × (1 - 0.3) = 0.7 → игрок получает 0 (щит полностью поглотил)
		actual_damage = int(actual_damage * (1.0 - BLOCK_DAMAGE_REDUCTION))
	health = max(0, health - actual_damage)
	health_changed.emit(health, max_health)
	if health == 0:
		state = State.DEAD
		died.emit()

## Восстанавливает [param amount] HP, не превышая max_health.
func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	health_changed.emit(health, max_health)

# ─── Статы ─────────────────────────────────────────────────────────────────

## Возвращает итоговое значение стата с учётом снаряжения, эссенций и модификаторов.
## Формула: (base + equipment + essence + ADD_mods) * MULTIPLY_mods.
func get_total_stat(stat_name: String) -> int:
	if stat_name == "max_health":
		return max_health
	var base_value := 0
	match stat_name:
		"strength":  base_value = base_strength
		"agility":   base_value = base_agility
		"intellect": base_value = base_intellect
	var pool := float(
		base_value
		+ EquipmentManager.get_total_stat(stat_name)
		+ EssenceSystem.get_total_stat(stat_name)
		+ _sum_add_modifiers(stat_name)
	)
	return int(pool * _product_multiply_modifiers(stat_name))

## Добавляет временный модификатор стата (от ауры, расходника, достижения и т.д.).
func apply_modifier(modifier: StatModifier) -> void:
	_modifiers.append(modifier)
	_recalculate_derived_stats()

## Снимает все модификаторы с source_id == [param source_id].
func remove_modifiers_by_source(source_id: String) -> void:
	var filtered: Array[StatModifier] = []
	for modifier in _modifiers:
		if modifier.source_id != source_id:
			filtered.append(modifier)
	_modifiers = filtered
	_recalculate_derived_stats()

# ─── Атака ─────────────────────────────────────────────────────────────────

func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack") and _attack_timer <= 0.0:
		_start_attack()

func _start_attack() -> void:
	state = State.ATTACK
	_attack_state_timer = ATTACK_STATE_DURATION
	_attack_timer = _get_attack_cooldown()
	_perform_attack()

func _tick_attack_state(delta: float) -> void:
	_attack_state_timer -= delta
	if _attack_state_timer <= 0.0:
		state = State.IDLE

func _perform_attack() -> void:
	var weapon := EquipmentManager.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon != null and weapon.weapon_type == EquipmentData.WeaponType.RANGED:
		_perform_ranged_attack(weapon)
	else:
		_perform_melee_attack()

func _perform_melee_attack() -> void:
	var atk_range := _get_attack_range()
	var atk_damage := _get_attack_damage()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist > atk_range:
			continue
		# Ограничиваем удар передней полусферой (~150°).
		var dir_to_enemy := (enemy.global_position - global_position)
		dir_to_enemy.y = 0.0
		if dir_to_enemy.length_squared() > 0.001 and _last_move_dir.dot(dir_to_enemy.normalized()) < -0.5:
			continue
		enemy.take_damage(atk_damage)

func _perform_ranged_attack(weapon: EquipmentData) -> void:
	# Временная реализация: мгновенный хит ближайшего врага в радиусе.
	# Заменить на ProjectileComponent когда добавится визуал.
	var atk_range: float = float(weapon.stat_bonuses.get("range", 10.0))
	var atk_damage := _get_attack_damage()
	var nearest_enemy: Node3D = null
	var nearest_dist: float = atk_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_enemy = enemy
	if nearest_enemy != null and nearest_enemy.has_method("take_damage"):
		nearest_enemy.take_damage(atk_damage)

func _get_attack_damage() -> int:
	var weapon := EquipmentManager.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon != null:
		var weapon_damage: int = weapon.stat_bonuses.get("damage", 0)
		return weapon_damage + get_total_stat("strength") / 2
	return max(1, UNARMED_DAMAGE_BASE + get_total_stat("strength") / 3)

func _get_attack_cooldown() -> float:
	var weapon := EquipmentManager.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon == null:
		return UNARMED_COOLDOWN
	match weapon.weapon_type:
		EquipmentData.WeaponType.MELEE_ONE_HAND: return 0.5
		EquipmentData.WeaponType.MELEE_TWO_HAND: return 0.9
		EquipmentData.WeaponType.RANGED:         return 0.7
	return UNARMED_COOLDOWN

func _get_attack_range() -> float:
	var weapon := EquipmentManager.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon != null:
		return float(weapon.stat_bonuses.get("range", 1.5))
	return UNARMED_RANGE

# ─── Блок ──────────────────────────────────────────────────────────────────

func _handle_block_input() -> void:
	is_blocking = _has_shield() and Input.is_action_pressed("block")

func _has_shield() -> bool:
	var off_hand := EquipmentManager.get_equipped(EquipmentData.Slot.WEAPON_OFF)
	return off_hand != null and off_hand.weapon_type == EquipmentData.WeaponType.SHIELD

# ─── Движение и уклонение ──────────────────────────────────────────────────

func _handle_movement(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input.x, 0.0, input.y)
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		_last_move_dir = direction
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.z * MOVE_SPEED
		if state == State.IDLE:
			state = State.MOVE
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)
		if state == State.MOVE:
			state = State.IDLE

func _handle_dodge_input() -> void:
	if Input.is_action_just_pressed("dodge"):
		state = State.DODGE
		_dodge_timer = DODGE_DURATION
		_dodge_direction = _last_move_dir
		_is_invincible = true

func _tick_dodge(delta: float) -> void:
	_dodge_timer -= delta
	velocity.x = _dodge_direction.x * DODGE_SPEED
	velocity.z = _dodge_direction.z * DODGE_SPEED
	if _dodge_timer <= 0.0:
		state = State.IDLE
		_is_invincible = false

# ─── Расходники ────────────────────────────────────────────────────────────

func _handle_consumable_input() -> void:
	for slot_idx in range(quick_slots.size()):
		if Input.is_action_just_pressed("consumable_%d" % (slot_idx + 1)):
			_use_quick_slot(slot_idx)
			return

func _use_quick_slot(slot_idx: int) -> void:
	var item_id: String = quick_slots[slot_idx]
	if item_id.is_empty():
		return
	InventorySystem.use_consumable(item_id, self)

## Назначает предмет на быстрый слот. Вызывается из UI инвентаря.
func set_quick_slot(slot_idx: int, item_id: String) -> void:
	if slot_idx < 0 or slot_idx >= quick_slots.size():
		return
	quick_slots[slot_idx] = item_id

# ─── Инициализация и пересчёт статов ───────────────────────────────────────

func _init_race_stats() -> void:
	var stats := GameManager.get_race_base_stats(GameManager.player_race)
	base_max_health = stats.get("max_health", 100)
	base_strength   = stats.get("strength", 10)
	base_agility    = stats.get("agility", 10)
	base_intellect  = stats.get("intellect", 10)

	# Восстановить quick_slots из сохранения если есть.
	var saved := GameManager.saved_quick_slots
	if saved.size() == quick_slots.size():
		quick_slots = saved.duplicate()
		GameManager.saved_quick_slots = ["", "", "", ""]

	# SaveSystem записывает saved_health при загрузке; -1 → старт с полным HP.
	health = GameManager.saved_health if GameManager.saved_health > 0 else base_max_health
	GameManager.saved_health = -1

	_recalculate_derived_stats()

func _on_level_up(_new_level: int) -> void:
	var bonus := GameManager.get_race_level_bonus(GameManager.player_race)
	base_max_health += bonus.get("max_health", 0)
	_recalculate_derived_stats()

func _on_essence_changed(_slot_index: int, _essence: EssenceData) -> void:
	_recalculate_derived_stats()

func _on_essence_slot_cleared(_slot_index: int) -> void:
	_recalculate_derived_stats()

func _on_equipment_changed() -> void:
	_recalculate_derived_stats()

## Пересчитывает max_health по формуле (base + ADD_mods) * MULTIPLY_mods.
func _recalculate_derived_stats() -> void:
	var old_max := max_health
	var pool := float(
		base_max_health
		+ EquipmentManager.get_total_stat("max_health")
		+ EssenceSystem.get_total_stat("max_health")
		+ _sum_add_modifiers("max_health")
	)
	max_health = max(1, int(pool * _product_multiply_modifiers("max_health")))

	if old_max > 0 and max_health != old_max:
		health = max(1, int(float(health) / float(old_max) * float(max_health)))

	health = min(health, max_health)
	health_changed.emit(health, max_health)

## Суммирует ADD-модификаторы для стата [param stat_name].
func _sum_add_modifiers(stat_name: String) -> int:
	var total := 0
	for modifier in _modifiers:
		if modifier.stat == stat_name and modifier.op == StatModifier.Op.ADD:
			total += int(modifier.value)
	return total

## Перемножает все MULTIPLY-модификаторы для стата [param stat_name].
func _product_multiply_modifiers(stat_name: String) -> float:
	var product := 1.0
	for modifier in _modifiers:
		if modifier.stat == stat_name and modifier.op == StatModifier.Op.MULTIPLY:
			product *= modifier.value
	return product

func _on_portal_closed() -> void:
	is_in_town = true
