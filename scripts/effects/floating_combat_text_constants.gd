## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name FloatingCombatTextConstants
extends RefCounted

## Полное время жизни числа (сек) — «буквально пару секунд».
const LIFETIME: float = 1.4

## Высота подскока при появлении (мировые единицы).
const RISE_HEIGHT: float = 0.7

## Дистанция падения вниз на фазе исчезания.
const FALL_DISTANCE: float = 0.9

## Доля жизни, после которой число начинает гаснуть и падать.
const FADE_START: float = 0.55

## Длительность дрожания при появлении (только крит), сек.
const SHAKE_TIME: float = 0.28

## Амплитуда дрожания крита (мировые единицы).
const SHAKE_AMPLITUDE: float = 0.09

const BASE_FONT_SIZE: int = 32

const CRIT_FONT_SIZE: int = 46

## Шрифт интерфейса — чтобы цифры совпадали по стилю с остальным UI (не дефолтный шрифт).
const UI_FONT_PATH: String = "res://assets/fonts/DotGothic16-Regular.ttf"
