extends Node

# =============================================================================
# Cargo Container Visual — Shows/hides container meshes on a ship based on
# the cargo fill percentage. Containers fill in a spatially coherent order:
# bottom level first (back→front), then top level (back→front).
# Each pair (left+right at same position) appears together.
#
# Added as child of ShipModel by ShipFactory (only for ships with containers).
# =============================================================================

const UPDATE_INTERVAL: float = 0.5

## Fill order: pairs of containers that appear together.
## Bottom level back→front, then top level back→front.
## Based on actual 3D positions in the Freighter Arion model.
var FILL_ORDER: Array = [
	# --- Bottom level (Z ≈ 1.8) back → front ---
	[1, 5],    # Y ≈ -21.7 (rear-most pair)
	[6, 2],    # Y ≈ -13.5
	[7, 8],    # Y ≈ -5.3
	[4, 3],    # Y ≈ +2.9 (front-most pair)
	# --- Top level (Z ≈ 5.0) back → front ---
	[9, 13],   # Y ≈ -21.7
	[10, 12],  # Y ≈ -13.5
	[11, 15],  # Y ≈ -5.3
	[14, 16],  # Y ≈ +2.9
]

var _container_nodes: Dictionary = {}  # container_number -> Node3D
var _fleet_ship: RefCounted = null
var _timer: float = 0.0
var _last_visible_pairs: int = -1
var _is_player: bool = false


func _ready() -> void:
	_find_containers.call_deferred()


func _find_containers() -> void:
	# Parent is ShipModel — search containers in it
	var ship_model: Node = get_parent()
	_search_recursive(ship_model, _container_nodes)

	if _container_nodes.is_empty():
		set_process(false)
		return

	# ShipModel → ShipController
	var controller = ship_model.get_parent()
	_is_player = controller.get("is_player_controlled") == true

	if _is_player:
		_connect_player_cargo()
	else:
		var fs = controller.get("fleet_ship")
		if fs and fs.cargo:
			_fleet_ship = fs
		else:
			# Generic NPC freighter — show all containers
			_show_all(true)
			set_process(false)
			return

	_update_containers()


func _search_recursive(node: Node, found: Dictionary) -> void:
	if node is Node3D and node.name.begins_with("Container_"):
		var num_str: String = node.name.substr(10)
		if num_str.is_valid_int():
			found[num_str.to_int()] = node
	for child in node.get_children():
		_search_recursive(child, found)


func _connect_player_cargo() -> void:
	if not GameManager.player_data:
		return
	var fleet = GameManager.player_data.fleet
	if fleet == null:
		return
	var fs = fleet.get_active()
	if fs and fs.cargo:
		_fleet_ship = fs
		if not fs.cargo.cargo_changed.is_connected(_update_containers):
			fs.cargo.cargo_changed.connect(_update_containers)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0

	if _is_player and _fleet_ship == null:
		_connect_player_cargo()

	_update_containers()


func _update_containers() -> void:
	if _fleet_ship == null or _fleet_ship.cargo == null:
		_set_visible_pairs(0)
		return

	var cargo_max: int = _fleet_ship.cargo.capacity
	if cargo_max <= 0:
		_set_visible_pairs(0)
		return

	# Total cargo = loot items + mined resources
	var cargo_used: int = _fleet_ship.cargo.get_total_count()
	for res_id in _fleet_ship.ship_resources:
		cargo_used += _fleet_ship.ship_resources[res_id]

	var fill_ratio: float = clampf(float(cargo_used) / float(cargo_max), 0.0, 1.0)

	# 8 pairs total — each pair represents 1/8 of cargo capacity
	var pairs_to_show: int = ceili(fill_ratio * FILL_ORDER.size())
	_set_visible_pairs(pairs_to_show)


func _set_visible_pairs(pairs: int) -> void:
	if pairs == _last_visible_pairs:
		return
	_last_visible_pairs = pairs

	for pair_idx in FILL_ORDER.size():
		var visible: bool = pair_idx < pairs
		for container_num in FILL_ORDER[pair_idx]:
			var node: Node3D = _container_nodes.get(container_num)
			if node:
				node.visible = visible


func _show_all(visible: bool) -> void:
	for node in _container_nodes.values():
		node.visible = visible
