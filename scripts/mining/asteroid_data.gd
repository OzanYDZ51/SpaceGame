class_name AsteroidData
extends RefCounted

# =============================================================================
# Asteroid Data - Pure data representation of a single asteroid
# =============================================================================

enum AsteroidSize { SMALL, MEDIUM, LARGE }

var id: StringName = &""
var field_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var rotation_axis: Vector3 = Vector3.UP
var rotation_speed: float = 0.1
var size: AsteroidSize = AsteroidSize.SMALL
var primary_resource: StringName = &"iron"
var health_max: float = 100.0
var health_current: float = 100.0
var is_depleted: bool = false
var respawn_timer: float = 0.0
var visual_radius: float = 10.0
var color_tint: Color = Color.GRAY
var scale_distort: Vector3 = Vector3.ONE  # Non-uniform scale for rocky look
var has_resource: bool = true       # false = barren rock (no yield)
var is_scanned: bool = false        # true = resource revealed by scanner
var scan_expire_time: float = 0.0   # Time.get_ticks_msec() when scan expires
var resource_color: Color = Color.GRAY  # True resource color (hidden until scanned)

# Runtime references (null when data-only / LOD3+)
var node_ref: Node3D = null


func get_yield_per_hit() -> int:
	match size:
		AsteroidSize.SMALL: return 1
		AsteroidSize.MEDIUM: return 2
		AsteroidSize.LARGE: return 4
	return 1


func get_health_for_size() -> float:
	match size:
		AsteroidSize.SMALL: return 50.0
		AsteroidSize.MEDIUM: return 150.0
		AsteroidSize.LARGE: return 400.0
	return 50.0


func get_radius_for_size() -> float:
	match size:
		AsteroidSize.SMALL: return 8.0
		AsteroidSize.MEDIUM: return 18.0
		AsteroidSize.LARGE: return 35.0
	return 8.0
