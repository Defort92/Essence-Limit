## Управляет паузой игры.
## Слушает Input Action "pause" (назначить в Project Settings → Input Map).
## Является Autoload-синглтоном; регистрировать как "PauseManager" в Project Settings.
## UI-меню паузы должно иметь process_mode = WHEN_PAUSED, чтобы работать во время паузы.
extends Node

var is_paused: bool = false

signal paused()
signal unpaused()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_just_pressed("pause"):
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
