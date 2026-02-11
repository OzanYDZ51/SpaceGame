class_name SystemEnvironmentData
extends Resource

# =============================================================================
# System Environment Data — Visual identity of a star system
# Editable in Godot inspector. Save as .tres for per-system overrides.
# =============================================================================

@export_group("Star Light")
@export var star_light_color: Color = Color(0.95, 0.9, 0.85)
@export var star_light_energy: float = 1.0

@export_group("Ambient Light")
@export var ambient_color: Color = Color(0.04, 0.04, 0.07)
@export var ambient_energy: float = 0.2

@export_group("Glow")
@export var glow_intensity: float = 0.5
@export var glow_bloom: float = 0.035

@export_group("Skybox — Nebula")
@export var nebula_warm: Color = Color(0.12, 0.03, 0.05)
@export var nebula_cool: Color = Color(0.03, 0.04, 0.10)
@export var nebula_accent: Color = Color(0.06, 0.02, 0.12)
@export var nebula_intensity: float = 0.35

@export_group("Skybox — Stars")
@export var star_density: float = 0.4
@export var star_brightness: float = 3.5

@export_group("Skybox — Milky Way")
@export var milky_way_intensity: float = 0.5
@export var milky_way_width: float = 0.16
@export var milky_way_color: Color = Color(0.08, 0.07, 0.14)

@export_group("Skybox — Dust Lanes")
@export var dust_intensity: float = 0.5

@export_group("Skybox — God Rays")
@export var god_ray_intensity: float = 0.5

@export_group("Skybox — Nebula Detail")
@export var nebula_warp_strength: float = 0.6
@export var nebula_emission_strength: float = 1.5

@export_group("Skybox — Star Clusters")
@export var star_cluster_density: float = 0.3
