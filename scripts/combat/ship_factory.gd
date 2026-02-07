class_name ShipFactory
extends RefCounted

# =============================================================================
# Ship Factory - Creates and configures ships with all combat systems
# =============================================================================

# Reference mount positions for TIE model — fire from central ball.
const _REF_MOUNTS := [
	Vector3(-0.3, 0.0, -1.5),   # 0: Center left
	Vector3(0.3, 0.0, -1.5),    # 1: Center right
	Vector3(0.0, 0.0, -1.5),    # 2: Center
	Vector3(-0.2, 0.2, -1.5),   # 3: Upper left
	Vector3(0.2, 0.2, -1.5),    # 4: Upper right
	Vector3(-0.2, -0.2, -1.5),  # 5: Lower left
	Vector3(0.2, -0.2, -1.5),   # 6: Lower right
	Vector3(-0.15, 0.0, -1.5),  # 7: Inner left
	Vector3(0.15, 0.0, -1.5),   # 8: Inner right
	Vector3(-0.1, -0.1, -1.5),  # 9: Under left
	Vector3(0.1, -0.1, -1.5),   # 10: Under right
]

static func setup_player_ship(ship_class: StringName, controller: ShipController) -> void:
	var data := ShipRegistry.get_ship_data(ship_class)
	if data == null:
		push_error("ShipFactory: Could not find ship data for '%s'" % ship_class)
		return

	controller.ship_data = data
	controller.is_player_controlled = true
	controller.mass = data.mass
	controller.add_to_group("ships")

	# Apply model scale to player ship
	var player_model := controller.get_node_or_null("ShipModel") as ShipModel
	if player_model:
		player_model.model_scale = _get_model_scale(ship_class)

	# Health System
	var health := HealthSystem.new()
	health.name = "HealthSystem"
	controller.add_child(health)
	health.setup(data)

	# Energy System
	var energy := EnergySystem.new()
	energy.name = "EnergySystem"
	controller.add_child(energy)
	energy.setup(data)

	# Weapon Manager
	var wm := WeaponManager.new()
	wm.name = "WeaponManager"
	controller.add_child(wm)
	wm.setup_hardpoints(data, controller)

	# Equip default weapons
	var loadout := WeaponRegistry.get_default_loadout(ship_class)
	wm.equip_weapons(loadout)

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

	# Targeting System
	var targeting := TargetingSystem.new()
	targeting.name = "TargetingSystem"
	controller.add_child(targeting)



static func spawn_npc_ship(ship_class: StringName, behavior_name: StringName, pos: Vector3, parent: Node, faction_name: StringName = &"hostile", skip_registration: bool = false) -> ShipController:
	# Create RigidBody3D ship
	var ship := ShipController.new()
	ship.name = "NPC_%s_%d" % [ship_class, randi() % 10000]
	ship.is_player_controlled = false
	ship.faction = faction_name

	var data := ShipRegistry.get_ship_data(ship_class)
	if data == null:
		push_error("ShipFactory: Unknown ship class '%s'" % ship_class)
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

	# Add collision shape
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	match ship_class:
		&"Scout": box.size = Vector3(16, 8, 22)
		&"Interceptor": box.size = Vector3(20, 9, 26)
		&"Fighter": box.size = Vector3(28, 12, 36)
		&"Bomber": box.size = Vector3(30, 14, 38)
		&"Corvette": box.size = Vector3(40, 18, 50)
		&"Frigate": box.size = Vector3(55, 22, 70)
		&"Cruiser": box.size = Vector3(80, 30, 100)
		_: box.size = Vector3(28, 12, 36)
	col_shape.shape = box
	ship.add_child(col_shape)

	# Add real ship model (same .glb as player, scaled per class, tinted by faction)
	var ship_model := ShipModel.new()
	ship_model.name = "ShipModel"
	ship_model.model_path = "res://assets/models/tie.glb"
	ship_model.model_scale = _get_model_scale(ship_class)
	# Faction color tint + engine light color
	if faction_name == &"hostile":
		ship_model.color_tint = Color(1.0, 0.55, 0.5)  # Red-ish tint
		ship_model.engine_light_color = Color(1.0, 0.3, 0.2)  # Red engines
	elif faction_name == &"friendly":
		ship_model.color_tint = Color(0.5, 1.0, 0.6)  # Green-ish tint
		ship_model.engine_light_color = Color(0.2, 1.0, 0.4)  # Green engines
	else:
		ship_model.color_tint = Color(0.8, 0.7, 1.0)  # Slight purple for neutral NPCs
		ship_model.engine_light_color = Color(0.5, 0.4, 1.0)
	ship.add_child(ship_model)

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
				"ship_class": String(ship_class),
			},
		})

	# Health System
	var health := HealthSystem.new()
	health.name = "HealthSystem"
	ship.add_child(health)
	health.setup(data)

	# Energy System
	var energy := EnergySystem.new()
	energy.name = "EnergySystem"
	ship.add_child(energy)
	energy.setup(data)

	# Weapon Manager
	var wm := WeaponManager.new()
	wm.name = "WeaponManager"
	ship.add_child(wm)
	wm.setup_hardpoints(data, ship)
	_position_npc_hardpoints(wm, _get_model_scale(ship_class))
	var loadout := WeaponRegistry.get_default_loadout(ship_class)
	wm.equip_weapons(loadout)
	# All weapons in group 0 for NPCs
	var all_indices: Array = []
	for i in wm.hardpoints.size():
		all_indices.append(i)
	wm.set_weapon_group(0, all_indices)

	# Targeting System
	var targeting := TargetingSystem.new()
	targeting.name = "TargetingSystem"
	ship.add_child(targeting)

	# AI Brain
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	ship.add_child(brain)
	brain.setup(behavior_name)

	# AI Pilot
	var pilot := AIPilot.new()
	pilot.name = "AIPilot"
	ship.add_child(pilot)

	# Connect destruction
	# Safety net: unregister on tree exit
	ship.tree_exiting.connect(func(): EntityRegistry.unregister(ship.name))

	health.ship_destroyed.connect(func():
		# Spawn loot crate at death position (before cleanup)
		var death_pos: Vector3 = ship.global_position
		var drops := LootTable.roll_drops(ship.ship_data.ship_class)
		if not drops.is_empty():
			var crate := CargoCrate.new()
			crate.contents = drops
			crate.global_position = death_pos
			# Add to same parent (Universe node) so floating origin shifts it
			ship.get_parent().call_deferred("add_child", crate)

		EntityRegistry.unregister(ship.name)
		# Unregister from LOD system
		var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
		if lod_mgr:
			lod_mgr.unregister_ship(StringName(ship.name))
		ship.set_process(false)
		ship.set_physics_process(false)
		# Death effect: scale down and free
		var tween := ship.create_tween()
		tween.tween_property(ship, "scale", Vector3.ZERO, 0.5)
		tween.tween_callback(ship.queue_free)
	)

	# Register with LOD system (skip when LOD manager is promoting)
	if not skip_registration:
		var lod_mgr := GameManager.get_node_or_null("ShipLODManager") as ShipLODManager
		if lod_mgr:
			var lod_data := ShipLODData.new()
			lod_data.id = StringName(ship.name)
			lod_data.ship_class = ship_class
			lod_data.faction = faction_name
			# Extract unique number from node name (NPC_Scout_1234 → 234)
			var name_parts := ship.name.split("_")
			var name_suffix := name_parts[-1].right(3) if name_parts.size() > 0 else str(randi() % 1000)
			lod_data.display_name = "%s #%s" % [data.ship_name, name_suffix]
			lod_data.position = pos
			lod_data.node_ref = ship
			lod_data.current_lod = ShipLODData.LODLevel.LOD0
			lod_data.model_scale = _get_model_scale(ship_class)
			lod_data.behavior_name = behavior_name
			if faction_name == &"hostile":
				lod_data.color_tint = Color(1.0, 0.55, 0.5)
			elif faction_name == &"friendly":
				lod_data.color_tint = Color(0.5, 1.0, 0.6)
			else:
				lod_data.color_tint = Color(0.8, 0.7, 1.0)
			lod_mgr.register_ship(StringName(ship.name), lod_data)

	return ship


static func create_npc_data_only(ship_class: StringName, behavior_name: StringName, pos: Vector3, faction_name: StringName = &"hostile") -> ShipLODData:
	var data := ShipRegistry.get_ship_data(ship_class)
	if data == null:
		push_error("ShipFactory: Unknown ship class '%s'" % ship_class)
		return null

	var lod_data := ShipLODData.new()
	var uid := randi() % 100000
	lod_data.id = StringName("NPC_%s_%d" % [ship_class, uid])
	lod_data.ship_class = ship_class
	lod_data.faction = faction_name
	lod_data.display_name = "%s #%d" % [data.ship_name, uid % 1000]
	lod_data.behavior_name = behavior_name
	lod_data.position = pos
	lod_data.velocity = Vector3.ZERO
	lod_data.model_scale = _get_model_scale(ship_class)
	lod_data.current_lod = ShipLODData.LODLevel.LOD3
	lod_data.node_ref = null

	# Faction color
	if faction_name == &"hostile":
		lod_data.color_tint = Color(1.0, 0.55, 0.5)
	elif faction_name == &"friendly":
		lod_data.color_tint = Color(0.5, 1.0, 0.6)
	else:
		lod_data.color_tint = Color(0.8, 0.7, 1.0)

	return lod_data


static func _get_model_scale(ship_class: StringName) -> float:
	# Scale the ship model proportionally based on class size
	# Base: Fighter = 10.0 scale (matches player ship)
	match ship_class:
		&"Scout": return 2.0
		&"Interceptor": return 2.0
		&"Fighter": return 2.0
		&"Bomber": return 2.0
		&"Corvette": return 2.0
		&"Frigate": return 2.0
		&"Cruiser": return 2.0
	return 2.0


static func _get_faction_map_color(faction: StringName) -> Color:
	match faction:
		&"hostile": return MapColors.NPC_HOSTILE
		&"friendly": return MapColors.NPC_FRIENDLY
	return MapColors.NPC_NEUTRAL


static func _position_npc_hardpoints(wm: WeaponManager, model_scale: float) -> void:
	# Place hardpoints at standard model-relative positions, scaled for ship class.
	# All NPCs use the same .glb model so mount points are consistent.
	var s: float = model_scale / 10.0  # Ratio vs Fighter (reference)
	for i in wm.hardpoints.size():
		if i < _REF_MOUNTS.size():
			wm.hardpoints[i].position = _REF_MOUNTS[i] * s
