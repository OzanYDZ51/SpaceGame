class_name PlayerFleet
extends RefCounted

# =============================================================================
# Player Fleet - Tracks all owned ships and the active ship
# =============================================================================

signal fleet_changed
signal active_ship_changed(ship)

var ships: Array = []
var active_index: int = 0
var squadrons: Array = []
var _next_squadron_id: int = 1


func add_ship(ship) -> int:
	ships.append(ship)
	fleet_changed.emit()
	return ships.size() - 1


func remove_ship(index: int):
	if index < 0 or index >= ships.size():
		return null
	if ships.size() <= 1:
		push_warning("PlayerFleet: Cannot remove last ship")
		return null
	var removed = ships[index]
	ships.remove_at(index)
	if active_index >= ships.size():
		active_index = ships.size() - 1
	fleet_changed.emit()
	return removed


func get_active():
	if active_index >= 0 and active_index < ships.size():
		return ships[active_index]
	return null


func set_active(index: int) -> void:
	if index < 0 or index >= ships.size():
		return
	if index == active_index:
		return
	active_index = index
	active_ship_changed.emit(ships[active_index])


func get_ship_count() -> int:
	return ships.size()


func serialize() -> Array:
	var result: Array = []
	for i in ships.size():
		var ship = ships[i]
		# Skip destroyed and empty ships — they're gone forever
		if ship.ship_id == &"" or ship.deployment_state == FleetShip.DeploymentState.DESTROYED:
			continue
		var d = ship.serialize()
		d["active"] = (i == active_index)
		result.append(d)
	return result


static func deserialize(data: Array):
	var fleet = PlayerFleet.new()
	for i in data.size():
		if data[i].get("empty", false):
			continue  # Purge legacy ghost entries
		var ship = FleetShip.deserialize(data[i])
		# Skip destroyed ships on load (shouldn't be saved, but safety net)
		if ship.deployment_state == FleetShip.DeploymentState.DESTROYED:
			continue
		if ship.ship_id == &"":
			continue
		fleet.ships.append(ship)
		if data[i].get("active", false):
			fleet.active_index = fleet.ships.size() - 1
	return fleet


func get_squadron(squadron_id: int) -> Squadron:
	for sq in squadrons:
		if sq.squadron_id == squadron_id:
			return sq
	return null


func get_ship_squadron(fleet_index: int) -> Squadron:
	for sq in squadrons:
		if sq.is_leader(fleet_index) or sq.is_member(fleet_index):
			return sq
	return null


func next_squadron_id() -> int:
	var id =_next_squadron_id
	_next_squadron_id += 1
	return id


func get_ships_at_station(station_id: String) -> Array[int]:
	var result: Array[int] = []
	for i in ships.size():
		var fs = ships[i]
		if fs.deployment_state == FleetShip.DeploymentState.DOCKED and fs.docked_station_id == station_id:
			result.append(i)
	return result


func get_deployed_in_system(system_id: int) -> Array[int]:
	var result: Array[int] = []
	for i in ships.size():
		var fs = ships[i]
		if fs.deployment_state == FleetShip.DeploymentState.DEPLOYED and fs.docked_system_id == system_id:
			result.append(i)
	return result


func get_ships_in_system(system_id: int) -> Array[int]:
	var result: Array[int] = []
	for i in ships.size():
		var fs = ships[i]
		if fs.ship_id != &"" and fs.docked_system_id == system_id and fs.deployment_state != FleetShip.DeploymentState.DESTROYED:
			result.append(i)
	return result
