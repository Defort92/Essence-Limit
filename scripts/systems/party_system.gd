## Управляет отрядом на двух уровнях:
## - roster — персистентный состав (Array[Dictionary]): переживает смену сцены и попадает
##   в сохранение. Индекс 0 — всегда главный герой. Наёмники добавляются через recruit().
## - members — живые Player-узлы текущей сцены. Пересоздаются каждой сценой: статический
##   Player сцены регистрируется как герой, остальных PartySystem доспавнивает из roster.
## Активный участник управляется игроком, остальные — ИИ. При смерти активного управление
## переходит к следующему живому; если умерли все — вайп (GameManager.on_player_died()).
## Доверие: при падении trust наёмника до 0 он предаёт (становится врагом) или сбегает.
## Является Autoload-синглтоном; регистрировать как "PartySystem" в Project Settings.
extends Node

const MAX_PARTY_SIZE: int = 5
## Сколько секунд новый активный участник неуязвим после переключения — защита от
## мгновенной смерти, если управление передали посреди боя.
const SWITCH_INVULNERABILITY_DURATION: float = 1.2
## На сколько падает доверие каждого наёмника, когда участник отряда погибает.
const TRUST_LOSS_ON_MEMBER_DEATH: int = 15
## Шанс предательства (иначе побег) при падении доверия до нуля.
const BETRAYAL_CHANCE: float = 0.5

const COMPANION_SCENE_PATH := "res://scenes/characters/player.tscn"

## Персистентные данные участников. Ключи записи:
## race:int, name:String, trust:int, role:int (CompanionData.Role),
## health:int (-1 = полное HP),
## quick_slots:Array, equipment:Dictionary (EquipmentManager.serialize),
## inventory:Array (InventoryComponent.serialize — личный рюкзак, включая золото-предмет),
## essence_bonus_slots:int, essences:Array (пути ресурсов или null).
var roster: Array[Dictionary] = []
var members: Array[Player] = []
var active_index: int = -1

## Режим позиционирования отряда — циклическая команда одной кнопкой (см.
## Player._handle_party_command_input). FREE — свободное следование за лидером с личной
## формацией; GATHER («Ко мне») — тугой строй вплотную к лидеру; HOLD («Стоять здесь») —
## союзники не следуют за лидером, держат текущую позицию (бой в радиусе не отключается).
enum FormationMode { FREE, GATHER, HOLD }
var formation_mode: FormationMode = FormationMode.FREE

signal active_member_changed(old_member: Player, new_member: Player)
signal party_wiped()
signal member_recruited(roster_index: int)
## [param betrayed] true — участник стал врагом; false — сбежал с поля боя.
signal member_left(member: Player, betrayed: bool)
## Сменился режим формации отряда (для HUD-индикатора и т.п.).
signal formation_mode_changed(mode: FormationMode)

# ─── Регистрация и спавн ────────────────────────────────────────────────────

## Вызывается каждым Player из _ready(). Узел с roster_index == -1 — статический Player
## сцены, он считается героем (roster[0]); наёмникам roster_index назначается до add_child.
## Первый зарегистрированный становится активным, остальные — ИИ-союзниками.
func register_member(member: Player) -> void:
	if members.has(member):
		return
	if members.size() >= MAX_PARTY_SIZE:
		push_warning("PartySystem: отряд уже полон (%d/%d), '%s' не добавлен" % [members.size(), MAX_PARTY_SIZE, member.name])
		return
	if member.roster_index == -1:
		if roster.is_empty():
			roster.append(_make_roster_entry(GameManager.player_race, GameManager.player_name, 100))
		member.roster_index = 0
	members.append(member)
	member.died.connect(_on_member_died.bind(member))
	member.tree_exiting.connect(_on_member_exiting.bind(member))
	if active_index == -1:
		active_index = members.size() - 1
		member.set_control_mode(Player.ControlMode.HUMAN)
		# Герой зашёл в новую сцену — доспавнить остальной отряд рядом с ним.
		if member.roster_index == 0 and roster.size() > 1:
			call_deferred("_spawn_missing_companions", member)
	else:
		member.set_control_mode(Player.ControlMode.AI)

## Спавнит Player-узлы для записей roster, у которых ещё нет живого экземпляра в сцене.
func _spawn_missing_companions(hero: Player) -> void:
	if not is_instance_valid(hero) or not hero.is_inside_tree():
		return
	for idx in range(1, roster.size()):
		if _find_member_by_roster_index(idx) != null:
			continue
		_spawn_companion(idx, hero)

func _spawn_companion(roster_idx: int, near: Player) -> void:
	var packed := load(COMPANION_SCENE_PATH) as PackedScene
	var companion := packed.instantiate() as Player
	companion.roster_index = roster_idx
	near.get_parent().add_child(companion)
	companion.global_position = near.global_position + Vector3(1.5 * roster_idx, 0.0, 1.2)

func _find_member_by_roster_index(roster_idx: int) -> Player:
	for member in members:
		if member.roster_index == roster_idx:
			return member
	return null

# ─── Вербовка ───────────────────────────────────────────────────────────────

## Нанимает наёмника [param data] за золото. Спавнит его рядом с активным участником.
## Возвращает [code]false[/code] если отряд полон или не хватает золота.
func recruit(data: CompanionData) -> bool:
	if roster.size() >= MAX_PARTY_SIZE or get_active_member() == null:
		return false
	if not GameManager.spend_gold(data.hire_cost):
		return false
	return add_companion(data)

## Добавляет наёмника [param data] в отряд бесплатно (стартовые союзники сцены,
## скриптовые события). Спавнит его рядом с активным участником.
## Возвращает [code]false[/code] если отряд полон или в сцене нет активного участника.
func add_companion(data: CompanionData) -> bool:
	if roster.size() >= MAX_PARTY_SIZE:
		return false
	var leader := get_active_member()
	if leader == null:
		return false
	roster.append(_make_roster_entry(data.race, data.display_name, data.initial_trust, data.combat_role))
	var new_index := roster.size() - 1
	_spawn_companion(new_index, leader)
	member_recruited.emit(new_index)
	return true

## true если в отряде уже есть участник с именем [param member_name] —
## защита от повторного добавления стартовых союзников при перезаходе в сцену.
func has_member_named(member_name: String) -> bool:
	for entry in roster:
		if str(entry.get("name", "")) == member_name:
			return true
	return false

# ─── Активный участник ──────────────────────────────────────────────────────

## Возвращает текущего активного (управляемого игроком) участника, или null если отряд вайпнут.
func get_active_member() -> Player:
	if active_index < 0 or active_index >= members.size():
		return null
	return members[active_index]

## Рюкзак активного участника. У каждого персонажа свой инвентарь (Player.inventory) —
## лут с монстров, находки и покупки у торговца по умолчанию попадают именно сюда.
## null, если активного участника нет (отряд вайпнут).
func get_active_inventory() -> InventoryComponent:
	var member := get_active_member()
	return member.inventory if member != null else null

# ─── Формация (команда отряду) ──────────────────────────────────────────────

## Переключает режим формации по кругу FREE → GATHER → HOLD → FREE. Вызывается активным
## (управляемым игроком) участником по нажатию кнопки команды отряду.
func cycle_formation_mode() -> void:
	formation_mode = ((formation_mode + 1) % FormationMode.size()) as FormationMode
	formation_mode_changed.emit(formation_mode)

## Человекочитаемое имя режима формации (для HUD).
static func formation_mode_name(mode: FormationMode) -> String:
	match mode:
		FormationMode.GATHER: return "Ко мне"
		FormationMode.HOLD: return "Стоять"
		_: return "Свободно"

# ─── Активный участник ──────────────────────────────────────────────────────

## Передаёт управление участнику с индексом [param index] в members. Не действует,
## если он мёртв или уже активен.
func switch_active(index: int) -> void:
	if index < 0 or index >= members.size():
		return
	var new_member := members[index]
	if new_member.state == Player.State.DEAD:
		return
	var old_member := get_active_member()
	if old_member == new_member:
		return
	if old_member != null:
		old_member.set_control_mode(Player.ControlMode.AI)
	new_member.set_control_mode(Player.ControlMode.HUMAN)
	new_member.grant_switch_invulnerability(SWITCH_INVULNERABILITY_DURATION)
	active_index = index
	active_member_changed.emit(old_member, new_member)

# ─── Доверие: предательство и побег ─────────────────────────────────────────

## Вызывается из Player.modify_trust() при падении доверия до нуля.
## Герой (roster[0]) не может предать сам себя; наёмник либо становится врагом,
## либо сбегает с поля боя и исчезает.
func on_trust_bottomed(member: Player) -> void:
	if member.roster_index <= 0 or not members.has(member):
		return
	var betrayed: bool = randf() < BETRAYAL_CHANCE
	_remove_from_party(member)
	if betrayed:
		member.turn_traitor()
	else:
		member.start_fleeing()
	member_left.emit(member, betrayed)
	# Если предал/сбежал сам активный участник — передать управление следующему живому,
	# иначе игрок останется без управляемого персонажа при живом отряде.
	if get_active_member() == null and not members.is_empty():
		_switch_to_next_alive()

## Удаляет участника из roster и members, поправляя roster_index остальных и active_index.
## Сам узел не удаляется — дальнейшая судьба (предатель/беглец) решается вызывающим кодом.
func _remove_from_party(member: Player) -> void:
	var removed_idx := member.roster_index
	var active_member := get_active_member()
	if removed_idx >= 0 and removed_idx < roster.size():
		roster.remove_at(removed_idx)
	for other in members:
		if other != member and other.roster_index > removed_idx:
			other.roster_index -= 1
	member.roster_index = -1
	if member.died.is_connected(_on_member_died):
		member.died.disconnect(_on_member_died)
	if member.tree_exiting.is_connected(_on_member_exiting):
		member.tree_exiting.disconnect(_on_member_exiting)
	members.erase(member)
	active_index = members.find(active_member)

# ─── Смерть и вайп ──────────────────────────────────────────────────────────

func _on_member_died(member: Player) -> void:
	# Гибель товарища бьёт по доверию оставшихся наёмников.
	for other in members:
		if other != member and other.state != Player.State.DEAD and other.roster_index > 0:
			other.modify_trust(-TRUST_LOSS_ON_MEMBER_DEATH)
	if get_active_member() != member:
		return
	_switch_to_next_alive()

func _switch_to_next_alive() -> void:
	for i in members.size():
		if members[i].state != Player.State.DEAD:
			switch_active(i)
			return
	active_index = -1
	party_wiped.emit()
	GameManager.on_player_died()

# ─── Персистентность (смена сцены и сохранения) ─────────────────────────────

## При выходе узла из дерева (смена сцены) сохраняем его состояние в roster,
## чтобы новый экземпляр в следующей сцене продолжил с того же места.
func _on_member_exiting(member: Player) -> void:
	_store_member_state(member)
	var active_member := get_active_member()
	members.erase(member)
	if members.is_empty():
		active_index = -1
	elif active_member == member:
		active_index = 0
	else:
		active_index = members.find(active_member)

## Записывает текущее состояние живого участника в его запись roster.
func _store_member_state(member: Player) -> void:
	if member.roster_index < 0 or member.roster_index >= roster.size():
		return
	var entry: Dictionary = roster[member.roster_index]
	entry["race"] = member.race
	entry["name"] = member.member_name
	entry["trust"] = member.trust
	# Павшие возрождаются при смене сцены с полным HP (лор: время в подземелье течёт
	# иначе). Полный вайп обрабатывается отдельно через party_wiped.
	entry["health"] = -1 if member.state == Player.State.DEAD else member.health
	entry["quick_slots"] = member.quick_slots.duplicate()
	entry["equipment"] = member.equipment.serialize()
	entry["inventory"] = member.inventory.serialize()
	entry["essence_bonus_slots"] = member.essence.bonus_slots
	var essence_paths := []
	for slot_essence in member.essence.slots:
		essence_paths.append(slot_essence.resource_path if slot_essence != null else null)
	entry["essences"] = essence_paths

## Возвращает запись roster для [param roster_idx], или пустой словарь если индекс вне диапазона.
func get_roster_entry(roster_idx: int) -> Dictionary:
	if roster_idx < 0 or roster_idx >= roster.size():
		return {}
	return roster[roster_idx]

## Сериализует состав отряда для SaveSystem (предварительно синхронизировав живых участников).
func serialize() -> Dictionary:
	for member in members:
		_store_member_state(member)
	return { "roster": roster.duplicate(true) }

## Восстанавливает состав отряда из сохранения. Вызывать до смены сцены:
## живые экземпляры инициализируются из roster при следующем register_member.
func deserialize(data: Dictionary) -> void:
	roster.clear()
	for entry in data.get("roster", []):
		if entry is Dictionary:
			roster.append(entry)

## Полный сброс (новая игра). Живые узлы очистятся сами при смене сцены.
func reset() -> void:
	roster.clear()
	active_index = -1
	formation_mode = FormationMode.FREE

func _make_roster_entry(race: int, member_name: String, trust: int, role: int = CompanionData.Role.FIGHTER) -> Dictionary:
	return {
		"race": int(race),
		"name": member_name,
		"trust": trust,
		"role": int(role),
		"health": -1,
		"quick_slots": ["", "", "", ""],
		"equipment": {},
		"inventory": [],
		"essence_bonus_slots": 0,
		"essences": [],
	}
