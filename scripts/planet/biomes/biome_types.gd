class_name BiomeTypes
extends RefCounted

# =============================================================================
# Biome Types — Definitions, color palettes, and properties for each biome.
# Used by BiomeGenerator and terrain shaders for visual variety.
# =============================================================================

enum Biome {
	OCEAN,
	BEACH,
	DESERT,
	SAVANNA,
	GRASSLAND,
	FOREST,
	RAINFOREST,
	TAIGA,
	TUNDRA,
	SNOW,
	VOLCANIC,
	MOUNTAIN,
}

## Color palettes per biome: [base, accent, detail]
const PALETTES: Dictionary = {
	Biome.OCEAN:      [Color(0.04, 0.12, 0.35), Color(0.06, 0.20, 0.50), Color(0.08, 0.25, 0.55)],
	Biome.BEACH:      [Color(0.76, 0.70, 0.50), Color(0.68, 0.62, 0.42), Color(0.82, 0.75, 0.55)],
	Biome.DESERT:     [Color(0.80, 0.68, 0.40), Color(0.72, 0.55, 0.30), Color(0.88, 0.78, 0.50)],
	Biome.SAVANNA:    [Color(0.55, 0.50, 0.22), Color(0.65, 0.58, 0.28), Color(0.48, 0.42, 0.18)],
	Biome.GRASSLAND:  [Color(0.22, 0.42, 0.10), Color(0.30, 0.52, 0.15), Color(0.18, 0.35, 0.08)],
	Biome.FOREST:     [Color(0.08, 0.28, 0.06), Color(0.12, 0.35, 0.08), Color(0.06, 0.22, 0.05)],
	Biome.RAINFOREST: [Color(0.05, 0.22, 0.04), Color(0.08, 0.30, 0.06), Color(0.04, 0.18, 0.03)],
	Biome.TAIGA:      [Color(0.12, 0.22, 0.12), Color(0.18, 0.30, 0.16), Color(0.08, 0.18, 0.10)],
	Biome.TUNDRA:     [Color(0.42, 0.48, 0.40), Color(0.50, 0.55, 0.46), Color(0.38, 0.42, 0.36)],
	Biome.SNOW:       [Color(0.88, 0.90, 0.94), Color(0.82, 0.85, 0.90), Color(0.92, 0.94, 0.97)],
	Biome.VOLCANIC:   [Color(0.18, 0.10, 0.06), Color(0.75, 0.22, 0.04), Color(0.30, 0.15, 0.08)],
	Biome.MOUNTAIN:   [Color(0.42, 0.40, 0.36), Color(0.52, 0.48, 0.42), Color(0.35, 0.32, 0.28)],
}

## Vegetation density per biome (0-1). Used by future VegetationSpawner.
const VEGETATION_DENSITY: Dictionary = {
	Biome.OCEAN: 0.0,
	Biome.BEACH: 0.15,
	Biome.DESERT: 0.05,
	Biome.SAVANNA: 0.45,
	Biome.GRASSLAND: 0.75,
	Biome.FOREST: 1.0,
	Biome.RAINFOREST: 1.0,
	Biome.TAIGA: 0.75,
	Biome.TUNDRA: 0.15,
	Biome.SNOW: 0.0,
	Biome.VOLCANIC: 0.0,
	Biome.MOUNTAIN: 0.20,
}

## Roughness per biome (for PBR terrain shader).
const ROUGHNESS: Dictionary = {
	Biome.OCEAN: 0.08,
	Biome.BEACH: 0.75,
	Biome.DESERT: 0.90,
	Biome.SAVANNA: 0.82,
	Biome.GRASSLAND: 0.78,
	Biome.FOREST: 0.85,
	Biome.RAINFOREST: 0.80,
	Biome.TAIGA: 0.82,
	Biome.TUNDRA: 0.75,
	Biome.SNOW: 0.50,
	Biome.VOLCANIC: 0.92,
	Biome.MOUNTAIN: 0.88,
}
