## Фракции для боевого таргетинга. Не Resource, не нода — статический хелпер.
## Kind.ALLY/HOSTILE_NPC пока никем не используются — задел под будущих "проходимцев"
## (союзников или враждебных людей), концепция которых ещё не определена.
extends RefCounted
class_name Faction

enum Kind { PLAYER, MONSTER, ALLY, HOSTILE_NPC, NEUTRAL }

## Возвращает [code]true[/code], если фракция [param a] враждебна фракции [param b].
## NEUTRAL никому не враждебна (и ей никто).
static func is_hostile(a: Kind, b: Kind) -> bool:
	if a == Kind.NEUTRAL or b == Kind.NEUTRAL:
		return false
	match a:
		Kind.PLAYER, Kind.ALLY:
			return b == Kind.MONSTER or b == Kind.HOSTILE_NPC
		Kind.MONSTER, Kind.HOSTILE_NPC:
			return b == Kind.PLAYER or b == Kind.ALLY
	return false
