## Рюкзак игрока (до MAX_SLOTS ячеек).
## Каждая ячейка — словарь { item: ItemData, quantity: int }.
## Является Autoload-синглтоном; регистрировать как "InventorySystem" в Project Settings.
extends Node

const MAX_SLOTS: int = 30

var _slots: Array = []

signal item_added(item: ItemData, quantity: int)
signal item_removed(item: ItemData, quantity: int)
signal inventory_changed()

## Добавляет [param quantity] единиц [param item] в рюкзак.
## Стакабельные предметы сначала докладываются в существующие стаки.
## Возвращает [code]false[/code] если рюкзак полон и ни одна единица не добавлена.
func add_item(item: ItemData, quantity: int = 1) -> bool:
	var any_added := false

	if item.is_stackable:
		for slot in _slots:
			if slot.item.id == item.id and slot.quantity < item.max_stack:
				var space: int = item.max_stack - slot.quantity
				var to_add: int = min(space, quantity)
				slot.quantity += to_add
				quantity -= to_add
				any_added = true
				item_added.emit(item, to_add)
				if quantity == 0:
					inventory_changed.emit()
					return true

	while quantity > 0:
		if _slots.size() >= MAX_SLOTS:
			# Частичное добавление состоялось — UI должен обновиться.
			if any_added:
				inventory_changed.emit()
			return false
		var to_add: int = min(quantity, item.max_stack) if item.is_stackable else 1
		_slots.append({ "item": item, "quantity": to_add })
		item_added.emit(item, to_add)
		any_added = true
		quantity -= to_add

	inventory_changed.emit()
	return true

## Удаляет [param quantity] единиц предмета с id == [param item_id].
## Возвращает [code]true[/code] если нужное количество было удалено полностью.
func remove_item(item_id: String, quantity: int = 1) -> bool:
	var removed := 0
	for idx in range(_slots.size() - 1, -1, -1):
		var slot = _slots[idx]
		if slot.item.id != item_id:
			continue
		var take: int = min(slot.quantity, quantity - removed)
		slot.quantity -= take
		removed += take
		item_removed.emit(slot.item, take)
		if slot.quantity == 0:
			_slots.remove_at(idx)
		if removed >= quantity:
			break

	if removed > 0:
		inventory_changed.emit()
	return removed >= quantity

## Возвращает [code]true[/code] если в рюкзаке есть хотя бы [param quantity] единиц предмета.
func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity

## Возвращает суммарное количество единиц предмета с id == [param item_id].
func get_item_count(item_id: String) -> int:
	var total := 0
	for slot in _slots:
		if slot.item.id == item_id:
			total += slot.quantity
	return total

## Возвращает копию массива ячеек (изменение копии не влияет на инвентарь).
func get_slots() -> Array:
	return _slots.duplicate()

## Возвращает [code]true[/code] если все ячейки заняты.
func is_full() -> bool:
	return _slots.size() >= MAX_SLOTS

## Очищает рюкзак полностью.
func clear() -> void:
	_slots.clear()
	inventory_changed.emit()

## Сериализует содержимое в массив словарей для сохранения в JSON.
func serialize() -> Array:
	var result := []
	for slot in _slots:
		result.append({ "path": slot.item.resource_path, "quantity": slot.quantity })
	return result

## Восстанавливает содержимое из данных, сохранённых через [method serialize].
func deserialize(data: Array) -> void:
	_slots.clear()
	for entry in data:
		var res_path: String = entry.get("path", "")
		if res_path and ResourceLoader.exists(res_path):
			var item := load(res_path) as ItemData
			if item:
				_slots.append({ "item": item, "quantity": entry.get("quantity", 1) })
	inventory_changed.emit()

## Использует один расходник [param item_id] на [param target].
## Применяет эффект через ConsumableData.apply() и удаляет 1 единицу из стека.
## Возвращает [code]false[/code] если предмет не найден или он не является расходником.
func use_consumable(item_id: String, target: Node) -> bool:
	for slot in _slots:
		if slot.item.id == item_id and slot.item is ConsumableData:
			(slot.item as ConsumableData).apply(target)
			return remove_item(item_id, 1)
	return false
