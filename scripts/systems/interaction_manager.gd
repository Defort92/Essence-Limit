## Единая точка обработки действия "interact".
##
## Интерактивный узел добавляется в группу "interactable" и реализует контракт:
##  - is_interaction_available(interactor: Node3D) -> bool
##  - interact(interactor: Node3D) -> bool
## Опционально:
##  - get_interaction_priority() -> int (по умолчанию 0)
##
## Из всех доступных целей выбирается одна: сначала с наибольшим приоритетом, затем
## ближайшая к активному персонажу. Поэтому порядок узлов в сцене не влияет на результат.
extends Node


func _unhandled_input(event: InputEvent) -> void:
	if PauseManager.is_paused or not event.is_action_pressed("interact"):
		return
	# Видимое игровое окно само использует клавишу для закрытия; взаимодействовать с миром
	# сквозь него нельзя.
	for screen in get_tree().get_nodes_in_group("modal_screen"):
		if screen.visible:
			return

	var interactor := PartySystem.get_active_member() as Node3D
	if interactor == null:
		return
	var target := _select_target(interactor)
	if target == null:
		return
	if bool(target.interact(interactor)):
		get_viewport().set_input_as_handled()


func _select_target(interactor: Node3D) -> Node:
	var best: Node = null
	var best_priority := -2147483648
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(candidate):
			continue
		if not candidate.has_method("is_interaction_available") or not candidate.has_method("interact"):
			continue
		if not bool(candidate.is_interaction_available(interactor)):
			continue
		var priority := 0
		if candidate.has_method("get_interaction_priority"):
			priority = int(candidate.get_interaction_priority())
		var distance := _distance_squared(candidate, interactor)
		if priority > best_priority or (priority == best_priority and distance < best_distance):
			best = candidate
			best_priority = priority
			best_distance = distance
	return best


func _distance_squared(candidate: Node, interactor: Node3D) -> float:
	if candidate is Node3D:
		return interactor.global_position.distance_squared_to((candidate as Node3D).global_position)
	return INF
