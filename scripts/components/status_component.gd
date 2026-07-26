## Компонент активных статус-эффектов существа (благ и недугов). Живёт дочерним узлом
## Player (как Equipment/Essence/Abilities). Пока статус активен — накладывает его
## StatModifier'ы на родителя через apply_modifier/remove_modifiers_by_source, ведёт
## таймеры длительности и испускает statuses_changed для UI (экран состояний, HUD).
extends Node
class_name StatusComponent

## Активный статус: { data: StatusEffectData, remaining: float, source_id: String }.
## remaining < 0 у постоянных статусов (не тикают, живут до ручного снятия).
var _active: Array[Dictionary] = []

## Родитель, к которому применяются модификаторы (обычно Player). Кэшируется в _ready.
var _owner: Node = null

## Монотонный счётчик для уникальных source_id — чтобы source_id двух разных наложений
## не совпал при снятии модификаторов.
var _next_uid: int = 0


signal statuses_changed()

func _ready() -> void:
	_owner = get_parent()

func _process(delta: float) -> void:
	if _active.is_empty():
		return
	var expired: Array[Dictionary] = []
	for entry in _active:
		var remaining: float = entry.remaining
		if remaining < 0.0:
			continue  # постоянный статус — не тикает
		remaining -= delta
		entry.remaining = remaining
		if remaining <= 0.0:
			expired.append(entry)
	if expired.is_empty():
		return
	for entry in expired:
		_remove_entry(entry)
	statuses_changed.emit()

## Накладывает статус [param data]. Если статус с тем же id уже активен — обновляет его
## таймер (refresh), а не дублирует: типичный кейс для дебафа, накладываемого каждой атакой.
func apply_status(data: StatusEffectData) -> void:
	if data == null:
		return
	for entry in _active:
		var existing: StatusEffectData = entry.data
		if existing.id == data.id:
			entry.remaining = data.duration if data.duration > 0.0 else -1.0
			statuses_changed.emit()
			return
	var source_id: String = "status_%s_%d" % [data.id, _next_uid]
	_next_uid += 1
	var entry: Dictionary = {
		"data": data,
		"remaining": data.duration if data.duration > 0.0 else -1.0,
		"source_id": source_id,
	}
	_active.append(entry)
	_apply_modifiers(data, source_id)
	statuses_changed.emit()

## Снимает статус по [param id] (например, когда ушёл источник-аура). Ничего, если нет.
func remove_status(id: String) -> void:
	for entry in _active:
		var existing: StatusEffectData = entry.data
		if existing.id == id:
			_remove_entry(entry)
			statuses_changed.emit()
			return

## Снимает все статусы (например, при выходе из подземелья или возрождении).
func clear_all() -> void:
	if _active.is_empty():
		return
	for entry in _active:
		_clear_modifiers(entry.source_id)
	_active.clear()
	statuses_changed.emit()

## Раздаёт демо-набор статусов (благ и недугов) — заглушка «как будто выдали на уровне»,
## чтобы экран состояний и панель HUD были наполнены до появления реальных источников.
func grant_demo_statuses() -> void:
	for path in StatusComponentConstants.DEMO_STATUSES:
		if ResourceLoader.exists(path):
			apply_status(load(path) as StatusEffectData)

## Активные благи (is_debuff == false), в порядке наложения.
func get_buffs() -> Array[Dictionary]:
	return _filter(false)

## Активные недуги (is_debuff == true), в порядке наложения.
func get_debuffs() -> Array[Dictionary]:
	return _filter(true)

func has_any() -> bool:
	return not _active.is_empty()

func _filter(want_debuff: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _active:
		var existing: StatusEffectData = entry.data
		if existing.is_debuff == want_debuff:
			result.append(entry)
	return result

func _remove_entry(entry: Dictionary) -> void:
	_clear_modifiers(entry.source_id)
	_active.erase(entry)

## Возвращает узел-владельца (родителя), к которому применяются модификаторы.
## Разрешается лениво — на случай, если статус наложат до _ready компонента.
func _get_owner_node() -> Node:
	if _owner == null:
		_owner = get_parent()
	return _owner

func _apply_modifiers(data: StatusEffectData, source_id: String) -> void:
	var owner_node: Node = _get_owner_node()
	if owner_node == null or not owner_node.has_method("apply_modifier"):
		return
	for modifier in data.modifiers:
		# Копируем модификатор, чтобы у каждого наложения был свой source_id для снятия.
		var copy := StatModifier.new()
		copy.stat = modifier.stat
		copy.op = modifier.op
		copy.value = modifier.value
		copy.source_id = source_id
		owner_node.apply_modifier(copy)

func _clear_modifiers(source_id: String) -> void:
	var owner_node: Node = _get_owner_node()
	if owner_node != null and owner_node.has_method("remove_modifiers_by_source"):
		owner_node.remove_modifiers_by_source(source_id)

## Форматирует оставшееся время статуса для UI: "12с", "1:05" или "" для постоянного.
static func format_remaining(remaining: float) -> String:
	if remaining < 0.0:
		return ""
	var secs: int = int(ceil(remaining))
	if secs >= 60:
		return "%d:%02d" % [int(float(secs) / 60.0), secs % 60]
	return "%dс" % secs
