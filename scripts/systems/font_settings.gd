## Хранит и применяет выбранные игроком шрифты интерфейса. Autoload-синглтон "FontSettings".
##
## Раздельно настраиваются два шрифта:
##   • шрифт ЗАГОЛОВКОВ — типовая вариация TitleLabel в общей теме;
##   • шрифт ОСНОВНОГО ТЕКСТА — базовый шрифт темы и вариации кнопок/полей/подписей.
## Тема (res://assets/themes/essence_theme.tres) общая, поэтому смена применяется сразу
## ко всему интерфейсу. Выбор сохраняется в user://settings.cfg, секция [display].
##
## Все шрифты в списке — пиксельные и поддерживают кириллицу (игра на русском).
extends Node


signal title_font_changed(index: int)
signal body_font_changed(index: int)

var title_index: int = FontSettingsConstants.DEFAULT_TITLE
var body_index: int = FontSettingsConstants.DEFAULT_BODY

var _theme: Theme = null

func _ready() -> void:
	_theme = load(FontSettingsConstants.THEME_PATH) as Theme
	_load_saved()
	_apply_title(title_index)
	_apply_body(body_index)

## Список отображаемых имён шрифтов — для заполнения выпадающих списков в настройках.
func font_names() -> PackedStringArray:
	var names := PackedStringArray()
	for font in FontSettingsConstants.FONTS:
		names.append(str(font["name"]))
	return names

## Применяет шрифт заголовков с индексом [param index] и сохраняет выбор.
func select_title_font(index: int) -> void:
	if not _is_valid(index) or index == title_index:
		return
	title_index = index
	_apply_title(index)
	_save()
	title_font_changed.emit(index)

## Применяет шрифт основного текста с индексом [param index] и сохраняет выбор.
func select_body_font(index: int) -> void:
	if not _is_valid(index) or index == body_index:
		return
	body_index = index
	_apply_body(index)
	_save()
	body_font_changed.emit(index)

func _is_valid(index: int) -> bool:
	return index >= 0 and index < FontSettingsConstants.FONTS.size()

## Загружает базовый шрифт по индексу списка.
func _base_font(index: int) -> Font:
	return load(str(FontSettingsConstants.FONTS[index]["path"]))

## Подменяет шрифт у типовой вариации TitleLabel.
func _apply_title(index: int) -> void:
	if _theme == null:
		return
	var variation := FontVariation.new()
	variation.base_font = _base_font(index)
	variation.spacing_glyph = 2
	_theme.set_font("font", "TitleLabel", variation)

## Подменяет шрифт основного текста во всех ролях из [constant BODY_ROLES].
func _apply_body(index: int) -> void:
	if _theme == null:
		return
	var base := _base_font(index)
	for role in FontSettingsConstants.BODY_ROLES:
		var variation := FontVariation.new()
		variation.base_font = base
		variation.spacing_glyph = int(FontSettingsConstants.BODY_ROLES[role])
		if role == "":
			_theme.set_default_font(variation)
		else:
			_theme.set_font("font", str(role), variation)

func _load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FontSettingsConstants.SETTINGS_PATH) != OK:
		return
	var saved_title := int(cfg.get_value("display", "title_font", FontSettingsConstants.DEFAULT_TITLE))
	var saved_body := int(cfg.get_value("display", "body_font", FontSettingsConstants.DEFAULT_BODY))
	title_index = saved_title if _is_valid(saved_title) else FontSettingsConstants.DEFAULT_TITLE
	body_index = saved_body if _is_valid(saved_body) else FontSettingsConstants.DEFAULT_BODY

func _save() -> void:
	var cfg := ConfigFile.new()
	# Подгружаем существующие секции (controls/keybinds), чтобы не затереть их.
	cfg.load(FontSettingsConstants.SETTINGS_PATH)
	cfg.set_value("display", "title_font", title_index)
	cfg.set_value("display", "body_font", body_index)
	cfg.save(FontSettingsConstants.SETTINGS_PATH)
