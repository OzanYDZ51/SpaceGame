class_name PlayerEconomy
extends RefCounted

# =============================================================================
# Player Economy - Credits + resources tracking
# Hardcoded for testing. Future: sync with server DB.
# =============================================================================

signal credits_changed(new_amount: int)
signal resources_changed(resource_id: StringName, new_amount: int)

var credits: int = 0
var resources: Dictionary = {}  # StringName -> int

# Resource definitions (display name, color for HUD)
# Includes all minable ores — single source of truth for the economy.
const RESOURCE_DEFS := {
	&"ice": { "name": "GLACE", "color": Color(0.6, 0.8, 1.0) },
	&"iron": { "name": "FER", "color": Color(0.6, 0.58, 0.55) },
	&"copper": { "name": "CUIVRE", "color": Color(0.85, 0.55, 0.25) },
	&"titanium": { "name": "TITANE", "color": Color(0.75, 0.8, 0.9) },
	&"gold": { "name": "OR", "color": Color(1.0, 0.85, 0.3) },
	&"crystal": { "name": "CRISTAL", "color": Color(0.4, 0.8, 0.9) },
	&"uranium": { "name": "URANIUM", "color": Color(0.3, 1.0, 0.4) },
	&"platinum": { "name": "PLATINE", "color": Color(0.95, 0.95, 1.0) },
}

const CREDITS_COLOR := Color(1.0, 0.85, 0.2)


func _init() -> void:
	for res_id in RESOURCE_DEFS:
		resources[res_id] = 0


func add_credits(amount: int) -> void:
	credits += amount
	credits_changed.emit(credits)


func spend_credits(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	credits_changed.emit(credits)
	return true


func add_resource(resource_id: StringName, amount: int) -> void:
	if resource_id not in resources:
		resources[resource_id] = 0
	resources[resource_id] += amount
	resources_changed.emit(resource_id, resources[resource_id])


func spend_resource(resource_id: StringName, amount: int) -> bool:
	if resources.get(resource_id, 0) < amount:
		return false
	resources[resource_id] -= amount
	resources_changed.emit(resource_id, resources[resource_id])
	return true


func get_resource(resource_id: StringName) -> int:
	return resources.get(resource_id, 0)


## Format credits with thousand separators: 12500 -> "12 500"
static func format_credits(amount: int) -> String:
	var s := str(amount)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = " " + result
		result = s[i] + result
		count += 1
	return result
