class_name FleetCommand
extends RefCounted

# =============================================================================
# Fleet Command — static registry of available deployment commands
# =============================================================================

static var _commands: Dictionary = {}
static var _initialized: bool = false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_register(&"move_to", {
		"display_name": "EN ROUTE",
		"description": "Se deplacer vers une position",
		"requires_position": true,
		"requires_target": false,
	})
	_register(&"patrol", {
		"display_name": "PATROUILLE",
		"description": "Patrouiller autour d'une zone",
		"requires_position": true,
		"requires_target": false,
	})
	_register(&"return_to_station", {
		"display_name": "RAPPEL",
		"description": "Retourner a la station et s'amarrer",
		"requires_position": false,
		"requires_target": false,
	})
	_register(&"attack", {
		"display_name": "ATTAQUER",
		"description": "Attaquer une cible ennemie",
		"requires_position": false,
		"requires_target": true,
	})


static func _register(id: StringName, data: Dictionary) -> void:
	data["id"] = id
	_commands[id] = data


static func get_command(id: StringName) -> Dictionary:
	_ensure_init()
	return _commands.get(id, {})


static func get_all_commands() -> Dictionary:
	_ensure_init()
	return _commands


static func get_deployable_commands() -> Array[Dictionary]:
	_ensure_init()
	var result: Array[Dictionary] = []
	for cmd in _commands.values():
		if cmd["id"] != &"return_to_station":
			result.append(cmd)
	return result
