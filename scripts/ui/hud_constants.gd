## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name HUDConstants
extends RefCounted

## Как часто (сек) обновляются подписи таймеров статусов в развёрнутой панели.
const STATUS_TIMER_REFRESH: float = 0.2

## Сколько секунд «тост» нового статуса живёт в ленте, прежде чем угаснуть.
const TOAST_LIFETIME: float = 3.0

## Длительность плавного исчезания тоста.
const TOAST_FADE: float = 0.4

## Максимум одновременно видимых тостов в ленте (FIFO — старые вытесняются).
const MAX_TOASTS: int = 5

const BUFF_ACCENT: Color = Color(0.498, 0.682, 0.384)

const DEBUFF_ACCENT: Color = Color(0.82, 0.416, 0.29)

const NAME_COLOR: Color = Color(0.757, 0.675, 0.525)

const TIMER_COLOR: Color = Color(0.604, 0.545, 0.494)

## Фон тоста в ленте и фон строки в развёрнутом списке.
const TOAST_BG: Color = Color(0.039, 0.031, 0.035, 0.82)

const ROW_BG: Color = Color(0.078, 0.063, 0.055, 0.4)

const PORTRAIT_BG: Color = Color(0.086, 0.067, 0.067)

const PORTRAIT_BORDER: Color = Color(0.725, 0.541, 0.369, 0.8)
