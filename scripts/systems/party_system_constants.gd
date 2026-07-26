## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name PartySystemConstants
extends RefCounted

const MAX_PARTY_SIZE: int = 5

## Сколько секунд новый активный участник неуязвим после переключения — защита от
## мгновенной смерти, если управление передали посреди боя.
const SWITCH_INVULNERABILITY_DURATION: float = 1.2

## На сколько падает доверие каждого наёмника, когда участник отряда погибает.
const TRUST_LOSS_ON_MEMBER_DEATH: int = 15

## Шанс предательства (иначе побег) при падении доверия до нуля.
const BETRAYAL_CHANCE: float = 0.5

const COMPANION_SCENE_PATH := "res://scenes/characters/player.tscn"
