class_name MiningSystem
extends Node

# =============================================================================
# Mining System - Fire-button driven mining via equipped mining laser
# Aim at asteroid + hold fire → beam from hardpoint, extract resources
# Heat/overheat system with hysteresis for satisfying gameplay loop
# =============================================================================

signal mining_started(asteroid: AsteroidData)
signal mining_progress(resource_name: String, quantity: int)
signal mining_stopped
signal heat_changed(heat_ratio: float, is_overheated: bool)

var _asteroid_mgr: AsteroidFieldManager = null
var _ship: RigidBody3D = null
var _weapon_mgr: WeaponManager = null
var _beam: MiningLaserBeam = null

# Mining state
var is_mining: bool = false
var mining_target: AsteroidData = null
var _mining_tick_timer: float = 0.0
const MINING_TICK_INTERVAL: float = 0.5

# Firing state (true while fire button held + mining laser equipped)
var _is_firing: bool = false

# Heat system
var heat: float = 0.0           # 0.0 to 1.0
var is_overheated: bool = false
const HEAT_RATE: float = 0.12   # per second while firing (~8s to overheat)
const COOL_RATE: float = 0.08   # per second while not firing (~12s full cool)
const OVERHEAT_THRESHOLD: float = 0.3  # must cool below this to resume after overheat

# Mining laser stats (updated from equipped weapon)
var mining_dps: float = 10.0
var mining_energy_per_second: float = 4.0


func _ready() -> void:
	_ship = get_parent() as RigidBody3D
	_beam = MiningLaserBeam.new()
	_beam.name = "MiningLaserBeam"
	add_child(_beam)
	GameManager.player_ship_rebuilt.connect(_on_player_ship_rebuilt)


func _on_player_ship_rebuilt(ship: ShipController) -> void:
	set_weapon_manager(ship.get_node_or_null("WeaponManager") as WeaponManager)


func set_asteroid_manager(mgr: AsteroidFieldManager) -> void:
	_asteroid_mgr = mgr


func set_weapon_manager(mgr: WeaponManager) -> void:
	_weapon_mgr = mgr


## Called every frame while fire_primary is held and a mining laser is equipped.
func try_fire(aim_point: Vector3) -> void:
	if _ship == null or _asteroid_mgr == null or _weapon_mgr == null:
		return
	if is_overheated:
		return

	_is_firing = true

	# Get mining hardpoint positions
	var mining_hps := _weapon_mgr.get_mining_hardpoints_in_group(0)
	if mining_hps.is_empty():
		return

	var source_hp: Hardpoint = mining_hps[0]
	# Use muzzle point if weapon model has one, otherwise fallback to hardpoint position
	var source_pos: Vector3 = source_hp.get_muzzle_transform_stable().origin

	# Update stats from equipped mining laser
	if source_hp.mounted_weapon:
		mining_dps = source_hp.mounted_weapon.damage_per_hit
		mining_energy_per_second = source_hp.mounted_weapon.energy_cost_per_shot * 2.0

	# Raycast from camera to find asteroid at crosshair
	var asteroid_hit := _raycast_for_asteroid()

	if asteroid_hit == null:
		# Firing but not hitting an asteroid — beam shoots forward (visual only)
		if is_mining:
			_stop_extraction()
		var beam_end := source_pos + (aim_point - source_pos).normalized() * Constants.MINING_RANGE
		if not _beam._active:
			_beam.activate(source_pos, beam_end)
		_beam.update_beam(source_pos, beam_end)
		return

	# Hitting an asteroid — start/continue extraction
	var target_pos: Vector3 = asteroid_hit.position
	if asteroid_hit.node_ref and is_instance_valid(asteroid_hit.node_ref):
		target_pos = asteroid_hit.node_ref.global_position

	# Check range
	var dist: float = _ship.global_position.distance_to(target_pos)
	if dist > Constants.MINING_RANGE:
		if is_mining:
			_stop_extraction()
		var beam_end := source_pos + (aim_point - source_pos).normalized() * Constants.MINING_RANGE
		if not _beam._active:
			_beam.activate(source_pos, beam_end)
		_beam.update_beam(source_pos, beam_end)
		return

	if not is_mining or mining_target != asteroid_hit:
		_start_extraction(asteroid_hit)

	# Update beam visual
	if not _beam._active:
		_beam.activate(source_pos, target_pos)
	_beam.update_beam(source_pos, target_pos)


## Called when fire button released.
func stop_firing() -> void:
	_is_firing = false
	if is_mining:
		_stop_extraction()
	_beam.deactivate()


func has_mining_laser() -> bool:
	if _weapon_mgr == null:
		return false
	return not _weapon_mgr.get_mining_hardpoints_in_group(0).is_empty()


func _process(delta: float) -> void:
	if _ship == null:
		return

	# Heat system (always ticks)
	_update_heat(delta)

	# Mining extraction tick
	if is_mining and mining_target != null:
		# Check if target depleted
		if mining_target.is_depleted:
			_stop_extraction()
			if not _is_firing:
				_beam.deactivate()
			return

		# Check energy
		var energy_sys := _ship.get_node_or_null("EnergySystem") as EnergySystem
		if energy_sys and energy_sys.energy_current < mining_energy_per_second * delta:
			_stop_extraction()
			_beam.deactivate()
			return

		# Drain energy
		if energy_sys:
			energy_sys.energy_current -= mining_energy_per_second * delta

		# Mining damage tick
		_mining_tick_timer += delta
		if _mining_tick_timer >= MINING_TICK_INTERVAL:
			_mining_tick_timer -= MINING_TICK_INTERVAL
			_do_mining_tick()


func _update_heat(delta: float) -> void:
	var old_heat := heat

	if _is_firing and not is_overheated:
		heat = minf(heat + HEAT_RATE * delta, 1.0)
		if heat >= 1.0:
			is_overheated = true
			stop_firing()
	else:
		heat = maxf(heat - COOL_RATE * delta, 0.0)
		if is_overheated and heat <= OVERHEAT_THRESHOLD:
			is_overheated = false

	if abs(heat - old_heat) > 0.001:
		heat_changed.emit(heat, is_overheated)


func _raycast_for_asteroid() -> AsteroidData:
	var cam := _ship.get_viewport().get_camera_3d()
	if cam == null:
		return null

	var screen_center := _ship.get_viewport().get_visible_rect().size / 2.0
	var ray_origin := cam.project_ray_origin(screen_center)
	var ray_dir := cam.project_ray_normal(screen_center)

	var world := _ship.get_world_3d()
	if world == null:
		return null

	var space_state := world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * Constants.MINING_RANGE * 2.0
	)
	query.collision_mask = Constants.LAYER_ASTEROIDS
	query.exclude = [_ship.get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider := result["collider"] as Node3D
	if collider is AsteroidNode:
		return (collider as AsteroidNode).data

	return null


func _start_extraction(asteroid: AsteroidData) -> void:
	if is_mining and mining_target == asteroid:
		return
	if is_mining:
		_stop_extraction()

	is_mining = true
	mining_target = asteroid
	_mining_tick_timer = 0.0

	# Auto-reveal asteroid on mining (no scanner needed)
	if not asteroid.is_scanned and asteroid.has_resource and _asteroid_mgr:
		_asteroid_mgr.reveal_single_asteroid(asteroid)

	# Show scan label if it has a resource
	if asteroid.has_resource and asteroid.node_ref and is_instance_valid(asteroid.node_ref):
		(asteroid.node_ref as AsteroidNode).show_scan_info()

	mining_started.emit(mining_target)


func _stop_extraction() -> void:
	if not is_mining:
		return

	# Hide scan label
	if mining_target and mining_target.node_ref and is_instance_valid(mining_target.node_ref):
		(mining_target.node_ref as AsteroidNode).hide_scan_info()

	is_mining = false
	mining_target = null
	mining_stopped.emit()


func _do_mining_tick() -> void:
	if mining_target == null or mining_target.is_depleted:
		_stop_extraction()
		return

	# Barren asteroids: take damage but yield nothing
	var is_barren: bool = not mining_target.has_resource

	var res := MiningRegistry.get_resource(mining_target.primary_resource) if not is_barren else null
	var difficulty: float = res.mining_difficulty if res else 1.0
	var damage: float = mining_dps * MINING_TICK_INTERVAL / difficulty

	var yield_data: Dictionary
	if mining_target.node_ref and is_instance_valid(mining_target.node_ref):
		var node := mining_target.node_ref as AsteroidNode
		yield_data = node.take_mining_damage(damage)
	else:
		mining_target.health_current -= damage
		if mining_target.health_current <= 0.0:
			mining_target.health_current = 0.0
			mining_target.is_depleted = true
			mining_target.respawn_timer = Constants.ASTEROID_RESPAWN_TIME
		yield_data = {
			"resource_id": mining_target.primary_resource,
			"quantity": mining_target.get_yield_per_hit(),
		}

	# Only give resources if the asteroid has them
	if not is_barren and not yield_data.is_empty() and yield_data.get("quantity", 0) > 0:
		var resource_id: StringName = yield_data["resource_id"]
		var qty: int = yield_data["quantity"]
		var mining_res := MiningRegistry.get_resource(resource_id)
		if mining_res and GameManager.player_data:
			GameManager.player_data.add_active_ship_resource(resource_id, qty)
			mining_progress.emit(mining_res.display_name, qty)

	if not is_barren and mining_target and mining_target.node_ref and is_instance_valid(mining_target.node_ref):
		(mining_target.node_ref as AsteroidNode)._update_label_text()

	if mining_target and mining_target.is_depleted:
		# Broadcast depletion to other players
		_broadcast_asteroid_depleted(mining_target.id)
		_stop_extraction()
		_beam.deactivate()


func _broadcast_asteroid_depleted(asteroid_id: StringName) -> void:
	if not NetworkManager.is_connected_to_server():
		push_warning("MiningSystem: skipping asteroid depletion broadcast — not connected to server")
		return
	var id_str := String(asteroid_id)
	if NetworkManager.is_host:
		var npc_auth := GameManager.get_node_or_null("NpcAuthority") as NpcAuthority
		if npc_auth:
			var gm := GameManager as GameManagerSystem
			var sys_id: int = gm._system_transition.current_system_id if gm and gm._system_transition else -1
			npc_auth.broadcast_asteroid_depleted(id_str, sys_id, 1)
	else:
		NetworkManager._rpc_asteroid_depleted.rpc_id(1, id_str)
