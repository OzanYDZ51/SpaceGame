class_name MapCamera
extends RefCounted

# =============================================================================
# Map Camera - Zoom/Pan state and coordinate projection
# Handles logarithmic zoom, smooth interpolation, universe↔screen conversion
# =============================================================================

# Zoom is in "pixels per meter" (logarithmic scale)
const ZOOM_MIN: float = 5e-6     # Full system view (~384M meters visible)
const ZOOM_MAX: float = 2.0       # Tactical view (~960m visible)
const ZOOM_STEP: float = 1.12     # Multiplier per scroll notch
const ZOOM_SMOOTH_SPEED: float = 8.0

# Zoom presets (pixels per meter)
const PRESET_TACTICAL: float = 1.0
const PRESET_LOCAL: float = 0.01
const PRESET_REGIONAL: float = 0.0001
const PRESET_SYSTEM: float = 1e-5
const PRESET_FULL: float = 5e-6

# Current state
var zoom: float = 0.0001           # current zoom (pixels per meter)
var target_zoom: float = 0.0001    # target zoom for smooth interpolation
var center_x: float = 0.0         # universe position at screen center (float64)
var center_z: float = 0.0         # (we use X/Z plane, Y is up in Godot)
var screen_size: Vector2 = Vector2(1920, 1080)

# Follow
var follow_entity_id: String = ""
var follow_enabled: bool = true

# Pan limits
var system_radius: float = 100_000_000.0

# Zoom anchor: world point under cursor stays fixed during smooth zoom
var _anchor_world_x: float = 0.0
var _anchor_world_z: float = 0.0
var _anchor_screen: Vector2 = Vector2.ZERO
var _anchored: bool = false


func update(delta: float) -> void:
	# Smooth zoom interpolation (logarithmic)
	if absf(log(zoom) - log(target_zoom)) > 0.001:
		var log_current: float = log(zoom)
		var log_target: float = log(target_zoom)
		var log_new: float = lerpf(log_current, log_target, minf(ZOOM_SMOOTH_SPEED * delta, 1.0))
		zoom = exp(log_new)

		# Keep anchor point fixed on screen each frame
		if _anchored and not follow_enabled:
			center_x = _anchor_world_x - (_anchor_screen.x - screen_size.x * 0.5) / zoom
			center_z = _anchor_world_z - (_anchor_screen.y - screen_size.y * 0.5) / zoom
	else:
		zoom = target_zoom
		_anchored = false

	# Follow entity
	if follow_enabled and follow_entity_id != "":
		var ent: Dictionary = EntityRegistry.get_entity(follow_entity_id)
		if not ent.is_empty():
			center_x = ent["pos_x"]
			center_z = ent["pos_z"]

	clamp_center()


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	# Record world point under cursor as anchor
	_anchor_world_x = screen_to_universe_x(screen_pos.x)
	_anchor_world_z = screen_to_universe_z(screen_pos.y)
	_anchor_screen = screen_pos
	_anchored = true

	target_zoom = clampf(target_zoom * factor, ZOOM_MIN, ZOOM_MAX)


func pan(screen_delta: Vector2) -> void:
	center_x -= screen_delta.x / zoom
	center_z -= screen_delta.y / zoom
	follow_enabled = false
	clamp_center()


func set_preset(index: int) -> void:
	match index:
		1: target_zoom = PRESET_TACTICAL
		2: target_zoom = PRESET_LOCAL
		3: target_zoom = PRESET_REGIONAL
		4: target_zoom = PRESET_SYSTEM
		5: target_zoom = PRESET_FULL
	target_zoom = clampf(target_zoom, ZOOM_MIN, ZOOM_MAX)


func recenter_on_player() -> void:
	follow_enabled = true


func universe_to_screen(ux: float, uz: float) -> Vector2:
	var sx: float = (ux - center_x) * zoom + screen_size.x * 0.5
	var sy: float = (uz - center_z) * zoom + screen_size.y * 0.5
	return Vector2(sx, sy)


func screen_to_universe_x(sx: float) -> float:
	return center_x + (sx - screen_size.x * 0.5) / zoom


func screen_to_universe_z(sy: float) -> float:
	return center_z + (sy - screen_size.y * 0.5) / zoom


func get_visible_range() -> float:
	# Returns the approximate width in meters visible on screen
	return screen_size.x / zoom


func get_zoom_label() -> String:
	if zoom >= 0.5:
		return "TACTIQUE"
	elif zoom >= 0.005:
		return "LOCAL"
	elif zoom >= 5e-5:
		return "RÉGIONAL"
	elif zoom >= 5e-6:
		return "SYSTÈME"
	else:
		return "VUE COMPLÈTE"


func clamp_center() -> void:
	var limit: float = system_radius * 2.0
	center_x = clampf(center_x, -limit, limit)
	center_z = clampf(center_z, -limit, limit)


func format_distance(meters: float) -> String:
	var au: float = Constants.AU_IN_METERS
	if meters >= au * 0.1:
		return "%.2f AU" % (meters / au)
	elif meters >= 1e6:
		return "%.1f Mm" % (meters / 1e6)
	elif meters >= 1000.0:
		return "%.1f km" % (meters / 1000.0)
	else:
		return "%.0f m" % meters
