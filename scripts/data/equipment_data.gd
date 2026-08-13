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

## MAGIC добавлен в конец, чтобы числовые значения уже сохранённых типов оружия
## (особенно SHIELD) не изменились в старых сохранениях и .tres-файлах.
enum WeaponType { NONE, MELEE_ONE_HAND, MELEE_TWO_HAND, RANGED, SHIELD, MAGIC }

@export var slot: Slot = Slot.BODY
@export var weapon_type: WeaponType = WeaponType.NONE
## Каталог 128x128 кадров отдельного визуального слоя экипировки.
## Повторяет библиотеку тела: <direction>/<state>/<variant>/frame_NN.png.
## Например: back/idle/default/frame_01.png и back/attack/light_01/frame_01.png.
@export_dir var sprite_frames_dir: String = ""
## Optional non-destructive placement metadata authored by Equipment Alignment Editor.
@export var alignment_profile: EquipmentAlignmentProfile
## Ключи — названия статов: "strength", "agility", "intellect", "max_health".
@export var stat_bonuses: Dictionary = {}

## Луки и магические посохи по правилам проекта всегда занимают обе руки.
func is_two_handed_weapon() -> bool:
	return weapon_type in [
		WeaponType.MELEE_TWO_HAND,
		WeaponType.RANGED,
		WeaponType.MAGIC,
	]
