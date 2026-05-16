## Предмет, лежащий в мире. Игрок автоматически подбирает его при входе в зону.
## Если в рюкзаке нет места — pickup остаётся на месте.
## Добавить на сцену как Area3D с CollisionShape3D.
extends Area3D
class_name ItemPickup

@export var item: ItemData
@export var quantity: int = 1
## Если задано — это подбор золота, item игнорируется.
@export var gold_amount: int = 0

signal picked_up(pickup: ItemPickup)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return

	if gold_amount > 0:
		GameManager.add_gold(gold_amount)
		picked_up.emit(self)
		queue_free()
		return

	if item == null:
		return

	if InventorySystem.add_item(item, quantity):
		picked_up.emit(self)
		queue_free()
