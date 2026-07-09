## Экран смерти. GameManager.on_player_died() уже закрыл портал и сбросил HP —
## здесь только возврат в город.
extends Control

func _on_return_pressed() -> void:
	SceneManager.go_to_city()
