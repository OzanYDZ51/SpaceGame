class_name ShipFactory
extends RefCounted

# =============================================================================
# Ship Factory - Creates and configures ships with all combat systems.
# All lookups use ship_id (unique per ship variant), NOT ship_class (category).
# Ship scenes (.tscn) are the single source of truth for hardpoints, collision,
# and model. Forward direction is -Z (Godot convention). ModelPivot in each
# scene rotates the 3D model to face -Z if needed.
# =============================================================================

# Scene cache to avoid reloading ship scenes every spawn
static var _scene_cache: Dictionary = {}
# Convex collision shape cache — one ConvexPolygonShape3D per ship_scene_path (shared resource)
static var _convex_cache: Dictionary = {}


static func setup_player_ship(ship_id: StringName, controller) -> void:
	var data =ShipRegistry.get_ship_data(ship_id)
	if data == null:
		push_error("ShipFactory: Could not find ship data for '%s'" % ship_id)
		return

	controller.ship_data = data
	controller.is_player_controlled = true
	controller.mass = data.mass
	controller.add_to_group("ships")

	# Load ship scene (source of truth for model, hardpoints, collision)
	var scene_result =_load_ship_scene(data)
	controller.center_offset = scene_result.center_offset

	# Clean up all components from a previous ship (when switching ships)
	for node_name in ["ShipModel", "CollisionShape3D", "HardpointRoot", "HealthSystem", "EnergySystem", "WeaponManager", "TargetingSystem", "EquipmentManager", "ShipAnimator"]:
		var old = controller.get_node_or_null(node_name)
		if old:
			controller.remove_child(old)
			old.free()

	# Create new ShipModel
	var ship_model =ShipModel.new()
	ship_model.name = "ShipModel"
	ship_model.model_path = data.model_path
	ship_model.model_scale = scene_result.model_scale
	ship_model.model_rotation_degrees = scene_result.model_rotation
	ship_model.external_model_instance = scene_result.get("model_node", null)
	# Set VFX engine positions on ShipModel for engine lights
	var engine_pts: Array[Vector3] = []
	for vp in scene_result.get("vfx_points", []):
		if vp.get("type") == &"ENGINE":
			engine_pts.append(vp["position"])
	ship_model.vfx_engine_positions = engine_pts
	controller.add_child(ship_model)

	# Cargo container visual — only for ships with Container_XX meshes in model
	if scene_result.get("has_containers", false):
		var ccv = load("res://scripts/ship/cargo_container_visual.gd").new()
		ccv.name = "CargoContainerVisual"
		ship_model.add_child(ccv)

	controller.add_child(scene_result.collision_shape)

	# Health System
	var health =HealthSystem.new()
	health.name = "HealthSystem"
	controller.add_child(health)
	health.setup(data)

	# Energy System
	var energy =EnergySystem.new()
	energy.name = "EnergySystem"
	controller.add_child(energy)
	energy.setup(data)

	# HardpointRoot — preserves the ship scene root's transform (rotation + scale).
	# Hardpoints inherit this naturally, matching their editor positions exactly.
	var hp_root =Node3D.new()
	hp_root.name = "HardpointRoot"
	hp_root.transform.basis = scene_result.root_basis
	controller.add_child(hp_root)

	# Weapon Manager
	var wm =WeaponManager.new()
	wm.name = "WeaponManager"
	controller.add_child(wm)

	wm.setup_hardpoints_from_configs(scene_result.configs, controller, hp_root)

	# Set up weapon groups: S weapons in group 0, M weapons in group 1, L in group 2
	var group_s: Array = []
	var group_m: Array = []
	var group_l: Array = []
	for i in wm.hardpoints.size():
		match wm.hardpoints[i].slot_size:
			"S": group_s.append(i)
			"M": group_m.append(i)
			"L": group_l.append(i)
	if not group_s.is_empty():
		wm.set_weapon_group(0, group_s)
	else:
		wm.set_weapon_group(0, group_m)  # Fallback: group 0 = M if no S
	if not group_m.is_empty():
		wm.set_weapon_group(1, group_m)
	if not group_l.is_empty():
		wm.set_weapon_group(2, group_l)

	# Ship Animator (for models with animations — nacelle tilt, fan spin, etc.)
	if scene_result.get("has_animations", false):
		var animator = ShipAnimator.new()
		animator.name = "ShipAnimator"
		controller.add_child(animator)
		animator.setup(ship_model)

	# Targeting System
	var targeting =TargetingSystem.new()
	targeting.name = "TargetingSystem"
	controller.add_child(targeting)

	# Equipment Manager (shields, engines, modules)
	var em =EquipmentManager.new()
	em.name = "EquipmentManager"
	controller.add_child(em)
	em.setup(data)
	# Equip defaults from ShipData
	if data.default_shield != &"":
		var default_shield =ShieldRegistry.get_shield(data.default_shield)
		if default_shield:
			em.equip_shield(default_shield)
	if data.default_engine != &"":
		var default_engine =EngineRegistry.get_engine(data.default_engine)
		if default_engine:
			em.equip_engine(default_engine)
	for i in mini(data.default_modules.size(), data.module_slots.size()):
		var mod =ModuleRegistry.get_module(data.default_modules[i])
		if mod:
			em.equip_module(i, mod)


static func spawn_npc_ship(ship_id: StringName, behavior_name: StringName, pos: Vector3, parent: Node, faction_name: StringName = &"hostile", skip_registration: bool = false, skip_default_loadout: bool = false):
	# Create RigidBody3D ship
	var ship =ShipController.new()
	ship.name = "NPC_%s_%d" % [ship_id, randi() % 10000]
	ship.is_player_controlled = false
	ship.faction = faction_name

	var data =ShipRegistry.get_ship_data(ship_id)
	if data == null:
		push_error("ShipFactory: Unknown ship_id '%s'" % ship_id)
		ship.queue_free()
		return null

	ship.ship_data = data
	ship.mass = data.mass
	ship.rotation_responsiveness = 3.0  # AI needs snappier rotation than player
	ship.auto_roll_factor = 0.2
	ship.can_sleep = false
	ship.custom_integrator = true
	ship.gravity_scale = 0.0
	ship.linear_damp = 0.0
	ship.angular_damp = 0.0
	ship.collision_layer = Constants.LAYER_SHIPS
	ship.collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS

	# Load ship scene (source of truth for model, hardpoints, collision)
	var scene_result =_load_ship_scene(data)
	ship.center_offset = scene_result.center_offset
	ship.add_child(scene_result.collision_shape)

	# Add ship model from ShipData (path + scale), tinted by faction
	var ship_model =ShipModel.new()
	ship_model.name = "ShipModel"
	ship_model.model_path = data.model_path
	ship_model.model_scale = scene_result.model_scale
	ship_model.model_rotation_degrees = scene_result.model_rotation
	ship_model.external_model_instance = scene_result.get("model_node", null)
	# Faction color tint + engine light color
	if faction_name == &"hostile":
		ship_model.color_tint = Color(1.0, 0.55, 0.5)  # Red-ish tint
		ship_model.engine_light_color = Color(1.0, 0.3, 0.2)  # Red engines
	elif faction_name == &"pirate":
		ship_model.color_tint = Color(1.0, 0.7, 0.2)  # Orange/gold tint
		ship_model.engine_light_color = Color(1.0, 0.5, 0.1)  # Orange engines
	elif faction_name == &"friendly":
		ship_model.color_tint = Color(0.5, 1.0, 0.6)  # Green-ish tint
		ship_model.engine_light_color = Color(0.2, 1.0, 0.4)  # Green engines
	elif faction_name == &"player_fleet":
		ship_model.color_tint = Color(0.5, 0.7, 1.0)  # Blue tint for fleet
		ship_model.engine_light_color = Color(0.3, 0.5, 1.0)  # Blue engines
	else:
		ship_model.color_tint = Color(0.8, 0.7, 1.0)  # Slight purple for neutral NPCs
		ship_model.engine_light_color = Color(0.5, 0.4, 1.0)
	# Set VFX engine positions on ShipModel for engine lights
	var npc_engine_pts: Array[Vector3] = []
	for vp in scene_result.get("vfx_points", []):
		if vp.get("type") == &"ENGINE":
			npc_engine_pts.append(vp["position"])
	ship_model.vfx_engine_positions = npc_engine_pts
	ship.add_child(ship_model)

	# Cargo container visual — only for ships with Container_XX meshes
	if scene_result.get("has_containers", false):
		var npc_ccv = load("res://scripts/ship/cargo_container_visual.gd").new()
		npc_ccv.name = "CargoContainerVisual"
		ship_model.add_child(npc_ccv)

	parent.add_child(ship)
	ship.global_position = pos
	ship.add_to_group("ships")

	# Register in EntityRegistry for stellar map (skip when LOD manager is promoting)
	if not skip_registration:
		EntityRegistry.register(ship.name, {
			"name": data.ship_name + " (" + str(ship.name) + ")",
			"type": EntityRegistrySystem.EntityType.SHIP_NPC,
			"node": ship,
			"radius": 10.0,
			"color": _get_faction_map_color(faction_name),
			"extra": {
				"faction": String(faction_name),
				"ship_class": String(data.ship_class),
			},
		})

	# Health System
	var health =HealthSystem.new()
	health.name = "HealthSystem"
	ship.add_child(health)
	health.setup(data)

	# Energy System
	var energy =EnergySystem.new()
	energy.name = "EnergySystem"
	ship.add_child(energy)
	energy.setup(data)

	# Ship Animator for NPC (same as player — nacelle tilt, fan spin)
	if scene_result.get("has_animations", false):
		var npc_animator = ShipAnimator.new()
		npc_animator.name = "ShipAnimator"
		ship.add_child(npc_animator)
		npc_animator.setup(ship_model)

	# HardpointRoot for NPC
	var hp_root =Node3D.new()
	hp_root.name = "HardpointRoot"
	hp_root.transform.basis = scene_result.root_basis
	ship.add_child(hp_root)

	# Weapon Manager
	var wm =WeaponManager.new()
	wm.name = "WeaponManager"
	ship.add_child(wm)

	wm.setup_hardpoints_from_configs(scene_result.configs, ship, hp_root)
	if not skip_default_loadout:
		wm.equip_weapons(data.default_loadout)
		# All weapons in group 0 for NPCs
		var all_indices: Array = []
		for i in wm.hardpoints.size():
			all_indices.append(i)
		wm.set_weapon_group(0, all_indices)

	# Targeting System
	var targeting =TargetingSystem.new()
	targeting.name = "TargetingSystem"
	ship.add_child(targeting)

	# Loot Pickup System (same component as player — NPCs auto-collect nearby crates)
	var lps =LootPickupSystem.new()
	lps.name = "LootPickupSystem"
	lps.override_peer_id = 0  # NPCs only loot unowned/abandoned crates
	ship.add_child(lps)

	# AI Brain
	var brain =AIBrain.new()
	brain.name = "AIBrain"
	ship.add_child(brain)
	brain.setup(behavior_name)

	# AI Pilot
	var pilot =AIPilot.new()
	pilot.name = "AIPilot"
	ship.add_child(pilot)

	# Obstacle Sensor (omnidirectional proximity + velocity avoidance)
	var sensor =ObstacleSensor.new()
	sensor.name = "ObstacleSensor"
	ship.add_child(sensor)

	# Connect destruction
	# Safety net: unregister on tree exit (skip if LOD system already nulled node ref)
	ship.tree_exiting.connect(func():
		var ent =EntityRegistry.get_entity(ship.name)
		if ent.is_empty() or ent.get("node") == ship:
			EntityRegistry.unregister(ship.name)
	)

	health.ship_destroyed.connect(func():
		var death_pos: Vector3 = ship.global_position
		var npc_name =StringName(ship.name)

		# Server only: broadcast death via NpcAuthority (clients get loot via RPC)
		if NetworkManager.is_server():
			var npc_auth = GameManager.get_node_or_null("NpcAuthority")
			var info: Dictionary = npc_auth._npcs.get(npc_name, {}) if npc_auth else {}
			if info.get("_player_killing", false):
				pass  # _on_npc_killed handles death with correct killer_pid — skip
			elif npc_auth and npc_auth._npcs.has(npc_name):
				var upos =FloatingOrigin.to_universe_pos(death_pos)
				var drops =LootTable.roll_drops_for_ship(ship.ship_data)
				# killer_pid=0 means killed by local AI/combat bridge (no player killer)
				npc_auth.broadcast_npc_death(npc_name, 0, upos, drops)
				npc_auth.unregister_npc(npc_name)
			else:
				push_warning("ShipFactory: NPC '%s' died but not registered in NpcAuthority — skipping loot" % String(npc_name))

		EntityRegistry.unregister(ship.name)
		# Unregister from LOD system
		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		if lod_mgr:
			lod_mgr.unregister_ship(npc_name)
		ship.set_process(false)
		ship.set_physics_process(false)
		# Death effect: scale down and free
		var tween =ship.create_tween()
		tween.tween_property(ship, "scale", Vector3.ZERO, 0.5)
		tween.tween_callback(ship.queue_free)
	)

	# Register with LOD system (skip when LOD manager is promoting)
	if not skip_registration:
		var lod_mgr = GameManager.get_node_or_null("ShipLODManager")
		if lod_mgr:
			var lod_data =ShipLODData.new()
			lod_data.id = StringName(ship.name)
			lod_data.ship_id = data.ship_id
			lod_data.ship_class = data.ship_class
			lod_data.faction = faction_name
			# Extract unique number from node name (NPC_chasseur_viper_1234 → 234)
			var name_parts =ship.name.split("_")
			var name_suffix =name_parts[-1].right(3) if name_parts.size() > 0 else str(randi() % 1000)
			lod_data.display_name = "%s #%s" % [data.ship_name, name_suffix]
			lod_data.position = pos
			lod_data.node_ref = ship
			lod_data.current_lod = ShipLODData.LODLevel.LOD0
			lod_data.model_scale = scene_result.model_scale
			lod_data.behavior_name = behavior_name
			if faction_name == &"hostile":
				lod_data.color_tint = Color(1.0, 0.55, 0.5)
			elif faction_name == &"pirate":
				lod_data.color_tint = Color(1.0, 0.7, 0.2)
			elif faction_name == &"friendly":
				lod_data.color_tint = Color(0.5, 1.0, 0.6)
			elif faction_name == &"player_fleet":
				lod_data.color_tint = Color(0.5, 0.7, 1.0)
			else:
				lod_data.color_tint = Color(0.8, 0.7, 1.0)
			lod_mgr.register_ship(StringName(ship.name), lod_data)

	return ship


static func create_npc_data_only(ship_id: StringName, behavior_name: StringName, pos: Vector3, faction_name: StringName = &"hostile"):
	var data =ShipRegistry.get_ship_data(ship_id)
	if data == null:
		push_error("ShipFactory: Unknown ship_id '%s'" % ship_id)
		return null

	var lod_data =ShipLODData.new()
	var uid =randi() % 100000
	lod_data.id = StringName("NPC_%s_%d" % [ship_id, uid])
	lod_data.ship_id = data.ship_id
	lod_data.ship_class = data.ship_class
	lod_data.faction = faction_name
	lod_data.display_name = "%s #%d" % [data.ship_name, uid % 1000]
	lod_data.behavior_name = behavior_name
	lod_data.position = pos
	lod_data.velocity = Vector3.ZERO
	lod_data.model_scale = data.model_scale
	lod_data.current_lod = ShipLODData.LODLevel.LOD3
	lod_data.node_ref = null

	# Faction color
	if faction_name == &"hostile":
		lod_data.color_tint = Color(1.0, 0.55, 0.5)
	elif faction_name == &"pirate":
		lod_data.color_tint = Color(1.0, 0.7, 0.2)
	elif faction_name == &"friendly":
		lod_data.color_tint = Color(0.5, 1.0, 0.6)
	elif faction_name == &"player_fleet":
		lod_data.color_tint = Color(0.5, 0.7, 1.0)
	else:
		lod_data.color_tint = Color(0.8, 0.7, 1.0)

	return lod_data


## Returns hardpoint configs for a ship_id (lightweight, no collision generation).
## Used by display systems (hangar, equipment screen) to show weapon visuals.
static var _config_cache: Dictionary = {}  # ship_id -> Array[Dictionary]
static var _rotation_cache: Dictionary = {}  # ship_id -> Vector3
static var _root_basis_cache: Dictionary = {}  # ship_id -> Basis
static var _model_scale_cache: Dictionary = {}  # ship_id -> float
static var _center_offset_cache: Dictionary = {}  # ship_id -> Vector3
static var _vfx_points_cache: Dictionary = {}  # ship_id -> Array[Dictionary]
static var _equip_camera_cache: Dictionary = {}  # ship_id -> Dictionary (position, basis, fov...)

static func get_hardpoint_configs(ship_id: StringName) -> Array[Dictionary]:
	if _config_cache.has(ship_id):
		return _config_cache[ship_id]
	_cache_scene_info(ship_id)
	return _config_cache.get(ship_id, [] as Array[Dictionary])


static func get_model_rotation(ship_id: StringName) -> Vector3:
	if _rotation_cache.has(ship_id):
		return _rotation_cache[ship_id]
	_cache_scene_info(ship_id)
	return _rotation_cache.get(ship_id, Vector3.ZERO)


static func get_root_basis(ship_id: StringName) -> Basis:
	if _root_basis_cache.has(ship_id):
		return _root_basis_cache[ship_id]
	_cache_scene_info(ship_id)
	return _root_basis_cache.get(ship_id, Basis.IDENTITY)


static func get_scene_model_scale(ship_id: StringName) -> float:
	if _model_scale_cache.has(ship_id):
		return _model_scale_cache[ship_id]
	_cache_scene_info(ship_id)
	return _model_scale_cache.get(ship_id, 1.0)


static func get_center_offset(ship_id: StringName) -> Vector3:
	if _center_offset_cache.has(ship_id):
		return _center_offset_cache[ship_id]
	_cache_scene_info(ship_id)
	return _center_offset_cache.get(ship_id, Vector3.ZERO)


## Returns VFX attach points for a ship, transformed by root_basis (ready for ShipModel space).
static func get_vfx_points(ship_id: StringName) -> Array[Dictionary]:
	if _vfx_points_cache.has(ship_id):
		return _vfx_points_cache[ship_id]
	_cache_scene_info(ship_id)
	return _vfx_points_cache.get(ship_id, [] as Array[Dictionary])



## Returns EquipmentCamera data for a ship (position, basis, fov, projection, size).
## Empty dict if no EquipmentCamera node exists in the ship scene.
static func get_equipment_camera_data(ship_id: StringName) -> Dictionary:
	if _equip_camera_cache.has(ship_id):
		return _equip_camera_cache[ship_id]
	_cache_scene_info(ship_id)
	return _equip_camera_cache.get(ship_id, {})


static func _cache_scene_info(ship_id: StringName) -> void:
	var data =ShipRegistry.get_ship_data(ship_id)
	if data == null or data.ship_scene_path == "":
		_config_cache[ship_id] = [] as Array[Dictionary]
		_rotation_cache[ship_id] = Vector3.ZERO
		_root_basis_cache[ship_id] = Basis.IDENTITY
		_model_scale_cache[ship_id] = 1.0
		_center_offset_cache[ship_id] = Vector3.ZERO
		_vfx_points_cache[ship_id] = [] as Array[Dictionary]
		_equip_camera_cache[ship_id] = {}
		return
	if not _scene_cache.has(data.ship_scene_path):
		if not ResourceLoader.exists(data.ship_scene_path):
			push_warning("ShipFactory: Ship scene not found: %s" % data.ship_scene_path)
			_config_cache[ship_id] = [] as Array[Dictionary]
			_rotation_cache[ship_id] = Vector3.ZERO
			_root_basis_cache[ship_id] = Basis.IDENTITY
			_model_scale_cache[ship_id] = 1.0
			_center_offset_cache[ship_id] = Vector3.ZERO
			_vfx_points_cache[ship_id] = [] as Array[Dictionary]
			_equip_camera_cache[ship_id] = {}
			return
		var packed: PackedScene = load(data.ship_scene_path) as PackedScene
		if packed == null:
			_config_cache[ship_id] = [] as Array[Dictionary]
			_rotation_cache[ship_id] = Vector3.ZERO
			_root_basis_cache[ship_id] = Basis.IDENTITY
			_model_scale_cache[ship_id] = 1.0
			_center_offset_cache[ship_id] = Vector3.ZERO
			_vfx_points_cache[ship_id] = [] as Array[Dictionary]
			_equip_camera_cache[ship_id] = {}
			return
		_scene_cache[data.ship_scene_path] = packed
	var instance: Node3D = _scene_cache[data.ship_scene_path].instantiate() as Node3D
	var configs: Array[Dictionary] = []
	var vfx_points: Array[Dictionary] = []
	var equip_cam_data: Dictionary = {}
	var root_rotation: Vector3 = instance.rotation_degrees
	var root_scale: float = instance.scale.x
	var model_rot: Vector3 = Vector3.ZERO
	var model_scale: float = 1.0
	var center_off: Vector3 = Vector3.ZERO
	for child in instance.get_children():
		if child is HardpointSlot:
			configs.append(child.get_slot_config())
		elif child is VFXAttachPoint:
			vfx_points.append(child.get_config())
		elif child.name == "ShipCenter":
			center_off = child.position
		elif child.name == "EquipmentCamera" and child is Camera3D:
			var cam =child as Camera3D
			equip_cam_data = {
				"position": cam.position,
				"basis": cam.transform.basis,
				"fov": cam.fov,
				"projection": cam.projection,
				"size": cam.size,
			}
		elif child.name == "ModelPivot" or child.name.begins_with("Model"):
			model_rot = root_rotation + child.rotation_degrees
			model_scale = root_scale * child.scale.x

	# Configs stay raw — display screens use root_basis wrapper for correct positioning
	var root_xform_basis: Basis = instance.transform.basis
	if not root_xform_basis.is_equal_approx(Basis.IDENTITY):
		center_off = root_xform_basis * center_off
		# Transform VFX points from scene-local to ShipController/ShipModel space
		for vp in vfx_points:
			vp["position"] = root_xform_basis * vp["position"]
			vp["direction"] = root_xform_basis * vp["direction"]
		# Transform EquipmentCamera data by root basis
		if not equip_cam_data.is_empty():
			equip_cam_data["position"] = root_xform_basis * equip_cam_data["position"]
			equip_cam_data["basis"] = (root_xform_basis * equip_cam_data["basis"]).orthonormalized()

	instance.queue_free()
	_config_cache[ship_id] = configs
	_rotation_cache[ship_id] = model_rot
	_root_basis_cache[ship_id] = root_xform_basis
	_model_scale_cache[ship_id] = model_scale
	_center_offset_cache[ship_id] = center_off
	_vfx_points_cache[ship_id] = vfx_points
	_equip_camera_cache[ship_id] = equip_cam_data


## Loads a ship scene and extracts HardpointSlot configs and model node.
## Generates a ConvexPolygonShape3D collision from the mesh (cached per ship type).
static func _load_ship_scene(data) -> Dictionary:
	assert(data.ship_scene_path != "", "ShipFactory: ship_scene_path is empty for '%s'" % data.ship_id)

	# Check cache
	if not _scene_cache.has(data.ship_scene_path):
		var packed: PackedScene = load(data.ship_scene_path) as PackedScene
		assert(packed != null, "ShipFactory: Could not load ship scene '%s'" % data.ship_scene_path)
		_scene_cache[data.ship_scene_path] = packed

	var packed_scene: PackedScene = _scene_cache[data.ship_scene_path]
	var instance: Node3D = packed_scene.instantiate() as Node3D

	# Extract HardpointSlot configs, VFX points, model node, model scale, center offset
	var configs: Array[Dictionary] = []
	var vfx_points: Array[Dictionary] = []
	var model_node: Node3D = null
	var scene_model_scale: float = 1.0
	var scene_model_rotation: Vector3 = Vector3.ZERO
	var center_offset: Vector3 = Vector3.ZERO

	# Capture root node rotation and scale (user may set these on root instead of ModelPivot)
	var root_rotation: Vector3 = instance.rotation_degrees
	var root_scale: float = instance.scale.x

	for child in instance.get_children():
		if child is HardpointSlot:
			configs.append(child.get_slot_config())
		elif child is VFXAttachPoint:
			vfx_points.append(child.get_config())
		elif child.name == "ShipCenter":
			center_offset = child.position
		elif child.name == "ModelPivot" or child.name.begins_with("Model"):
			scene_model_scale = root_scale * child.scale.x
			scene_model_rotation = root_rotation + child.rotation_degrees
			if child.get_child_count() > 0:
				var inner_model: Node3D = child.get_child(0) as Node3D
				child.remove_child(inner_model)
				model_node = inner_model
			else:
				instance.remove_child(child)
				model_node = child

	# If no model pivot found, look for first non-HardpointSlot child with mesh
	if model_node == null:
		for child in instance.get_children():
			if not (child is HardpointSlot):
				instance.remove_child(child)
				model_node = child
				break

	# Root's full basis (rotation + scale) — used for HardpointRoot wrapper node.
	# Hardpoints stay in raw scene-local space; the wrapper applies root's transform
	# automatically via Godot's scene tree, guaranteeing WYSIWYG with the editor.
	var root_xform_basis: Basis = instance.transform.basis

	# Only center_offset and VFX points need manual transform (standalone vectors)
	if not root_xform_basis.is_equal_approx(Basis.IDENTITY):
		center_offset = root_xform_basis * center_offset
		for vp in vfx_points:
			vp["position"] = root_xform_basis * vp["position"]
			vp["direction"] = root_xform_basis * vp["direction"]

	# Clean up the temporary instance
	instance.queue_free()

	assert(not configs.is_empty(), "ShipFactory: No HardpointSlots in scene '%s'" % data.ship_scene_path)
	assert(model_node != null, "ShipFactory: No model found in scene '%s'" % data.ship_scene_path)

	# Generate convex collision from model mesh (cached per ship type)
	var convex_shape: ConvexPolygonShape3D
	if _convex_cache.has(data.ship_scene_path):
		convex_shape = _convex_cache[data.ship_scene_path]
	else:
		convex_shape = _generate_convex_shape(model_node, scene_model_scale)
		_convex_cache[data.ship_scene_path] = convex_shape

	var col_node =CollisionShape3D.new()
	col_node.shape = convex_shape
	# Align collision with visual model (rotation from root + ModelPivot)
	col_node.rotation_degrees = scene_model_rotation

	# Detect animations in model tree (for ShipAnimator)
	var has_animations: bool = _has_animation_player(model_node)

	# Detect cargo containers (Container_XX nodes) in model
	var has_containers: bool = _has_container_nodes(model_node)

	return {
		"configs": configs,
		"vfx_points": vfx_points,
		"model_node": model_node,
		"model_scale": scene_model_scale,
		"model_rotation": scene_model_rotation,
		"collision_shape": col_node,
		"center_offset": center_offset,
		"root_basis": root_xform_basis,
		"has_animations": has_animations,
		"has_containers": has_containers,
	}


## Generates a ConvexPolygonShape3D from all MeshInstance3D vertices in a model node tree.
## Vertices are scaled by model_scale to match the visual size.
static func _generate_convex_shape(model_root: Node3D, model_scale: float) -> ConvexPolygonShape3D:
	var verts =PackedVector3Array()
	_collect_mesh_vertices(model_root, verts, Transform3D.IDENTITY)
	assert(not verts.is_empty(), "ShipFactory: No mesh vertices found for convex collision")

	# Scale vertices to match visual model size
	if not is_equal_approx(model_scale, 1.0):
		for i in verts.size():
			verts[i] *= model_scale

	var shape =ConvexPolygonShape3D.new()
	shape.points = verts
	return shape


## Recursively collects all mesh vertices from a node tree, applying transforms.
static func _collect_mesh_vertices(node: Node, verts: PackedVector3Array, parent_xform: Transform3D) -> void:
	var xform =parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			for si in mesh.get_surface_count():
				var arrays =mesh.surface_get_arrays(si)
				if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
					var surface_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					for v in surface_verts:
						verts.append(xform * v)

	for child in node.get_children():
		_collect_mesh_vertices(child, verts, xform)


## Returns a ConvexPolygonShape3D for a given ship_id, suitable for remote ship collision.
## Loads the .glb model, generates the convex hull at the correct scale, and caches it.
## Returns null if the ship data or model is unavailable.
static func get_convex_shape_for_ship(ship_id: StringName) -> ConvexPolygonShape3D:
	var data = ShipRegistry.get_ship_data(ship_id)
	if data == null:
		return null
	# Re-use existing convex cache from scene-based loading if available
	if _convex_cache.has(data.ship_scene_path):
		return _convex_cache[data.ship_scene_path]
	# Generate from the .glb model (same path ShipModel uses for remote ships)
	var model_path: String = data.model_path
	if model_path == "" or not ResourceLoader.exists(model_path):
		return null
	var scene: PackedScene = load(model_path)
	if scene == null:
		return null
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		return null
	var model_scale: float = get_scene_model_scale(ship_id)
	var shape := _generate_convex_shape(instance, model_scale)
	instance.queue_free()
	# Cache under the scene path so it's shared
	_convex_cache[data.ship_scene_path] = shape
	return shape


## Recursively checks if a node tree contains an AnimationPlayer.
static func _has_animation_player(node: Node) -> bool:
	if node is AnimationPlayer:
		return true
	for child in node.get_children():
		if _has_animation_player(child):
			return true
	return false


static func _has_container_nodes(node: Node) -> bool:
	if node.name.begins_with("Container_"):
		return true
	for child in node.get_children():
		if _has_container_nodes(child):
			return true
	return false


static func _get_faction_map_color(faction: StringName) -> Color:
	match faction:
		&"hostile": return MapColors.NPC_HOSTILE
		&"friendly": return MapColors.NPC_FRIENDLY
		&"player_fleet": return MapColors.FLEET_SHIP
		&"nova_terra": return Color(0.2, 0.6, 1.0, 0.9)
		&"kharsis": return Color(0.9, 0.15, 0.15, 0.9)
		&"pirate": return Color(0.9, 0.6, 0.1, 0.9)  # Gold/orange — pirate faction color
		&"neutral": return MapColors.NPC_SHIP
	return MapColors.NPC_NEUTRAL
