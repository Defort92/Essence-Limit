## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name ControlsSettingsConstants
extends RefCounted

## Действия передвижения — рабочие только в режиме клавиатуры (в режиме мыши бег по ПКМ).
const MOVEMENT_ACTIONS: Array = ["move_up", "move_down", "move_left", "move_right"]

## Прочие привязываемые действия — общие для обоих режимов бега.
const COMMON_ACTIONS: Array = [
	"dodge", "interact",
	"ability_1", "ability_2", "ability_3", "ability_4",
	"consumable_1", "consumable_2", "consumable_3", "consumable_4",
	"inventory", "states", "party_command",
]

const ACTION_LABELS := {
	"move_up": "Движение вверх",
	"move_down": "Движение вниз",
	"move_left": "Движение влево",
	"move_right": "Движение вправо",
	"dodge": "Уклонение",
	"interact": "Взаимодействие",
	"ability_1": "Способность 1",
	"ability_2": "Способность 2",
	"ability_3": "Способность 3",
	"ability_4": "Способность 4",
	"consumable_1": "Расходник 1",
	"consumable_2": "Расходник 2",
	"consumable_3": "Расходник 3",
	"consumable_4": "Расходник 4",
	"inventory": "Инвентарь",
	"states": "Состояния",
	"party_command": "Команда отряду (формация)",
}

## Действия, сознательно НЕ показываемые здесь — привязаны к мыши (attack/block) или это
## служебный "pause" (Esc), который не переназначается. Любое другое действие из InputMap,
## которого нет ни здесь, ни в MOVEMENT_ACTIONS/COMMON_ACTIONS, считается забытым — см.
## _warn_about_unlisted_actions().
const EXCLUDED_ACTIONS: Array = ["attack", "block", "pause"]
