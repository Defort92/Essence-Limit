extends CharacterBody3D
class_name Player

const MAX_ACCESSORY_SLOTS: int = 3

# --- Movement ---
const MOVE_SPEED: float = 5.0
const GRAVITY: float = -20.0
const DODGE_SPEED: float = 12.0
const DODGE_DURATION: float = 0.25

enum State { IDLE, MOVE, DODGE, ATTACK, DEAD }
var state: State = State.IDLE

var _dodge_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _last_move_dir: Vector3 = Vector3.BACK

# --- RPG Stats ---
var max_health: int = 100
var health: int = 100
var base_strength: int = 10
var base_agility: int = 10
var base_intellect: int = 10

var equipment: Dictionary = {}
var accessories: Array[EquipmentData] = []

var is_in_town: bool = true

signal health_changed(current: int, maximum: int)
signal died()

func _ready() -> void:
	add_to_group("player")
	EssenceSystem.resize_to_level(XPSystem.current_level)
	DungeonPortal.portal_closed.connect(_on_portal_closed)

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

# --- Health ---
func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	if health == 0:
		state = State.DEAD
		died.emit()

func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	health_changed.emit(health, max_health)

# --- Equipment ---
func equip_item(item: EquipmentData) -> bool:
	if item.slot == EquipmentData.Slot.ACCESSORY:
		if accessories.size() >= MAX_ACCESSORY_SLOTS:
			return false
		accessories.append(item)
		return true
	if item.weapon_type == EquipmentData.WeaponType.MELEE_TWO_HAND:
		equipment.erase(EquipmentData.Slot.WEAPON_OFF)
	equipment[item.slot] = item
	return true

func get_total_stat(stat: String) -> int:
	var total := 0
	match stat:
		"strength":  total += base_strength
		"agility":   total += base_agility
		"intellect": total += base_intellect
	for item in equipment.values():
		if item and item.stat_bonuses.has(stat):
			total += item.stat_bonuses[stat]
	for item in accessories:
		if item.stat_bonuses.has(stat):
			total += item.stat_bonuses[stat]
	total += EssenceSystem.get_total_stat(stat)
	return total

func _on_portal_closed() -> void:
	is_in_town = true
