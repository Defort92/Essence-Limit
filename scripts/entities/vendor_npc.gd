## NPC-торговец: открывает UI лавки (группа "shop_ui") по клавише "interact",
## когда игрок находится в радиусе InteractionArea.
extends StaticBody3D
class_name VendorNPC

@export var vendor_data: VendorData

@onready var _prompt: Label3D = get_node_or_null("PromptLabel") as Label3D

var _player_in_range: bool = false

func _ready() -> void:
	$InteractionArea.body_entered.connect(_on_body_entered)
	$InteractionArea.body_exited.connect(_on_body_exited)

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
	if not _player_in_range or vendor_data == null:
		return
	if event.is_action_pressed("interact"):
		var shop_ui := get_tree().get_first_node_in_group("shop_ui")
		if shop_ui != null and shop_ui.has_method("open"):
			shop_ui.open(vendor_data)
