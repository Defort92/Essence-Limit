extends CanvasLayer

## Название локации мира для баннера места (см. LocationBanner). Задаётся на инстансе HUD
## в каждой сцене; в подземелье баннер вместо него показывает «ЭТАЖ N» из DungeonPortal.
@export var location_name: String = ""


@onready var hp_bar: ProgressBar = $Control/TopLeft/HPContainer/HPBar
@onready var hp_text: Label = $Control/TopLeft/HPContainer/HPText
@onready var _gold_badge: PanelContainer = $Control/GoldBadge
@onready var _gold_value: Label = $Control/GoldBadge/Row/GoldValue
@onready var level_label: Label = $Control/TopLeft/LevelLabel
@onready var _player_portrait: Control = $Control/PlayerPortrait
@onready var _status_panel: PanelContainer = $Control/StatusPanel
@onready var _header_row: HBoxContainer = $Control/StatusPanel/Root/Header
@onready var _buff_count: Label = $Control/StatusPanel/Root/Header/BuffCount
@onready var _debuff_count: Label = $Control/StatusPanel/Root/Header/DebuffCount
@onready var _chevron: Label = $Control/StatusPanel/Root/Header/Chevron
@onready var _ticker: VBoxContainer = $Control/StatusPanel/Root/Ticker
@onready var _expanded_box: VBoxContainer = $Control/StatusPanel/Root/Expanded
@onready var _status_list: VBoxContainer = $Control/StatusPanel/Root/Expanded/Scroll/StatusList
@onready var _show_all_btn: Button = $Control/StatusPanel/Root/Expanded/ShowAllButton
@onready var _location_banner: Control = $Control/LocationBanner

## Участник, чьи статусы сейчас показывает панель (обычно активный игрок).
var _status_member: Player = null
## Ссылки на подписи таймеров развёрнутого списка для живого отсчёта: [{ label, entry }].
var _timer_refs: Array[Dictionary] = []
var _refresh_accum: float = 0.0
## Развёрнут ли список состояний (false = свёрнутая лента тостов).
var _expanded: bool = false
## source_id уже показанных статусов — чтобы тост всплывал только на новое наложение.
var _seen_ids: Dictionary = {}
## Картинка портрета активного игрока в TopLeft (обновляется при смене активного участника).
var _player_portrait_image: TextureRect = null
## Подпись текущего режима формации отряда (внизу по центру). Строится кодом в _ready.
var _formation_label: Label = null
## Активные тосты ленты в порядке появления (FIFO при переполнении MAX_TOASTS).
var _toast_nodes: Array[Control] = []

## Стиль панели состояний в развёрнутом виде (градиентное затемнение) и свёрнутом
## (пусто — тосты «висят» на пустом фоне без рамки). Строятся в _ready.
var _states_style_expanded: StyleBox = null
var _states_style_collapsed: StyleBox = null

func _ready() -> void:
	GameManager.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(GameManager.gold)
	XPSystem.level_up.connect(_on_level_up)
	_on_level_up(XPSystem.current_level)
	PartySystem.active_member_changed.connect(_on_active_member_changed)
	PartySystem.formation_mode_changed.connect(_on_formation_mode_changed)
	_header_row.gui_input.connect(_on_header_input)
	_show_all_btn.pressed.connect(_open_states_modal)
	_build_badge_styles()
	_build_player_portrait()
	_build_formation_indicator()
	_apply_expanded_state()
	_location_banner.set_world_location(location_name)
	call_deferred("_connect_player")

## Строит градиентные подложки: золото (затемнение к правому краю экрана) и такую же
## по стилю подложку для развёрнутой панели состояний. Свёрнутая панель — без рамки.
func _build_badge_styles() -> void:
	_gold_badge.add_theme_stylebox_override("panel",
		_make_gradient_stylebox(Color(0.02, 0.015, 0.02, 0.88), 22, 6, 16, 6))
	_states_style_expanded = _make_gradient_stylebox(Color(0.02, 0.015, 0.02, 0.72), 12, 9, 12, 9)
	_states_style_collapsed = StyleBoxEmpty.new()

## Подложка с горизонтальным градиентным затемнением: прозрачно слева → [param dark] справа
## (к краю экрана). Отступы контента задаются аргументами.
func _make_gradient_stylebox(dark: Color, ml: int, mt: int, mr: int, mb: int) -> StyleBoxTexture:
	var grad := Gradient.new()
	grad.set_color(0, Color(dark.r, dark.g, dark.b, 0.0))
	grad.set_color(1, dark)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 8
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.content_margin_left = ml
	sb.content_margin_top = mt
	sb.content_margin_right = mr
	sb.content_margin_bottom = mb
	return sb

func _process(delta: float) -> void:
	if _timer_refs.is_empty():
		return
	_refresh_accum += delta
	if _refresh_accum < HUDConstants.STATUS_TIMER_REFRESH:
		return
	_refresh_accum = 0.0
	for ref in _timer_refs:
		var label: Label = ref.label
		var entry: Dictionary = ref.entry
		label.text = StatusComponent.format_remaining(entry.remaining)

## Клавиша "states" (C) переключает свёрнутую ленту ↔ развёрнутый список. Открытие
## полного окна — только клик по статусу или «Показать все» (см. _open_states_modal).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("states"):
		_toggle_expanded()
		get_viewport().set_input_as_handled()

func _connect_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		# Player ещё не добавлен в сцену — ждём через scene tree signal.
		get_tree().node_added.connect(_on_node_added_to_tree)
		return
	_subscribe_to_player(players[0] as Player)

func _on_node_added_to_tree(node: Node) -> void:
	if not node.is_in_group("player"):
		return
	get_tree().node_added.disconnect(_on_node_added_to_tree)
	_subscribe_to_player(node as Player)

## При переключении активного участника отряда переподписывается на его health_changed
## и statuses_changed, чтобы HUD всегда показывал того, кем сейчас управляет игрок.
func _on_active_member_changed(old_member: Player, new_member: Player) -> void:
	if old_member != null and old_member.health_changed.is_connected(_on_health_changed):
		old_member.health_changed.disconnect(_on_health_changed)
	if old_member != null and old_member.statuses.statuses_changed.is_connected(_on_statuses_changed):
		old_member.statuses.statuses_changed.disconnect(_on_statuses_changed)
	# Новый участник — своя лента: сбрасываем «виденные» статусы и очищаем тосты.
	_seen_ids.clear()
	_clear_ticker()
	_subscribe_to_player(new_member)

func _subscribe_to_player(player: Player) -> void:
	if player == null:
		return
	if not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)
	_on_health_changed(player.health, player.max_health)
	_status_member = player
	_update_player_portrait(player)
	if not player.statuses.statuses_changed.is_connected(_on_statuses_changed):
		player.statuses.statuses_changed.connect(_on_statuses_changed)
	# Первичное наполнение считаем «уже виденным», чтобы стартовые статусы не сыпались тостами.
	_seed_seen_ids()
	_on_statuses_changed()

func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_text.text = "%d / %d" % [current, maximum]

func _on_gold_changed(amount: int) -> void:
	_gold_value.text = "%d" % amount

func _on_level_up(new_level: int) -> void:
	level_label.text = "Ур. %d" % new_level

# ─── Портрет активного игрока (TopLeft) ─────────────────────────────────────

## Кликабельный портрет активного игрока: рамка + фон строятся один раз здесь,
## сама картинка (_player_portrait_image) обновляется в _update_player_portrait
## при подписке/смене активного участника (см. _subscribe_to_player).
func _build_player_portrait() -> void:
	_player_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_player_portrait.gui_input.connect(_on_player_portrait_input)

	var bg := ColorRect.new()
	bg.color = HUDConstants.PORTRAIT_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_portrait.add_child(bg)

	_player_portrait_image = TextureRect.new()
	_player_portrait_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_player_portrait_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_portrait_image.clip_contents = true
	_player_portrait_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_portrait.add_child(_player_portrait_image)

	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(2)
	style.border_color = HUDConstants.PORTRAIT_BORDER
	border.add_theme_stylebox_override("panel", style)
	_player_portrait.add_child(border)

# ─── Индикатор формации отряда ──────────────────────────────────────────────

## Строит подпись режима формации внизу по центру. Держится приглушённой, коротко
## пульсирует ярче при смене режима (см. _on_formation_mode_changed).
func _build_formation_indicator() -> void:
	_formation_label = Label.new()
	_formation_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_formation_label.offset_top = -46
	_formation_label.offset_bottom = -22
	_formation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_formation_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_formation_label.add_theme_color_override("font_color", HUDConstants.NAME_COLOR)
	_formation_label.add_theme_font_size_override("font_size", 14)
	$Control.add_child(_formation_label)
	_update_formation_label(PartySystem.formation_mode)
	_formation_label.modulate.a = 0.55

func _on_formation_mode_changed(mode: int) -> void:
	_update_formation_label(mode)
	if _formation_label == null:
		return
	# Короткий пульс, чтобы игрок заметил переключение, затем возврат к приглушённому виду.
	_formation_label.modulate.a = 1.0
	var t := _formation_label.create_tween()
	t.tween_interval(0.8)
	t.tween_property(_formation_label, "modulate:a", 0.55, 0.5)

func _update_formation_label(mode: int) -> void:
	if _formation_label != null:
		_formation_label.text = "Отряд: %s" % PartySystem.formation_mode_name(mode)

func _update_player_portrait(player: Player) -> void:
	if _player_portrait_image == null or player == null:
		return
	var sprite := player.get_node_or_null("Sprite3D") as DirectionalSprite3D
	_player_portrait_image.texture = sprite.tex_front if sprite != null else null

func _on_player_portrait_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_character_screen(_status_member)

## Общая точка открытия экрана персонажа/инвентаря по клику (портрет игрока здесь,
## портреты союзников — party_panel.gd). [param member] — null открывает на активном.
func _open_character_screen(member: Player) -> void:
	var modal := get_tree().get_first_node_in_group("character_screen")
	if modal != null and modal.has_method("open"):
		modal.open(member)

# ─── Панель состояний ────────────────────────────────────────────────────────

## Обновляет счётчики в шапке, всплывает тосты для новых статусов (в свёрнутом режиме)
## и пересобирает развёрнутый список, если он открыт. Вызывается по statuses_changed.
func _on_statuses_changed() -> void:
	if _status_member == null:
		return
	var buffs: Array[Dictionary] = _status_member.statuses.get_buffs()
	var debuffs: Array[Dictionary] = _status_member.statuses.get_debuffs()
	# Итоговое кол-во положительных/отрицательных состояний видно всегда, даже свёрнуто.
	_buff_count.text = "▲ %d" % buffs.size()
	_debuff_count.text = "▼ %d" % debuffs.size()

	_process_new_toasts(buffs, debuffs)

	if _expanded:
		_rebuild_expanded_list(buffs, debuffs)

## Всплывает тост для каждого статуса, чьего source_id мы ещё не видели, и обновляет
## множество «виденных» под текущий состав (снятые статусы уходят из него).
func _process_new_toasts(buffs: Array[Dictionary], debuffs: Array[Dictionary]) -> void:
	var current: Dictionary = {}
	for entry in buffs:
		current[entry.source_id] = true
		if not _seen_ids.has(entry.source_id) and not _expanded:
			_spawn_toast(entry, HUDConstants.BUFF_ACCENT)
	for entry in debuffs:
		current[entry.source_id] = true
		if not _seen_ids.has(entry.source_id) and not _expanded:
			_spawn_toast(entry, HUDConstants.DEBUFF_ACCENT)
	_seen_ids = current

## Помечает все текущие статусы как «виденные» без всплытия тостов (стартовое наполнение).
func _seed_seen_ids() -> void:
	_seen_ids.clear()
	if _status_member == null:
		return
	for entry in _status_member.statuses.get_buffs():
		_seen_ids[entry.source_id] = true
	for entry in _status_member.statuses.get_debuffs():
		_seen_ids[entry.source_id] = true

func _spawn_toast(entry: Dictionary, accent: Color) -> void:
	var card := _make_status_card(entry, accent, HUDConstants.TOAST_BG, false)
	card.gui_input.connect(_on_card_input)
	_ticker.add_child(card)
	_toast_nodes.append(card)
	# Живёт TOAST_LIFETIME, затем плавно гаснет и удаляется. Твин привязан к самой
	# карточке: если её удалят раньше, твин авто-остановится.
	var life := card.create_tween()
	life.tween_interval(HUDConstants.TOAST_LIFETIME)
	life.tween_property(card, "modulate:a", 0.0, HUDConstants.TOAST_FADE)
	life.tween_callback(_remove_toast.bind(card))
	card.set_meta("life_tween", life)
	# FIFO: не больше MAX_TOASTS — лишние старые затираются анимацией удаления.
	while _toast_nodes.size() > HUDConstants.MAX_TOASTS:
		_evict_toast(_toast_nodes.pop_front())

## Обычное истечение времени жизни тоста: убрать из учёта и удалить узел.
func _remove_toast(card: Control) -> void:
	_toast_nodes.erase(card)
	if is_instance_valid(card):
		card.queue_free()

## Досрочное вытеснение самого старого тоста при переполнении: короткая анимация
## удаления (быстрое угасание), затем узел освобождается.
func _evict_toast(card: Control) -> void:
	if not is_instance_valid(card):
		return
	if card.has_meta("life_tween"):
		var t: Tween = card.get_meta("life_tween")
		if t != null and t.is_valid():
			t.kill()
	var out := card.create_tween()
	out.tween_property(card, "modulate:a", 0.0, 0.15)
	out.tween_callback(card.queue_free)

func _toggle_expanded() -> void:
	_expanded = not _expanded
	_apply_expanded_state()

## Приводит панель к текущему режиму: свёрнуто — лента тостов на пустом фоне (без рамки);
## развёрнуто — список со скроллом и кнопкой «Показать все» на градиентной подложке.
func _apply_expanded_state() -> void:
	_chevron.text = "⌃" if _expanded else "⌄"
	_ticker.visible = not _expanded
	_expanded_box.visible = _expanded
	_status_panel.add_theme_stylebox_override("panel",
		_states_style_expanded if _expanded else _states_style_collapsed)
	if _expanded:
		_clear_ticker()
		_rebuild_expanded_list()
	else:
		_clear_expanded_list()

## Пересобирает развёрнутый список. Аргументы опциональны — если не переданы, берутся
## актуальные из компонента статусов участника.
func _rebuild_expanded_list(buffs: Array[Dictionary] = [], debuffs: Array[Dictionary] = []) -> void:
	_clear_expanded_list()
	if _status_member == null:
		return
	if buffs.is_empty() and debuffs.is_empty():
		buffs = _status_member.statuses.get_buffs()
		debuffs = _status_member.statuses.get_debuffs()
	if buffs.is_empty() and debuffs.is_empty():
		var empty := Label.new()
		empty.text = "Активных состояний нет."
		empty.add_theme_color_override("font_color", HUDConstants.TIMER_COLOR)
		empty.add_theme_font_size_override("font_size", 13)
		_status_list.add_child(empty)
		return
	for entry in buffs:
		_add_expanded_row(entry, HUDConstants.BUFF_ACCENT)
	for entry in debuffs:
		_add_expanded_row(entry, HUDConstants.DEBUFF_ACCENT)

func _add_expanded_row(entry: Dictionary, accent: Color) -> void:
	var card := _make_status_card(entry, accent, HUDConstants.ROW_BG, true)
	card.gui_input.connect(_on_card_input)
	_status_list.add_child(card)

## Клик по тосту или строке списка — открыть полное окно состояний (с паузой и блюром).
func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_open_states_modal()

func _open_states_modal() -> void:
	var modal := get_tree().get_first_node_in_group("states_screen")
	if modal != null and modal.has_method("open"):
		modal.open()

func _clear_ticker() -> void:
	for child in _ticker.get_children():
		child.queue_free()
	_toast_nodes.clear()

func _clear_expanded_list() -> void:
	for child in _status_list.get_children():
		child.queue_free()
	_timer_refs.clear()

## Строит строку статуса: цветная левая грань (accent), глиф, имя и таймер на фоне bg.
## Дети получают mouse_filter=IGNORE, чтобы клик по всей карточке ловил её PanelContainer.
## [param track_timer] = true регистрирует таймер в _timer_refs для живого отсчёта.
func _make_status_card(entry: Dictionary, accent: Color, bg: Color, track_timer: bool) -> PanelContainer:
	var data: StatusEffectData = entry.data
	var card := PanelContainer.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _make_card_style(accent, bg))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)

	var glyph := Label.new()
	glyph.text = data.glyph
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.custom_minimum_size = Vector2(18, 0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_color_override("font_color", data.color)
	glyph.add_theme_font_size_override("font_size", 16)
	row.add_child(glyph)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", HUDConstants.NAME_COLOR)
	name_label.add_theme_font_size_override("font_size", 14)
	row.add_child(name_label)

	var timer_label := Label.new()
	timer_label.text = StatusComponent.format_remaining(entry.remaining)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.add_theme_color_override("font_color", HUDConstants.TIMER_COLOR)
	timer_label.add_theme_font_size_override("font_size", 13)
	row.add_child(timer_label)
	if track_timer:
		_timer_refs.append({"label": timer_label, "entry": entry})

	card.add_child(row)
	return card

func _make_card_style(accent: Color, bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 3
	style.border_color = accent
	style.content_margin_left = 9
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6
	return style

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_expanded()
