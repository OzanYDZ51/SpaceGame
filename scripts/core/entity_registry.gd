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

## Set of entity IDs whose orbital motion is frozen (player is nearby).
var _frozen_orbits: Dictionary = {}  # id -> true

## Distance below which station nodes stop being moved (prevents StaticBody3D physics desync).
const STATION_NODE_FREEZE_DIST: float = 10000.0


## Freeze an entity's orbital motion (call when player approaches a planet).
func freeze_orbit(id: String) -> void:
	_frozen_orbits[id] = true


## Unfreeze an entity's orbital motion (call when player leaves).
func unfreeze_orbit(id: String) -> void:
	_frozen_orbits.erase(id)


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
	# Store seed angle for deterministic orbit from unix time
	data["orbital_angle_base"] = data["orbital_angle"]
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


## Compute the deterministic orbital angle at the current moment.
## Uses Unix time so all clients get the same result regardless of when they loaded.
static func compute_orbital_angle(base_angle: float, period: float) -> float:
	if period <= 0.0:
		return base_angle
	var phase: float = fmod(Time.get_unix_time_from_system(), period) / period
	return fmod(base_angle + phase * TAU, TAU)


func get_position(id: String) -> Array:
	var ent: Dictionary = _entities.get(id, {})
	if ent.is_empty():
		return [0.0, 0.0, 0.0]
	return [ent["pos_x"], ent["pos_y"], ent["pos_z"]]


## Returns the orbital velocity vector [vx, vy, vz] in meters/sec for an orbiting entity.
## Velocity is tangent to the circular orbit in the XZ plane.
func get_orbital_velocity(id: String) -> Array:
	var ent: Dictionary = _entities.get(id, {})
	if ent.is_empty():
		return [0.0, 0.0, 0.0]
	var r: float = ent.get("orbital_radius", 0.0)
	var period: float = ent.get("orbital_period", 0.0)
	if r <= 0.0 or period <= 0.0:
		return [0.0, 0.0, 0.0]
	var omega: float = TAU / period  # angular velocity (rad/s)
	var angle: float = ent.get("orbital_angle", 0.0)
	# Position derivative: d/dt [r*cos(θ), 0, r*sin(θ)] = [-r*ω*sin(θ), 0, r*ω*cos(θ)]
	var vx: float = -r * omega * sin(angle)
	var vz: float = r * omega * cos(angle)
	return [vx, 0.0, vz]


func _process(delta: float) -> void:
	_accumulated_delta += delta
	_sync_timer -= delta
	if _sync_timer > 0.0:
		return
	_accumulated_delta = 0.0
	_sync_timer = SYNC_INTERVAL

	for ent in _entities.values():
		# Use untyped var to safely check freed references
		var node_ref = ent.get("node")
		if node_ref != null and not is_instance_valid(node_ref):
			ent["node"] = null
			node_ref = null

		if node_ref != null:
			# Check if this entity has orbital motion (e.g. stations)
			if ent.get("orbital_radius", 0.0) > 0.0 and ent.get("orbital_period", 0.0) > 0.0:
				if not _frozen_orbits.has(ent["id"]):
					ent["orbital_angle"] = compute_orbital_angle(ent["orbital_angle_base"], ent["orbital_period"])
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
					# Move the actual node — but for stations, skip if player is nearby
					# (StaticBody3D global_position writes desync physics vs visual)
					var node: Node3D = node_ref
					if ent["type"] == EntityType.STATION:
						var player_ent: Dictionary = _entities.get("player_ship", {})
						var pnode = player_ent.get("node")
						if pnode != null and is_instance_valid(pnode):
							if node.global_position.distance_to((pnode as Node3D).global_position) < STATION_NODE_FREEZE_DIST:
								continue
					node.global_position = FloatingOrigin.to_local_pos([ent["pos_x"], ent["pos_y"], ent["pos_z"]])
			else:
				# Non-orbiting node: read position from node + floating origin
				var node: Node3D = node_ref
				var upos: Array = FloatingOrigin.to_universe_pos(node.global_position)
				ent["pos_x"] = upos[0]
				ent["pos_y"] = upos[1]
				ent["pos_z"] = upos[2]
			# Velocity for RigidBody3D (both orbiting and non-orbiting)
			if node_ref is RigidBody3D:
				var rb: RigidBody3D = node_ref
				ent["vel_x"] = float(rb.linear_velocity.x)
				ent["vel_y"] = float(rb.linear_velocity.y)
				ent["vel_z"] = float(rb.linear_velocity.z)
		elif ent.get("orbital_radius", 0.0) > 0.0 and ent.get("orbital_period", 0.0) > 0.0:
			# Skip orbital update if frozen (player is near this planet)
			if _frozen_orbits.has(ent["id"]):
				continue
			# Deterministic orbit from unix time — all clients compute the same
			# angle regardless of when they loaded the system.
			ent["orbital_angle"] = compute_orbital_angle(ent["orbital_angle_base"], ent["orbital_period"])
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
