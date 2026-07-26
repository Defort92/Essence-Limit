## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name CharacterScreenConstants
extends RefCounted

const SLOT_NAMES := {
	EquipmentData.Slot.HEAD: "Голова",
	EquipmentData.Slot.BODY: "Тело",
	EquipmentData.Slot.LEGS: "Ноги",
	EquipmentData.Slot.GLOVES: "Перчатки",
	EquipmentData.Slot.WEAPON_MAIN: "Оружие",
	EquipmentData.Slot.WEAPON_OFF: "Вторая рука",
}

## Порядок отображения основных слотов экипировки (аксессуары показываются отдельно).
const ARMOR_SLOTS := [
	EquipmentData.Slot.HEAD, EquipmentData.Slot.BODY,
	EquipmentData.Slot.LEGS, EquipmentData.Slot.GLOVES,
	EquipmentData.Slot.WEAPON_MAIN, EquipmentData.Slot.WEAPON_OFF,
]
