## Панель отряда «ОТРЯД» на основном экране: компактные карточки союзников (все участники
## PartySystem, кроме активного — тот показан крупно в левом верхнем углу HUD). На карточке —
## портрет с рамкой по «настроению» (производное от доверия), уровень, точка-индикатор,
## полоса HP, имя и подпись состояния. Значения обновляются по таймеру, полная пересборка —
## только при смене состава (спавн/уход союзников, смена активного).
extends Control


@onready var _cards_column: VBoxContainer = $Root/CardsColumn

## Карточки по id участника: портрет, рамка, уровень, индикатор и полоса HP.
var _cards: Dictionary = {}
## Снимок состава (id участников), по которому строится текущая раскладка — для дешёвой
## проверки, не изменился ли отряд, без ежекадровой пересборки.
var _member_ids: Array[int] = []
var _accum: float = 0.0

func _process(delta: float) -> void:
	_accum += delta
	if _accum < PartyPanelConstants.REFRESH_INTERVAL:
		return
	_accum = 0.0
	var members := _visible_members()
	var ids: Array[int] = []
	for m in members:
		ids.append(m.get_instance_id())
	if ids != _member_ids:
		_rebuild(members)
	else:
		_update_values(members)

## Участники отряда, показываемые на панели: все, кроме активного (тот — крупно в HUD).
func _visible_members() -> Array[Player]:
	var result: Array[Player] = []
	var active := PartySystem.get_active_member()
	for member in PartySystem.members:
		if is_instance_valid(member) and member != active:
			result.append(member)
	return result

func _rebuild(members: Array[Player]) -> void:
	for child in _cards_column.get_children():
		child.queue_free()
	_cards.clear()
	_member_ids.clear()
	for member in members:
		_member_ids.append(member.get_instance_id())
		_cards_column.add_child(_build_card(member))
	_update_values(members)
	visible = not members.is_empty()

func _build_card(member: Player) -> Control:
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(
		PartyPanelConstants.PORTRAIT_SIZE,
		PartyPanelConstants.PORTRAIT_SIZE
	)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.alignment = BoxContainer.ALIGNMENT_CENTER

	# --- Портрет с рамкой, уровнем, точкой-индикатором и полосой HP ---
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(PartyPanelConstants.PORTRAIT_SIZE, PartyPanelConstants.PORTRAIT_SIZE)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# STOP (не IGNORE, как у остальных декоративных детей карточки) — портрет кликабелен,
	# открывает экран персонажа/инвентаря для этого союзника.
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	portrait.gui_input.connect(_on_portrait_input.bind(member))

	var bg := _make_portrait_image(member)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(bg)

	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style_border := StyleBoxFlat.new()
	style_border.bg_color = Color(0, 0, 0, 0)
	style_border.set_border_width_all(2)
	border.add_theme_stylebox_override("panel", style_border)
	portrait.add_child(border)

	var level_label := Label.new()
	level_label.position = Vector2(2, 0)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_color_override("font_color", PartyPanelConstants.LEVEL_COLOR)
	level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	level_label.add_theme_font_size_override("font_size", 12)
	portrait.add_child(level_label)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(11, 11)
	dot.position = Vector2(PartyPanelConstants.PORTRAIT_SIZE - 7, -4)
	dot.size = Vector2(11, 11)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style_dot := StyleBoxFlat.new()
	style_dot.set_corner_radius_all(6)
	style_dot.set_border_width_all(2)
	style_dot.border_color = Color(0.051, 0.039, 0.043)
	dot.add_theme_stylebox_override("panel", style_dot)
	portrait.add_child(dot)

	# Полоса HP по нижней кромке портрета.
	var hp_bar := ColorRect.new()
	hp_bar.color = PartyPanelConstants.HP_BG
	hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hp_bar.offset_top = -7
	hp_bar.offset_bottom = 0
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(hp_bar)

	var hp_fill := ColorRect.new()
	hp_fill.color = PartyPanelConstants.HP_FILL
	hp_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	hp_fill.anchor_right = 1.0
	hp_fill.offset_right = 0
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.add_child(hp_fill)

	card.add_child(portrait)

	_cards[member.get_instance_id()] = {
		"portrait": portrait,
		"style_border": style_border,
		"level_label": level_label,
		"style_dot": style_dot,
		"hp_fill": hp_fill,
	}
	return card

## Портрет союзника из его спрайта (кадр «лицом»), либо тёмная заглушка, если спрайта нет.
func _make_portrait_image(member: Player) -> Control:
	var sprite := member.get_node_or_null("Sprite3D") as DirectionalSprite3D
	if sprite != null and sprite.tex_front != null:
		var tex := TextureRect.new()
		tex.texture = PortraitUtils.make_face_texture(sprite.tex_front)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.clip_contents = true
		return tex
	var placeholder := ColorRect.new()
	placeholder.color = PartyPanelConstants.PORTRAIT_BG
	return placeholder

## Обновляет динамические поля карточек (уровень, HP, настроение) без пересборки узлов.
func _update_values(members: Array[Player]) -> void:
	for member in members:
		var refs: Dictionary = _cards.get(member.get_instance_id(), {})
		if refs.is_empty():
			continue
		var morale: Dictionary = _morale_for(member.trust)
		var color: Color = morale.color

		var style_border: StyleBoxFlat = refs.style_border
		style_border.border_color = color
		var style_dot: StyleBoxFlat = refs.style_dot
		style_dot.bg_color = color

		var level_label: Label = refs.level_label
		level_label.text = str(XPSystem.current_level)
		var portrait: Control = refs.portrait
		var member_name := member.member_name if not member.member_name.is_empty() else "Союзник"
		portrait.tooltip_text = "%s\n%s" % [member_name, str(morale.label)]

		var ratio: float = 0.0
		if member.max_health > 0:
			ratio = clampf(float(member.health) / float(member.max_health), 0.0, 1.0)
		var hp_fill: ColorRect = refs.hp_fill
		hp_fill.anchor_right = ratio
		hp_fill.offset_right = 0
		hp_fill.color = PartyPanelConstants.HP_LOW_FILL if ratio < PartyPanelConstants.HP_LOW_THRESHOLD else PartyPanelConstants.HP_FILL

## Клик по портрету союзника — открыть экран персонажа/инвентаря сразу на нём.
func _on_portrait_input(event: InputEvent, member: Player) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var modal := get_tree().get_first_node_in_group("character_screen")
		if modal != null and modal.has_method("open"):
			modal.open(member)

func _morale_for(trust: int) -> Dictionary:
	for tier in PartyPanelConstants.MORALE_TIERS:
		if trust >= int(tier.min):
			return tier
	return PartyPanelConstants.MORALE_TIERS[PartyPanelConstants.MORALE_TIERS.size() - 1]
