## Экран персонажа: экипировка, рюкзак, эссенции — в одном окне.
## Одно и то же окно показывает ЛЮБОГО участника отряда — вкладки в MemberTabsRow
## переключают, чьи данные отображаются (_target_member). Рюкзак, экипировка и эссенции —
## свои у каждого персонажа (см. Player.inventory/equipment/essence).
## Открывается/закрывается клавишей "inventory" (I). Каркас модалки — в UIModalScreen.
extends UIModalScreen

const SLOT_NAMES := {
	EquipmentData.Slot.HEAD: "Голова",
	EquipmentData.Slot.BODY: "Тело",
	EquipmentData.Slot.LEGS: "Ноги",
	EquipmentData.Slot.GLOVES: "Перчатки",
	EquipmentData.Slot.WEAPON_MAIN: "Оружие",
	EquipmentData.Slot.WEAPON_OFF: "Вторая рука",
}
## Порядок отображения основных слотов экипировки (аксессуары показываются отдельно).
const ARMOR_SLOTS := [
	EquipmentData.Slot.HEAD, EquipmentData.Slot.BODY,
	EquipmentData.Slot.LEGS, EquipmentData.Slot.GLOVES,
	EquipmentData.Slot.WEAPON_MAIN, EquipmentData.Slot.WEAPON_OFF,
]

@onready var _member_tabs: HBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/MemberTabsRow
@onready var _equipment_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ColumnsRow/EquipmentColumn/ScrollContainer/EquipmentList
@onready var _inventory_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ColumnsRow/InventoryColumn/ScrollContainer/InventoryList
@onready var _essence_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ColumnsRow/EssenceColumn/ScrollContainer/EssenceList

## Чьё снаряжение/эссенции сейчас показаны. По умолчанию — активный (управляемый игроком).
var _target_member: Player = null

func _ready() -> void:
	screen_group = "character_screen"
	close_action = "inventory"
	super._ready()

## Клавиша "inventory" при скрытом экране открывает его (экран-переключатель).
func _on_action_while_hidden() -> void:
	open()
	get_viewport().set_input_as_handled()

## [param member] — кого показать сразу (клик по портрету в HUD/панели отряда).
## По умолчанию (null) — активный участник, как при открытии клавишей "inventory".
func open(member: Player = null) -> void:
	_select_member(member if member != null else PartySystem.get_active_member())
	_show_modal()

func _on_state_changed() -> void:
	if visible:
		_refresh()

## Переключает, чьи экипировка/эссенции отображаются. Отписывается от предыдущего
## участника и подписывается на нового, чтобы _refresh() шёл на актуальные сигналы.
func _select_member(member: Player) -> void:
	if member == null:
		return
	if _target_member != null and _target_member != member:
		if _target_member.equipment.equipment_changed.is_connected(_on_state_changed):
			_target_member.equipment.equipment_changed.disconnect(_on_state_changed)
		if _target_member.essence.slots_changed.is_connected(_on_state_changed):
			_target_member.essence.slots_changed.disconnect(_on_state_changed)
		if _target_member.inventory.inventory_changed.is_connected(_on_state_changed):
			_target_member.inventory.inventory_changed.disconnect(_on_state_changed)
	_target_member = member
	if not _target_member.equipment.equipment_changed.is_connected(_on_state_changed):
		_target_member.equipment.equipment_changed.connect(_on_state_changed)
	if not _target_member.essence.slots_changed.is_connected(_on_state_changed):
		_target_member.essence.slots_changed.connect(_on_state_changed)
	if not _target_member.inventory.inventory_changed.is_connected(_on_state_changed):
		_target_member.inventory.inventory_changed.connect(_on_state_changed)
	_rebuild_member_tabs()
	_refresh()

func _refresh() -> void:
	_rebuild_equipment_list()
	_rebuild_inventory_list()
	_rebuild_essence_list()

# ─── Вкладки участников отряда ──────────────────────────────────────────────

func _rebuild_member_tabs() -> void:
	for child in _member_tabs.get_children():
		child.queue_free()
	for idx in PartySystem.members.size():
		var member: Player = PartySystem.members[idx]
		var label_text: String = member.member_name
		if label_text.is_empty():
			label_text = "Герой" if member.roster_index == 0 else "Союзник %d" % idx
		_member_tabs.add_child(UIListRow.make_button(
			label_text,
			func() -> void: _select_member(member),
			member == _target_member
		))

# ─── Экипировка ────────────────────────────────────────────────────────────

func _rebuild_equipment_list() -> void:
	for child in _equipment_list.get_children():
		child.queue_free()

	var target_equipment: EquipmentManager = _target_member.equipment
	for slot: EquipmentData.Slot in ARMOR_SLOTS:
		var item: EquipmentData = target_equipment.get_equipped(slot)
		var label_name: String = SLOT_NAMES.get(slot, "?")
		if item == null:
			_equipment_list.add_child(UIListRow.create("%s: пусто" % label_name))
			continue
		if target_equipment.is_slot_broken(slot):
			var cost: int = target_equipment.get_repair_cost(slot)
			_equipment_list.add_child(UIListRow.create(
				"%s: %s [сломано]" % [label_name, item.display_name],
				[{"text": "Починить (%d зол.)" % cost, "callback": func() -> void: target_equipment.repair_slot(slot)}]
			))
		else:
			_equipment_list.add_child(UIListRow.create(
				"%s: %s" % [label_name, item.display_name],
				[{"text": "Снять", "callback": func() -> void: target_equipment.unequip_slot(slot)}]
			))

	var accessories: Array[EquipmentData] = target_equipment.get_accessories()
	for idx in accessories.size():
		var item: EquipmentData = accessories[idx]
		if target_equipment.is_accessory_broken(idx):
			var cost: int = target_equipment.get_accessory_repair_cost(idx)
			_equipment_list.add_child(UIListRow.create(
				"Аксессуар: %s [сломано]" % item.display_name,
				[{"text": "Починить (%d зол.)" % cost, "callback": func() -> void: target_equipment.repair_accessory(idx)}]
			))
		else:
			_equipment_list.add_child(UIListRow.create(
				"Аксессуар: %s" % item.display_name,
				[{"text": "Снять", "callback": func() -> void: target_equipment.unequip_accessory(idx)}]
			))
	for _idx in (EquipmentManager.MAX_ACCESSORIES - accessories.size()):
		_equipment_list.add_child(UIListRow.create("Аксессуар: пусто"))

# ─── Рюкзак (общий на весь отряд) ───────────────────────────────────────────

func _rebuild_inventory_list() -> void:
	for child in _inventory_list.get_children():
		child.queue_free()

	var target_equipment: EquipmentManager = _target_member.equipment
	var target_essence: EssenceSystem = _target_member.essence
	for slot: Dictionary in _target_member.inventory.get_slots():
		var item: ItemData = slot.item
		var quantity: int = slot.quantity
		var label_text: String = "%s x%d" % [item.display_name, quantity]
		var actions: Array = []

		if item is EquipmentData:
			actions.append({"text": "Надеть", "callback": func() -> void: target_equipment.equip_from_inventory(item as EquipmentData)})
		elif item is EssenceData:
			actions.append({"text": "Установить", "callback": func() -> void: target_essence.equip_from_inventory(item as EssenceData)})
		elif item is ConsumableData:
			for quick_idx in 4:
				actions.append({
					"text": str(quick_idx + 1),
					"callback": func() -> void: _assign_quick_slot(quick_idx, item.id),
				})

		_inventory_list.add_child(UIListRow.create(label_text, actions))

func _assign_quick_slot(slot_idx: int, item_id: String) -> void:
	_target_member.set_quick_slot(slot_idx, item_id)

# ─── Эссенции ──────────────────────────────────────────────────────────────

func _rebuild_essence_list() -> void:
	for child in _essence_list.get_children():
		child.queue_free()

	var target_essence: EssenceSystem = _target_member.essence
	for idx in target_essence.slots.size():
		if target_essence.is_slot_locked(idx):
			_essence_list.add_child(UIListRow.create("Слот %d: заблокирован" % (idx + 1)))
			continue
		var slot_essence: EssenceData = target_essence.slots[idx]
		if slot_essence == null:
			_essence_list.add_child(UIListRow.create("Слот %d: пусто" % (idx + 1)))
		else:
			_essence_list.add_child(UIListRow.create(
				"Слот %d: %s" % [idx + 1, slot_essence.display_name],
				[{"text": "Снять (%d зол.)" % slot_essence.removal_cost, "callback": func() -> void: target_essence.remove(idx)}]
			))
