class_name VFXManager
extends Node

# =============================================================================
# VFX Manager - Central orchestrator for all visual effects
# Created by GameManager, manages lifecycle of every VFX subsystem.
# Each subsystem is independent and can be toggled at runtime.
# =============================================================================

# --- Per-system toggles (runtime-editable) ---
var engine_trails_enabled := true
var speed_effects_enabled := true
var space_dust_reactive_enabled := true
var camera_vibration_enabled := true
var gforce_enabled := true
var rcs_thrusters_enabled := true
var heat_haze_enabled := true

# --- Internal refs ---
var _ship: ShipController = null
var _camera: ShipCamera = null
var _universe: Node3D = null
var _main_scene: Node3D = null

var _engine_trail: EngineTrail = null
var _speed_effects: SpeedEffects = null
var _space_dust: SpaceDust = null
var _gforce: GForceEffects = null
var _rcs: RCSThrusters = null
var _heat_haze: EngineHeatHaze = null


func initialize(ship: ShipController, camera: ShipCamera, universe: Node3D, main_scene: Node3D) -> void:
	_ship = ship
	_camera = camera
	_universe = universe
	_main_scene = main_scene

	# --- Space Dust (ambient, universe child, follows camera) ---
	if camera and universe:
		_space_dust = SpaceDust.new()
		_space_dust.name = "SpaceDust"
		_space_dust.set_camera(camera)
		_space_dust.set_ship(ship)
		universe.add_child(_space_dust)

	# --- Engine Trails (child of ShipModel) ---
	_create_engine_trail()

	# --- Speed Effects (CanvasLayer, fullscreen post-process) ---
	_speed_effects = SpeedEffects.new()
	_speed_effects.name = "SpeedEffects"
	main_scene.add_child(_speed_effects)
	_speed_effects.set_ship(ship)
	_connect_damage_flash(ship)

	# --- G-force overlay (CanvasLayer) ---
	_gforce = GForceEffects.new()
	_gforce.name = "GForceEffects"
	main_scene.add_child(_gforce)
	_gforce.set_ship(ship)

	# --- RCS Thrusters (child of ShipModel) ---
	_create_rcs_thrusters()

	# --- Heat Haze (child of ShipModel) ---
	_create_heat_haze()

	# --- Camera vibration toggle ---
	if _camera:
		_camera.vibration_enabled = camera_vibration_enabled


func on_ship_rebuilt(new_ship: ShipController) -> void:
	_ship = new_ship
	var new_camera := new_ship.get_node_or_null("ShipCamera") as ShipCamera
	if new_camera:
		_camera = new_camera

	# Rewire subsystems that persist across ship changes
	if _space_dust:
		_space_dust.set_ship(new_ship)
	if _speed_effects:
		_speed_effects.set_ship(new_ship)
		_connect_damage_flash(new_ship)
	if _gforce:
		_gforce.set_ship(new_ship)
	if _camera:
		_camera.vibration_enabled = camera_vibration_enabled

	# Recreate ship-model-parented effects
	_recreate_ship_model_effects()


func _recreate_ship_model_effects() -> void:
	# Destroy old
	if _engine_trail and is_instance_valid(_engine_trail):
		_engine_trail.queue_free()
		_engine_trail = null
	if _rcs and is_instance_valid(_rcs):
		_rcs.queue_free()
		_rcs = null
	if _heat_haze and is_instance_valid(_heat_haze):
		_heat_haze.queue_free()
		_heat_haze = null

	# Recreate on new ShipModel
	_create_engine_trail()
	_create_rcs_thrusters()
	_create_heat_haze()


func _create_engine_trail() -> void:
	if _ship == null or not engine_trails_enabled:
		return
	var model := _ship.get_node_or_null("ShipModel") as ShipModel
	if model == null:
		return
	_engine_trail = EngineTrail.new()
	_engine_trail.name = "EngineTrail"
	model.add_child(_engine_trail)
	_engine_trail.setup(model.model_scale, model.engine_light_color)


func _create_rcs_thrusters() -> void:
	if _ship == null or not rcs_thrusters_enabled:
		return
	var model := _ship.get_node_or_null("ShipModel") as ShipModel
	if model == null:
		return
	_rcs = RCSThrusters.new()
	_rcs.name = "RCSThrusters"
	model.add_child(_rcs)
	_rcs.setup(model.model_scale)


func _create_heat_haze() -> void:
	if _ship == null or not heat_haze_enabled:
		return
	var model := _ship.get_node_or_null("ShipModel") as ShipModel
	if model == null:
		return
	_heat_haze = EngineHeatHaze.new()
	_heat_haze.name = "EngineHeatHaze"
	model.add_child(_heat_haze)
	_heat_haze.setup(model.model_scale)


func _connect_damage_flash(ship: ShipController) -> void:
	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health and _speed_effects:
		if not health.damage_taken.is_connected(_speed_effects.trigger_damage_flash):
			health.damage_taken.connect(_speed_effects.trigger_damage_flash)


func set_all_enabled(enabled: bool) -> void:
	engine_trails_enabled = enabled
	speed_effects_enabled = enabled
	space_dust_reactive_enabled = enabled
	camera_vibration_enabled = enabled
	gforce_enabled = enabled
	rcs_thrusters_enabled = enabled
	heat_haze_enabled = enabled

	if _speed_effects:
		_speed_effects.visible = enabled
	if _gforce:
		_gforce.visible = enabled
	if _camera:
		_camera.vibration_enabled = enabled

	# Ship-model effects: destroy or recreate
	if not enabled:
		if _engine_trail and is_instance_valid(_engine_trail):
			_engine_trail.queue_free()
			_engine_trail = null
		if _rcs and is_instance_valid(_rcs):
			_rcs.queue_free()
			_rcs = null
		if _heat_haze and is_instance_valid(_heat_haze):
			_heat_haze.queue_free()
			_heat_haze = null
	else:
		_recreate_ship_model_effects()


func _process(_delta: float) -> void:
	if _ship == null:
		return

	var throttle: float = clampf(_ship.throttle_input.length(), 0.0, 1.0)

	# Update engine trail intensity from ship throttle
	if _engine_trail and is_instance_valid(_engine_trail):
		_engine_trail.update_intensity(throttle)

	# Update heat haze intensity from ship throttle
	if _heat_haze and is_instance_valid(_heat_haze):
		_heat_haze.update_intensity(throttle)
