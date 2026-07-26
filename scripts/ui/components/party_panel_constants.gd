## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name PartyPanelConstants
extends RefCounted

## Порог доверия → «настроение»: подпись и цвет рамки/точки/подписи карточки.
## Проверяются по убыванию; первое подходящее и берётся.
const MORALE_TIERS: Array[Dictionary] = [
	{ "min": 75, "label": "Спокоен",    "color": Color(0.435, 0.682, 0.384) },
	{ "min": 50, "label": "Встревожен", "color": Color(0.839, 0.635, 0.306) },
	{ "min": 25, "label": "Дрогнул",    "color": Color(0.839, 0.404, 0.184) },
	{ "min":  0, "label": "Безумие",    "color": Color(0.722, 0.157, 0.110) },
]

const NAME_COLOR: Color = Color(0.780, 0.710, 0.600)

const LEVEL_COLOR: Color = Color(0.910, 0.863, 0.769)

const HEADER_COLOR: Color = Color(0.490, 0.447, 0.408)

const PORTRAIT_BG: Color = Color(0.086, 0.067, 0.067)

const HP_BG: Color = Color(0.102, 0.039, 0.035)

const HP_FILL: Color = Color(0.722, 0.157, 0.110)

## Цвет полосы HP, когда здоровья мало (доля ниже этого порога) — тревожный ярко-красный.
const HP_LOW_FILL: Color = Color(0.847, 0.290, 0.165)

const HP_LOW_THRESHOLD: float = 0.30

const PORTRAIT_SIZE: float = 58.0

const CARD_WIDTH: float = 82.0

## Как часто (сек) обновляются значения карточек и проверяется смена состава отряда.
const REFRESH_INTERVAL: float = 0.15
