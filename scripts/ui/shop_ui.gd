## Оверлей лавки: покупка у торговца и продажа предметов из рюкзака.
## Открывается вызовом open(vendor) — вызывается NPC-торговцем (см. vendor_npc.gd)
## через группу "shop_ui". Каркас модалки (пауза, закрытие крестиком/ESC) — в UIModalScreen.
extends UIModalScreen

@onready var _vendor_name_label: Label = $Dim/CenterContainer/Panel/Margin/VBoxContainer/HeaderRow/VendorNameLabel
@onready var _gold_label: Label = $Dim/CenterContainer/Panel/Margin/VBoxContainer/HeaderRow/GoldLabel
@onready var _buy_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ColumnsRow/BuyColumn/ScrollContainer/BuyList
@onready var _sell_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ColumnsRow/SellColumn/ScrollContainer/SellList

var _current_vendor: VendorData = null

func _ready() -> void:
	screen_group = "shop_ui"
	super._ready()
	ShopSystem.item_bought.connect(func(_v, _i, _q) -> void: _refresh())
	ShopSystem.item_sold.connect(func(_i, _q) -> void: _refresh())

## Открывает лавку [param vendor] и ставит игру на паузу.
func open(vendor: VendorData) -> void:
	_current_vendor = vendor
	_vendor_name_label.text = vendor.display_name
	_refresh()
	_show_modal()

func _before_close() -> void:
	_current_vendor = null

func _refresh() -> void:
	_gold_label.text = "Золото: %d" % GameManager.gold
	_rebuild_buy_list()
	_rebuild_sell_list()

func _rebuild_buy_list() -> void:
	for child in _buy_list.get_children():
		child.queue_free()
	if _current_vendor == null:
		return
	for item: ItemData in _current_vendor.stock:
		_buy_list.add_child(UIListRow.create(
			"%s — %d зол." % [item.display_name, item.buy_price],
			[{"text": "Купить", "callback": func() -> void: ShopSystem.buy(_current_vendor, item, 1)}]
		))

func _rebuild_sell_list() -> void:
	for child in _sell_list.get_children():
		child.queue_free()
	var inv := PartySystem.get_active_inventory()
	if inv == null:
		return
	for slot: Dictionary in inv.get_slots():
		var item: ItemData = slot.item
		if item.sell_price <= 0:
			continue
		_sell_list.add_child(UIListRow.create(
			"%s x%d — %d зол." % [item.display_name, slot.quantity, item.sell_price],
			[{"text": "Продать", "callback": func() -> void: ShopSystem.sell(item, 1)}]
		))
