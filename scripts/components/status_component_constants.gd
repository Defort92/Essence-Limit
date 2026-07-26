## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name StatusComponentConstants
extends RefCounted

## Демо-набор статусов, раздаваемых на старте (см. grant_demo_statuses). Оба типа —
## благо и недуг — чтобы экран состояний был наполнен сразу.
const DEMO_STATUSES: Array[String] = [
	"res://resources/statuses/vigor.tres",
	"res://resources/statuses/blessing.tres",
	"res://resources/statuses/fatigue.tres",
]
