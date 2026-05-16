## Снаряжение: броня, оружие, аксессуары.
## Слоты брони — по одному на каждый тип (BG3-стиль).
## Аксессуаров — не более MAX_ACCESSORIES, определённых в EquipmentManager.
extends ItemData
class_name EquipmentData

enum Slot {
	HEAD,
	BODY,
	LEGS,
	GLOVES,
	WEAPON_MAIN,
	WEAPON_OFF,
	ACCESSORY,
}

enum WeaponType { NONE, MELEE_ONE_HAND, MELEE_TWO_HAND, RANGED, SHIELD }

@export var slot: Slot = Slot.BODY
@export var weapon_type: WeaponType = WeaponType.NONE
## Ключи — названия статов: "strength", "agility", "intellect", "max_health".
@export var stat_bonuses: Dictionary = {}
