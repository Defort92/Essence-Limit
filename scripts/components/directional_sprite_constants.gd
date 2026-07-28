## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name DirectionalSpriteConstants
extends RefCounted

## Подпапки ракурсов в порядке секторов (индекс = сектор из face_direction).
const DIR_FOLDERS: PackedStringArray = [
	"front", "front-right", "full-right", "rear-right",
	"back", "rear-left", "full-left", "front-left",
]

## Исходный сектор для зеркальной левой анимации. -1 означает уникальную серию.
const MIRROR_SOURCE_SECTORS: PackedInt32Array = [
	-1, -1, -1, -1, -1, 3, 2, 1,
]
