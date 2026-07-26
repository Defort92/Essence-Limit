## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name LootableCorpseConstants
extends RefCounted

## Радиус, в котором появляется подсказка «F — Обыскать».
const DETECT_RADIUS: float = 1.6

## Русские названия слотов экипировки для отображения в списке лута.
const SLOT_NAMES := {
	EquipmentData.Slot.HEAD: "Голова",
	EquipmentData.Slot.BODY: "Тело",
	EquipmentData.Slot.LEGS: "Ноги",
	EquipmentData.Slot.GLOVES: "Перчатки",
	EquipmentData.Slot.WEAPON_MAIN: "Оружие",
	EquipmentData.Slot.WEAPON_OFF: "Вторая рука",
}

const ARMOR_SLOTS := [
	EquipmentData.Slot.HEAD, EquipmentData.Slot.BODY,
	EquipmentData.Slot.LEGS, EquipmentData.Slot.GLOVES,
	EquipmentData.Slot.WEAPON_MAIN, EquipmentData.Slot.WEAPON_OFF,
]
