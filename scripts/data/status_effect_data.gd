## Описание статус-эффекта (благо или недуг): что показать в UI и какие модификаторы
## статов наложить, пока эффект активен. Задаётся .tres-ресурсом и накладывается через
## StatusComponent.apply_status(). Благо/недуг определяет колонку и подсветку в UI.
extends Resource
class_name StatusEffectData

## Уникальный ключ статуса. Повторное наложение статуса с тем же id обновляет
## таймер, а не создаёт дубликат (см. StatusComponent.apply_status).
@export var id: String = ""
@export var display_name: String = "Статус"
@export_multiline var description: String = ""
## Юникод-глиф-иконка в стиле дизайна (✦ ✧ ♨ ⚔ ❄ и т.п.).
@export var glyph: String = "◆"
## Цвет глифа и акцентов строки в UI.
@export var color: Color = Color(0.839, 0.698, 0.353)
## true — недуг (дебафф, колонка НЕДУГИ), false — благо (бафф, колонка БЛАГА).
@export var is_debuff: bool = false
## Длительность в секундах. 0 — постоянный (снимается вручную или источником).
@export var duration: float = 0.0
## Модификаторы статов, действующие пока статус активен. Могут быть пустыми —
## тогда статус чисто визуальный/флаговый.
@export var modifiers: Array[StatModifier] = []
