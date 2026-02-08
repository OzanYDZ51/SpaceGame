class_name AsteroidFieldData
extends RefCounted

# =============================================================================
# Asteroid Field Data - Data for an entire asteroid belt/field
# =============================================================================

var field_name: String = ""
var field_id: StringName = &""
var orbital_radius: float = 0.0
var width: float = 0.0
var dominant_resource: StringName = &"iron"
var secondary_resource: StringName = &"copper"
var rare_resource: StringName = &"gold"
var asteroids: Array[AsteroidData] = []
