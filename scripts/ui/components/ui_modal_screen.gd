## Базовый класс модального экрана поверх игры (обыск, лавка, экран персонажа, состояния).
## Берёт на себя общий каркас:
##  - регистрация в своей группе (screen_group) и общей группе "modal_screen";
##  - работа всегда (PROCESS_MODE_ALWAYS) — и на паузе (чтобы закрытие/крестик/фон работали,
##    пока сам экран держит игру на паузе), и без неё (чтобы клавиша-открывашка вроде
##    "inventory" срабатывала из обычной игры, а не только когда пауза уже включена извне);
##  - опциональная пауза при открытии (_show_modal) и снятие при закрытии (close);
##  - закрытие непаусящего окна при внешней паузе и паусящего — при снятии паузы;
##  - закрытие по клавише close_action, крестику (_on_close_pressed) и клику по фону
##    (_on_backdrop_input — подключается в сцене от узла Backdrop, если он есть).
##
## Подкласс в _ready() задаёт screen_group/close_action и вызывает super._ready().
## Публичный open(...) подкласса делает свою подготовку и вызывает _show_modal().
## Очистка при ЛЮБОМ способе закрытия — в переопределённом _before_close().
extends CanvasLayer
class_name UIModalScreen

## Группа, через которую этот экран находят другие системы (например, "loot_ui").
var screen_group: String = ""
## Input-действие, закрывающее видимый экран ("" — закрытие только ESC/крестиком/фоном).
var close_action: String = ""
## Обычные игровые окна не останавливают мир. Включается только для экранов, которым
## действительно нужна пауза (сейчас — окно состояний).
var pauses_game: bool = false
## Кадр закрытия тоже блокирует игровой ввод, чтобы клавиша окна не запускала заодно
## уклонение, атаку или другое действие персонажа.
var _gameplay_input_blocked_through_frame: int = -1

func _ready() -> void:
	if not screen_group.is_empty():
		add_to_group(screen_group)
	add_to_group("modal_screen")
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	PauseManager.paused.connect(_on_external_pause)
	# ESC снимает паузу через PauseManager напрямую (не через close()) — синхронизируемся.
	PauseManager.unpaused.connect(_on_external_unpause)

func _unhandled_input(event: InputEvent) -> void:
	if close_action.is_empty() or not event.is_action_pressed(close_action):
		return
	if visible:
		close()
		get_viewport().set_input_as_handled()
	elif not PauseManager.is_paused:
		# Во время паузы не открываем новый игровой экран поверх меню или паусящей модалки.
		_on_action_while_hidden()

## Клавиша close_action нажата, когда экран скрыт и игра не на паузе (см. выше). По умолчанию
## ничего не делаем и не поглощаем событие — его обработает следующий слушатель (например, HUD).
## Экран-переключатель (экран персонажа) переопределяет это, чтобы открыть себя той же клавишей.
func _on_action_while_hidden() -> void:
	pass

## Показывает экран и, если запрошено подклассом, ставит игру на паузу.
func _show_modal() -> void:
	show()
	if pauses_game:
		PauseManager.pause()

## Закрывает экран и снимает только ту паузу, которую этот экран сам использует.
func close() -> void:
	_gameplay_input_blocked_through_frame = Engine.get_process_frames() + 1
	_before_close()
	hide()
	if pauses_game and PauseManager.is_paused:
		PauseManager.unpause()

## Пока окно видно (и в кадре его закрытия), персонаж не получает команды сквозь UI.
func is_gameplay_input_blocking() -> bool:
	return visible or Engine.get_process_frames() <= _gameplay_input_blocked_through_frame

## При Esc непаусящее окно закрывается, а обычная пауза остаётся включённой.
func _on_external_pause() -> void:
	if not visible or pauses_game:
		return
	_gameplay_input_blocked_through_frame = Engine.get_process_frames() + 1
	_before_close()
	hide()

## Пауза снята извне (ESC) — прячемся с той же очисткой, что и при обычном закрытии.
func _on_external_unpause() -> void:
	if not visible or not pauses_game:
		return
	_gameplay_input_blocked_through_frame = Engine.get_process_frames() + 1
	_before_close()
	hide()

## Точка очистки подкласса перед любым закрытием (отписки, сброс ссылок и т.п.).
func _before_close() -> void:
	pass

## Клик по фону вне панели закрывает экран. Подключается в сцене:
## сигнал gui_input узла Backdrop → _on_backdrop_input.
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()

## Обработчик крестика (UICloseButton): сигнал pressed → _on_close_pressed.
func _on_close_pressed() -> void:
	close()
