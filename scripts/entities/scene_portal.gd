## Портал перехода между локациями: по клавише "interact" переносит в сцену target_scene,
## когда активный участник отряда стоит в зоне PortalArea. Весь отряд следует за героем:
## состав хранится в PartySystem.roster и доспавнивается в новой сцене автоматически.
## Не путать с DungeonPortal (цикл подземелья) — это обычный переход между локациями мира.
extends Node3D
class_name ScenePortal

## Сцена назначения (.tscn).
@export_file("*.tscn") var target_scene: String = ""
## Название места назначения — постоянная надпись над порталом и текст подсказки.
@export var destination_name: String = ""
## Переход между сценами важнее локальных действий вроде обыска лежащего рядом тела.
@export var interaction_priority: int = 100

@onready var _prompt: Label3D = get_node_or_null("PromptLabel") as Label3D
@onready var _title: Label3D = get_node_or_null("TitleLabel") as Label3D

var _player_in_range: bool = false

func _ready() -> void:
	add_to_group("minimap_object")
	add_to_group("interactable")
	$PortalArea.body_entered.connect(_on_body_entered)
	$PortalArea.body_exited.connect(_on_body_exited)
	# Подсказка показывает актуальную клавишу «interact» — обновляем её при переназначении.
	InputSettings.bindings_changed.connect(_update_prompt_text)
	_update_prompt_text()
	if _title != null:
		_title.text = destination_name

func _on_body_entered(body: Node3D) -> void:
	if _is_active_member(body):
		_player_in_range = true
		if _prompt != null:
			_prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if _is_active_member(body):
		_player_in_range = false
		if _prompt != null:
			_prompt.visible = false

## Порталом пользуется только управляемый игроком участник — ИИ-союзники, проходя
## сквозь зону, не включают подсказку и не могут увести отряд в другую сцену.
func _is_active_member(body: Node3D) -> bool:
	return body is Player and body == PartySystem.get_active_member()

func is_interaction_available(interactor: Node3D) -> bool:
	return _player_in_range and _is_active_member(interactor) and not target_scene.is_empty()

func get_interaction_priority() -> int:
	return interaction_priority

func interact(_interactor: Node3D) -> bool:
	SceneManager.go_to(target_scene)
	return true

func _update_prompt_text() -> void:
	if _prompt == null:
		return
	_prompt.text = "%s — Войти: %s" % [InputSettings.action_key_label("interact"), destination_name]
