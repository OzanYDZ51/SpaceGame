class_name FleetShip
extends RefCounted

# =============================================================================
# Fleet Ship - Represents a single owned ship with its loadout
# =============================================================================

enum DeploymentState { DOCKED, DEPLOYED, DESTROYED }

var ship_id: StringName = &""
var custom_name: String = ""
var weapons: Array[StringName] = []     # per hardpoint (empty = &"")
var shield_name: StringName = &""
var engine_name: StringName = &""
var modules: Array[StringName] = []     # per slot (empty = &"")

# Per-ship cargo and resources
var cargo: PlayerCargo = null
var ship_resources: Dictionary = {}  # StringName -> int

# Deployment tracking
var deployment_state: DeploymentState = DeploymentState.DOCKED
var docked_station_id: String = ""       # EntityRegistry station ID
var docked_system_id: int = -1           # System where docked/deployed
var deployed_npc_id: StringName = &""    # Transient: ShipLODManager NPC ref
var deployed_command: StringName = &""   # Current command ID
var deployed_command_params: Dictionary = {}


static func create_bare(sid: StringName) -> FleetShip:
	var data := ShipRegistry.get_ship_data(sid)
	if data == null:
		push_error("FleetShip.create_bare: unknown ship_id '%s'" % sid)
		return null
	var fs := FleetShip.new()
	fs.ship_id = sid
	fs.custom_name = String(data.ship_name)
	fs.weapons.resize(data.hardpoints.size())
	for i in data.hardpoints.size():
		fs.weapons[i] = &""
	fs.shield_name = &""
	fs.engine_name = &""
	fs.modules.resize(data.module_slots.size())
	for i in data.module_slots.size():
		fs.modules[i] = &""
	fs._init_cargo(data.cargo_capacity)
	return fs


static func from_ship_data(data: ShipData) -> FleetShip:
	var fs := FleetShip.new()
	fs.ship_id = data.ship_id
	fs.custom_name = String(data.ship_name)
	# Copy default weapon loadout
	fs.weapons.resize(data.hardpoints.size())
	for i in data.hardpoints.size():
		if i < data.default_loadout.size():
			fs.weapons[i] = data.default_loadout[i]
		else:
			fs.weapons[i] = &""
	# Default equipment from registries
	fs.shield_name = ShieldRegistry.get_default_shield(data.ship_class)
	fs.engine_name = EngineRegistry.get_default_engine(data.ship_class)
	var default_mods := ModuleRegistry.get_default_modules(data.ship_class)
	fs.modules.resize(data.module_slots.size())
	for i in data.module_slots.size():
		if i < default_mods.size():
			fs.modules[i] = default_mods[i]
		else:
			fs.modules[i] = &""
	fs._init_cargo(data.cargo_capacity)
	return fs


func _init_cargo(cap: int) -> void:
	cargo = PlayerCargo.new()
	cargo.capacity = cap
	ship_resources = {}
	for res_id in PlayerEconomy.RESOURCE_DEFS:
		ship_resources[res_id] = 0


func add_resource(resource_id: StringName, amount: int) -> void:
	if resource_id not in ship_resources:
		ship_resources[resource_id] = 0
	ship_resources[resource_id] += amount


func spend_resource(resource_id: StringName, amount: int) -> bool:
	if ship_resources.get(resource_id, 0) < amount:
		return false
	ship_resources[resource_id] -= amount
	return true


func get_resource(resource_id: StringName) -> int:
	return ship_resources.get(resource_id, 0)


func get_total_equipment_value() -> int:
	var total: int = 0
	for wn in weapons:
		if wn != &"":
			var w := WeaponRegistry.get_weapon(wn)
			if w: total += w.price
	if shield_name != &"":
		var s := ShieldRegistry.get_shield(shield_name)
		if s: total += s.price
	if engine_name != &"":
		var e := EngineRegistry.get_engine(engine_name)
		if e: total += e.price
	for mn in modules:
		if mn != &"":
			var m := ModuleRegistry.get_module(mn)
			if m: total += m.price
	return total


func serialize() -> Dictionary:
	var d := {
		"ship_id": String(ship_id),
		"custom_name": custom_name,
		"weapons": weapons.map(func(w): return String(w)),
		"shield": String(shield_name),
		"engine": String(engine_name),
		"modules": modules.map(func(m): return String(m)),
		"deployment_state": deployment_state,
		"docked_station_id": docked_station_id,
		"docked_system_id": docked_system_id,
		"deployed_command": String(deployed_command),
		"deployed_command_params": deployed_command_params,
	}
	# Per-ship cargo
	if cargo:
		d["cargo"] = cargo.serialize()
	# Per-ship resources
	var res_out: Dictionary = {}
	for res_id in ship_resources:
		var qty: int = ship_resources[res_id]
		if qty > 0:
			res_out[String(res_id)] = qty
	if not res_out.is_empty():
		d["ship_resources"] = res_out
	return d


static func deserialize(data: Dictionary) -> FleetShip:
	var fs := FleetShip.new()
	fs.ship_id = StringName(data.get("ship_id", ""))
	fs.custom_name = data.get("custom_name", "")
	for w in data.get("weapons", []):
		fs.weapons.append(StringName(w))
	fs.shield_name = StringName(data.get("shield", ""))
	fs.engine_name = StringName(data.get("engine", ""))
	for m in data.get("modules", []):
		fs.modules.append(StringName(m))
	fs.deployment_state = data.get("deployment_state", DeploymentState.DOCKED) as DeploymentState
	fs.docked_station_id = data.get("docked_station_id", "")
	fs.docked_system_id = int(data.get("docked_system_id", -1))
	fs.deployed_command = StringName(data.get("deployed_command", ""))
	fs.deployed_command_params = data.get("deployed_command_params", {})
	# Per-ship cargo + resources
	var ship_data := ShipRegistry.get_ship_data(fs.ship_id)
	var cap: int = ship_data.cargo_capacity if ship_data else 50
	fs._init_cargo(cap)
	var cargo_items: Array = data.get("cargo", [])
	for item in cargo_items:
		fs.cargo.add_item({
			"name": item.get("item_name", ""),
			"type": item.get("item_type", ""),
			"quantity": item.get("quantity", 1),
			"icon_color": item.get("icon_color", ""),
		})
	var saved_res: Dictionary = data.get("ship_resources", {})
	for res_key in saved_res:
		var res_id := StringName(str(res_key))
		var qty: int = int(saved_res[res_key])
		if qty > 0:
			fs.ship_resources[res_id] = qty
	return fs
