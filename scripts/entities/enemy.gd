## Базовый враг: состояния IDLE → CHASE → ATTACK, система модификаторов статов.
## Наследуй от этого класса для создания специальных врагов (боссы, уникальные).
## Виртуальные методы для переопределения: _on_attack, _on_die.
extends CharacterBody3D
class_name Enemy

@export var data: EnemyData

var health: int
var _modifiers: Array[StatModifier] = []


var _regen_timer: float = 0.0
## Оставшийся кулдаун самолечения (data.self_heal_consumable), сек.
var _self_heal_cooldown: float = 0.0

var _retarget_timer: float = 0.0


## Угол этого врага в кольце окружения цели. Назначается детерминированно:
## все враги с той же целью сортируются по instance_id, ранг задаёт угол.
var _surround_angle: float = 0.0

enum State { IDLE, CHASE, ATTACK, DEAD }
var state: State = State.IDLE

## Копируется из data.faction в _ready(). Определяет, кто для этого врага враждебен
## (см. scripts/data/faction.gd) — заменяет прежний жёсткий таргетинг только на игрока.
var faction: Faction.Kind = Faction.Kind.MONSTER
## Ближайшая вражеская по фракции цель, переоценивается раз в RETARGET_INTERVAL.
var _target: Node3D = null
var _attack_cooldown: float = 0.0

## 2.5D-спрайт с 8 ракурсами. Может отсутствовать (тогда враг без визуала).
var _sprite: DirectionalSprite3D = null
## Навигационный агент для обхода препятствий. Может отсутствовать
## (тогда движение по прямой, как раньше).
var _nav_agent: NavigationAgent3D = null
## Полоска HP над головой (создаётся в _ready, обновляется по health_changed).
var _health_bar: EnemyHealthBar = null

signal died(enemy: Enemy)
signal health_changed(current: int, maximum: int)
## Испускается при смерти. LootSpawner слушает и спавнит обыскиваемое тело (LootableCorpse).
signal loot_dropped(items: Array, gold: int, at_position: Vector3)

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("combatants")
	_sprite = get_node_or_null("Sprite3D") as DirectionalSprite3D
	_nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	LootSpawner.register_enemy(self)
	if data == null:
		push_error("Enemy '%s': EnemyData не назначен" % name)
		return
	_apply_collision_profile()
	faction = data.faction
	if _sprite != null:
		_sprite.set_tint(data.sprite_tint)
	health = get_stat_int("max_health")
	_setup_health_bar()
	# Форсируем поиск цели на первом же _physics_process — не нужно ждать кадр
	# и проверять is_inside_tree(): периодический тик сам подхватит игрока,
	# как только тот появится в группе "combatants".
	_retarget_timer = EnemyConstants.RETARGET_INTERVAL

## Подгоняет физическую капсулу под ресурс конкретного типа врага. Shape дублируется,
## чтобы изменение гоблина не меняло все экземпляры общей PackedScene одновременно.
func _apply_collision_profile() -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not (collision_shape.shape is CapsuleShape3D):
		return
	var capsule := collision_shape.shape.duplicate() as CapsuleShape3D
	capsule.radius = maxf(data.collision_radius, 0.05)
	capsule.height = maxf(capsule.height, capsule.radius * 2.0)
	collision_shape.shape = capsule

func can_be_dodged_through() -> bool:
	return data != null and data.can_dodge_through

func get_body_mass() -> float:
	return data.mass if data != null else 70.0

func get_body_size() -> EnemyData.BodySize:
	return data.body_size if data != null else EnemyData.BodySize.MEDIUM

func get_knockback_resistance() -> float:
	return data.knockback_resistance if data != null else 0.0

## Создаёт полоску HP над головой и подписывает её на изменения здоровья.
func _setup_health_bar() -> void:
	_health_bar = EnemyHealthBar.new()
	add_child(_health_bar)
	_health_bar.position = Vector3(0.0, 2.15, 0.0)
	_health_bar.set_values(health, get_stat_int("max_health"))
	health_changed.connect(
		func(current: int, maximum: int) -> void:
			if is_instance_valid(_health_bar):
				_health_bar.set_values(current, maximum)
	)

## Всплывающее боевое число над врагом (урон/лечение), см. FloatingCombatText.
func _show_combat_text(amount: int, kind: int) -> void:
	FloatingCombatText.spawn(self, global_position + Vector3(0.0, 2.0, 0.0), amount, kind)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y += EnemyConstants.GRAVITY * delta
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	_tick_passive_regen(delta)
	_tick_self_heal(delta)
	_tick_retarget(delta)
	match state:
		State.IDLE:   _tick_idle()
		State.CHASE:  _tick_chase(delta)
		State.ATTACK: _tick_attack()
	_update_facing()
	move_and_slide()

## Разворачивает спрайт по движению; в покое/атаке — лицом к цели.
func _update_facing() -> void:
	if _sprite == null:
		return
	var face := Vector3(velocity.x, 0.0, velocity.z)
	if face.length_squared() < 0.01 and _target != null:
		face = _target.global_position - global_position
	_sprite.face_direction(face)

## Раз в RETARGET_INTERVAL секунд ищет ближайшую цель среди группы "combatants",
## враждебную по фракции (см. Faction.is_hostile). Периодический тик, а не разовый
## поиск при спавне — самовосстанавливается, если цель умерла или ещё не заспавнилась.
func _tick_retarget(delta: float) -> void:
	_retarget_timer += delta
	if _retarget_timer < EnemyConstants.RETARGET_INTERVAL:
		return
	_retarget_timer = 0.0
	_retarget()
	_update_surround_angle()

func _retarget() -> void:
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for candidate in get_tree().get_nodes_in_group("combatants"):
		if candidate == self or not is_instance_valid(candidate):
			continue
		if not ("faction" in candidate) or not Faction.is_hostile(faction, candidate.faction):
			continue
		# Трупы участников отряда остаются в сцене — не фиксируемся на них.
		if "health" in candidate and candidate.health <= 0:
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = candidate
	_target = nearest

## Распределяет врагов с общей целью по кольцу вокруг неё, чтобы они окружали,
## а не сливались в один маршрут. Децентрализованно: каждый сам считает свой ранг
## среди id всех врагов с той же целью — сортировка одинакова у всех, поэтому углы
## не конфликтуют без централизованного менеджера.
func _update_surround_angle() -> void:
	if _target == null:
		return
	var peer_ids: Array[int] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.state == State.DEAD or enemy._target != _target:
			continue
		peer_ids.append(enemy.get_instance_id())
	if peer_ids.size() <= 1:
		# Одиночка идёт на цель напрямую со своей стороны, кольцо не нужно.
		var to_self: Vector3 = global_position - _target.global_position
		_surround_angle = atan2(to_self.z, to_self.x)
		return
	peer_ids.sort()
	var rank: int = peer_ids.find(get_instance_id())
	_surround_angle = (float(rank) / float(peer_ids.size())) * TAU

## Точка на кольце вокруг цели, куда этот враг стремится при погоне.
func _surround_point() -> Vector3:
	var ring_radius: float = maxf(get_stat("attack_range") * EnemyConstants.SURROUND_RING_SCALE, 0.6)
	var offset := Vector3(cos(_surround_angle), 0.0, sin(_surround_angle)) * ring_radius
	return _target.global_position + offset

## Направление движения к точке окружения: через NavigationAgent3D, если он есть
## (обход препятствий), иначе по прямой.
func _chase_direction() -> Vector3:
	var destination: Vector3 = _surround_point()
	if _nav_agent != null:
		_nav_agent.target_position = destination
		var next_point: Vector3 = _nav_agent.get_next_path_position()
		var nav_dir: Vector3 = next_point - global_position
		nav_dir.y = 0.0
		if nav_dir.length_squared() > 0.001:
			return nav_dir.normalized()
	var direct: Vector3 = destination - global_position
	direct.y = 0.0
	if direct.length_squared() > 0.001:
		return direct.normalized()
	return Vector3.ZERO

## Вектор отталкивания от соседних врагов в радиусе SEPARATION_RADIUS.
## Чем ближе сосед, тем сильнее толчок (линейное затухание к краю радиуса).
func _separation_vector() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node):
			continue
		var other := node as Node3D
		if other == null:
			continue
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		var dist: float = away.length()
		if dist < 0.001 or dist > EnemyConstants.SEPARATION_RADIUS:
			continue
		push += (away / dist) * (1.0 - dist / EnemyConstants.SEPARATION_RADIUS)
	return push

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

## Данные для визуального трупа (LootableCorpse рисует затемнённый спрайт врага).
## Вызывается LootSpawner в момент гибели, пока враг ещё в сцене.
func get_death_visual() -> Dictionary:
	return {
		"texture": _sprite.texture if _sprite != null else null,
		"tint": data.sprite_tint if data != null else Color.WHITE,
	}

## Текущая цель врага (ближайший враждебный по фракции боец), или null.
## Публичный доступ для EnemyAbilityController и способностей.
func get_target() -> Node3D:
	if _target != null and is_instance_valid(_target):
		return _target
	return null

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

## Наносит урон с учётом защиты врага. Минимальный урон — 1.
## [param is_crit] = true рисует число красным и крупнее (крит определяет атакующий).
func take_damage(amount: int, is_crit: bool = false) -> void:
	if state == State.DEAD:
		return
	var actual_damage: int = max(1, amount - get_stat_int("defense"))
	health = max(0, health - actual_damage)
	health_changed.emit(health, get_stat_int("max_health"))
	_show_combat_text(actual_damage, FloatingCombatText.Kind.HIT_CRIT if is_crit else FloatingCombatText.Kind.HIT)
	if _sprite != null:
		_sprite.flash(Color(1.0, 0.2, 0.2))
	if health == 0:
		_die()

## Итоговый шанс крита атак этого врага (база data.crit_chance + модификаторы "crit_chance").
func get_attack_crit_chance() -> float:
	if data == null:
		return CombatMathConstants.BASE_CRIT_CHANCE
	return clampf(get_stat("crit_chance"), 0.0, CombatMathConstants.MAX_CRIT_CHANCE)

## Прибавка к шансу крита атакующего от ослаблений на этом враге (модификаторы
## "crit_vulnerability", доля 0.0–1.0). Так дебаффы делают врага уязвимее к криту.
func get_incoming_crit_bonus() -> float:
	var bonus: float = 0.0
	for modifier in _modifiers:
		if modifier.stat == "crit_vulnerability" and modifier.op == StatModifier.Op.ADD:
			bonus += modifier.value
	return bonus

## Восстанавливает HP, не превышая max_health. [param flash] = false подавляет вспышку
## (используется пассивной регенерацией, чтобы не мигать каждую секунду).
## [param is_crit] форсирует крит; иначе при flash==true крит бросается автоматически.
func heal(amount: int, flash: bool = true, is_crit: bool = false) -> void:
	if state == State.DEAD or amount <= 0:
		return
	# Лечение без вспышки (пассивная регенерация) не критует и не рисует число.
	var crit: bool = is_crit
	if flash and not crit:
		crit = CombatMath.roll_crit(self, self)
	var healed: int = CombatMath.apply_crit(amount) if crit else amount
	var max_hp: int = get_stat_int("max_health")
	var before: int = health
	health = min(max_hp, health + healed)
	health_changed.emit(health, max_hp)
	var real_gain: int = health - before
	if flash:
		if real_gain > 0:
			_show_combat_text(real_gain, FloatingCombatText.Kind.HEAL_CRIT if crit else FloatingCombatText.Kind.HEAL)
		if _sprite != null:
			_sprite.flash(Color(0.3, 1.0, 0.4))

## Раз в REGEN_TICK_INTERVAL секунд восстанавливает HP на величину стата "regen".
func _tick_passive_regen(delta: float) -> void:
	if state == State.DEAD:
		return
	_regen_timer += delta
	if _regen_timer < EnemyConstants.REGEN_TICK_INTERVAL:
		return
	_regen_timer = 0.0
	var regen: int = get_stat_int("regen")
	if regen > 0:
		heal(regen, false)

## Использует расходник самолечения (data.self_heal_consumable), когда HP падает
## ниже data.self_heal_threshold. Запас расходников не моделируется — только кулдаун.
func _tick_self_heal(delta: float) -> void:
	_self_heal_cooldown = max(0.0, _self_heal_cooldown - delta)
	if state == State.DEAD or data == null or data.self_heal_consumable == null or _self_heal_cooldown > 0.0:
		return
	if float(health) >= get_stat("max_health") * data.self_heal_threshold:
		return
	_self_heal_cooldown = data.self_heal_cooldown
	data.self_heal_consumable.apply(self)

func _base_stat(stat_name: String) -> float:
	match stat_name:
		"max_health":      return data.max_health
		"move_speed":      return data.move_speed
		"attack_damage":   return data.attack_damage + _weapon_bonus("damage")
		"attack_range":    return maxf(data.attack_range, _weapon_bonus("range"))
		"attack_cooldown": return data.attack_cooldown
		"detection_range": return data.detection_range
		"defense":         return data.defense + _weapon_bonus("defense")
		"crit_chance":     return data.crit_chance
	return 0.0

## Бонус стата [param bonus_name] от фиксированного оружия врага (data.equipped_weapon).
func _weapon_bonus(bonus_name: String) -> float:
	if data.equipped_weapon == null:
		return 0.0
	return float(data.equipped_weapon.stat_bonuses.get(bonus_name, 0.0))

# ─── Машина состояний ──────────────────────────────────────────────────────

func _tick_idle() -> void:
	if _target != null and is_instance_valid(_target) and global_position.distance_to(_target.global_position) <= get_stat("detection_range"):
		state = State.CHASE

func _tick_chase(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		state = State.IDLE
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= get_stat("attack_range"):
		velocity.x = 0.0
		velocity.z = 0.0
		state = State.ATTACK
		return
	if dist > get_stat("detection_range") * 1.5:
		state = State.IDLE
		return
	# Направление к своей точке окружения + отталкивание от соседей,
	# чтобы группа рассредоточивалась вокруг цели, а не сливалась в колонну.
	var dir: Vector3 = _chase_direction() + _separation_vector() * EnemyConstants.SEPARATION_WEIGHT
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		dir = dir.normalized()
	velocity.x = dir.x * get_stat("move_speed")
	velocity.z = dir.z * get_stat("move_speed")

func _tick_attack() -> void:
	if _target == null or not is_instance_valid(_target):
		state = State.IDLE
		return
	if global_position.distance_to(_target.global_position) > get_stat("attack_range"):
		state = State.CHASE
		return
	if _attack_cooldown <= 0.0:
		_attack_cooldown = get_stat("attack_cooldown")
		_on_attack(_target)

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
		# Золото и предметы кладутся в обыскиваемое тело (LootSpawner), а не выдаются сразу —
		# игрок должен подойти и обыскать труп, чтобы забрать лут.
		loot_dropped.emit(loot_items, gold_amount, global_position)
	_on_die()
	died.emit(self)
	queue_free()

## Переопределяй для кастомной атаки (дальний бой, AOE и т.д.).
## [param target] — Player или другой Enemy (см. Faction) с методом take_damage().
## Помимо урона накладывает data.attack_status (недуг), если он задан и цель его принимает.
func _on_attack(target: Node3D) -> void:
	if target.has_method("take_damage"):
		var base_dmg: int = get_stat_int("attack_damage")
		var is_crit: bool = CombatMath.roll_crit(self, target)
		target.take_damage(CombatMath.apply_crit(base_dmg) if is_crit else base_dmg, is_crit)
	if data != null and data.attack_status != null and target.has_method("apply_status_effect"):
		target.apply_status_effect(data.attack_status)

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
		if player.equipment.get_equipped(slot) != null and not player.equipment.is_slot_broken(slot):
			targets.append({"type": "slot", "key": slot})
	for idx in player.equipment.get_accessories().size():
		if not player.equipment.is_accessory_broken(idx):
			targets.append({"type": "acc", "key": idx})
	if targets.is_empty():
		return
	var chosen: Dictionary = targets[randi() % targets.size()]
	if chosen.type == "slot":
		player.equipment.break_equipped_item(chosen.key)
	else:
		player.equipment.break_accessory(chosen.key)
