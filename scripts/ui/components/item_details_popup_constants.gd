## Подписи и цвета карточки предмета.
class_name ItemDetailsPopupConstants
extends RefCounted


const RARITY_NAMES := ["Обычный", "Необычный", "Редкий", "Эпический", "Легендарный"]
const RARITY_COLORS := [
	Color(0.72, 0.69, 0.64),
	Color(0.38, 0.78, 0.42),
	Color(0.36, 0.58, 0.92),
	Color(0.69, 0.39, 0.9),
	Color(0.95, 0.68, 0.24),
]

const STAT_NAMES := {
	"damage": "Урон",
	"range": "Дальность",
	"projectile_speed": "Скорость снаряда",
	"defense": "Защита",
	"strength": "Сила",
	"agility": "Ловкость",
	"intellect": "Интеллект",
	"max_health": "Макс. здоровье",
	"regen": "Регенерация",
}

const SLOT_NAMES := {
	EquipmentData.Slot.HEAD: "Голова",
	EquipmentData.Slot.BODY: "Тело",
	EquipmentData.Slot.LEGS: "Ноги",
	EquipmentData.Slot.GLOVES: "Перчатки",
	EquipmentData.Slot.WEAPON_MAIN: "Основная рука",
	EquipmentData.Slot.WEAPON_OFF: "Вспомогательная рука",
	EquipmentData.Slot.ACCESSORY: "Аксессуар",
}

const WEAPON_TYPE_NAMES := {
	EquipmentData.WeaponType.NONE: "Снаряжение",
	EquipmentData.WeaponType.MELEE_ONE_HAND: "Одноручное оружие",
	EquipmentData.WeaponType.MELEE_TWO_HAND: "Двуручное оружие",
	EquipmentData.WeaponType.RANGED: "Двуручное дальнобойное оружие",
	EquipmentData.WeaponType.SHIELD: "Щит",
	EquipmentData.WeaponType.MAGIC: "Двуручное магическое оружие",
}

const EFFECT_NAMES := {
	ConsumableData.EffectType.HEAL_HP: "Восстановление здоровья",
	ConsumableData.EffectType.HEAL_PERCENT: "Восстановление здоровья",
	ConsumableData.EffectType.BUFF_STRENGTH: "Усиление силы",
	ConsumableData.EffectType.BUFF_AGILITY: "Усиление ловкости",
	ConsumableData.EffectType.BUFF_INTELLECT: "Усиление интеллекта",
	ConsumableData.EffectType.BUFF_REGEN: "Регенерация",
}

const LARGE_ICON_SIZE := Vector2(144, 144)
