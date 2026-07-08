## Горизонтальная линия-разделитель в фирменном цвете. Общий компонент вместо копипасты
## ColorRect с цветом в каждой сцене: прикрепляется к узлу ColorRect или создаётся из
## кода (UISeparator.new()). Цвет и высоту задаёт сама в _ready — в сцене не прописывать.
extends ColorRect
class_name UISeparator

const LINE_COLOR := Color(0.471, 0.376, 0.212, 0.16)

func _ready() -> void:
	color = LINE_COLOR
	custom_minimum_size = Vector2(0, 1)
