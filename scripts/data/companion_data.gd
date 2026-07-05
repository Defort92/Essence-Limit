## Данные кандидата на вербовку в отряд (предлагается NPC-вербовщиком в городе).
## При найме создаётся запись в PartySystem.roster и спавнится обычный Player-инстанс —
## наёмник использует ту же логику, что и главный герой.
extends Resource
class_name CompanionData

@export var display_name: String = ""
## Раса определяет базовые статы (GameManager.RACE_BASE_STATS).
## Порядок значений совпадает с GameManager.Race.
@export_enum("Человек", "Варвар", "Эльф", "Демон", "Ангел") var race: int = 0
@export var hire_cost: int = 100
## Стартовое доверие (0–100). При падении до 0 наёмник предаёт отряд или сбегает.
@export_range(0, 100) var initial_trust: int = 50
