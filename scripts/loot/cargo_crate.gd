class_name CargoCrate
extends Node3D

# =============================================================================
# Cargo Crate - Lootable container that spawns at NPC death
# Tumbles in space, glows yellow-orange, despawns after 2 minutes.
# Registered in EntityRegistry as CARGO_CRATE.
# =============================================================================

signal picked_up(crate: CargoCrate)

var contents: Array[Dictionary] = []   # loot items from LootTable
var owner_peer_id: int = -1            # peer who killed the NPC (-1 = anyone)
var _abandon_time: float = 120.0       # seconds until anyone can loot
var _lifetime: float = 120.0           # despawn timer (seconds)
var _spin_axis: Vector3 = Vector3.UP
var _spin_speed: float = 0.0
var _drift: Vector3 = Vector3.ZERO
var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null
var _registry_id: String = ""


func _ready() -> void:
	# Generate unique registry id
	_registry_id = "crate_%d" % (randi() % 1000000)
	name = _registry_id

	# Random tumble
	_spin_axis = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
	_spin_speed = randf_range(0.5, 2.0)

	# Small random drift so crates don't stack on death point
	_drift = Vector3(randf_range(-3.0, 3.0), randf_range(-1.0, 1.0), randf_range(-3.0, 3.0))

	# Visual: glowing box
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1)
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	add_child(_mesh)

	# Point light so it's visible from distance
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.2)
	_light.light_energy = 1.5
	_light.omni_range = 30.0
	_light.omni_attenuation = 1.5
	add_child(_light)

	# Register in EntityRegistry
	EntityRegistry.register(_registry_id, {
		"name": "Cargo Crate",
		"type": EntityRegistrySystem.EntityType.CARGO_CRATE,
		"node": self,
		"radius": 2.0,
		"color": Color(1.0, 0.7, 0.15),
	})


func is_abandoned() -> bool:
	return _abandon_time <= 0.0


func can_be_looted_by(peer_id: int) -> bool:
	return owner_peer_id == -1 or owner_peer_id == peer_id or is_abandoned()


func _process(delta: float) -> void:
	# Tumble disabled

	# Drift
	global_position += _drift * delta

	# Abandon timer
	if _abandon_time > 0.0:
		_abandon_time -= delta

	# Despawn countdown
	_lifetime -= delta
	if _lifetime <= 0.0:
		_destroy()
		return

	# Fade out in last 10 seconds
	if _lifetime < 10.0:
		var fade: float = _lifetime / 10.0
		if _mesh and _mesh.material_override:
			(_mesh.material_override as StandardMaterial3D).albedo_color.a = fade
		if _light:
			_light.light_energy = 1.5 * fade


func collect() -> Array[Dictionary]:
	var loot := contents.duplicate(true)
	picked_up.emit(self)
	_destroy()
	return loot


func _destroy() -> void:
	EntityRegistry.unregister(_registry_id)
	queue_free()


func get_contents_summary() -> String:
	if contents.is_empty():
		return "Vide"
	var count: int = 0
	for item in contents:
		count += item.get("quantity", 1)
	return "%d objet%s" % [count, "s" if count > 1 else ""]
