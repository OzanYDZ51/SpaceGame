class_name EntityRegistrySystem
extends Node

# =============================================================================
# Entity Registry
# Global singleton tracking all entities with float64 universe positions.
# Scene-based entities (ships, stations) read from their Node3D + FloatingOrigin.
# Procedural entities (planets, star) update via orbital mechanics.
# =============================================================================

signal entity_registered(id: String)
signal entity_unregistered(id: String)

enum EntityType { STAR, PLANET, STATION, SHIP_PLAYER, SHIP_NPC, ASTEROID_BELT, ASTEROID, JUMP_GATE, CARGO_CRATE, SHIP_FLEET, CONSTRUCTION_SITE }

# Entity data stored as dictionaries for flexibility:
# {
#   "id": String,
#   "name": String,
#   "type": EntityType,
#   "pos_x": float,  "pos_y": float,  "pos_z": float,   # universe float64
#   "vel_x": float,  "vel_y": float,  "vel_z": float,   # m/s
#   "node": Node3D or null,          # scene node (null for procedural)
#   "orbital_radius": float,         # 0 if not orbiting
#   "orbital_period": float,         # seconds for full orbit
#   "orbital_angle": float,          # current angle in radians
#   "orbital_parent": String,        # id of parent body ("" if none)
#   "radius": float,                 # visual radius in meters
#   "color": Color,
#   "extra": Dictionary,             # type-specific data
# }
var _entities: Dictionary = {}  # id -> entity dict
var _sync_timer: float = 0.0
var _accumulated_delta: float = 0.0
const SYNC_INTERVAL: float = 0.1  # 10 Hz position sync


func register(id: String, data: Dictionary) -> void:
	data["id"] = id
	# Ensure defaults
	if not data.has("pos_x"): data["pos_x"] = 0.0
	if not data.has("pos_y"): data["pos_y"] = 0.0
	if not data.has("pos_z"): data["pos_z"] = 0.0
	if not data.has("vel_x"): data["vel_x"] = 0.0
	if not data.has("vel_y"): data["vel_y"] = 0.0
	if not data.has("vel_z"): data["vel_z"] = 0.0
	if not data.has("node"): data["node"] = null
	if not data.has("orbital_radius"): data["orbital_radius"] = 0.0
	if not data.has("orbital_period"): data["orbital_period"] = 0.0
	if not data.has("orbital_angle"): data["orbital_angle"] = 0.0
	if not data.has("orbital_parent"): data["orbital_parent"] = ""
	if not data.has("radius"): data["radius"] = 1.0
	if not data.has("color"): data["color"] = Color.WHITE
	if not data.has("extra"): data["extra"] = {}
	_entities[id] = data
	entity_registered.emit(id)


func unregister(id: String) -> void:
	if _entities.has(id):
		_entities.erase(id)
		entity_unregistered.emit(id)


func get_entity(id: String) -> Dictionary:
	if _entities.has(id):
		return _entities[id]
	return {}


func get_all() -> Dictionary:
	return _entities


func clear_all() -> void:
	var ids := _entities.keys().duplicate()
	for id in ids:
		entity_unregistered.emit(id)
	_entities.clear()


func get_by_type(type: EntityType) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ent in _entities.values():
		if ent["type"] == type:
			result.append(ent)
	return result


func get_position(id: String) -> Array:
	var ent: Dictionary = _entities.get(id, {})
	if ent.is_empty():
		return [0.0, 0.0, 0.0]
	return [ent["pos_x"], ent["pos_y"], ent["pos_z"]]


func _process(delta: float) -> void:
	_accumulated_delta += delta
	_sync_timer -= delta
	if _sync_timer > 0.0:
		return
	var elapsed: float = _accumulated_delta
	_accumulated_delta = 0.0
	_sync_timer = SYNC_INTERVAL

	for ent in _entities.values():
		# Use untyped var to safely check freed references
		var node_ref = ent.get("node")
		if node_ref != null and not is_instance_valid(node_ref):
			ent["node"] = null
			node_ref = null

		if node_ref != null:
			# Scene-based entity: read position from node + floating origin
			var node: Node3D = node_ref
			var upos: Array = FloatingOrigin.to_universe_pos(node.global_position)
			ent["pos_x"] = upos[0]
			ent["pos_y"] = upos[1]
			ent["pos_z"] = upos[2]
			if node is RigidBody3D:
				var vel: Vector3 = node.linear_velocity
				ent["vel_x"] = float(vel.x)
				ent["vel_y"] = float(vel.y)
				ent["vel_z"] = float(vel.z)
		elif ent.get("orbital_radius", 0.0) > 0.0 and ent.get("orbital_period", 0.0) > 0.0:
			# Procedural orbiting entity: update angle and compute position
			var period: float = ent["orbital_period"]
			ent["orbital_angle"] += (TAU / period) * elapsed
			if ent["orbital_angle"] > TAU:
				ent["orbital_angle"] -= TAU
			var parent_id: String = ent["orbital_parent"]
			var px: float = 0.0
			var pz: float = 0.0
			if parent_id != "" and _entities.has(parent_id):
				px = _entities[parent_id]["pos_x"]
				pz = _entities[parent_id]["pos_z"]
			var r: float = ent["orbital_radius"]
			var angle: float = ent["orbital_angle"]
			ent["pos_x"] = px + cos(angle) * r
			ent["pos_z"] = pz + sin(angle) * r
