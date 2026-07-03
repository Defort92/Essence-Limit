## Торговец: список товаров, доступных для покупки в лавке.
## Цены берутся из ItemData.buy_price/sell_price — у торговца своих цен нет.
extends Resource
class_name VendorData

@export var id: String = ""
@export var display_name: String = ""
@export var stock: Array[ItemData] = []
