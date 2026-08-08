## Developer-facing visual style settings shared by the game scene and settings UI.
## Values are persisted separately from save slots in user://settings.cfg.
extends Node


signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "developer_visual"

const DEFAULT_SHOW_GRASS := true
const DEFAULT_PIXELATION_ENABLED := true
const DEFAULT_PIXEL_SIZE := 2.0
const DEFAULT_PALETTE_ENABLED := false
const DEFAULT_PALETTE_LEVELS := 19.0
const DEFAULT_OUTLINES_ENABLED := true
const DEFAULT_OUTLINE_THICKNESS := 1.0
const DEFAULT_OUTLINE_STRENGTH := 0.50
const DEFAULT_EXCLUDE_GRASS_OUTLINES := true
const DEFAULT_DARK_EDGES_ENABLED := true
const DEFAULT_DARK_SURFACE_THRESHOLD := 0.02
const DEFAULT_DARK_EDGE_STRENGTH := 0.05
const DEFAULT_TOON_CUTS := 3.0
const DEFAULT_QUANTISED_GRASS := true
const DEFAULT_GRASS_FPS := 5.0

var show_grass := DEFAULT_SHOW_GRASS
var pixelation_enabled := DEFAULT_PIXELATION_ENABLED
var pixel_size := DEFAULT_PIXEL_SIZE
var palette_enabled := DEFAULT_PALETTE_ENABLED
var palette_levels := DEFAULT_PALETTE_LEVELS
var outlines_enabled := DEFAULT_OUTLINES_ENABLED
var outline_thickness := DEFAULT_OUTLINE_THICKNESS
var outline_strength := DEFAULT_OUTLINE_STRENGTH
var exclude_grass_outlines := DEFAULT_EXCLUDE_GRASS_OUTLINES
var dark_edges_enabled := DEFAULT_DARK_EDGES_ENABLED
var dark_surface_threshold := DEFAULT_DARK_SURFACE_THRESHOLD
var dark_edge_strength := DEFAULT_DARK_EDGE_STRENGTH
var toon_cuts := DEFAULT_TOON_CUTS
var quantised_grass := DEFAULT_QUANTISED_GRASS
var grass_fps := DEFAULT_GRASS_FPS

var _save_queued := false


func _ready() -> void:
	_load_settings()


func set_setting(key: StringName, value: Variant) -> void:
	var normalized: Variant = _normalize(key, value)
	if normalized == null:
		push_warning("VisualSettings: unknown setting '%s'." % key)
		return
	if get(key) == normalized:
		return
	set(key, normalized)
	settings_changed.emit()
	_queue_save()


func reset_to_defaults() -> void:
	show_grass = DEFAULT_SHOW_GRASS
	pixelation_enabled = DEFAULT_PIXELATION_ENABLED
	pixel_size = DEFAULT_PIXEL_SIZE
	palette_enabled = DEFAULT_PALETTE_ENABLED
	palette_levels = DEFAULT_PALETTE_LEVELS
	outlines_enabled = DEFAULT_OUTLINES_ENABLED
	outline_thickness = DEFAULT_OUTLINE_THICKNESS
	outline_strength = DEFAULT_OUTLINE_STRENGTH
	exclude_grass_outlines = DEFAULT_EXCLUDE_GRASS_OUTLINES
	dark_edges_enabled = DEFAULT_DARK_EDGES_ENABLED
	dark_surface_threshold = DEFAULT_DARK_SURFACE_THRESHOLD
	dark_edge_strength = DEFAULT_DARK_EDGE_STRENGTH
	toon_cuts = DEFAULT_TOON_CUTS
	quantised_grass = DEFAULT_QUANTISED_GRASS
	grass_fps = DEFAULT_GRASS_FPS
	settings_changed.emit()
	_queue_save()


func _normalize(key: StringName, value: Variant) -> Variant:
	match key:
		&"show_grass", &"pixelation_enabled", &"palette_enabled", \
		&"outlines_enabled", &"exclude_grass_outlines", \
		&"dark_edges_enabled", &"quantised_grass":
			return bool(value)
		&"pixel_size":
			return snappedf(clampf(float(value), 1.0, 8.0), 1.0)
		&"palette_levels":
			return snappedf(clampf(float(value), 2.0, 32.0), 1.0)
		&"outline_thickness":
			return snappedf(clampf(float(value), 1.0, 4.0), 0.25)
		&"outline_strength", &"dark_edge_strength":
			return snappedf(clampf(float(value), 0.0, 1.0), 0.05)
		&"dark_surface_threshold":
			return snappedf(clampf(float(value), 0.01, 0.30), 0.01)
		&"toon_cuts":
			return snappedf(clampf(float(value), 1.0, 8.0), 1.0)
		&"grass_fps":
			return snappedf(clampf(float(value), 1.0, 20.0), 1.0)
	return null


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key: StringName in _setting_keys():
		var fallback: Variant = get(key)
		var normalized: Variant = _normalize(key, cfg.get_value(SECTION, key, fallback))
		if normalized != null:
			set(key, normalized)


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_save_deferred.call_deferred()


func _save_deferred() -> void:
	_save_queued = false
	var cfg := ConfigFile.new()
	# Preserve settings owned by the input, font and camera systems.
	cfg.load(SETTINGS_PATH)
	for key: StringName in _setting_keys():
		cfg.set_value(SECTION, key, get(key))
	var error := cfg.save(SETTINGS_PATH)
	if error != OK:
		push_warning("VisualSettings: failed to save settings (%s)." % error_string(error))


func _setting_keys() -> Array[StringName]:
	return [
		&"show_grass",
		&"pixelation_enabled",
		&"pixel_size",
		&"palette_enabled",
		&"palette_levels",
		&"outlines_enabled",
		&"outline_thickness",
		&"outline_strength",
		&"exclude_grass_outlines",
		&"dark_edges_enabled",
		&"dark_surface_threshold",
		&"dark_edge_strength",
		&"toon_cuts",
		&"quantised_grass",
		&"grass_fps",
	]
