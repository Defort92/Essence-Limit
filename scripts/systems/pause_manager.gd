## Управляет паузой игры.
## Слушает Input Action "pause" (назначить в Project Settings → Input Map).
## Является Autoload-синглтоном; регистрировать как "PauseManager" в Project Settings.
## UI-меню паузы должно иметь process_mode = WHEN_PAUSED, чтобы работать во время паузы.
extends Node

var is_paused: bool = false

func _enter_tree() -> void:
	# ALWAYS гарантирует, что _unhandled_input работает даже когда дерево поставлено на паузу.
	# Без этого нажатие "pause" для снятия паузы не сработает.
	process_mode = Node.PROCESS_MODE_ALWAYS

signal paused()
signal unpaused()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()

## Переключает паузу: если активна — снимает, иначе — включает.
func toggle_pause() -> void:
	if is_paused:
		unpause()
	else:
		pause()

## Ставит игру на паузу и испускает сигнал [signal paused].
func pause() -> void:
	is_paused = true
	get_tree().paused = true
	paused.emit()

## Снимает паузу и испускает сигнал [signal unpaused].
func unpause() -> void:
	is_paused = false
	get_tree().paused = false
	unpaused.emit()
