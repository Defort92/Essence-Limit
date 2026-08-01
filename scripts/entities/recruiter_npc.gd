## NPC-вербовщик: нанимает наёмника в отряд за золото по клавише "interact",
## когда игрок находится в радиусе InteractionArea. Один вербовщик — один наёмник;
## после успешного найма предложение исчезает.
extends StaticBody3D
class_name RecruiterNPC

@export var companion_data: CompanionData
@export var interaction_priority: int = 10

@onready var _prompt: Label3D = get_node_or_null("PromptLabel") as Label3D

var _player_in_range: bool = false

func _ready() -> void:
	add_to_group("minimap_object")
	add_to_group("interactable")
	$InteractionArea.body_entered.connect(_on_body_entered)
	$InteractionArea.body_exited.connect(_on_body_exited)
	# Подсказка показывает актуальную клавишу «interact» — обновляем её при переназначении.
	InputSettings.bindings_changed.connect(_update_prompt_text)
	_update_prompt_text()

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		if _prompt != null:
			_prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		if _prompt != null:
			_prompt.visible = false

func is_interaction_available(interactor: Node3D) -> bool:
	return companion_data != null and interactor == PartySystem.get_active_member() \
		and $InteractionArea.overlaps_body(interactor)

func get_interaction_priority() -> int:
	return interaction_priority

func interact(_interactor: Node3D) -> bool:
	if not PartySystem.recruit(companion_data):
		return false
	companion_data = null
	_update_prompt_text()
	return true

func _update_prompt_text() -> void:
	if _prompt == null:
		return
	if companion_data == null:
		_prompt.text = "Наёмников больше нет"
	else:
		var role_label: String = "лекарь" if companion_data.combat_role == CompanionData.Role.HEALER else "боец"
		_prompt.text = "%s — Нанять: %s, %s (%d зол.)" % [InputSettings.action_key_label("interact"), companion_data.display_name, role_label, companion_data.hire_cost]
