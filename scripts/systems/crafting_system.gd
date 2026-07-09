## Крафт снаряжения из предметов в рюкзаке активного персонажа (обычно — дропов с монстров).
## Не привязан к надетому снаряжению — только к содержимому его личного рюкзака.
## Является Autoload-синглтоном; регистрировать как "CraftingSystem" в Project Settings.
extends Node

signal item_crafted(recipe: RecipeData)

## Возвращает [code]true[/code] если в рюкзаке активного персонажа хватает всех ингредиентов.
func can_craft(recipe: RecipeData) -> bool:
	if recipe == null:
		return false
	var inv := PartySystem.get_active_inventory()
	if inv == null:
		return false
	for ingredient in recipe.ingredients:
		if not inv.has_item(ingredient.item.id, ingredient.quantity):
			return false
	return true

## Списывает ингредиенты рецепта [param recipe] и добавляет результат в рюкзак активного
## персонажа. Если результату не хватило места — ингредиенты возвращаются, крафт отменяется.
## Возвращает [code]false[/code] если ингредиентов недостаточно или крафт не удался.
func craft(recipe: RecipeData) -> bool:
	if not can_craft(recipe):
		return false
	var inv := PartySystem.get_active_inventory()

	for ingredient in recipe.ingredients:
		inv.remove_item(ingredient.item.id, ingredient.quantity)

	if not inv.add_item(recipe.result_item, recipe.result_quantity):
		for ingredient in recipe.ingredients:
			inv.add_item(ingredient.item, ingredient.quantity)
		return false

	item_crafted.emit(recipe)
	return true
