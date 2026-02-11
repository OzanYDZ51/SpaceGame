class_name AtmosphereDragZone
extends RefCounted

# =============================================================================
# Atmosphere Drag Zone — Computes atmospheric drag based on altitude
# Used by PlanetApproachManager to feed drag values to ShipController.
# Pure data class, no scene node needed.
# =============================================================================

## Compute drag coefficient at a given altitude.
## Returns 0.0 (no drag) to 1.0 (maximum drag at surface).
static func compute_drag(altitude: float, atmo_height: float, density: float) -> float:
	if altitude > atmo_height or density < 0.01:
		return 0.0
	var norm_alt: float = clampf(altitude / maxf(atmo_height, 1.0), 0.0, 1.0)
	# Exponential falloff: dense at surface, thin at edge
	var drag: float = (1.0 - norm_alt) * (1.0 - norm_alt) * density
	return clampf(drag, 0.0, 1.0)
