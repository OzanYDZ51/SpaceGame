class_name DeathRespawnManager
extends Node

# =============================================================================
# Death & Respawn Manager — handles player death, death screen, and respawn.
# Child Node of GameManager.
# =============================================================================

signal player_died
signal player_respawned

var _death_screen: Control = null
var _death_fade: float = 0.0

# Injected refs
var player_ship: RigidBody3D = null
var main_scene: Node3D = null
var galaxy: GalaxyData = null
var system_transition: SystemTransition = null
var route_manager: RouteManager = null
var fleet_deployment_mgr: FleetDeploymentManager = null
var discord_rpc: DiscordRPC = null
var toast_manager: UIToastManager = null


func _process(delta: float) -> void:
	if _death_screen:
		_death_fade = minf(_death_fade + delta * 1.5, 1.0)
		_death_screen.modulate.a = _death_fade


func handle_player_destroyed() -> void:
	if route_manager:
		route_manager.cancel_route()
	if fleet_deployment_mgr:
		fleet_deployment_mgr.auto_retrieve_all()

	# Big explosion at player position
	_spawn_death_explosion()

	# Disable player controls & hide ship
	var ship := player_ship as ShipController
	if ship:
		ship.is_player_controlled = false
		ship.throttle_input = Vector3.ZERO
		ship.set_rotation_target(0, 0, 0)
		var act_ctrl := ship.get_node_or_null("ShipActivationController") as ShipActivationController
		if act_ctrl:
			act_ctrl.deactivate(ShipActivationController.DeactivationMode.FULL, true)

	# Hide flight HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = false

	# Show death screen with fade-in
	_death_fade = 0.0
	_create_death_screen()

	player_died.emit()


func handle_respawn() -> void:
	var current_sys_id: int = system_transition.current_system_id if system_transition else 0
	var target_sys: int = current_sys_id
	if galaxy:
		target_sys = galaxy.find_nearest_repair_system(target_sys)

	# Remove death screen
	if _death_screen and is_instance_valid(_death_screen):
		_death_screen.queue_free()
		_death_screen = null

	# Restore player ship
	_repair_ship()

	# Jump to target system (or reposition if same system)
	if system_transition and target_sys != system_transition.current_system_id:
		system_transition.jump_to_system(target_sys)
	elif system_transition:
		system_transition._position_player()

	# Restore HUD
	var hud := main_scene.get_node_or_null("UI/FlightHUD") as Control
	if hud:
		hud.visible = true

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	player_respawned.emit()


func _spawn_death_explosion() -> void:
	if player_ship == null:
		return
	var pos: Vector3 = player_ship.global_position
	var scene_root := get_tree().current_scene

	# Main explosion (big)
	var main_exp := ExplosionEffect.new()
	scene_root.add_child(main_exp)
	main_exp.global_position = pos
	main_exp.scale = Vector3.ONE * 4.0

	# Secondary explosions with slight delays and offsets
	for i in 5:
		var timer := get_tree().create_timer(0.15 * (i + 1))
		var offset := Vector3(
			randf_range(-15.0, 15.0),
			randf_range(-10.0, 10.0),
			randf_range(-15.0, 15.0)
		)
		var scale_mult: float = randf_range(1.5, 3.0)
		timer.timeout.connect(_spawn_delayed_explosion.bind(pos + offset, scale_mult))


func _spawn_delayed_explosion(pos: Vector3, scale_mult: float) -> void:
	var explosion := ExplosionEffect.new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos
	explosion.scale = Vector3.ONE * scale_mult


func _create_death_screen() -> void:
	_death_screen = Control.new()
	_death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_screen.modulate.a = 0.0

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.02, 0.7)
	_death_screen.add_child(overlay)

	var title := Label.new()
	title.text = "VAISSEAU DÉTRUIT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = -60
	title.offset_bottom = 0
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1, 1.0))
	_death_screen.add_child(title)

	var prompt := Label.new()
	prompt.text = "Appuyez sur [R] pour respawn à la station de réparation"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = 20
	prompt.offset_bottom = 60
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85, 0.8))
	_death_screen.add_child(prompt)

	var ui_layer := main_scene.get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(_death_screen)
	else:
		main_scene.add_child(_death_screen)


func _repair_ship() -> void:
	var ship := player_ship as ShipController
	if ship == null:
		return

	# Restore ship via activation controller (collision, visibility, group, map, targeting)
	var act_ctrl := ship.get_node_or_null("ShipActivationController") as ShipActivationController
	if act_ctrl:
		act_ctrl.activate()

	ship.is_player_controlled = true
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO

	var health := ship.get_node_or_null("HealthSystem") as HealthSystem
	if health:
		health.revive()

	var energy := ship.get_node_or_null("EnergySystem") as EnergySystem
	if energy:
		energy.energy_current = energy.energy_max
		energy.reset_pips()

	ship.speed_mode = Constants.SpeedMode.NORMAL
	ship.combat_locked = false
	ship.cruise_warp_active = false
	ship.cruise_time = 0.0
