## Зона восстановления здоровья. Расширяет AuraComponent, но вместо «сырого» модификатора
## накладывает на вошедших полноценный статус-эффект (StatusEffectData «Регенерация»).
## Благодаря этому вход в зону сразу даёт уведомление (тост «Регенерация» в HUD) и строку
## в списке состояний, а само лечение идёт постепенно через тик регенерации существа
## (модификатор "regen" внутри статуса). При выходе из зоны статус снимается.
## Аура действует строго в пределах radius — того же радиуса, что и зелёный диск-маркер.
extends AuraComponent
class_name HealingAura

## Статус, накладываемый внутри зоны (обычно resources/statuses/regeneration.tres).
@export var status_effect: StatusEffectData
## Рисовать зелёный диск-маркер на земле по радиусу зоны.
@export var show_marker: bool = true

func _ready() -> void:
	if status_effect == null:
		status_effect = _build_default_status()
	super._ready()
	if show_marker:
		_build_marker()

## Вход существа в зону — накладываем статус (это же даёт уведомление в HUD).
## Переопределяет базовый _apply_to (тот раскладывал бы массив modifiers).
func _apply_to(entity: Node3D) -> void:
	if status_effect != null and entity.has_method("apply_status_effect"):
		entity.apply_status_effect(status_effect)

## Выход существа из зоны — снимаем статус.
func _remove_from(entity: Node3D) -> void:
	if status_effect != null and entity.has_method("remove_status_effect"):
		entity.remove_status_effect(status_effect.id)

## Запасной статус регенерации, если ресурс не назначен в сцене.
func _build_default_status() -> StatusEffectData:
	var mod := StatModifier.new()
	mod.stat = "regen"
	mod.op = StatModifier.Op.ADD
	mod.value = 6.0
	var data := StatusEffectData.new()
	data.id = "regeneration"
	data.display_name = "Регенерация"
	data.description = "Целебная аура затягивает раны."
	data.glyph = "✚"
	data.color = Color(0.373, 0.83, 0.478)
	data.is_debuff = false
	data.duration = 0.0
	data.modifiers = [mod]
	return data

func _build_marker() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.9, 0.4, 0.22)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.03, 0.0)
	add_child(mi)
