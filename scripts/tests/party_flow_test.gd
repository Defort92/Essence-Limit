# Headless-тест цикла отряда: вербовка, доверие, сохранение.
# Запуск: godot --headless --path . "res://scenes/party_flow_test.tscn"
# Печатает PARTY_TEST_PASS/FAIL и завершает процесс с кодом 0/1.
# Слот сохранения 2 используется как временный: реальный сейв бэкапится и восстанавливается.
extends Node3D


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var failures: Array[String] = []

	# 1. Герой зарегистрирован как roster[0] и активен.
	if PartySystem.members.size() != 1:
		failures.append("members после спавна героя: %d (ожидался 1)" % PartySystem.members.size())
	if PartySystem.roster.size() != 1:
		failures.append("roster после спавна героя: %d (ожидался 1)" % PartySystem.roster.size())
	if PartySystem.get_active_member() == null:
		failures.append("нет активного участника")

	# 2. Вербовка наёмника.
	GameManager.add_gold(100)
	var data := load("res://resources/companions/mercenary_barbarian.tres") as CompanionData
	if not PartySystem.recruit(data):
		failures.append("recruit() вернул false")
	await get_tree().process_frame
	if PartySystem.members.size() != 2:
		failures.append("members после вербовки: %d (ожидалось 2)" % PartySystem.members.size())
	if GameManager.gold != 50:
		failures.append("золото после найма: %d (ожидалось 50)" % GameManager.gold)

	var companion: Player = null
	for member in PartySystem.members:
		if member.roster_index == 1:
			companion = member
	if companion == null:
		failures.append("наёмник не найден в members")
	else:
		if companion.trust != 50:
			failures.append("trust наёмника: %d (ожидалось 50)" % companion.trust)
		if companion.control_mode != Player.ControlMode.AI:
			failures.append("наёмник не в режиме AI")
		if companion.race != GameManager.Race.BARBARIAN:
			failures.append("раса наёмника: %d (ожидался варвар)" % companion.race)
		if companion.member_name != "Гром":
			failures.append("имя наёмника: '%s'" % companion.member_name)
		if companion.combat_role != CompanionData.Role.FIGHTER:
			failures.append("combat_role варвара: %d (ожидался FIGHTER)" % companion.combat_role)

		# В режиме «Ко мне» бой допустим рядом с лидером, но удалившийся союзник обязан
		# возвращаться до внутреннего порога (гистерезис), даже если цель ещё жива.
		var leader := PartySystem.get_active_member()
		var original_position := companion.global_position
		PartySystem.set_formation_mode(PartySystem.FormationMode.GATHER)
		companion.global_position = leader.global_position + Vector3(
			PlayerConstants.AI_GATHER_COMBAT_LEASH + 0.1, 0.0, 0.0
		)
		if not companion._ai_should_regroup():
			failures.append("режим «Ко мне» не прервал удалённый бой")
		companion.global_position = leader.global_position + Vector3(
			PlayerConstants.AI_GATHER_REENGAGE_DISTANCE + 0.1, 0.0, 0.0
		)
		if not companion._ai_should_regroup():
			failures.append("возврат к лидеру сбросился до внутреннего порога")
		companion.global_position = leader.global_position + Vector3(
			PlayerConstants.AI_GATHER_REENGAGE_DISTANCE - 0.1, 0.0, 0.0
		)
		if companion._ai_should_regroup():
			failures.append("союзник не вернулся к авто-бою рядом с лидером")
		companion.global_position = original_position
		PartySystem.set_formation_mode(PartySystem.FormationMode.FREE)

		# Боевой smoke-тест: боец действительно выбирает цель и наносит урон во всех
		# режимах. В HOLD дополнительно проверяется граница закреплённого поста.
		var enemy := Enemy.new()
		enemy.data = load("res://resources/enemies/goblin.tres") as EnemyData
		add_child(enemy)
		for mode in [
			PartySystem.FormationMode.FREE,
			PartySystem.FormationMode.GATHER,
			PartySystem.FormationMode.HOLD,
		]:
			PartySystem.set_formation_mode(mode)
			companion.global_position = leader.global_position + Vector3(1.0, 0.0, 0.0)
			enemy.global_position = companion.global_position + Vector3(-0.8, 0.0, 0.0)
			enemy.health = enemy.get_stat_int("max_health")
			companion.state = Player.State.IDLE
			companion._attack_timer = 0.0
			companion._ai_retarget_timer = 0.0
			companion._ai_cached_target = null
			var health_before := enemy.health
			companion._ai_process(PlayerConstants.AI_RETARGET_INTERVAL)
			if companion._ai_cached_target != enemy:
				failures.append("союзник не выбрал врага в режиме %d" % mode)
			if enemy.health >= health_before:
				failures.append("союзник не атаковал в режиме %d" % mode)

		# Даже если танк успел убежать, центром «Занять позицию» становится лидер,
		# а не место танка в момент приказа.
		companion.global_position = leader.global_position + Vector3(
			PlayerConstants.AI_HOLD_COMBAT_LEASH + 0.1, 0.0, 0.0
		)
		PartySystem.set_formation_mode(PartySystem.FormationMode.HOLD)
		var hold_anchor := PartySystem.hold_position
		if not hold_anchor.is_equal_approx(leader.global_position):
			failures.append("центр «Занять позицию» не совпал с позицией лидера")
		var hold_slot := companion._ai_hold_slot_position()
		if hold_slot.is_equal_approx(hold_anchor):
			failures.append("союзник занял центр вместо личной позиции рядом")
		if hold_slot.distance_to(hold_anchor) >= PlayerConstants.AI_HOLD_COMBAT_LEASH:
			failures.append("личная позиция союзника вышла за область обороны")
		enemy.global_position = hold_anchor + Vector3(
			PlayerConstants.AI_HOLD_COMBAT_LEASH + 0.1, 0.0, 0.0
		)
		if companion._ai_find_target() != null:
			failures.append("HOLD выбрал цель за границей поста")
		if not companion._ai_should_return_to_hold():
			failures.append("HOLD не вернул убежавшего союзника к позиции лидера")
		enemy.queue_free()
		companion.global_position = original_position
		companion.state = Player.State.IDLE
		PartySystem.set_formation_mode(PartySystem.FormationMode.FREE)

		# 3. Доверие в ноль → предаёт или сбегает, покидает отряд.
		companion.modify_trust(-50)
		if PartySystem.members.size() != 1:
			failures.append("наёмник не покинул members при trust=0")
		if PartySystem.roster.size() != 1:
			failures.append("запись наёмника не удалена из roster")
		if not (companion._is_traitor or companion._is_fleeing):
			failures.append("наёмник ни предатель, ни беглец")
		if companion._is_traitor and companion.faction != Faction.Kind.HOSTILE_NPC:
			failures.append("предатель не сменил фракцию")

	# 4. Вербовка лекаря: роль из CompanionData доходит до записи roster и спавненного участника.
	GameManager.add_gold(100)
	var healer_data := load("res://resources/companions/mercenary_healer.tres") as CompanionData
	if healer_data.combat_role != CompanionData.Role.HEALER:
		failures.append("ресурс mercenary_healer без роли HEALER")
	if not PartySystem.recruit(healer_data):
		failures.append("recruit(лекарь) вернул false")
	await get_tree().process_frame
	var healer: Player = null
	for member in PartySystem.members:
		if member.roster_index == 1:
			healer = member
	if healer == null:
		failures.append("лекарь не найден в members")
	elif healer.combat_role != CompanionData.Role.HEALER:
		failures.append("combat_role лекаря: %d (ожидался HEALER)" % healer.combat_role)

	# 5. Сохранение и загрузка состава (с бэкапом реального сейва в слоте 2).
	var backup_text := ""
	var had_real_save := SaveSystem.has_save(2)
	if had_real_save:
		var backup_file := FileAccess.open(PartyFlowTestConstants.TEST_SLOT_PATH, FileAccess.READ)
		if backup_file:
			backup_text = backup_file.get_as_text()
			backup_file.close()

	SaveSystem.save(2)
	PartySystem.reset()
	if not SaveSystem.load_game(2):
		failures.append("load_game(2) вернул false")
	if PartySystem.roster.size() != 2:
		failures.append("roster после загрузки: %d (ожидалось 2: герой + лекарь)" % PartySystem.roster.size())
	elif int(PartySystem.roster[1].get("role", -1)) != CompanionData.Role.HEALER:
		failures.append("роль лекаря не пережила сохранение/загрузку")

	if had_real_save:
		var restore_file := FileAccess.open(PartyFlowTestConstants.TEST_SLOT_PATH, FileAccess.WRITE)
		if restore_file:
			restore_file.store_string(backup_text)
			restore_file.close()
	else:
		SaveSystem.delete_save(2)

	if failures.is_empty():
		print("PARTY_TEST_PASS")
	else:
		for failure in failures:
			print("PARTY_TEST_FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
