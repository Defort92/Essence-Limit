extends Node3D


func _ready() -> void:
	var failures: Array[String] = []
	PartySystem.reset()

	var player_scene := load("res://scenes/characters/player.tscn") as PackedScene
	var hero := player_scene.instantiate() as Player
	add_child(hero)
	hero.global_position = Vector3.ZERO

	var companion_data := load("res://resources/companions/mercenary_barbarian.tres") as CompanionData
	PartySystem.add_companion(companion_data)
	await get_tree().process_frame
	var companion: Player = null
	for member in PartySystem.members:
		if member != hero:
			companion = member
	if companion == null:
		failures.append("не удалось создать союзника для collision-теста")
		_finish(failures)
		return

	var enemy_scene := load("res://scenes/characters/enemy_base.tscn") as PackedScene
	var enemy := enemy_scene.instantiate() as Enemy
	var goblin_data := (load("res://resources/enemies/goblin.tres") as EnemyData).duplicate(true) as EnemyData
	enemy.data = goblin_data
	add_child(enemy)
	var rear_enemy := enemy_scene.instantiate() as Enemy
	rear_enemy.data = goblin_data
	add_child(rear_enemy)

	# Отключаем автономные тики: тест сам переставляет тела и вызывает физические запросы.
	hero.set_physics_process(false)
	companion.set_physics_process(false)
	enemy.set_physics_process(false)
	rear_enemy.set_physics_process(false)
	hero.global_position = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	companion.velocity = Vector3.ZERO
	enemy.velocity = Vector3.ZERO
	rear_enemy.velocity = Vector3.ZERO
	companion.global_position = Vector3(20.0, 0.0, 0.0)
	enemy.global_position = Vector3(20.0, 0.0, 2.0)
	rear_enemy.global_position = Vector3(20.0, 0.0, 4.0)
	await get_tree().physics_frame

	if hero.collision_mask != 7:
		failures.append("маска игрока %d, ожидалась terrain|party|enemies (7)" % hero.collision_mask)
	if enemy.collision_mask != 7:
		failures.append("маска врага %d, ожидалась terrain|party|enemies (7)" % enemy.collision_mask)

	# Обычное движение физически блокируется врагом.
	enemy.global_position = Vector3(1.5, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var enemy_hit := hero.move_and_collide(Vector3(3.0, 0.0, 0.0), true)
	if enemy_hit == null or enemy_hit.get_collider() != enemy:
		failures.append("обычное движение прошло сквозь врага (hit=%s, hero_pos=%s, enemy_pos=%s, exceptions=%s)" % [
			enemy_hit.get_collider() if enemy_hit != null else null,
			hero.global_position,
			enemy.global_position,
			hero.get_collision_exceptions(),
		])

	# Обычное движение физически блокируется союзником.
	enemy.global_position = Vector3(20.0, 0.0, 2.0)
	companion.global_position = Vector3(1.5, 0.0, 0.0)
	await get_tree().physics_frame
	var ally_hit := hero.move_and_collide(Vector3(3.0, 0.0, 0.0), true)
	if ally_hit == null or ally_hit.get_collider() != companion:
		failures.append("обычное движение прошло сквозь союзника (hit=%s, ally_pos=%s)" % [
			ally_hit.get_collider() if ally_hit != null else null,
			companion.global_position,
		])

	# Разрешённого гоблина можно пересечь рывком, если конечная точка свободна.
	companion.global_position = Vector3(20.0, 0.0, 0.0)
	enemy.global_position = Vector3(1.3, 0.0, 0.0)
	rear_enemy.global_position = Vector3(20.0, 0.0, 4.0)
	goblin_data.can_dodge_through = true
	await get_tree().physics_frame
	hero._start_dodge(Vector3.RIGHT)
	if hero._dodge_distance_remaining < 2.8:
		failures.append("рывок не прошёл сквозь разрешённого гоблина: %.2f" % hero._dodge_distance_remaining)
	hero._finish_dodge()

	# Первый гоблин проходим, но второй стоит в расчётной точке: рывок проходит первого
	# и сокращается перед вторым, а не заканчивается внутри него.
	enemy.global_position = Vector3(1.0, 0.0, 0.0)
	rear_enemy.global_position = Vector3(3.0, 0.0, 0.0)
	await get_tree().physics_frame
	hero._start_dodge(Vector3.RIGHT)
	if hero._dodge_distance_remaining >= 2.8:
		failures.append("конечная точка рывка осталась внутри второго врага")
	if hero._dodge_distance_remaining <= 1.8:
		failures.append("второй враг помешал пересечь первого разрешённого врага")
	# Сокращение пути не сокращает окно состояния/неуязвимости.
	hero._tick_dodge(0.1)
	if hero._dodge_timer < 0.14 or not hero._is_invincible:
		failures.append("блокировка пути преждевременно завершила неуязвимость рывка")
	hero._finish_dodge()

	# Если между двумя телами нет безопасного места для всей капсулы с запасом,
	# пересечь даже первого нельзя: рывок заканчивается перед плотной группой.
	enemy.global_position = Vector3(1.3, 0.0, 0.0)
	rear_enemy.global_position = Vector3(3.0, 0.0, 0.0)
	await get_tree().physics_frame
	hero._start_dodge(Vector3.RIGHT)
	if hero._dodge_distance_remaining >= 1.0:
		failures.append("рывок втиснул игрока в слишком тесный промежуток между врагами")
	hero._finish_dodge()

	# Индивидуальный запрет полностью возвращает гоблина в физическую маску рывка.
	goblin_data.can_dodge_through = false
	rear_enemy.global_position = Vector3(20.0, 0.0, 4.0)
	enemy.global_position = Vector3(1.3, 0.0, 0.0)
	await get_tree().physics_frame
	hero._start_dodge(Vector3.RIGHT)
	if hero._dodge_distance_remaining >= 1.2:
		failures.append("рывок прошёл сквозь врага с can_dodge_through=false")
	hero._finish_dodge()

	# Союзник проходим в пути рывка, но также не может занимать конечную капсулу.
	goblin_data.can_dodge_through = true
	enemy.global_position = Vector3(20.0, 0.0, 2.0)
	companion.global_position = Vector3(1.3, 0.0, 0.0)
	await get_tree().physics_frame
	hero._start_dodge(Vector3.RIGHT)
	if hero._dodge_distance_remaining < 2.8:
		failures.append("рывок не прошёл сквозь союзника при свободной посадке")
	hero._finish_dodge()
	companion.global_position = Vector3(3.0, 0.0, 0.0)
	await get_tree().physics_frame
	hero._start_dodge(Vector3.RIGHT)
	if hero._dodge_distance_remaining >= 2.8:
		failures.append("рывок попытался закончиться внутри союзника")
	hero._finish_dodge()

	# Уступание выбирает свободную сторону: справа от союзника ставим стену, значит
	# результат должен уйти в противоположную полуплоскость.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 1.0)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	add_child(wall)
	hero.global_position = Vector3.ZERO
	companion.global_position = Vector3(1.0, 0.0, 0.0)
	enemy.global_position = Vector3(20.0, 0.0, 2.0)
	rear_enemy.global_position = Vector3(20.0, 0.0, 4.0)
	wall.global_position = companion.global_position + Vector3(0.0, 0.0, 0.9)
	await get_tree().physics_frame
	var yield_dir := companion._ai_choose_yield_direction(
		hero,
		Vector3.RIGHT,
		Vector3.RIGHT
	)
	if yield_dir == Vector3.ZERO or yield_dir.z >= 0.0:
		failures.append("союзник не выбрал свободную сторону от стены: %s" % yield_dir)

	# На достижимой дистанции удара союзник должен остановиться и продолжать бой,
	# а не воспринимать саму цель как препятствие и отходить от неё.
	wall.global_position = Vector3(20.0, 0.0, 8.0)
	hero.global_position = Vector3(20.0, 0.0, 0.0)
	companion.global_position = Vector3.ZERO
	enemy.global_position = Vector3(0.85, 0.0, 0.0)
	companion.velocity = Vector3.ZERO
	companion._attack_timer = 1.0
	await get_tree().physics_frame
	companion._ai_engage(enemy)
	var away_from_enemy := companion.global_position - enemy.global_position
	away_from_enemy.y = 0.0
	var combat_velocity := Vector3(companion.velocity.x, 0.0, companion.velocity.z)
	if combat_velocity.dot(away_from_enemy) > 0.01:
		failures.append("союзник отходит от достигнутой боевой цели: %s" % combat_velocity)

	# Враг попадает в lookahead раньше, чем союзник входит в attack_range. Он остаётся
	# физическим блокером, но как конечная цель не должен запускать боковой обход.
	enemy.global_position = Vector3(1.45, 0.0, 0.0)
	companion.velocity = Vector3.ZERO
	companion._ai_delta = 0.1
	await get_tree().physics_frame
	companion._ai_engage(enemy)
	var approach_velocity := Vector3(companion.velocity.x, 0.0, companion.velocity.z)
	var approach_direction := (enemy.global_position - companion.global_position).normalized()
	if approach_velocity.length_squared() < 0.01 \
			or approach_velocity.normalized().dot(approach_direction) < 0.9:
		failures.append("союзник обходит саму боевую цель вместо сближения: %s" % approach_velocity)
	for _approach_frame in 12:
		companion._ai_engage(enemy)
		companion.move_and_slide()
		await get_tree().physics_frame
	if companion.global_position.distance_to(enemy.global_position) > companion._get_attack_range() + 0.03:
		failures.append("союзник не вошёл в дальность удара за несколько кадров")
	if absf(companion.global_position.z) > 0.05:
		failures.append("союзник танцует вбок при прямом свободном сближении: z=%.3f" % companion.global_position.z)

	# Следующие проверки начинаются с уже достигнутой ближней дистанции.
	companion.global_position = Vector3.ZERO
	companion.velocity = Vector3.ZERO
	enemy.global_position = Vector3(0.85, 0.0, 0.0)
	await get_tree().physics_frame

	# Уступание в бою должно менять угол вокруг врага, сохраняя исходный радиус.
	hero.global_position = Vector3(-0.7, 0.0, 0.0)
	hero.velocity = Vector3.RIGHT * 3.0
	companion._ai_yield_cooldown = 0.0
	companion._ai_yield_active = false
	var combat_radius_before := companion.global_position.distance_to(enemy.global_position)
	var combat_yield := companion._ai_choose_yield_direction(
		hero,
		Vector3.RIGHT,
		Vector3.RIGHT,
		enemy
	)
	var yielded_position := companion.global_position + combat_yield
	var combat_radius_after := yielded_position.distance_to(enemy.global_position)
	if combat_yield == Vector3.ZERO:
		failures.append("союзник не нашёл допустимое уступание вокруг боевой цели")
	elif absf(combat_radius_after - combat_radius_before) > 0.03:
		failures.append("уступание изменило дистанцию до цели: %.3f -> %.3f" % [
			combat_radius_before,
			combat_radius_after,
		])

	# Прямой мягкий толчок от цели преобразуется в касательный, а не отменяет бой.
	companion._ai_cached_target = enemy
	var outward_push := (companion.global_position - enemy.global_position).normalized() * 2.0
	var constrained_push := companion._ai_constrain_soft_push_to_combat(outward_push)
	if constrained_push.dot(companion.global_position - enemy.global_position) > 0.01:
		failures.append("мягкий толчок продолжает выталкивать союзника от цели: %s" % constrained_push)

	# Сохранённая сторона обхода не должна уводить AI по дуге после исчезновения
	# препятствия и освобождения прямого пути.
	hero.global_position = Vector3(20.0, 0.0, 0.0)
	enemy.global_position = Vector3(20.0, 0.0, 2.0)
	companion._ai_avoidance_timer = 0.5
	companion._ai_avoidance_side = 1.0
	await get_tree().physics_frame
	var clear_steering := companion._ai_steer_around_obstacle(Vector3.RIGHT)
	if clear_steering.dot(Vector3.RIGHT) < 0.99:
		failures.append("AI продолжил обход после освобождения пути: %s" % clear_steering)

	# Спавнер обязан отвергать точку внутри любого боевого тела.
	var spawner := MobSpawner.new()
	add_child(spawner)
	hero.global_position = Vector3.ZERO
	await get_tree().physics_frame
	if spawner._is_spawn_position_clear(hero.global_position, 0.4):
		failures.append("спавнер признал занятую игроком точку свободной")
	if not spawner._is_spawn_position_clear(Vector3(30.0, 0.0, 30.0), 0.4):
		failures.append("спавнер не признал заведомо свободную точку доступной")

	# Прямой маршрут перекрыт статическим телом: локальный steering должен выбрать
	# боковую составляющую и за несколько шагов действительно провести капсулу вокруг.
	hero.global_position = Vector3(20.0, 0.0, 0.0)
	companion.global_position = Vector3.ZERO
	companion.velocity = Vector3.ZERO
	companion._ai_avoidance_timer = 0.0
	wall.global_position = Vector3(1.2, 0.0, 0.0)
	await get_tree().physics_frame
	var route_target := Vector3(3.5, 0.0, 0.0)
	var route_dir := companion._ai_navigation_direction(route_target)
	if route_dir == Vector3.ZERO or absf(route_dir.z) < 0.1:
		failures.append("локальный маршрут не обошёл препятствие: %s" % route_dir)
	var last_route_dir := Vector3.ZERO
	for _step in 60:
		companion._ai_delta = 0.1
		companion._ai_avoidance_timer = maxf(0.0, companion._ai_avoidance_timer - 0.1)
		last_route_dir = companion._ai_navigation_direction(route_target)
		companion._ai_move_toward(route_target)
		companion.move_and_slide()
		await get_tree().physics_frame
	if companion.global_position.x <= 1.8:
		var slide_normals: Array[Vector3] = []
		for collision_index in companion.get_slide_collision_count():
			slide_normals.append(companion.get_slide_collision(collision_index).get_normal())
		failures.append("союзник не прошёл вокруг препятствия: pos=%s dir=%s vel=%s" % [
			companion.global_position,
			last_route_dir,
			"%s normals=%s" % [companion.velocity, slide_normals],
		])

	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("ENTITY_COLLISION_TEST_PASS")
	else:
		for failure in failures:
			print("ENTITY_COLLISION_TEST_FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
