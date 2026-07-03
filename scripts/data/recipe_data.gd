## Рецепт крафта: набор ингредиентов (обычно — дропы с монстров) → один результат.
## Крафт не завязан на надетое снаряжение — только на содержимое рюкзака.
extends Resource
class_name RecipeData

@export var id: String = ""
@export var display_name: String = ""
@export var ingredients: Array[RecipeIngredient] = []
@export var result_item: ItemData
@export var result_quantity: int = 1
