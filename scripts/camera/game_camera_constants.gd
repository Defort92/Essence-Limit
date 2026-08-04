## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name GameCameraConstants
extends RefCounted

# Угол камеры: ~60° вниз, фиксирован — 2.5D перспектива
const PITCH_DEG: float = -60.0

# Player scenes use their root at the feet; the sprite center is 0.96 units higher.
const TARGET_FOCUS_HEIGHT: float = 0.96

const FOLLOW_SPEED: float = 8.0

# Camera distance in world units. Lower values bring the camera closer.
# DEFAULT_DISTANCE is used until the player changes it in the settings menu.
const DEFAULT_DISTANCE: float = 11.5
const MIN_DISTANCE: float = 9.0
const MAX_DISTANCE: float = 15.0
const DISTANCE_STEP: float = 0.5
