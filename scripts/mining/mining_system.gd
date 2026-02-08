class_name MiningSystem
extends Node

# =============================================================================
# Mining System - Handles mining mechanics for the player ship
# Child of PlayerShip, scans for nearby asteroids, extracts resources
# =============================================================================

signal mining_started(asteroid: AsteroidData)
signal mining_progress(resource_name: String, quantity: int)
signal mining_stopped
signal scan_result(asteroid: AsteroidData)

var _asteroid_mgr: AsteroidFieldManager = null
var _ship: RigidBody3D = null
var _beam: MiningLaserBeam = null

# Scan state
var scan_target: AsteroidData = null
var _scan_timer: float = 0.0
const SCAN_INTERVAL: float = 0.25

# Mining state
var is_mining: bool = false
var mining_target: AsteroidData = null
var _mining_tick_timer: float = 0.0
const MINING_TICK_INTERVAL: float = 0.5

# Mining laser stats (from equipped mining laser weapon, or defaults)
var mining_dps: float = 10.0
var mining_energy_per_second: float = 4.0


func _ready() -> void:
	_ship = get_parent() as RigidBody3D
	# Create beam visual
	_beam = MiningLaserBeam.new()
	_beam.name = "MiningLaserBeam"
	add_child(_beam)


func set_asteroid_manager(mgr: AsteroidFieldManager) -> void:
	_asteroid_mgr = mgr


func _process(delta: float) -> void:
	if _ship == null or _asteroid_mgr == null:
		return

	# Periodic scan for nearby asteroids
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL:
		_scan_timer -= SCAN_INTERVAL
		_update_scan()

	# Mining tick
	if is_mining and mining_target != null:
		# Check range
		var dist: float = _ship.global_position.distance_to(mining_target.position)
		if dist > Constants.MINING_RANGE or mining_target.is_depleted:
			stop_mining()
			return

		# Check energy
		var energy_sys := _ship.get_node_or_null("EnergySystem") as EnergySystem
		if energy_sys and energy_sys.energy_current < mining_energy_per_second * delta:
			stop_mining()
			return

		# Drain energy
		if energy_sys:
			energy_sys.energy_current -= mining_energy_per_second * delta

		# Update beam visual
		var source_pos: Vector3 = _ship.global_position + _ship.global_transform.basis * Vector3(0, -2, -20)
		_beam.update_beam(source_pos, mining_target.position)

		# Mining damage tick
		_mining_tick_timer += delta
		if _mining_tick_timer >= MINING_TICK_INTERVAL:
			_mining_tick_timer -= MINING_TICK_INTERVAL
			_do_mining_tick()


func _update_scan() -> void:
	var old_target := scan_target
	scan_target = _asteroid_mgr.get_nearest_minable_asteroid(
		_ship.global_position, Constants.MINING_SCAN_RANGE
	)

	if scan_target != old_target:
		# Show/hide scan labels
		if old_target and old_target.node_ref and is_instance_valid(old_target.node_ref):
			(old_target.node_ref as AsteroidNode).hide_scan_info()
		if scan_target and scan_target.node_ref and is_instance_valid(scan_target.node_ref):
			(scan_target.node_ref as AsteroidNode).show_scan_info()
		scan_result.emit(scan_target)


func start_mining() -> void:
	if scan_target == null or scan_target.is_depleted:
		return

	var dist: float = _ship.global_position.distance_to(scan_target.position)
	if dist > Constants.MINING_RANGE:
		return

	is_mining = true
	mining_target = scan_target
	_mining_tick_timer = 0.0

	# Activate beam
	var source_pos: Vector3 = _ship.global_position + _ship.global_transform.basis * Vector3(0, -2, -20)
	_beam.activate(source_pos, mining_target.position)

	mining_started.emit(mining_target)


func stop_mining() -> void:
	if not is_mining:
		return
	is_mining = false
	mining_target = null
	_beam.deactivate()
	mining_stopped.emit()


func _do_mining_tick() -> void:
	if mining_target == null or mining_target.is_depleted:
		stop_mining()
		return

	# Calculate damage
	var res := MiningRegistry.get_resource(mining_target.primary_resource)
	var difficulty: float = res.mining_difficulty if res else 1.0
	var damage: float = mining_dps * MINING_TICK_INTERVAL / difficulty

	# Apply damage via node or data directly
	var yield_data: Dictionary
	if mining_target.node_ref and is_instance_valid(mining_target.node_ref):
		var node := mining_target.node_ref as AsteroidNode
		yield_data = node.take_mining_damage(damage)
	else:
		# Data-only mining (shouldn't happen at mining range, but safe)
		mining_target.health_current -= damage
		if mining_target.health_current <= 0.0:
			mining_target.health_current = 0.0
			mining_target.is_depleted = true
			mining_target.respawn_timer = Constants.ASTEROID_RESPAWN_TIME
		yield_data = {
			"resource_id": mining_target.primary_resource,
			"quantity": mining_target.get_yield_per_hit(),
		}

	# Transfer to PlayerEconomy (unified resource system)
	if not yield_data.is_empty() and yield_data.get("quantity", 0) > 0:
		var resource_id: StringName = yield_data["resource_id"]
		var qty: int = yield_data["quantity"]
		var mining_res := MiningRegistry.get_resource(resource_id)
		if mining_res and GameManager.player_economy:
			GameManager.player_economy.add_resource(resource_id, qty)
			mining_progress.emit(mining_res.display_name, qty)

	# Update scan label
	if mining_target and mining_target.node_ref and is_instance_valid(mining_target.node_ref):
		(mining_target.node_ref as AsteroidNode)._update_label_text()

	# Auto-stop if depleted
	if mining_target and mining_target.is_depleted:
		stop_mining()
