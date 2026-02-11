class_name PlanetBiomeProfile
extends Resource

# =============================================================================
# Planet Biome Profile — Customizable biome appearance per planet.
#
# Assign to PlanetData.biome_profile to override default biome colors.
# Unset fields (default Color(0,0,0,0)) use the shader's built-in defaults.
#
# Usage:
# 1. Create a .tres file: res://data/biome_profiles/lush_earth.tres
# 2. Set colors for the biomes you want to customize
# 3. Assign it to a PlanetData's biome_profile field
# 4. The terrain shader will use your colors instead of defaults
#
# For Star Citizen-style planet customization:
# - Override a few planets per system with hand-crafted profiles
# - Leave most planets procedural (they'll look fine with type-based defaults)
# - Future: add vegetation_density_mult, tree_type, surface_detail_texture
# =============================================================================

@export_group("Grasslands")
@export var grass_base: Color = Color(0, 0, 0, 0)
@export var grass_accent: Color = Color(0, 0, 0, 0)

@export_group("Forest")
@export var forest_base: Color = Color(0, 0, 0, 0)
@export var forest_accent: Color = Color(0, 0, 0, 0)
@export var rainforest_base: Color = Color(0, 0, 0, 0)

@export_group("Arid")
@export var desert_base: Color = Color(0, 0, 0, 0)
@export var desert_accent: Color = Color(0, 0, 0, 0)
@export var savanna_base: Color = Color(0, 0, 0, 0)
@export var savanna_accent: Color = Color(0, 0, 0, 0)

@export_group("Cold")
@export var snow_base: Color = Color(0, 0, 0, 0)
@export var snow_accent: Color = Color(0, 0, 0, 0)
@export var tundra_base: Color = Color(0, 0, 0, 0)
@export var taiga_base: Color = Color(0, 0, 0, 0)

@export_group("Special")
@export var ocean_base: Color = Color(0, 0, 0, 0)
@export var beach_base: Color = Color(0, 0, 0, 0)
@export var volcanic_base: Color = Color(0, 0, 0, 0)
@export var volcanic_accent: Color = Color(0, 0, 0, 0)
@export var mountain_base: Color = Color(0, 0, 0, 0)
@export var cliff_color: Color = Color(0, 0, 0, 0)

@export_group("Multipliers")
@export_range(0.0, 3.0) var vegetation_density_mult: float = 1.0
@export_range(0.5, 2.0) var terrain_roughness_mult: float = 1.0
@export_range(0.0, 2.0) var snow_line_offset: float = 0.0  ## Lower = more snow, higher = less snow


## Apply this profile's overrides to a ShaderMaterial.
## Only overrides colors that are set (alpha > 0).
func apply_to_material(mat: ShaderMaterial) -> void:
	_apply_color(mat, "biome_grass_base", grass_base)
	_apply_color(mat, "biome_grass_accent", grass_accent)
	_apply_color(mat, "biome_forest_base", forest_base)
	_apply_color(mat, "biome_forest_accent", forest_accent)
	_apply_color(mat, "biome_rainforest_base", rainforest_base)
	_apply_color(mat, "biome_desert_base", desert_base)
	_apply_color(mat, "biome_desert_accent", desert_accent)
	_apply_color(mat, "biome_savanna_base", savanna_base)
	_apply_color(mat, "biome_savanna_accent", savanna_accent)
	_apply_color(mat, "biome_snow_base", snow_base)
	_apply_color(mat, "biome_snow_accent", snow_accent)
	_apply_color(mat, "biome_tundra_base", tundra_base)
	_apply_color(mat, "biome_taiga_base", taiga_base)
	_apply_color(mat, "biome_ocean_base", ocean_base)
	_apply_color(mat, "biome_beach_base", beach_base)
	_apply_color(mat, "biome_volcanic_base", volcanic_base)
	_apply_color(mat, "biome_volcanic_accent", volcanic_accent)
	_apply_color(mat, "biome_mountain_base", mountain_base)
	_apply_color(mat, "biome_cliff_color", cliff_color)


static func _apply_color(mat: ShaderMaterial, param: String, col: Color) -> void:
	if col.a > 0.01:  # Only override if alpha is set
		mat.set_shader_parameter(param, col)
