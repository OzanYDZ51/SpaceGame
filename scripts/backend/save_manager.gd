class_name SaveManagerSystem
extends Node

# =============================================================================
# Save Manager — auto-saves player state to backend
# Autoload: SaveManager
# =============================================================================

signal save_completed()
signal save_failed(error: String)
signal load_completed(state: Dictionary)
signal load_failed(error: String)

const AUTO_SAVE_INTERVAL: float = 60.0
const MIN_SAVE_INTERVAL: float = 5.0

var _is_dirty: bool = false
var _last_save_time: float = 0.0
var _auto_save_timer: Timer = null
var _saving: bool = false


func _ready() -> void:
	_auto_save_timer = Timer.new()
	_auto_save_timer.name = "AutoSaveTimer"
	_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	_auto_save_timer.timeout.connect(_on_auto_save)
	add_child(_auto_save_timer)


func start_auto_save() -> void:
	_auto_save_timer.start()


func stop_auto_save() -> void:
	_auto_save_timer.stop()


func mark_dirty() -> void:
	_is_dirty = true


# --- Save ---

func save_player_state(force: bool = false) -> bool:
	if not AuthManager.is_authenticated:
		return false
	if _saving:
		return false

	# Debounce
	var now: float = Time.get_ticks_msec() / 1000.0
	if not force and (now - _last_save_time) < MIN_SAVE_INTERVAL:
		return false

	_saving = true
	var state := _collect_state()

	var result := await ApiClient.put_async("/api/v1/player/state", state)
	_saving = false
	_last_save_time = Time.get_ticks_msec() / 1000.0

	if result.get("ok", false) or result.get("_status_code", 0) == 200:
		_is_dirty = false
		save_completed.emit()
		print("SaveManager: State saved successfully")
		return true
	else:
		var error: String = result.get("error", "save failed")
		save_failed.emit(error)
		print("SaveManager: Save failed — %s" % error)
		return false


# --- Load ---

func load_player_state() -> Dictionary:
	if not AuthManager.is_authenticated:
		load_failed.emit("not authenticated")
		return {}

	var result := await ApiClient.get_async("/api/v1/player/state")
	var status: int = result.get("_status_code", 0)

	if status == 200:
		load_completed.emit(result)
		return result
	else:
		var error: String = result.get("error", "load failed")
		load_failed.emit(error)
		return {}


func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	# Ship
	var ship_id: String = state.get("current_ship_id", "fighter_mk1")
	var ship := GameManager.player_ship as ShipController
	if ship and ship_id != "":
		# Only change ship if different from current
		var current_model := ship.get_node_or_null("ShipModel") as ShipModel
		if current_model == null or str(ship.ship_data.ship_id if ship.ship_data else &"fighter_mk1") != ship_id:
			GameManager._on_ship_change_requested(StringName(ship_id))

	# Position
	var gal_seed: int = int(state.get("galaxy_seed", Constants.galaxy_seed))
	if gal_seed != Constants.galaxy_seed:
		Constants.galaxy_seed = gal_seed
		GameManager._galaxy = GalaxyGenerator.generate(gal_seed)
		if GameManager._system_transition:
			GameManager._system_transition.galaxy = GameManager._galaxy

	var sys_id: int = int(state.get("system_id", 0))
	if GameManager._system_transition and sys_id != GameManager._system_transition.current_system_id:
		GameManager._system_transition.jump_to_system(sys_id)

	# Credits & resources
	if GameManager.player_economy:
		var eco := GameManager.player_economy
		# Reset and set credits
		var current_credits: int = eco.credits
		if current_credits > 0:
			eco.add_credits(-current_credits)
		var saved_credits: int = int(state.get("credits", 1500))
		eco.add_credits(saved_credits)

		# Resources
		var resources: Array = state.get("resources", [])
		# Clear existing resources
		for res_id in eco.resources.keys():
			var qty: int = eco.resources[res_id]
			if qty > 0:
				eco.add_resource(res_id, -qty)
		# Apply saved resources
		for res in resources:
			var res_id := StringName(str(res.get("resource_id", "")))
			var qty: int = int(res.get("quantity", 0))
			if res_id != &"" and qty > 0:
				eco.add_resource(res_id, qty)

	# Inventory
	if GameManager.player_inventory:
		var inv := GameManager.player_inventory
		inv.clear_all()
		var items: Array = state.get("inventory", [])
		for item in items:
			var category: String = item.get("category", "")
			var item_name := StringName(str(item.get("item_name", "")))
			var qty: int = int(item.get("quantity", 1))
			match category:
				"weapon": inv.add_weapon(item_name, qty)
				"shield": inv.add_shield(item_name, qty)
				"engine": inv.add_engine(item_name, qty)
				"module": inv.add_module(item_name, qty)

	# Cargo
	if GameManager.player_cargo:
		var cargo := GameManager.player_cargo
		cargo.clear()
		var cargo_items: Array = state.get("cargo", [])
		var items_to_add: Array[Dictionary] = []
		for item in cargo_items:
			items_to_add.append({
				"name": item.get("item_name", ""),
				"type": item.get("item_type", ""),
				"quantity": item.get("quantity", 1),
				"icon_color": item.get("icon_color", ""),
			})
		if not items_to_add.is_empty():
			cargo.add_items(items_to_add)

	# Equipment
	var equipment: Dictionary = state.get("equipment", {})
	if not equipment.is_empty() and ship:
		var em := ship.get_node_or_null("EquipmentManager") as EquipmentManager
		if em:
			# Apply shield (lookup resource by name)
			var shield_name = equipment.get("shield_name", null)
			if shield_name != null and str(shield_name) != "":
				var shield_res := ShieldRegistry.get_shield(StringName(str(shield_name)))
				if shield_res:
					em.equip_shield(shield_res)
			# Apply engine (lookup resource by name)
			var engine_name = equipment.get("engine_name", null)
			if engine_name != null and str(engine_name) != "":
				var engine_res := EngineRegistry.get_engine(StringName(str(engine_name)))
				if engine_res:
					em.equip_engine(engine_res)
		# Apply hardpoints (via WeaponManager.equip_weapons)
		var wm := ship.get_node_or_null("WeaponManager") as WeaponManager
		if wm:
			var hardpoints: Array = equipment.get("hardpoints", [])
			var weapon_names: Array[StringName] = []
			for wp_name in hardpoints:
				weapon_names.append(StringName(str(wp_name)) if wp_name != null and str(wp_name) != "" else &"")
			if not weapon_names.is_empty():
				wm.equip_weapons(weapon_names)

	# Kills & deaths
	# These are tracked on the backend, not locally (read-only here)

	print("SaveManager: State applied — ship=%s, system=%d, credits=%d" % [
		ship_id, sys_id, int(state.get("credits", 0))
	])


# --- Collect current state ---

func _collect_state() -> Dictionary:
	var state: Dictionary = {}

	# Ship ID
	var ship := GameManager.player_ship as ShipController
	if ship:
		state["current_ship_id"] = str(ship.ship_data.ship_id if ship.ship_data else &"fighter_mk1")

	# Galaxy + system
	state["galaxy_seed"] = Constants.galaxy_seed
	if GameManager._system_transition:
		state["system_id"] = GameManager._system_transition.current_system_id

	# Position (floating origin absolute — to_universe_pos returns [float64, float64, float64])
	if GameManager.player_ship:
		var abs_pos: Array = FloatingOrigin.to_universe_pos(GameManager.player_ship.global_position)
		state["pos_x"] = abs_pos[0]
		state["pos_y"] = abs_pos[1]
		state["pos_z"] = abs_pos[2]

	# Rotation
	if ship:
		var rot: Vector3 = ship.rotation
		state["rotation_x"] = rot.x
		state["rotation_y"] = rot.y
		state["rotation_z"] = rot.z

	# Credits & resources
	if GameManager.player_economy:
		state["credits"] = GameManager.player_economy.credits
		var resources: Array = []
		for res_id in GameManager.player_economy.resources:
			var qty: int = GameManager.player_economy.resources[res_id]
			if qty > 0:
				resources.append({"resource_id": str(res_id), "quantity": qty})
		state["resources"] = resources

	# Inventory
	if GameManager.player_inventory:
		state["inventory"] = GameManager.player_inventory.serialize()

	# Cargo
	if GameManager.player_cargo:
		state["cargo"] = GameManager.player_cargo.serialize()

	# Equipment
	if ship:
		var em := ship.get_node_or_null("EquipmentManager") as EquipmentManager
		if em:
			state["equipment"] = em.serialize()
		var wm := ship.get_node_or_null("WeaponManager") as WeaponManager
		if wm and not state.has("equipment"):
			# Fallback: at least save hardpoints
			var hardpoints: Array = []
			for hp in wm.hardpoints:
				hardpoints.append(str(hp.mounted_weapon.weapon_name) if hp.mounted_weapon else "")
			state["equipment"] = {"hardpoints": hardpoints}

	return state


# --- Triggers ---

func _on_auto_save() -> void:
	if _is_dirty:
		save_player_state()


func trigger_save(reason: String = "") -> void:
	if reason != "":
		print("SaveManager: Save triggered — %s" % reason)
	mark_dirty()
	save_player_state(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Synchronous-ish save on quit
		if AuthManager.is_authenticated and _is_dirty:
			print("SaveManager: Saving before quit...")
			save_player_state(true)
