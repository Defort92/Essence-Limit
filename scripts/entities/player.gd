## Персонаж-участник отряда: движение, уклонение, атака, блок, HP, статы с модификаторами.
## Статы = base (раса + уровень) + equipment + essence + _modifiers.
## Экипировка/эссенции/способности — свои у каждого участника (дочерние компоненты
## Equipment/Essence/Abilities в player.tscn), не общие на весь отряд.
## Один и тот же скрипт используется и для главного героя, и для союзников — разница
## только в control_mode (HUMAN/AI), см. PartySystem. Группа "player" держит только
## текущего активного (управляемого игроком) участника; "party"/"combatants" — всех.
extends CharacterBody3D
class_name Player


enum State { IDLE, MOVE, DODGE, ATTACK, DEAD }
var state: State = State.IDLE

## Все участники отряда — PLAYER (см. scripts/data/faction.gd). Используется таргетингом
## врагов и атак, чтобы не бить союзников и находить враждебные по фракции цели.
var faction: Faction.Kind = Faction.Kind.PLAYER

## HUMAN — читает Input и управляется игроком. AI — управляется автономным поведением
## союзника (следование за лидером отряда, авто-атака в радиусе). Переключается через
## PartySystem.switch_active() при выборе активного персонажа или смерти текущего.
enum ControlMode { HUMAN, AI }
var control_mode: ControlMode = ControlMode.HUMAN

## Индекс записи этого участника в PartySystem.roster. -1 у статического Player сцены
## до регистрации (PartySystem назначит 0 — герой) и у покинувших отряд (предатель/беглец).
var roster_index: int = -1

## Раса участника: у героя — из создания персонажа, у наёмника — из CompanionData.
## Определяет базовые статы через GameManagerConstants.RACE_BASE_STATS.
var race: int = 0
var member_name: String = ""

## Боевая роль под управлением ИИ (CompanionData.Role): FIGHTER только атакует,
## HEALER только лечит отряд и не вступает в бой. На управление игроком не влияет.
var combat_role: int = CompanionData.Role.FIGHTER

## Доверие/признание наёмника к главному герою (0..100). При падении до 0 наёмник
## предаёт отряд (становится врагом) или сбегает — см. PartySystem.on_trust_bottomed().
## В будущем также будет влиять на приоритеты ИИ (лечить/баффать лидера охотнее).
var trust: int = 100

## true после предательства: фракция сменена на HOSTILE_NPC, отряд покинут.
var _is_traitor: bool = false
## true во время побега с поля боя: не сражается, убегает и исчезает по таймеру.
var _is_fleeing: bool = false


## Своя экипировка/эссенции/способности/рюкзак — не общие на отряд, см. player.tscn.
@onready var equipment: EquipmentManager = $Equipment
@onready var essence: EssenceSystem = $Essence
@onready var ability_manager: AbilityManager = $Abilities
@onready var statuses: StatusComponent = $Statuses
@onready var inventory: InventoryComponent = $Inventory

var _dodge_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _last_move_dir: Vector3 = Vector3.BACK

## Целевая точка для режима бега мышью (InputSettings.MovementMode.MOUSE). Персонаж бежит
## к ней, пока не окажется ближе MOVE_STOP_DISTANCE; сбрасывается при переходе под ИИ.
var _move_target: Vector3 = Vector3.ZERO
var _has_move_target: bool = false
var _attack_timer: float = 0.0
var _attack_state_timer: float = 0.0
var _regen_timer: float = 0.0

## true во время уклонения — игрок не получает урон (i-frames).
var _is_invincible: bool = false
var is_blocking: bool = false

## Сколько ещё секунд участник неуязвим после переключения на него через PartySystem
## (защита от мгновенной смерти, если управление передали посреди боя).
var _post_switch_invuln_timer: float = 0.0

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

## 2.5D-спрайт с 8 ракурсами. Может отсутствовать (тогда движение без визуала).
var _sprite: DirectionalSprite3D = null

signal health_changed(current: int, maximum: int)
signal died()
signal trust_changed(new_value: int)

func _ready() -> void:
	add_to_group("party")
	add_to_group("combatants")
	_sprite = get_node_or_null("Sprite3D") as DirectionalSprite3D
	PartySystem.register_member(self)  # назначает roster_index и control_mode
	_init_from_roster()
	AchievementSystem.apply_accumulated_to_player(self)
	DungeonPortal.portal_closed.connect(_on_portal_closed)
	XPSystem.level_up.connect(_on_level_up)
	essence.essence_equipped.connect(_on_essence_changed)
	essence.essence_removed.connect(_on_essence_slot_cleared)
	equipment.equipment_changed.connect(_on_equipment_changed)
	# Демо-раздача статусов «как будто выданных на уровне»: экран состояний и панель HUD
	# наполняются сразу, до появления реальных источников (аур этажей, эссенций).
	statuses.grant_demo_statuses()

func _physics_process(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta
	if _post_switch_invuln_timer > 0.0:
		_post_switch_invuln_timer = max(0.0, _post_switch_invuln_timer - delta)
	_ai_delta = delta
	_tick_passive_regen(delta)

	match state:
		State.IDLE, State.MOVE:
			if control_mode == ControlMode.HUMAN:
				_handle_movement(delta)
				_handle_attack_input()
				_handle_block_input()
				_handle_dodge_input()
				_handle_consumable_input()
				_handle_party_command_input()
			else:
				_ai_process(delta)
		State.ATTACK:
			if control_mode == ControlMode.HUMAN:
				_handle_movement(delta)
				_handle_block_input()
			else:
				# ИИ во время замаха стоит на месте, плавно гася инерцию, — иначе союзник
				# доезжает по инерции («скользит») весь ATTACK_STATE_DURATION.
				_ai_hold_position()
			_tick_attack_state(delta)
		State.DODGE:
			_tick_dodge(delta)
		State.DEAD:
			pass

	if not is_on_floor():
		velocity.y += PlayerConstants.GRAVITY * delta

	# Разворачиваем спрайт по последнему направлению взгляда (движение/атака/уклонение)
	# и переключаем анимацию ходьба/покой по фактической горизонтальной скорости.
	if _sprite != null and state != State.DEAD:
		_sprite.face_direction(_last_move_dir)
		var horiz_speed_sq: float = velocity.x * velocity.x + velocity.z * velocity.z
		_sprite.set_moving(horiz_speed_sq > PlayerConstants.MOVE_ANIM_THRESHOLD_SQ)

	move_and_slide()

# ─── Здоровье ──────────────────────────────────────────────────────────────

## Применяет урон с учётом защиты, блока и i-frames.
## [param is_crit] = true рисует число красным и крупнее (крит определяет атакующий).
func take_damage(amount: int, is_crit: bool = false) -> void:
	if state == State.DEAD or _is_invincible or _post_switch_invuln_timer > 0.0:
		return
	var defense := get_total_stat("defense")
	var actual_damage: int = max(1, amount - defense)
	if is_blocking and _has_shield():
		# Щит поглощает часть урона. int() отбрасывает дробную часть:
		# 10 урона × (1 - 0.5) = 5.0 → игрок получает 5
		#  1 урона × (1 - 0.3) = 0.7 → игрок получает 0 (щит полностью поглотил)
		actual_damage = int(actual_damage * (1.0 - PlayerConstants.BLOCK_DAMAGE_REDUCTION))
	health = max(0, health - actual_damage)
	health_changed.emit(health, max_health)
	if actual_damage > 0:
		_show_combat_text(actual_damage, FloatingCombatText.Kind.HIT_CRIT if is_crit else FloatingCombatText.Kind.HIT)
	if _sprite != null:
		_sprite.flash(Color(1.0, 0.2, 0.2))
	if health == 0:
		state = State.DEAD
		# Труп не участвует в бою: иначе Enemy._retarget()/_ai_find_target() будут вечно
		# выбирать его как ближайшую цель и бить лежачего вместо живых.
		remove_from_group("combatants")
		# Затемняем спрайт — тело союзника остаётся в сцене как визуальный труп/маркер лута.
		if _sprite != null:
			_sprite.set_moving(false)  # труп замирает в покое, а не «шагает» на месте
			_sprite.darken_base(0.5, 0.9)
		_spawn_loot_corpse()
		died.emit()

## Спавнит рядом с телом контейнер лута, если на павшем есть снаряжение. Контейнер ссылается
## на эту же equipment-компоненту — «взять» снимает предмет прямо с трупа в рюкзак активного
## (управляемого игроком) мародёра. Незалутанное снаряжение остаётся на союзнике и переживёт
## возрождение при смене сцены.
func _spawn_loot_corpse() -> void:
	if not equipment.has_any_equipped():
		return
	var corpse := LootableCorpse.new()
	corpse.source_player = self
	corpse.corpse_name = member_name if not member_name.is_empty() else "Павший союзник"
	# Добавляем отложенно: смерть может наступить внутри физического кадра.
	get_parent().call_deferred("add_child", corpse)
	corpse.set_deferred("global_position", global_position)

## Восстанавливает [param amount] HP, не превышая max_health.
## [param flash] = false подавляет вспышку и всплывающее число (пассивная регенерация).
## [param is_crit] форсирует крит; иначе при flash==true крит бросается автоматически.
func heal(amount: int, flash: bool = true, is_crit: bool = false) -> void:
	if amount <= 0:
		return
	var crit: bool = is_crit
	if flash and not crit:
		crit = CombatMath.roll_crit(self, self)
	var healed: int = CombatMath.apply_crit(amount) if crit else amount
	var before: int = health
	health = min(max_health, health + healed)
	health_changed.emit(health, max_health)
	var real_gain: int = health - before
	if flash:
		if real_gain > 0:
			_show_combat_text(real_gain, FloatingCombatText.Kind.HEAL_CRIT if crit else FloatingCombatText.Kind.HEAL)
		if _sprite != null:
			_sprite.flash(Color(0.3, 1.0, 0.4))

## Итоговый шанс крита атак/лечения этого участника: база + ловкость + плоские бонусы
## "crit_chance" (снаряжение/эссенции/модификаторы, трактуются как доли 0.0–1.0).
func get_attack_crit_chance() -> float:
	var chance: float = CombatMathConstants.BASE_CRIT_CHANCE
	chance += float(get_total_stat("agility")) * PlayerConstants.AGILITY_CRIT_FACTOR
	chance += _sum_add_modifiers_f("crit_chance")
	return clampf(chance, 0.0, CombatMathConstants.MAX_CRIT_CHANCE)

## Прибавка к шансу крита атакующего от ослаблений на этом участнике (модификаторы
## "crit_vulnerability", доля 0.0–1.0) — дебаффы делают персонажа уязвимее к криту.
func get_incoming_crit_bonus() -> float:
	return _sum_add_modifiers_f("crit_vulnerability")

## Всплывающее боевое число над персонажем (урон/лечение), см. FloatingCombatText.
func _show_combat_text(amount: int, kind: int) -> void:
	FloatingCombatText.spawn(self, global_position + Vector3(0.0, 2.0, 0.0), amount, kind)

## Раз в REGEN_TICK_INTERVAL секунд восстанавливает HP на величину стата "regen".
func _tick_passive_regen(delta: float) -> void:
	if state == State.DEAD:
		return
	_regen_timer += delta
	if _regen_timer < PlayerConstants.REGEN_TICK_INTERVAL:
		return
	_regen_timer = 0.0
	var regen: int = get_total_stat("regen")
	if regen > 0:
		heal(regen, false)

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
		+ equipment.get_total_stat(stat_name)
		+ essence.get_total_stat(stat_name)
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

## Накладывает статус-эффект (благо/недуг) на этого участника. Вызывается извне —
## например, врагом при удачной атаке (см. Enemy._on_attack). Подсвечивает спрайт.
func apply_status_effect(data: StatusEffectData) -> void:
	if data == null or state == State.DEAD:
		return
	statuses.apply_status(data)
	if _sprite != null:
		_sprite.flash(Color(0.7, 0.3, 0.9) if data.is_debuff else Color(0.35, 0.55, 1.0))

## Снимает статус-эффект по [param id] (например, при выходе из зоны-ауры). Парный к
## apply_status_effect; ничего не делает, если такого статуса нет.
func remove_status_effect(id: String) -> void:
	statuses.remove_status(id)

## Накладывает модификатор на [param duration] секунд (0 = бессрочно, снимать вручную).
## Подсвечивает спрайт: синим для бафа, фиолетовым для дебафа.
func apply_timed_modifier(modifier: StatModifier, duration: float, is_debuff: bool = false) -> void:
	apply_modifier(modifier)
	if _sprite != null:
		_sprite.flash(Color(0.7, 0.3, 0.9) if is_debuff else Color(0.35, 0.55, 1.0))
	if duration > 0.0 and is_inside_tree():
		var source_id_copy: String = modifier.source_id
		get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					remove_modifiers_by_source(source_id_copy)
		)

# ─── Атака ─────────────────────────────────────────────────────────────────

func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack") and _attack_timer <= 0.0:
		_start_attack()

func _start_attack() -> void:
	state = State.ATTACK
	_attack_state_timer = PlayerConstants.ATTACK_STATE_DURATION
	_attack_timer = _get_attack_cooldown()
	_perform_attack()

func _tick_attack_state(delta: float) -> void:
	_attack_state_timer -= delta
	if _attack_state_timer <= 0.0:
		state = State.IDLE

func _perform_attack() -> void:
	var weapon := equipment.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon != null and weapon.weapon_type == EquipmentData.WeaponType.RANGED:
		_perform_ranged_attack(weapon)
	else:
		_perform_melee_attack()

func _perform_melee_attack() -> void:
	var atk_range := _get_attack_range()
	var atk_damage := _get_attack_damage()
	for target in get_tree().get_nodes_in_group("combatants"):
		if not _is_hostile_target(target):
			continue
		var dist: float = global_position.distance_to(target.global_position)
		if dist > atk_range:
			continue
		# Ограничиваем удар передней полусферой (~150°).
		var dir_to_target: Vector3 = target.global_position - global_position
		dir_to_target.y = 0.0
		if dir_to_target.length_squared() > 0.001 and _last_move_dir.dot(dir_to_target.normalized()) < -0.5:
			continue
		var is_crit: bool = CombatMath.roll_crit(self, target)
		target.take_damage(CombatMath.apply_crit(atk_damage) if is_crit else atk_damage, is_crit)

func _perform_ranged_attack(weapon: EquipmentData) -> void:
	# Временная реализация: мгновенный хит ближайшего врага в радиусе.
	# Заменить на ProjectileComponent когда добавится визуал.
	var atk_range: float = float(weapon.stat_bonuses.get("range", 10.0))
	var atk_damage := _get_attack_damage()
	var nearest_target: Node3D = null
	var nearest_dist: float = atk_range
	for target in get_tree().get_nodes_in_group("combatants"):
		if not _is_hostile_target(target):
			continue
		var dist: float = global_position.distance_to(target.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_target = target
	if nearest_target != null:
		var is_crit: bool = CombatMath.roll_crit(self, nearest_target)
		nearest_target.take_damage(CombatMath.apply_crit(atk_damage) if is_crit else atk_damage, is_crit)

## true если [param target] — живой узел из группы "combatants" враждебной по фракции.
func _is_hostile_target(target: Node) -> bool:
	if target == self or not is_instance_valid(target):
		return false
	if not target.has_method("take_damage") or not ("faction" in target):
		return false
	# Трупы участников отряда остаются в сцене — не фиксируемся на них.
	if "health" in target and target.health <= 0:
		return false
	return Faction.is_hostile(faction, target.faction)

func _get_attack_damage() -> int:
	var weapon := equipment.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon != null:
		var weapon_damage: int = weapon.stat_bonuses.get("damage", 0)
		return weapon_damage + int(float(get_total_stat("strength")) / 2.0)
	return maxi(
		1,
		PlayerConstants.UNARMED_DAMAGE_BASE + int(float(get_total_stat("strength")) / 3.0)
	)

func _get_attack_cooldown() -> float:
	var weapon := equipment.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon == null:
		return PlayerConstants.UNARMED_COOLDOWN
	match weapon.weapon_type:
		EquipmentData.WeaponType.MELEE_ONE_HAND: return 0.5
		EquipmentData.WeaponType.MELEE_TWO_HAND: return 0.9
		EquipmentData.WeaponType.RANGED:         return 0.7
	return PlayerConstants.UNARMED_COOLDOWN

func _get_attack_range() -> float:
	var weapon := equipment.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	if weapon != null:
		return float(weapon.stat_bonuses.get("range", 1.5))
	return PlayerConstants.UNARMED_RANGE

# ─── Блок ──────────────────────────────────────────────────────────────────

func _handle_block_input() -> void:
	# В режиме бега мышью ПКМ занята командой «идти сюда», поэтому блок недоступен.
	if InputSettings.movement_mode == InputSettings.MovementMode.MOUSE:
		is_blocking = false
		return
	is_blocking = _has_shield() and Input.is_action_pressed("block")

func _has_shield() -> bool:
	var off_hand := equipment.get_equipped(EquipmentData.Slot.WEAPON_OFF)
	return off_hand != null and off_hand.weapon_type == EquipmentData.WeaponType.SHIELD

# ─── Движение и уклонение ──────────────────────────────────────────────────

func _handle_movement(_delta: float) -> void:
	if InputSettings.movement_mode == InputSettings.MovementMode.MOUSE:
		_handle_mouse_movement()
	else:
		_handle_keyboard_movement()

func _handle_keyboard_movement() -> void:
	# Клавиатурный ввод отменяет ранее заданную мышью цель (на случай смены режима на лету).
	_has_move_target = false
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input.x, 0.0, input.y)
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		_last_move_dir = direction
		velocity.x = direction.x * PlayerConstants.MOVE_SPEED
		velocity.z = direction.z * PlayerConstants.MOVE_SPEED
		if state == State.IDLE:
			state = State.MOVE
	else:
		_stop_horizontal()

## Бег к точке, заданной правой кнопкой мыши. ПКМ проецируется на плоскость земли на
## высоте персонажа; персонаж бежит к точке, пока не окажется ближе MOVE_STOP_DISTANCE.
func _handle_mouse_movement() -> void:
	# "block" привязан к ПКМ — в этом режиме трактуем нажатие как команду «идти сюда».
	if Input.is_action_just_pressed("block"):
		var target := _mouse_ground_point()
		if target != Vector3.INF:
			_move_target = target
			_has_move_target = true
	if not _has_move_target:
		_stop_horizontal()
		return
	var to_target := _move_target - global_position
	to_target.y = 0.0
	if to_target.length() <= PlayerConstants.MOVE_STOP_DISTANCE:
		_has_move_target = false
		_stop_horizontal()
		return
	var direction := to_target.normalized()
	_last_move_dir = direction
	velocity.x = direction.x * PlayerConstants.MOVE_SPEED
	velocity.z = direction.z * PlayerConstants.MOVE_SPEED
	if state == State.IDLE:
		state = State.MOVE

## Точка на плоскости земли (y = высота персонажа) под курсором. Vector3.INF если камеры
## нет или луч не пересёк плоскость.
func _mouse_ground_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_dir := cam.project_ray_normal(mouse_pos)
	var ground := Plane(Vector3.UP, global_position.y)
	var hit = ground.intersects_ray(ray_origin, ray_dir)
	if hit is Vector3:
		var point: Vector3 = hit
		return point
	return Vector3.INF

## Плавно гасит горизонтальную скорость и возвращает состояние в IDLE.
func _stop_horizontal() -> void:
	velocity.x = move_toward(velocity.x, 0.0, PlayerConstants.MOVE_SPEED)
	velocity.z = move_toward(velocity.z, 0.0, PlayerConstants.MOVE_SPEED)
	if state == State.MOVE:
		state = State.IDLE

func _handle_dodge_input() -> void:
	if Input.is_action_just_pressed("dodge"):
		state = State.DODGE
		_dodge_timer = PlayerConstants.DODGE_DURATION
		_dodge_direction = _last_move_dir
		_is_invincible = true

func _tick_dodge(delta: float) -> void:
	_dodge_timer -= delta
	velocity.x = _dodge_direction.x * PlayerConstants.DODGE_SPEED
	velocity.z = _dodge_direction.z * PlayerConstants.DODGE_SPEED
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
	inventory.use_consumable(item_id, self)

## Назначает предмет на быстрый слот. Вызывается из UI инвентаря.
func set_quick_slot(slot_idx: int, item_id: String) -> void:
	if slot_idx < 0 or slot_idx >= quick_slots.size():
		return
	quick_slots[slot_idx] = item_id

# ─── Управление отрядом (PartySystem) ──────────────────────────────────────

## Циклическая команда отряду по кнопке "party_command": переключает режим формации
## FREE → GATHER («Ко мне») → HOLD («Стоять») → FREE. Обрабатывается только активным
## (управляемым игроком) участником, поэтому вызывается из HUMAN-ветки _physics_process.
func _handle_party_command_input() -> void:
	if Input.is_action_just_pressed("party_command"):
		PartySystem.cycle_formation_mode()

## Переключает режим управления. Вызывается только из PartySystem.
## HUMAN добавляет узел в группу "player" (её ищут камера, HUD, AbilityManager),
## AI убирает из неё — при этом персонаж не замирает, а продолжает действовать сам.
func set_control_mode(mode: ControlMode) -> void:
	control_mode = mode
	if mode == ControlMode.HUMAN:
		if not is_in_group("player"):
			add_to_group("player")
	else:
		_has_move_target = false  # цель бега мышью актуальна только для управляемого игроком
		if is_in_group("player"):
			remove_from_group("player")

## Даёт временную неуязвимость после передачи управления, см. _post_switch_invuln_timer.
func grant_switch_invulnerability(duration: float) -> void:
	_post_switch_invuln_timer = max(_post_switch_invuln_timer, duration)

# ─── Доверие ────────────────────────────────────────────────────────────────

## Изменяет доверие на [param delta] (клампится в 0..100). При падении до нуля наёмник
## предаёт отряд или сбегает — решает PartySystem.on_trust_bottomed().
func modify_trust(delta: int) -> void:
	if _is_traitor or _is_fleeing:
		return
	var old_trust := trust
	trust = clampi(trust + delta, 0, 100)
	if trust == old_trust:
		return
	trust_changed.emit(trust)
	if trust == 0:
		PartySystem.on_trust_bottomed(self)

## Превращает наёмника во врага отряда. Вызывается только из PartySystem после удаления
## из состава: фракция становится HOSTILE_NPC, и ИИ начинает атаковать бывших товарищей
## (таргетинг у обеих сторон фракционный). Монстрам предатель не враждебен.
func turn_traitor() -> void:
	_is_traitor = true
	faction = Faction.Kind.HOSTILE_NPC
	remove_from_group("party")
	set_control_mode(ControlMode.AI)
	if _sprite != null:
		_sprite.set_tint(Color(1.0, 0.45, 0.45))

## Наёмник сбегает с поля боя: перестаёт сражаться, становится NEUTRAL (никто его
## не атакует), убегает от лидера и исчезает через FLEE_DESPAWN_TIME секунд.
## Вызывается только из PartySystem после удаления из состава.
func start_fleeing() -> void:
	_is_fleeing = true
	faction = Faction.Kind.NEUTRAL
	remove_from_group("party")
	remove_from_group("combatants")
	set_control_mode(ControlMode.AI)
	get_tree().create_timer(PlayerConstants.FLEE_DESPAWN_TIME).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				queue_free()
	)

## Ручной вызов способности этого участника (например, из радиального меню компаньона).
## Пока ничего не вызывает этот метод для не-активных союзников — они используют способности
## сами через ИИ (задел на будущее, см. trust) — но метод уже полностью рабочий.
func request_ability_use(slot_index: int) -> bool:
	return ability_manager.activate_ability(slot_index)

# ─── ИИ-поведение союзников (control_mode == AI) ───────────────────────────


var _ai_retarget_timer: float = 0.0
var _ai_cached_target: Node3D = null

# --- «Личность» движения союзника (задаётся в _seed_ai_personality) ---
## Личный множитель скорости следования: кто-то бодрее лидера, кто-то ленивее.
var _ai_speed_jitter: float = 1.0
## Стремление забегать вперёд по ходу движения лидера (0 — держится позади,
## 1 — норовит обогнать). Смещает точку следования вперёд, когда лидер идёт.
var _ai_eagerness: float = 0.5
## Личная комфортная дистанция следования (разброс вокруг AI_FOLLOW_DISTANCE).
var _ai_follow_distance: float = PlayerConstants.AI_FOLLOW_DISTANCE
## Параметры медленного бокового дрейфа точки следования — траектория «плавает»,
## а не тянется по линейке за лидером.
var _ai_sway_phase: float = 0.0
var _ai_sway_freq: float = 0.5
var _ai_sway_amp: float = 0.5
## С какой стороны лидера этот союзник пристраивается, когда идёт рядом (+1/-1).
var _ai_beside_side: float = 1.0
## > 0 — союзник недавно догнал сильное отставание и пока идёт рядом с лидером.
var _ai_beside_timer: float = 0.0
## > 0 — союзник сейчас уступает дорогу лидеру (шагает в сторону), см. _ai_try_yield.
var _ai_yield_timer: float = 0.0
## Гистерезис следования (см. AI_FOLLOW_STOP_FACTOR): true — союзник сейчас догоняет точку
## формации, false — стоит на месте. Переключается на разных порогах входа/выхода, чтобы
## не дёргаться туда-сюда у границы дистанции.
var _ai_is_following: bool = false
## Направление бокового шага при уступании дороги (мировые координаты, нормализовано).
var _ai_yield_dir: Vector3 = Vector3.ZERO
## Накопленное время ИИ — фаза для осцилляций дрейфа.
var _ai_time: float = 0.0
## Delta текущего физического кадра, проброшенная в ИИ-движение для плавного разгона/
## торможения (см. _ai_accelerate_to). Ставится в начале _physics_process.
var _ai_delta: float = 0.0

## Решает, атаковать ближайшую враждебную цель, следовать за лидером или убегать.
## Сама цель переоценивается раз в AI_RETARGET_INTERVAL, но сближение/атака идут каждый кадр.
func _ai_process(delta: float) -> void:
	_ai_time += delta
	if _ai_beside_timer > 0.0:
		_ai_beside_timer -= delta
	if _ai_yield_timer > 0.0:
		_ai_yield_timer -= delta
	if _is_fleeing:
		_ai_flee()
		return
	# Лекарь в составе отряда не сражается вовсе — только лечит и держится за лидером.
	# Предатель-лекарь теряет роль и дерётся как боец (иначе враг, который ничего не делает).
	if combat_role == CompanionData.Role.HEALER and PartySystem.members.has(self):
		_ai_healer_process(delta)
		return
	_ai_retarget_timer -= delta
	if _ai_retarget_timer <= 0.0:
		_ai_retarget_timer = PlayerConstants.AI_RETARGET_INTERVAL
		_ai_cached_target = _ai_find_target()
	if _ai_cached_target != null and is_instance_valid(_ai_cached_target):
		_ai_engage(_ai_cached_target)
	elif PartySystem.members.has(self):
		_ai_follow_or_hold()
	else:
		# Предатель без цели в радиусе — стоит на месте, за отрядом не ходит.
		_ai_hold_position()

## Вне боя: следовать за лидером либо стоять на месте — по режиму формации отряда.
## В режиме HOLD («Стоять здесь») союзник держит текущую позицию и за лидером не идёт;
## авто-бой в радиусе при этом сохраняется (см. _ai_process — engage идёт до этой ветки).
func _ai_follow_or_hold() -> void:
	if PartySystem.formation_mode == PartySystem.FormationMode.HOLD:
		_ai_hold_position()
	else:
		_ai_follow_leader()

## Возвращает ближайшую живую враждебную по фракции цель в радиусе AI_ENGAGE_RANGE.
## Фракционный поиск (не группа "enemies"): у лояльного союзника цели — монстры,
## у предателя (HOSTILE_NPC) — бывшие товарищи по отряду.
func _ai_find_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = PlayerConstants.AI_ENGAGE_RANGE
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if not _is_hostile_target(candidate):
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = candidate
	return nearest

## Бежит прочь от лидера отряда, пока таймер FLEE_DESPAWN_TIME не удалит узел.
func _ai_flee() -> void:
	var leader := PartySystem.get_active_member()
	if leader != null:
		_ai_move_away_from(leader.global_position)
	else:
		_ai_hold_position()

## Сближается/держит дистанцию до [param enemy] в зависимости от роли (ближний/дальний бой,
## определяется типом надетого оружия) и атакует, когда цель в радиусе атаки.
func _ai_engage(enemy: Node3D) -> void:
	var atk_range := _get_attack_range()
	var dist: float = global_position.distance_to(enemy.global_position)
	var is_ranged := _ai_is_ranged_role()
	var desired_range: float = atk_range * 0.85 if is_ranged else max(0.5, atk_range * 0.6)
	if dist > desired_range:
		# Расталкивание с соседями — чтобы бойцы окружали врага, а не толпились в одну точку.
		_ai_move_toward(enemy.global_position + _ai_separation())
	elif is_ranged and dist < desired_range * 0.5:
		_ai_move_away_from(enemy.global_position)
	else:
		_ai_hold_position()
	if dist <= atk_range and _attack_timer <= 0.0:
		_start_attack()


var _ai_heal_timer: float = 0.0

## Поведение лекаря: найти самого раненого живого участника отряда, подойти на дистанцию
## лечения и исцелять по кулдауну. Если лечить некого — держаться за лидером. Не атакует.
func _ai_healer_process(delta: float) -> void:
	if _ai_heal_timer > 0.0:
		_ai_heal_timer -= delta
	var patient := _ai_find_heal_target()
	if patient == null:
		_ai_follow_or_hold()
		return
	var dist: float = global_position.distance_to(patient.global_position)
	if dist > PlayerConstants.AI_HEAL_RANGE:
		_ai_move_toward(patient.global_position)
		return
	_ai_hold_position()
	# Разворачиваемся к пациенту (лечение самого себя направление не меняет).
	var to_patient: Vector3 = patient.global_position - global_position
	to_patient.y = 0.0
	if to_patient.length_squared() > 0.01:
		_last_move_dir = to_patient.normalized()
	if _ai_heal_timer <= 0.0:
		_ai_heal_timer = PlayerConstants.AI_HEAL_COOLDOWN
		patient.heal(_get_heal_power())

## Самый раненый (по доле HP) живой участник отряда ниже порога AI_HEAL_THRESHOLD,
## включая самого лекаря. null — если весь отряд достаточно здоров.
func _ai_find_heal_target() -> Player:
	var worst: Player = null
	var worst_ratio: float = PlayerConstants.AI_HEAL_THRESHOLD
	for member in PartySystem.members:
		if not is_instance_valid(member) or member.state == State.DEAD:
			continue
		var ratio: float = float(member.health) / float(member.max_health)
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst = member
	return worst

## Сила одного исцеления лекаря: масштабируется интеллектом, как урон — силой.
func _get_heal_power() -> int:
	return PlayerConstants.AI_HEAL_BASE_AMOUNT + int(float(get_total_stat("intellect")) / 2.0)

## true если в основной руке дальнобойное оружие — тогда ИИ держит дистанцию вместо сближения.
func _ai_is_ranged_role() -> bool:
	var weapon := equipment.get_equipped(EquipmentData.Slot.WEAPON_MAIN)
	return weapon != null and weapon.weapon_type == EquipmentData.WeaponType.RANGED

## Вне боя союзник держится рядом с активным (управляемым игроком) персонажем отряда,
## со смещением по формации — иначе все союзники сойдутся в одну точку и будут толкаться.
## Каждый следует чуть по-своему (личный темп, дистанция, дрейф, обгон) — см.
## _seed_ai_personality и _ai_follow_offset.
func _ai_follow_leader() -> void:
	var leader := PartySystem.get_active_member()
	if leader == null or leader == self:
		_ai_hold_position()
		return
	# Потерялся: лидер оторвался слишком далеко (застрял на геометрии, отстал за дверью
	# при смене зоны) — телепортируемся к нему, а не бежим напрямик через полкарты.
	var gap: Vector3 = leader.global_position - global_position
	gap.y = 0.0
	if gap.length() > PlayerConstants.AI_TELEPORT_DISTANCE:
		_ai_warp_near(leader)
		return
	# Вне боя уступаем дорогу: если лидер вплотную идёт прямо на нас, шагаем в сторону,
	# чтобы игрок не утыкался в товарища при исследовании территории.
	if _ai_try_yield(leader):
		return
	# Точка следования + расталкивание с соседями по отряду (separation): союзники сами
	# расходятся, а не слипаются в одну точку и толкаются физикой.
	var desired_pos: Vector3 = leader.global_position + _ai_follow_offset(leader) + _ai_separation()
	var dist: float = global_position.distance_to(desired_pos)
	# В режиме «Ко мне» (GATHER) жмёмся к лидеру — уменьшаем личную дистанцию следования.
	var follow_dist: float = _ai_follow_distance
	if PartySystem.formation_mode == PartySystem.FormationMode.GATHER:
		follow_dist *= PlayerConstants.AI_GATHER_DISTANCE_SCALE
	# Гистерезис: трогаемся, только выйдя за follow_dist; останавливаемся, лишь войдя внутрь
	# стоп-дистанции. Пока лидер стоит и точка формации не плавает (sway заморожен), союзник
	# спокойно стоит на месте вместо подползания у порога.
	var stop_dist: float = follow_dist * PlayerConstants.AI_FOLLOW_STOP_FACTOR
	if _ai_is_following:
		if dist <= stop_dist:
			_ai_is_following = false
	elif dist > follow_dist:
		_ai_is_following = true
	if not _ai_is_following:
		_ai_hold_position()
		return
	# Чем дальше отстал — тем быстрее догоняет (плавный разгон, а не скачок на пороге).
	# Потолок AI_MAX_CATCHUP_SCALE позволяет обогнать лидера и подтянуться рядом, а не
	# тащиться позади на его же скорости.
	var over: float = dist - stop_dist
	var speed_scale: float = clampf(1.0 + over * PlayerConstants.AI_CATCHUP_GAIN, 1.0, PlayerConstants.AI_MAX_CATCHUP_SCALE) * _ai_speed_jitter
	if dist > PlayerConstants.AI_FOLLOW_CATCHUP_DISTANCE:
		# Догнав сильное отставание, какое-то время идёт рядом с лидером, а не сваливается назад.
		_ai_beside_timer = PlayerConstants.AI_BESIDE_DURATION
	_ai_move_toward(desired_pos, speed_scale)

## Телепорт потерявшегося союзника на его место в формации рядом с лидером. Мгновенно
## гасит скорость и сбрасывает гистерезис — иначе он тут же снова «догоняет».
func _ai_warp_near(leader: Player) -> void:
	global_position = leader.global_position + _ai_follow_offset(leader)
	velocity = Vector3.ZERO
	_ai_is_following = false
	_ai_beside_timer = 0.0
	state = State.IDLE

## Вне боя союзник уступает дорогу лидеру: если тот подошёл вплотную и движется прямо на
## союзника, союзник делает шаг в сторону (перпендикулярно курсу лидера), освобождая путь.
## Возвращает true, пока уступает, — тогда обычное следование за лидером в этом кадре
## пропускается. Шаг удерживается AI_YIELD_DURATION секунд, чтобы движение не дёргалось.
func _ai_try_yield(leader: Player) -> bool:
	if _ai_yield_timer <= 0.0:
		var leader_dir: Vector3 = leader.velocity
		leader_dir.y = 0.0
		if leader_dir.length_squared() < PlayerConstants.AI_YIELD_LEADER_SPEED_SQ:
			return false  # лидер стоит — уступать некому
		var to_self: Vector3 = global_position - leader.global_position
		to_self.y = 0.0
		if to_self.length() > PlayerConstants.AI_YIELD_DISTANCE:
			return false  # лидер ещё далеко
		leader_dir = leader_dir.normalized()
		# Стоим ровно на лидере — уступаем перпендикулярно его курсу в любую сторону.
		var to_self_dir: Vector3 = to_self.normalized() if to_self.length_squared() > 0.0001 else leader_dir
		if leader_dir.dot(to_self_dir) < PlayerConstants.AI_YIELD_APPROACH_DOT:
			return false  # лидер идёт мимо, а не на нас — дорогу не перегораживаем
		# Шаг вбок: перпендикуляр к курсу лидера, в ту сторону, куда союзник уже смещён,
		# чтобы освободить путь кратчайшим движением.
		var side: Vector3 = leader_dir.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			return false
		side = side.normalized()
		if side.dot(to_self_dir) < 0.0:
			side = -side
		_ai_yield_dir = side
		_ai_yield_timer = PlayerConstants.AI_YIELD_DURATION
	# Активная фаза: делаем боковой шаг, освобождая дорогу.
	_ai_move_toward(global_position + _ai_yield_dir, PlayerConstants.AI_YIELD_SPEED_SCALE)
	return true

## Точка следования этого союзника относительно лидера. Формация повёрнута по курсу
## лидера (место в строю задано локально: x — вбок, z — назад), поэтому союзники держатся
## позади-сбоку, а не только строго по мировым осям. К месту добавляются личные поправки:
## - забегание вперёд по ходу движения — нетерпеливые подтягиваются вровень и обгоняют;
## - медленный боковой дрейф (синусоида) — путь слегка гуляет, а не тянется по линейке;
##   дрейф применяется ТОЛЬКО когда лидер идёт: на стоянке точка формации неподвижна, и
##   союзник спокойно стоит вместо бесконечного подползания в сторону.
## - после догона сильного отставания союзник идёт сбоку от лидера, плечом к плечу.
func _ai_follow_offset(leader: Player) -> Vector3:
	var leader_vel: Vector3 = leader.velocity
	leader_vel.y = 0.0
	var leader_moving: bool = leader_vel.length_squared() > 0.25

	# Курс лидера: направление движения, а стоя — куда он смотрит (_last_move_dir).
	var facing: Vector3 = leader_vel.normalized() if leader_moving else leader._last_move_dir
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > 0.01 else Vector3.BACK
	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	# Дрейф — только на ходу; на стоянке точка формации замирает (см. описание метода).
	var sway := Vector3.ZERO
	if leader_moving:
		sway = (right * sin(_ai_time * _ai_sway_freq + _ai_sway_phase)
			+ facing * cos(_ai_time * _ai_sway_freq * 0.8 + _ai_sway_phase * 1.7)) * _ai_sway_amp

	if _ai_beside_timer > 0.0 and leader_moving:
		# Идём плечом к плечу: точка сбоку от лидера, перпендикулярно его курсу.
		return right * (_ai_beside_side * 1.5) + sway * 0.5

	# Локальное место в строю → мировые координаты по курсу лидера (+z назад, x вбок).
	# В режиме «Ко мне» (GATHER) строй сжимается к лидеру.
	var local: Vector3 = _ai_formation_offset()
	if PartySystem.formation_mode == PartySystem.FormationMode.GATHER:
		local *= PlayerConstants.AI_GATHER_OFFSET_SCALE
	var offset: Vector3 = right * local.x - facing * local.z + sway
	if leader_moving:
		offset += facing * (_ai_eagerness * 2.5)  # нетерпеливые подтягиваются вперёд
	return offset

## Вектор расталкивания с ближайшими союзниками (separation): суммирует толчки «прочь» от
## каждого живого союзника-ИИ ближе AI_SEPARATION_RADIUS, тем сильнее, чем ближе сосед.
## Лидер (активный участник) исключён — дистанцию до него держит формация, а не separation.
## Складывается с точкой следования, поэтому даже стоящие союзники, оказавшись слишком
## близко, разъезжаются сами — до упора друг в друга физикой.
func _ai_separation() -> Vector3:
	var leader := PartySystem.get_active_member()
	var push := Vector3.ZERO
	for other in PartySystem.members:
		if other == self or other == leader or not is_instance_valid(other) or other.state == State.DEAD:
			continue
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		var d: float = away.length()
		if d >= PlayerConstants.AI_SEPARATION_RADIUS or d < 0.0001:
			continue
		# Линейный спад: вплотную — полная сила, на радиусе — ноль.
		push += away.normalized() * (1.0 - d / PlayerConstants.AI_SEPARATION_RADIUS)
	return push * PlayerConstants.AI_SEPARATION_STRENGTH


## Возвращает стабильное смещение по порядковому номеру этого союзника среди неактивных
## участников отряда — каждый союзник держит своё место в формации, а не общую точку.
func _ai_formation_offset() -> Vector3:
	var rank := 0
	for i in PartySystem.members.size():
		if i == PartySystem.active_index:
			continue
		if PartySystem.members[i] == self:
			return PlayerConstants.AI_FORMATION_OFFSETS[rank % PlayerConstants.AI_FORMATION_OFFSETS.size()]
		rank += 1
	return Vector3.ZERO

func _ai_move_toward(target_pos: Vector3, speed_scale: float = 1.0) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	_last_move_dir = dir
	_ai_accelerate_to(dir * (PlayerConstants.MOVE_SPEED * speed_scale))
	state = State.MOVE

func _ai_move_away_from(threat_pos: Vector3) -> void:
	var dir: Vector3 = global_position - threat_pos
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	_last_move_dir = -dir  # смотрим на цель, даже отступая от неё
	_ai_accelerate_to(dir * PlayerConstants.MOVE_SPEED)
	state = State.MOVE

## Плавно тянет горизонтальную скорость к [param target_vel] с ускорением AI_ACCEL —
## единая точка разгона/торможения для всего ИИ-движения (следование, бой, лечение,
## побег, остановка). Вертикальную скорость (гравитацию) не трогает.
func _ai_accelerate_to(target_vel: Vector3) -> void:
	var step: float = PlayerConstants.AI_ACCEL * _ai_delta
	velocity.x = move_toward(velocity.x, target_vel.x, step)
	velocity.z = move_toward(velocity.z, target_vel.z, step)

## Плавно гасит горизонтальную скорость до нуля и возвращает состояние в IDLE, когда
## союзнику некуда идти (цель в комфортной дистанции или лидер рядом).
func _ai_hold_position() -> void:
	_ai_accelerate_to(Vector3.ZERO)
	if state == State.MOVE and velocity.length_squared() < 0.01:
		state = State.IDLE

# ─── Инициализация и пересчёт статов ───────────────────────────────────────

## Инициализирует участника из его записи PartySystem.roster: раса, доверие, HP,
## quick slots, экипировка и эссенции. Числа приводятся через int() — запись могла
## пройти через JSON (сохранение), где все числа становятся float.
func _init_from_roster() -> void:
	var entry := PartySystem.get_roster_entry(roster_index)
	race = int(entry.get("race", GameManager.player_race))
	member_name = str(entry.get("name", GameManager.player_name))
	trust = int(entry.get("trust", 100))
	combat_role = int(entry.get("role", CompanionData.Role.FIGHTER))

	_seed_ai_personality()

	var stats := GameManager.get_race_base_stats(race as GameManager.Race)
	base_max_health = stats.get("max_health", 100)
	base_strength   = stats.get("strength", 10)
	base_agility    = stats.get("agility", 10)
	base_intellect  = stats.get("intellect", 10)
	# Расовый бонус HP за каждый уровень после первого — иначе перезаход в сцену
	# терял накопленную прибавку (base_max_health рос только по сигналу level_up).
	var level_bonus := GameManager.get_race_level_bonus(race as GameManager.Race)
	base_max_health += level_bonus.get("max_health", 0) * (XPSystem.current_level - 1)

	var saved_slots: Array = entry.get("quick_slots", [])
	if saved_slots.size() == quick_slots.size():
		for i in range(quick_slots.size()):
			quick_slots[i] = str(saved_slots[i])

	var equipment_data: Dictionary = entry.get("equipment", {})
	if not equipment_data.is_empty():
		equipment.deserialize(equipment_data)

	var inventory_data: Array = entry.get("inventory", [])
	if not inventory_data.is_empty():
		inventory.deserialize(inventory_data)

	essence.bonus_slots = int(entry.get("essence_bonus_slots", 0))
	essence.resize_to_level(XPSystem.current_level)
	var essence_paths: Array = entry.get("essences", [])
	for idx in range(min(essence_paths.size(), essence.slots.size())):
		var res_path = essence_paths[idx]
		if res_path != null and ResourceLoader.exists(str(res_path)):
			essence.slots[idx] = load(str(res_path)) as EssenceData
	if not essence_paths.is_empty():
		essence.slots_changed.emit()
		ability_manager.rebuild_from_slots()

	_recalculate_derived_stats()
	# health в roster: -1 (или отсутствие записи) = стартовать с полным HP.
	var saved_health := int(entry.get("health", -1))
	health = clampi(saved_health if saved_health > 0 else max_health, 1, max_health)
	health_changed.emit(health, max_health)

## Детерминированная «личность» движения: у каждого участника свой характер следования
## (темп, дистанция, дрейф, желание обгонять). Сид — из имени и места в roster, поэтому
## характер стабилен между кадрами и сменами сцен, но различается у разных наёмников.
func _seed_ai_personality() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(member_name) * 31 + roster_index
	_ai_speed_jitter = rng.randf_range(0.9, 1.15)
	_ai_eagerness = rng.randf()
	_ai_follow_distance = PlayerConstants.AI_FOLLOW_DISTANCE * rng.randf_range(0.7, 1.35)
	_ai_sway_phase = rng.randf_range(0.0, TAU)
	_ai_sway_freq = rng.randf_range(0.3, 0.7)
	_ai_sway_amp = rng.randf_range(0.25, 0.7)
	_ai_beside_side = 1.0 if rng.randf() < 0.5 else -1.0

func _on_level_up(_new_level: int) -> void:
	var bonus := GameManager.get_race_level_bonus(race as GameManager.Race)
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
		+ equipment.get_total_stat("max_health")
		+ essence.get_total_stat("max_health")
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

## То же, что _sum_add_modifiers, но без округления — для дробных статов (шанс крита и т.п.).
func _sum_add_modifiers_f(stat_name: String) -> float:
	var total: float = 0.0
	for modifier in _modifiers:
		if modifier.stat == stat_name and modifier.op == StatModifier.Op.ADD:
			total += modifier.value
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
