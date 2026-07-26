## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name AbilityManagerConstants
extends RefCounted

## Маппинг Input Action → индекс слота эссенции.
## Добавь ability_1..ability_4 в Project Settings → Input Map (клавиши Q/E/R/F).
const DEFAULT_BINDINGS: Dictionary = {
	"ability_1": 0,
	"ability_2": 1,
	"ability_3": 2,
	"ability_4": 3,
}
