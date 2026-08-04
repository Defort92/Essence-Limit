## NPC-торговец: открывает UI лавки (группа "shop_ui") по клавише "interact",
## когда игрок находится в радиусе InteractionArea.
extends StaticBody3D
class_name VendorNPC

@export var vendor_data: VendorData
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

func _update_prompt_text() -> void:
	if _prompt != null:
		_prompt.text = "%s — Торговать" % InputSettings.action_key_label("interact")

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
	return vendor_data != null and interactor == PartySystem.get_active_member() \
		and $InteractionArea.overlaps_body(interactor)

func get_interaction_priority() -> int:
	return interaction_priority

func interact(_interactor: Node3D) -> bool:
	var shop_ui := get_tree().get_first_node_in_group("shop_ui")
	if shop_ui == null or not shop_ui.has_method("open"):
		return false
	shop_ui.open(vendor_data)
	return true
