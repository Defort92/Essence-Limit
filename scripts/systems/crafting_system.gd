## Крафт снаряжения из предметов в рюкзаке (обычно — дропов с монстров).
## Не привязан к надетому снаряжению — только к содержимому InventorySystem.
## Является Autoload-синглтоном; регистрировать как "CraftingSystem" в Project Settings.
extends Node

signal item_crafted(recipe: RecipeData)

## Возвращает [code]true[/code] если в рюкзаке хватает всех ингредиентов рецепта.
func can_craft(recipe: RecipeData) -> bool:
	if recipe == null:
		return false
	for ingredient in recipe.ingredients:
		if not InventorySystem.has_item(ingredient.item.id, ingredient.quantity):
			return false
	return true

## Списывает ингредиенты рецепта [param recipe] и добавляет результат в рюкзак.
## Если результату не хватило места — ингредиенты возвращаются, крафт отменяется.
## Возвращает [code]false[/code] если ингредиентов недостаточно или крафт не удался.
func craft(recipe: RecipeData) -> bool:
	if not can_craft(recipe):
		return false

	for ingredient in recipe.ingredients:
		InventorySystem.remove_item(ingredient.item.id, ingredient.quantity)

	if not InventorySystem.add_item(recipe.result_item, recipe.result_quantity):
		for ingredient in recipe.ingredients:
			InventorySystem.add_item(ingredient.item, ingredient.quantity)
		return false

	item_crafted.emit(recipe)
	return true
