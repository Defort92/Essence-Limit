extends Node

enum PortalState { CLOSED, OPEN }

var state: PortalState = PortalState.CLOSED
var current_floor: int = 0
const MAX_FLOORS: int = 15

signal portal_opened()
signal portal_closed()
signal floor_changed(floor: int)

func open_portal() -> void:
	if state == PortalState.OPEN:
		return
	state = PortalState.OPEN
	XPSystem.on_run_started()
	portal_opened.emit()

func close_portal() -> void:
	if state == PortalState.CLOSED:
		return
	state = PortalState.CLOSED
	# Игрок телепортируется к входу — обрабатывается сценой игрока
	portal_closed.emit()
	current_floor = 0

func enter_floor(floor_index: int) -> void:
	assert(floor_index >= 1 and floor_index <= MAX_FLOORS)
	current_floor = floor_index
	floor_changed.emit(current_floor)

func is_inside() -> bool:
	return current_floor > 0

func is_open() -> bool:
	return state == PortalState.OPEN
