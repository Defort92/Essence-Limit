## Управляет сменой сцен. Единственное место в проекте, где вызывается change_scene_to_file.
## Является Autoload-синглтоном; регистрировать как "SceneManager" в Project Settings.
extends Node

signal scene_changed(scene_path: String)

## Меняет сцену на произвольный путь.
func go_to(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
	scene_changed.emit(scene_path)

## Переход в главное меню.
func go_to_main_menu() -> void:
	go_to("res://scenes/ui/main_menu.tscn")

## Переход на экран создания персонажа (выбор расы и имени).
func go_to_character_creation() -> void:
	go_to("res://scenes/ui/character_creation.tscn")

## Переход в человеческий город (основной хаб).
func go_to_city() -> void:
	go_to("res://scenes/world/human_city.tscn")

## Переход в стартовую локацию расы после создания персонажа.
func go_to_race_start(race: GameManager.Race) -> void:
	match race:
		GameManager.Race.HUMAN:     go_to("res://scenes/world/human_city.tscn")
		GameManager.Race.BARBARIAN: go_to("res://scenes/world/barbarian_camp.tscn")
		GameManager.Race.ELF:       go_to("res://scenes/world/elf_village.tscn")
		GameManager.Race.DEMON:     go_to("res://scenes/world/demon_ruins.tscn")
		GameManager.Race.ANGEL:     go_to("res://scenes/world/angel_citadel.tscn")

## Переход на этаж подземелья. floor_num: 1–15.
func go_to_dungeon_floor(floor_num: int) -> void:
	assert(floor_num >= 1 and floor_num <= DungeonPortalConstants.MAX_FLOORS)
	go_to("res://scenes/dungeon/floor_%02d.tscn" % floor_num)

## Экран смерти (показывает UI, затем возвращает в город).
func go_to_death_screen() -> void:
	go_to("res://scenes/ui/death_screen.tscn")
