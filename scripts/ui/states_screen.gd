## Модальное окно состояний: все активные статусы активного участника отряда — блага
## слева, недуги справа, с глифом, названием, таймером и описанием. Открывается поверх
## боя из HUD (клик по статусу в ленте/панели или по «Показать все»), см. HUD._open_states_modal.
## Каркас модалки (пауза, блюр, закрытие по клавише "states"/крестику/фону/ESC) —
## в UIModalScreen. Показывает снимок на момент открытия; живой отсчёт идёт в ленте HUD.
extends UIModalScreen


@onready var _subtitle_label: Label = $CenterContainer/Panel/Margin/VBox/HeaderRow/TitleBox/SubtitleLabel
@onready var _buffs_count_label: Label = $CenterContainer/Panel/Margin/VBox/HeaderRow/BuffsCountLabel
@onready var _debuffs_count_label: Label = $CenterContainer/Panel/Margin/VBox/HeaderRow/DebuffsCountLabel
@onready var _buffs_header: Label = $CenterContainer/Panel/Margin/VBox/Columns/BuffsColumn/BuffsHeader
@onready var _debuffs_header: Label = $CenterContainer/Panel/Margin/VBox/Columns/DebuffsColumn/DebuffsHeader
@onready var _buffs_list: VBoxContainer = $CenterContainer/Panel/Margin/VBox/Columns/BuffsColumn/Scroll/BuffsList
@onready var _debuffs_list: VBoxContainer = $CenterContainer/Panel/Margin/VBox/Columns/DebuffsColumn/Scroll/DebuffsList

## Чьи состояния показаны. По умолчанию — активный (управляемый игроком) участник.
var _target_member: Player = null

var _icon_buff_style: StyleBoxFlat
var _icon_debuff_style: StyleBoxFlat

func _ready() -> void:
	# Когда экран скрыт, "states" (C) не поглощается (см. UIModalScreen) — его обработает
	# HUD, где C переключает свёрнутую панель состояний.
	screen_group = "states_screen"
	close_action = "states"
	super._ready()
	_build_icon_styles()

func open() -> void:
	_select_member(PartySystem.get_active_member())
	_show_modal()

func _select_member(member: Player) -> void:
	if member == null:
		return
	if _target_member != null and _target_member != member:
		if _target_member.statuses.statuses_changed.is_connected(_refresh):
			_target_member.statuses.statuses_changed.disconnect(_refresh)
	_target_member = member
	if not _target_member.statuses.statuses_changed.is_connected(_refresh):
		_target_member.statuses.statuses_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if _target_member == null:
		return
	var member_name: String = _target_member.member_name
	if member_name.is_empty():
		member_name = "Герой"
	_subtitle_label.text = "%s · всё, что сейчас влияет на тебя" % member_name

	var buffs: Array[Dictionary] = _target_member.statuses.get_buffs()
	var debuffs: Array[Dictionary] = _target_member.statuses.get_debuffs()
	_buffs_count_label.text = "▲ %d блага" % buffs.size()
	_debuffs_count_label.text = "▼ %d недуга" % debuffs.size()
	_buffs_header.text = "БЛАГА · %d" % buffs.size()
	_debuffs_header.text = "НЕДУГИ · %d" % debuffs.size()

	_populate(_buffs_list, buffs, StatesScreenConstants.BUFF_ACCENT, "Благ пока нет.")
	_populate(_debuffs_list, debuffs, StatesScreenConstants.DEBUFF_ACCENT, "Недугов пока нет.")

func _populate(list: VBoxContainer, entries: Array[Dictionary], accent: Color, empty_text: String) -> void:
	for child in list.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = empty_text
		empty.theme_type_variation = &"MutedLabel"
		empty.add_theme_font_size_override("font_size", 15)
		list.add_child(empty)
		return
	for entry in entries:
		list.add_child(_make_status_row(entry, accent))

func _make_status_row(entry: Dictionary, accent: Color) -> HBoxContainer:
	var data: StatusEffectData = entry.data
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	# Иконка-глиф в рамке.
	var icon := PanelContainer.new()
	icon.add_theme_stylebox_override("panel", _icon_buff_style if not data.is_debuff else _icon_debuff_style)
	icon.custom_minimum_size = Vector2(46, 46)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := Label.new()
	glyph.text = data.glyph
	glyph.add_theme_color_override("font_color", data.color)
	glyph.add_theme_font_size_override("font_size", 24)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(glyph)
	row.add_child(icon)

	# Текстовый блок: имя + таймер, ниже описание.
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 3)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	var timer_text: String = StatusComponent.format_remaining(entry.remaining)
	if not timer_text.is_empty():
		var timer_label := Label.new()
		timer_label.text = "⏱ %s" % timer_text
		timer_label.add_theme_color_override("font_color", accent)
		timer_label.add_theme_font_size_override("font_size", 16)
		timer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(timer_label)
	text_box.add_child(name_row)

	if not data.description.is_empty():
		var desc := Label.new()
		desc.text = data.description
		desc.theme_type_variation = &"MutedLabel"
		desc.add_theme_font_size_override("font_size", 15)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(desc)

	row.add_child(text_box)
	return row

func _build_icon_styles() -> void:
	_icon_buff_style = StyleBoxFlat.new()
	_icon_buff_style.bg_color = Color(0.078, 0.118, 0.071, 0.5)
	_icon_buff_style.border_width_left = 1
	_icon_buff_style.border_width_top = 1
	_icon_buff_style.border_width_right = 1
	_icon_buff_style.border_width_bottom = 1
	_icon_buff_style.border_color = Color(0.373, 0.62, 0.353, 0.4)
	_icon_buff_style.content_margin_left = 10
	_icon_buff_style.content_margin_top = 10
	_icon_buff_style.content_margin_right = 10
	_icon_buff_style.content_margin_bottom = 10

	_icon_debuff_style = StyleBoxFlat.new()
	_icon_debuff_style.bg_color = Color(0.133, 0.063, 0.055, 0.5)
	_icon_debuff_style.border_width_left = 1
	_icon_debuff_style.border_width_top = 1
	_icon_debuff_style.border_width_right = 1
	_icon_debuff_style.border_width_bottom = 1
	_icon_debuff_style.border_color = Color(0.659, 0.251, 0.184, 0.4)
	_icon_debuff_style.content_margin_left = 10
	_icon_debuff_style.content_margin_top = 10
	_icon_debuff_style.content_margin_right = 10
	_icon_debuff_style.content_margin_bottom = 10
