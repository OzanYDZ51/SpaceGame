class_name PlayerFleet
extends RefCounted

# =============================================================================
# Player Fleet - Tracks all owned ships and the active ship
# =============================================================================

signal fleet_changed
signal active_ship_changed(ship: FleetShip)

var ships: Array[FleetShip] = []
var active_index: int = 0


func add_ship(ship: FleetShip) -> int:
	ships.append(ship)
	fleet_changed.emit()
	return ships.size() - 1


func remove_ship(index: int) -> FleetShip:
	if index < 0 or index >= ships.size():
		return null
	if ships.size() <= 1:
		push_warning("PlayerFleet: Cannot remove last ship")
		return null
	var removed := ships[index]
	ships.remove_at(index)
	if active_index >= ships.size():
		active_index = ships.size() - 1
	fleet_changed.emit()
	return removed


func get_active() -> FleetShip:
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
	for ship in ships:
		var d := ship.serialize()
		d["active"] = (ships.find(ship) == active_index)
		result.append(d)
	return result


static func deserialize(data: Array) -> PlayerFleet:
	var fleet := PlayerFleet.new()
	for i in data.size():
		var ship := FleetShip.deserialize(data[i])
		fleet.ships.append(ship)
		if data[i].get("active", false):
			fleet.active_index = i
	return fleet
