## Оверлей лавки: покупка у торговца и продажа предметов из рюкзака.
## Открывается вызовом open(vendor) — вызывается NPC-торговцем (см. vendor_npc.gd)
## через группу "shop_ui". Ставит игру на паузу, пока открыта (process_mode = WHEN_PAUSED
## позволяет самой панели продолжать реагировать на ввод).
extends CanvasLayer

@onready var _vendor_name_label: Label = $Dim/CenterContainer/Panel/Margin/VBoxContainer/HeaderRow/VendorNameLabel
@onready var _gold_label: Label = $Dim/CenterContainer/Panel/Margin/VBoxContainer/HeaderRow/GoldLabel
@onready var _buy_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ColumnsRow/BuyColumn/ScrollContainer/BuyList
@onready var _sell_list: VBoxContainer = $Dim/CenterContainer/Panel/Margin/VBoxContainer/ColumnsRow/SellColumn/ScrollContainer/SellList

var _current_vendor: VendorData = null
var _row_style_normal: StyleBoxFlat
var _row_style_hover: StyleBoxFlat

func _ready() -> void:
	add_to_group("shop_ui")
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_row_styles()
	hide()
	ShopSystem.item_bought.connect(func(_v, _i, _q) -> void: _refresh())
	ShopSystem.item_sold.connect(func(_i, _q) -> void: _refresh())
	# ESC снимает паузу через PauseManager напрямую (не через close()) — синхронизируемся,
	# чтобы панель не осталась висеть на экране поверх разблокированного мира.
	PauseManager.unpaused.connect(func() -> void: hide())

## Открывает лавку [param vendor] и ставит игру на паузу.
func open(vendor: VendorData) -> void:
	_current_vendor = vendor
	_vendor_name_label.text = vendor.display_name
	_refresh()
	show()
	PauseManager.pause()

## Закрывает лавку и снимает паузу.
func close() -> void:
	hide()
	_current_vendor = null
	PauseManager.unpause()

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
		_buy_list.add_child(_make_row(
			"%s — %d зол." % [item.display_name, item.buy_price],
			"Купить",
			func() -> void: ShopSystem.buy(_current_vendor, item, 1)
		))

func _rebuild_sell_list() -> void:
	for child in _sell_list.get_children():
		child.queue_free()
	for slot: Dictionary in InventorySystem.get_slots():
		var item: ItemData = slot.item
		if item.sell_price <= 0:
			continue
		_sell_list.add_child(_make_row(
			"%s x%d — %d зол." % [item.display_name, slot.quantity, item.sell_price],
			"Продать",
			func() -> void: ShopSystem.sell(item, 1)
		))

func _make_row(label_text: String, button_text: String, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.78, 0.71, 0.6, 1))
	row.add_child(label)

	var button := Button.new()
	button.text = button_text
	button.add_theme_stylebox_override("normal", _row_style_normal)
	button.add_theme_stylebox_override("hover", _row_style_hover)
	button.add_theme_color_override("font_color", Color(0.78, 0.71, 0.6, 1))
	button.add_theme_color_override("font_hover_color", Color(0.95, 0.83, 0.45, 1))
	button.pressed.connect(callback)
	row.add_child(button)

	return row

func _build_row_styles() -> void:
	_row_style_normal = StyleBoxFlat.new()
	_row_style_normal.bg_color = Color(0.039, 0.031, 0.035, 0.85)
	_row_style_normal.border_width_left = 1
	_row_style_normal.border_width_top = 1
	_row_style_normal.border_width_right = 1
	_row_style_normal.border_width_bottom = 1
	_row_style_normal.border_color = Color(0.471, 0.376, 0.212, 0.4)
	_row_style_normal.content_margin_left = 12
	_row_style_normal.content_margin_top = 4
	_row_style_normal.content_margin_right = 12
	_row_style_normal.content_margin_bottom = 4

	_row_style_hover = _row_style_normal.duplicate() as StyleBoxFlat
	_row_style_hover.bg_color = Color(0.588, 0.275, 0.141, 0.2)
	_row_style_hover.border_color = Color(0.55, 0.44, 0.25, 0.55)

func _on_close_pressed() -> void:
	close()
