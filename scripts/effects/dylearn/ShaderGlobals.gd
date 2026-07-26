# MIT License. 
# Made by Dylearn

# Node for ease of editing shader globals

@tool
extends Node

@export var cloud_contrast : float:
	set(value):
		cloud_contrast = value
		RenderingServer.global_shader_parameter_set("cloud_contrast", value)

@export var cloud_direction : Vector2:
	set(value):
		cloud_direction = value
		RenderingServer.global_shader_parameter_set("cloud_direction", value)

@export var cloud_diverge_angle : float:
	set(value):
		cloud_diverge_angle = value
		RenderingServer.global_shader_parameter_set("cloud_diverge_angle", value)

@export var cloud_scale : float:
	set(value):
		cloud_scale = value
		RenderingServer.global_shader_parameter_set("cloud_scale", value)

@export var cloud_speed : float:
	set(value):
		cloud_speed = value
		RenderingServer.global_shader_parameter_set("cloud_speed", value)

@export var cloud_threshold : float:
	set(value):
		cloud_threshold = value
		RenderingServer.global_shader_parameter_set("cloud_threshold", value)

@export var cloud_shadow_min : float:
	set(value):
		cloud_shadow_min = value
		RenderingServer.global_shader_parameter_set("cloud_shadow_min", value)

@export var cloud_world_y : float:
	set(value):
		cloud_world_y = value
		RenderingServer.global_shader_parameter_set("cloud_world_y", value)


func _ready():
	if Engine.is_editor_hint():
		# A fresh editor scan can instantiate this @tool node before shader globals
		# are registered. Keep the scene's exported values instead of assigning Nil.
		var value = RenderingServer.global_shader_parameter_get("cloud_contrast")
		if value != null:
			cloud_contrast = value
		value = RenderingServer.global_shader_parameter_get("cloud_direction")
		if value != null:
			cloud_direction = value
		value = RenderingServer.global_shader_parameter_get("cloud_diverge_angle")
		if value != null:
			cloud_diverge_angle = value
		value = RenderingServer.global_shader_parameter_get("cloud_scale")
		if value != null:
			cloud_scale = value
		value = RenderingServer.global_shader_parameter_get("cloud_speed")
		if value != null:
			cloud_speed = value
		value = RenderingServer.global_shader_parameter_get("cloud_threshold")
		if value != null:
			cloud_threshold = value
		value = RenderingServer.global_shader_parameter_get("cloud_shadow_min")
		if value != null:
			cloud_shadow_min = value
		value = RenderingServer.global_shader_parameter_get("cloud_world_y")
		if value != null:
			cloud_world_y = value
