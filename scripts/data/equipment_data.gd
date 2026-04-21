extends Resource
class_name EquipmentData

enum Slot { HEAD, BODY, LEGS, WEAPON_MAIN, WEAPON_OFF, ACCESSORY }
enum WeaponType { NONE, MELEE_ONE_HAND, MELEE_TWO_HAND, RANGED, SHIELD }

@export var id: String = ""
@export var display_name: String = ""
@export var slot: Slot = Slot.BODY
@export var weapon_type: WeaponType = WeaponType.NONE
@export var icon: Texture2D
@export var stat_bonuses: Dictionary = {}
@export var buy_price: int = 0
@export var sell_price: int = 0
