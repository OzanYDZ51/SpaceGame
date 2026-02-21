class_name VFXManager
extends Node

# =============================================================================
# VFX Manager - Central orchestrator for all visual effects
# Created by GameManager, manages lifecycle of every VFX subsystem.
# Each subsystem is independent and can be toggled at runtime.
# =============================================================================

# --- Per-system toggles (runtime-editable) ---
var engine_trails_enabled =true
var speed_effects_enabled =true
var space_dust_reactive_enabled =true
var camera_vibration_enabled =true
var gforce_enabled =true
var motion_blur_enabled =false  # Disabled — causes unwanted blur on ship model
var nebula_wisps_enabled =false

# --- Internal refs ---
var _ship = null
var _camera = null
var _universe: Node3D = null
var _main_scene: Node3D = null

var film_grain_enabled =true

var _engine_exhaust: EngineExhaust = null
var _speed_effects: SpeedEffects = null
var _gforce: GForceEffects = null
var _space_dust: SpaceDust = null
var _film_grain: FilmGrain = null
var _damage_screen: DamageScreenEffect = null


func initialize(ship, camera, universe: Node3D, main_scene: Node3D) -> void:
	_ship = ship
	_camera = camera
	_universe = universe
	_main_scene = main_scene

	# --- Space Dust (speed-reactive ambient particles) ---
	if space_dust_reactive_enabled and universe:
		# Kill any leftover instances from previous sessions
		for child in universe.get_children():
			if child.name == "SpaceDust":
				child.queue_free()
		_space_dust = SpaceDust.new()
		_space_dust.name = "SpaceDust"
		universe.add_child(_space_dust)
		_space_dust.set_camera(camera)
		_space_dust.set_ship(ship)

	# --- Nebula Wisps: DISABLED ---
	if universe:
		for child in universe.get_children():
			if child.name == "NebulaWisps":
				child.queue_free()

	# --- Engine Exhaust (child of ShipModel) ---
	_create_engine_exhaust()

	# --- Speed Effects (CanvasLayer, fullscreen post-process) ---
	if speed_effects_enabled:
		_speed_effects = SpeedEffects.new()
		_speed_effects.name = "SpeedEffects"
		main_scene.add_child(_speed_effects)
		_speed_effects.set_ship(ship)

	# --- G-force overlay (CanvasLayer) ---
	_gforce = GForceEffects.new()
	_gforce.name = "GForceEffects"
	main_scene.add_child(_gforce)
	_gforce.set_ship(ship)

	# --- Damage screen overlay (red vignette + directional hit indicator) ---
	_damage_screen = DamageScreenEffect.new()
	_damage_screen.name = "DamageScreenEffect"
	main_scene.add_child(_damage_screen)
	_damage_screen.set_ship(ship)

	# --- Film Grain (fullscreen anti-banding) ---
	if film_grain_enabled:
		_film_grain = FilmGrain.new()
		_film_grain.name = "FilmGrain"
		main_scene.add_child(_film_grain)

	# --- Camera vibration toggle ---
	if _camera:
		_camera.vibration_enabled = camera_vibration_enabled


func on_ship_rebuilt(new_ship) -> void:
	_ship = new_ship
	var new_camera =new_ship.get_node_or_null("ShipCamera")
	if new_camera:
		_camera = new_camera

	# Rewire subsystems that persist across ship changes
	if _speed_effects:
		_speed_effects.set_ship(new_ship)
	if _gforce:
		_gforce.set_ship(new_ship)
	if _damage_screen:
		_damage_screen.set_ship(new_ship)
	if _space_dust and is_instance_valid(_space_dust):
		_space_dust.set_ship(new_ship)
		if new_camera:
			_space_dust.set_camera(new_camera)
	if _camera:
		_camera.vibration_enabled = camera_vibration_enabled

	# Recreate ship-model-parented effects
	_recreate_ship_model_effects()


func _recreate_ship_model_effects() -> void:
	# Destroy old
	if _engine_exhaust and is_instance_valid(_engine_exhaust):
		_engine_exhaust.queue_free()
		_engine_exhaust = null

	# Recreate on new ShipModel
	_create_engine_exhaust()


func _create_engine_exhaust() -> void:
	if _ship == null or not engine_trails_enabled:
		return
	var model = _ship.get_node_or_null("ShipModel")
	if model == null:
		return
	var vfx_pts =_get_vfx_points()
	_engine_exhaust = EngineExhaust.new()
	_engine_exhaust.name = "EngineExhaust"
	model.add_child(_engine_exhaust)
	_engine_exhaust.setup(model.model_scale, model.engine_light_color, vfx_pts, _ship.ship_data)


## Called when entering a new star system to update nebula wisp colors/opacity.
## Pass the SystemEnvironmentData resolved by SpaceEnvironment.
func configure_nebula_environment(_env_data: SystemEnvironmentData) -> void:
	pass  # NebulaWisps disabled


func set_all_enabled(enabled: bool) -> void:
	engine_trails_enabled = enabled
	speed_effects_enabled = enabled
	space_dust_reactive_enabled = enabled
	camera_vibration_enabled = enabled
	gforce_enabled = enabled
	motion_blur_enabled = enabled
	nebula_wisps_enabled = enabled
	film_grain_enabled = enabled

	if _speed_effects:
		_speed_effects.visible = enabled
	if _gforce:
		_gforce.visible = enabled
	if _damage_screen:
		_damage_screen.visible = enabled
	if _space_dust and is_instance_valid(_space_dust):
		_space_dust.visible = enabled
	if _film_grain and is_instance_valid(_film_grain):
		_film_grain.visible = enabled
	if _camera:
		_camera.vibration_enabled = enabled

	# Ship-model effects: destroy or recreate
	if not enabled:
		if _engine_exhaust and is_instance_valid(_engine_exhaust):
			_engine_exhaust.queue_free()
			_engine_exhaust = null
	else:
		_recreate_ship_model_effects()


func _get_vfx_points() -> Array[Dictionary]:
	if _ship and _ship.ship_data:
		return ShipFactory.get_vfx_points(_ship.ship_data.ship_id)
	return [] as Array[Dictionary]


func _process(_delta: float) -> void:
	if _ship == null:
		return

	var throttle: float = clampf(_ship.throttle_input.length(), 0.0, 1.0)

	# Update engine exhaust (throttle + speed mode aware)
	if _engine_exhaust and is_instance_valid(_engine_exhaust):
		_engine_exhaust.update_intensity(throttle, _ship.speed_mode, _ship.current_speed)
