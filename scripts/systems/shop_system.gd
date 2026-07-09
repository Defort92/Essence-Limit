## Покупка и продажа предметов у торговцев. Цены берутся из ItemData (buy_price/sell_price).
## Стока не убывает при покупке — торговец не ограничен количеством товара.
## Является Autoload-синглтоном; регистрировать как "ShopSystem" в Project Settings.
extends Node

signal item_bought(vendor: VendorData, item: ItemData, quantity: int)
signal item_sold(item: ItemData, quantity: int)

## Покупает [param quantity] единиц [param item] у [param vendor] в рюкзак активного персонажа.
## Списывает золото, затем пытается добавить предмет в рюкзак.
## Если в рюкзаке не нашлось места — золото возвращается и покупка отменяется.
## Возвращает [code]false[/code] если предмета нет в стоке торговца, не хватает золота
## или не удалось добавить предмет в рюкзак.
func buy(vendor: VendorData, item: ItemData, quantity: int = 1) -> bool:
	if vendor == null or item == null or quantity <= 0:
		return false
	if item not in vendor.stock:
		return false
	var inv := PartySystem.get_active_inventory()
	if inv == null:
		return false

	var total_cost: int = item.buy_price * quantity
	if not GameManager.spend_gold(total_cost):
		return false

	if not inv.add_item(item, quantity):
		GameManager.add_gold(total_cost)
		return false

	item_bought.emit(vendor, item, quantity)
	return true

## Продаёт [param quantity] единиц предмета [param item] из рюкзака активного персонажа за золото.
## Предметы с sell_price <= 0 продавать нельзя.
## Возвращает [code]false[/code] если в рюкзаке недостаточно предметов или предмет не продаётся.
func sell(item: ItemData, quantity: int = 1) -> bool:
	if item == null or quantity <= 0 or item.sell_price <= 0:
		return false
	var inv := PartySystem.get_active_inventory()
	if inv == null or not inv.remove_item(item.id, quantity):
		return false

	GameManager.add_gold(item.sell_price * quantity)
	item_sold.emit(item, quantity)
	return true
