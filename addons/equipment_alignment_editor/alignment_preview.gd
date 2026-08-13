@tool
extends Control

signal offset_dragged(value: Vector2)

const BACKGROUND := Color("17151b")
const GRID_DARK := Color("201e25")
const GRID_LIGHT := Color("292630")
const CENTER_LINE := Color(1.0, 1.0, 1.0, 0.15)

var body_texture: Texture2D
var equipment_texture: Texture2D
var equipment_offset := Vector2.ZERO
var zoom := 3.0

var _dragging := false
var _drag_origin := Vector2.ZERO
var _offset_origin := Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(420.0, 420.0)
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_preview(body: Texture2D, equipment: Texture2D, value: Vector2) -> void:
	body_texture = body
	equipment_texture = equipment
	equipment_offset = value
	queue_redraw()


func set_equipment_offset(value: Vector2) -> void:
	equipment_offset = value
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	_draw_grid()
	var center := size * 0.5
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), CENTER_LINE)
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), CENTER_LINE)
	_draw_centered_texture(body_texture, Vector2.ZERO)
	_draw_centered_texture(equipment_texture, equipment_offset)


func _draw_grid() -> void:
	var cell := 8.0 * zoom
	var columns := ceili(size.x / cell)
	var rows := ceili(size.y / cell)
	for y in rows:
		for x in columns:
			var color := GRID_LIGHT if (x + y) % 2 == 0 else GRID_DARK
			draw_rect(Rect2(Vector2(x, y) * cell, Vector2.ONE * cell), color)


func _draw_centered_texture(texture: Texture2D, pixel_offset: Vector2) -> void:
	if texture == null:
		return
	var draw_size := texture.get_size() * zoom
	var draw_position := (size - draw_size) * 0.5 + pixel_offset * zoom
	draw_texture_rect(texture, Rect2(draw_position, draw_size), false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_origin = event.position
			_offset_origin = equipment_offset
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var delta_pixels: Vector2 = (event.position - _drag_origin) / zoom
		var value := _offset_origin + Vector2(roundi(delta_pixels.x), roundi(delta_pixels.y))
		offset_dragged.emit(value)
		accept_event()
