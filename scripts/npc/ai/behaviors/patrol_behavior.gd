class_name PatrolBehavior
extends AIBehavior

# =============================================================================
# Patrol Behavior — Area or route patrol with waypoint management.
# Extracted from AIBrain._tick_patrol + waypoint generation.
# =============================================================================

var waypoints: Array[Vector3] = []
var current_waypoint: int = 0
var patrol_center: Vector3 = Vector3.ZERO
var patrol_radius: float = 300.0
var route_priority: bool = false
var _waypoints_regenerated_for_obstacle: bool = false


func enter() -> void:
	if waypoints.is_empty() and controller:
		_generate_patrol_waypoints()


func tick(_dt: float) -> void:
	if controller == null:
		return
	var nav: AINavigation = controller.navigation
	var env: AIBrainEnvironment = controller.environment
	if nav == null:
		return

	# Regenerate waypoints if inside obstacle zone (debounced)
	if env and env.near_obstacle:
		if not _waypoints_regenerated_for_obstacle:
			_waypoints_regenerated_for_obstacle = true
			_generate_patrol_waypoints()
			current_waypoint = 0
	else:
		_waypoints_regenerated_for_obstacle = false

	# Guard ships: recenter patrol if too far from station
	if controller.guard_station and is_instance_valid(controller.guard_station) and controller._ship:
		var dist_to_station: float = controller._ship.global_position.distance_to(controller.guard_station.global_position)
		if dist_to_station > patrol_radius * 2.0:
			var dir_from_station: Vector3 = (controller._ship.global_position - controller.guard_station.global_position)
			if dir_from_station.length_squared() > 1.0:
				dir_from_station = dir_from_station.normalized()
			else:
				dir_from_station = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			var offset_center: Vector3 = controller.guard_station.global_position + dir_from_station * (AIBrainEnvironment.STATION_MODEL_RADIUS + 500.0)
			set_patrol_area(offset_center, patrol_radius)

	if waypoints.is_empty():
		return

	var arrival: float
	if patrol_radius <= 0.0:
		arrival = 80.0
	elif env and env.in_asteroid_belt:
		arrival = 150.0 if patrol_radius >= 150.0 else maxf(patrol_radius * 0.6, 15.0)
	else:
		arrival = 80.0 if patrol_radius >= 80.0 else maxf(patrol_radius * 0.6, 15.0)

	if current_waypoint >= waypoints.size():
		current_waypoint = 0
	var wp: Vector3 = waypoints[current_waypoint]
	if env:
		wp = env.deflect_from_obstacles(wp)
	nav.fly_toward(wp, arrival)

	if nav.get_distance_to(wp) < arrival:
		current_waypoint = (current_waypoint + 1) % waypoints.size()


func set_patrol_area(center: Vector3, radius: float) -> void:
	patrol_center = center
	patrol_radius = radius
	if controller and controller.environment:
		controller.environment.update_environment()
	_generate_patrol_waypoints()
	current_waypoint = randi() % maxi(waypoints.size(), 1)


func shift_patrol_waypoints(new_center: Vector3, new_radius: float) -> void:
	var shift: Vector3 = new_center - patrol_center
	patrol_center = new_center
	patrol_radius = new_radius
	for i in range(waypoints.size()):
		waypoints[i] += shift


func set_route(wps: Array[Vector3]) -> void:
	waypoints = wps
	current_waypoint = 0
	if not wps.is_empty():
		patrol_center = wps[0]
		var max_dist: float = 0.0
		for wp in wps:
			max_dist = maxf(max_dist, patrol_center.distance_to(wp))
		patrol_radius = max_dist + 5000.0


func _generate_patrol_waypoints() -> void:
	waypoints.clear()
	if patrol_radius <= 0.0:
		waypoints.append(patrol_center)
		return
	var phase: float = randf() * TAU
	var wp_count: int = randi_range(3, 5)
	var radius_var: float = patrol_radius * randf_range(0.8, 1.2)
	for i in wp_count:
		var angle: float = phase + (float(i) / float(wp_count)) * TAU
		var wp = patrol_center + Vector3(
			cos(angle) * radius_var,
			0.0,
			sin(angle) * radius_var,
		)
		wp += Vector3(randf_range(-200, 200), 0.0, randf_range(-200, 200))
		if controller and controller.environment:
			wp = controller.environment.push_away_from_obstacles(wp)
		waypoints.append(wp)


func get_behavior_name() -> StringName:
	return &"patrol"
