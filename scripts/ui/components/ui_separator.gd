## Горизонтальная линия-разделитель в фирменном цвете. Общий компонент вместо копипасты
## ColorRect с цветом в каждой сцене: прикрепляется к узлу ColorRect или создаётся из
## кода (UISeparator.new()). Цвет и высоту задаёт сама в _ready — в сцене не прописывать.
extends ColorRect
class_name UISeparator


func _ready() -> void:
	color = UISeparatorConstants.LINE_COLOR
	custom_minimum_size = Vector2(0, 1)
