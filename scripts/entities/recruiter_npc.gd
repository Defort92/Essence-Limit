## NPC-вербовщик: нанимает наёмника в отряд за золото по клавише "interact",
## когда игрок находится в радиусе InteractionArea. Один вербовщик — один наёмник;
## после успешного найма предложение исчезает.
extends StaticBody3D
class_name RecruiterNPC

@export var companion_data: CompanionData

@onready var _prompt: Label3D = get_node_or_null("PromptLabel") as Label3D

var _player_in_range: bool = false

func _ready() -> void:
	add_to_group("minimap_object")
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

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or companion_data == null:
		return
	if event.is_action_pressed("interact"):
		if PartySystem.recruit(companion_data):
			companion_data = null
			_update_prompt_text()

func _update_prompt_text() -> void:
	if _prompt == null:
		return
	if companion_data == null:
		_prompt.text = "Наёмников больше нет"
	else:
		var role_label: String = "лекарь" if companion_data.combat_role == CompanionData.Role.HEALER else "боец"
		_prompt.text = "%s — Нанять: %s, %s (%d зол.)" % [InputSettings.action_key_label("interact"), companion_data.display_name, role_label, companion_data.hire_cost]
