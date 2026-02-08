class_name SystemDataRegistry
extends RefCounted

# =============================================================================
# System Data Registry
# Resolves StarSystemData for any system:
#   1. Per-system override .tres (data/systems/system_42.tres) — highest priority
#   2. Procedural generation from seed (SystemGenerator)
#
# Override .tres files are editable in the Godot inspector.
# =============================================================================

const OVERRIDES_PATH := "res://data/systems/"

static var _override_cache: Dictionary = {}


## Get system data, checking for manual override first.
## Returns null if no override exists (caller should fall back to procedural).
static func get_override(system_id: int) -> StarSystemData:
	if _override_cache.has(system_id):
		return _override_cache[system_id]

	var path := OVERRIDES_PATH + "system_%d.tres" % system_id
	if ResourceLoader.exists(path):
		var data: StarSystemData = load(path)
		if data:
			_override_cache[system_id] = data
			return data

	return null


## Check if a system has a manual override.
static func has_override(system_id: int) -> bool:
	if _override_cache.has(system_id):
		return true
	var path := OVERRIDES_PATH + "system_%d.tres" % system_id
	return ResourceLoader.exists(path)


## Clear cache (useful on galaxy change / wormhole).
static func clear_cache() -> void:
	_override_cache.clear()
