class_name MapCamera
extends RefCounted

# =============================================================================
# Map Camera - Zoom/Pan state and coordinate projection
# Handles logarithmic zoom, smooth interpolation, universe↔screen conversion
# =============================================================================

# Zoom is in "pixels per meter" (logarithmic scale)
const ZOOM_MIN: float = 5e-6     # Full system view (~384M meters visible)
const ZOOM_MAX: float = 2.0       # Hard cap (limited by scale bar limit in practice)
const ZOOM_STEP: float = 1.35     # Multiplier per scroll notch (~42 notches full range)
const ZOOM_SMOOTH_SPEED: float = 14.0
# Scale bar zoom cap: ensures the bottom-right scale bar never shows less than 10 km.
# max_zoom = SCALE_BAR_PX / SCALE_BAR_MIN_METERS = 120 / 10000 = 0.012
const SCALE_BAR_PX: float = 120.0           # must match MapRenderer target_px
const SCALE_BAR_MIN_METERS: float = 10_000.0 # 10 km minimum on scale bar

# Zoom presets (pixels per meter)
const PRESET_TACTICAL: float = 0.012  # matches max zoom (~10 km scale bar)
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


## Effective max zoom: scale bar never shows less than SCALE_BAR_MIN_METERS.
func max_zoom() -> float:
	return minf(ZOOM_MAX, SCALE_BAR_PX / SCALE_BAR_MIN_METERS)


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	# Record world point under cursor as anchor
	_anchor_world_x = screen_to_universe_x(screen_pos.x)
	_anchor_world_z = screen_to_universe_z(screen_pos.y)
	_anchor_screen = screen_pos
	_anchored = true

	target_zoom = clampf(target_zoom * factor, ZOOM_MIN, max_zoom())


func pan(screen_delta: Vector2) -> void:
	center_x -= screen_delta.x / zoom
	center_z -= screen_delta.y / zoom
	follow_enabled = false
	_anchored = false  # Break zoom anchor so pan + zoom can coexist
	clamp_center()


func set_preset(index: int) -> void:
	match index:
		1: target_zoom = PRESET_TACTICAL
		2: target_zoom = PRESET_LOCAL
		3: target_zoom = PRESET_REGIONAL
		4: target_zoom = PRESET_SYSTEM
		5: target_zoom = PRESET_FULL
	target_zoom = clampf(target_zoom, ZOOM_MIN, max_zoom())


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
	if zoom >= 0.008:
		return "TACTIQUE"
	elif zoom >= 0.001:
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


func fit_entities(entities: Dictionary, animate: bool = true) -> void:
	# Compute bounding box of all entities to determine ideal zoom
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	var count: int = 0
	for ent in entities.values():
		var etype: int = ent["type"]
		# Skip asteroid belts for fit (they're background)
		if etype == EntityRegistrySystem.EntityType.ASTEROID_BELT:
			continue
		var px: float = ent["pos_x"]
		var pz: float = ent["pos_z"]
		min_x = minf(min_x, px)
		max_x = maxf(max_x, px)
		min_z = minf(min_z, pz)
		max_z = maxf(max_z, pz)
		count += 1
	if count == 0:
		return
	# Add 15% padding
	var range_x: float = maxf(max_x - min_x, 1000.0)
	var range_z: float = maxf(max_z - min_z, 1000.0)
	range_x *= 1.3
	range_z *= 1.3
	# Choose zoom so the larger dimension fits on screen
	var zoom_x: float = screen_size.x * 0.6 / range_x  # 0.6 = usable viewport fraction
	var zoom_z: float = screen_size.y * 0.85 / range_z
	var fit_zoom: float = minf(zoom_x, zoom_z)
	fit_zoom = clampf(fit_zoom, ZOOM_MIN, max_zoom())
	# Center on bounding box center
	center_x = (min_x + max_x) * 0.5
	center_z = (min_z + max_z) * 0.5
	follow_enabled = false
	if animate:
		target_zoom = fit_zoom
	else:
		zoom = fit_zoom
		target_zoom = fit_zoom


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
