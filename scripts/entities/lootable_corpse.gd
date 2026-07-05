## Обыскиваемое тело: контейнер с лутом, который игрок открывает по клавише "interact"
## (F), находясь рядом. Открывает общий экран лута (группа "loot_ui").
##
## Два режима наполнения:
##  - Враг: плоский список предметов (loot_items) + золото (loot_gold). Сам враг уже
##    удалён из сцены, лут был скатан в его _die() — контейнер просто хранит результат.
##  - Павший союзник: ссылка на его Player-узел (source_player). Предметы берутся прямо из
##    его экипировки; «взять» = снять слот (уходит в общий рюкзак через EquipmentManager).
##    Экипировку НЕ копируем заранее: незалутанное снаряжение остаётся на союзнике и
##    переживёт его возрождение при смене сцены (см. PartySystem._store_member_state).
extends Area3D
class_name LootableCorpse

## Радиус, в котором появляется подсказка «F — Обыскать».
const DETECT_RADIUS: float = 1.6

## Русские названия слотов экипировки для отображения в списке лута.
const SLOT_NAMES := {
	EquipmentData.Slot.HEAD: "Голова",
	EquipmentData.Slot.BODY: "Тело",
	EquipmentData.Slot.LEGS: "Ноги",
	EquipmentData.Slot.GLOVES: "Перчатки",
	EquipmentData.Slot.WEAPON_MAIN: "Оружие",
	EquipmentData.Slot.WEAPON_OFF: "Вторая рука",
}
const ARMOR_SLOTS := [
	EquipmentData.Slot.HEAD, EquipmentData.Slot.BODY,
	EquipmentData.Slot.LEGS, EquipmentData.Slot.GLOVES,
	EquipmentData.Slot.WEAPON_MAIN, EquipmentData.Slot.WEAPON_OFF,
]

## Плоский лут врага: массив { "item": ItemData, "quantity": int }.
var loot_items: Array = []
var loot_gold: int = 0
## Павший союзник — источник экипировки (опционально). Взаимоисключим с loot_items по смыслу.
var source_player: Player = null
var corpse_name: String = "Тело"

## Спрайт врага для визуального трупа (у союзника не используется — его тело остаётся в сцене).
var corpse_texture: Texture2D = null
var corpse_tint: Color = Color.WHITE

var _player_in_range: bool = false
var _prompt: Label3D = null

## Испускается при изменении содержимого — экран лута переподхватывает список.
signal loot_changed()

func _ready() -> void:
	add_to_group("lootable")
	collision_layer = 0
	collision_mask = 1  # слой игрока/персонажей
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = DETECT_RADIUS
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_changed)
	body_exited.connect(_on_body_changed)

	if corpse_texture != null:
		_spawn_corpse_sprite()

	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.pixel_size = 0.01
	_prompt.position = Vector3(0.0, 1.4, 0.0)
	_prompt.modulate = Color(0.85, 0.72, 0.4)
	add_child(_prompt)

	if source_player != null and is_instance_valid(source_player):
		source_player.equipment.equipment_changed.connect(_on_source_changed)
	_update_prompt()

## Рисует затемнённый спрайт погибшего врага как «труп»-маркер на месте гибели.
## Настройки (billboard/pixel_size/фильтр) — как у живого спрайта, но приглушённый цвет.
func _spawn_corpse_sprite() -> void:
	var sprite := Sprite3D.new()
	sprite.texture = corpse_texture
	sprite.pixel_size = 0.015
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.position = Vector3(0.0, 0.6, 0.0)
	var dim := corpse_tint.darkened(0.55)
	dim.a = 0.85
	sprite.modulate = dim
	add_child(sprite)

func _on_body_changed(_body: Node3D) -> void:
	_refresh_range()

## Пересчитывает наличие живого игрока-мародёра в радиусе. Исключает сам труп-источник
## (мёртвый союзник стоит внутри своего же радиуса) и павших/предателей.
func _refresh_range() -> void:
	_player_in_range = false
	for body in get_overlapping_bodies():
		if _is_valid_looter(body):
			_player_in_range = true
			break
	_update_prompt()

func _is_valid_looter(body: Node) -> bool:
	if not (body is Player) or body == source_player:
		return false
	return (body as Player).state != Player.State.DEAD

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or is_empty():
		return
	if event.is_action_pressed("interact"):
		var ui := get_tree().get_first_node_in_group("loot_ui")
		if ui != null and ui.has_method("open"):
			ui.open(self)
			get_viewport().set_input_as_handled()

func _on_source_changed() -> void:
	loot_changed.emit()
	_update_prompt()

func _update_prompt() -> void:
	if _prompt == null:
		return
	if is_empty():
		_prompt.text = ""
	elif _player_in_range:
		_prompt.text = "F — Обыскать"
	else:
		_prompt.text = "◆"

# ─── Контракт лута (используется loot_ui.gd) ────────────────────────────────

## Возвращает список записей для отображения. Каждая запись:
## { "text": String, "kind": "item"/"equip_slot"/"equip_acc", "key": Variant }.
func get_loot_entries() -> Array:
	var entries: Array = []
	for idx in loot_items.size():
		var entry: Dictionary = loot_items[idx]
		var item: ItemData = entry.item
		entries.append({
			"text": "%s x%d" % [item.display_name, int(entry.quantity)],
			"kind": "item",
			"key": idx,
		})
	if source_player != null and is_instance_valid(source_player):
		var eq: EquipmentManager = source_player.equipment
		for slot: EquipmentData.Slot in ARMOR_SLOTS:
			var item: EquipmentData = eq.get_equipped(slot)
			if item != null:
				var label: String = SLOT_NAMES.get(slot, "?")
				entries.append({
					"text": "%s: %s" % [label, item.display_name],
					"kind": "equip_slot",
					"key": slot,
				})
		var accessories: Array[EquipmentData] = eq.get_accessories()
		for acc_idx in accessories.size():
			entries.append({
				"text": "Аксессуар: %s" % accessories[acc_idx].display_name,
				"kind": "equip_acc",
				"key": acc_idx,
			})
	return entries

## Перекладывает запись [param entry] в общий рюкзак. Возвращает [code]false[/code],
## если рюкзак полон (предмет остаётся в теле).
func take_entry(entry: Dictionary) -> bool:
	var taken := false
	match entry.kind:
		"item":
			var idx: int = entry.key
			if idx < 0 or idx >= loot_items.size():
				return false
			var slot: Dictionary = loot_items[idx]
			if InventorySystem.add_item(slot.item, int(slot.quantity)):
				loot_items.remove_at(idx)
				taken = true
		"equip_slot":
			# unequip_slot сам кладёт предмет в общий рюкзак (или вернёт false если полон).
			taken = source_player != null and is_instance_valid(source_player) \
				and source_player.equipment.unequip_slot(entry.key)
		"equip_acc":
			taken = source_player != null and is_instance_valid(source_player) \
				and source_player.equipment.unequip_accessory(entry.key)
	if taken:
		loot_changed.emit()
		_update_prompt()
	return taken

## Забирает всё, что помещается в рюкзак. Останавливается, когда рюкзак полон.
func take_all() -> void:
	take_gold()
	var progressed := true
	while progressed:
		progressed = false
		# Список пересобирается после каждого взятия: индексы/слоты меняются.
		for entry in get_loot_entries():
			if take_entry(entry):
				progressed = true
				break

func get_loot_gold() -> int:
	return loot_gold

func take_gold() -> void:
	if loot_gold <= 0:
		return
	GameManager.add_gold(loot_gold)
	loot_gold = 0
	loot_changed.emit()
	_update_prompt()

## true если в теле не осталось ни предметов, ни золота.
func is_empty() -> bool:
	if loot_gold > 0 or not loot_items.is_empty():
		return false
	if source_player != null and is_instance_valid(source_player):
		return not source_player.equipment.has_any_equipped()
	return true

## Удаляет пустой контейнер. Тело павшего союзника (Player-узел) при этом не трогается —
## удаляется только сам контейнер лута.
func despawn() -> void:
	queue_free()
