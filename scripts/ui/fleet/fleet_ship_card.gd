class_name FleetShipCard
extends RefCounted

# =============================================================================
# Fleet Ship Card — Data for rendering a fleet ship in the scroll list
# =============================================================================

var fleet_index: int = -1
var ship_id: StringName = &""
var custom_name: String = ""
var deployment_state: int = 0  # FleetShip.DeploymentState
var command_name: String = ""
var is_active: bool = false


static func from_fleet_ship(fs: FleetShip, idx: int, active_idx: int) -> FleetShipCard:
	var card := FleetShipCard.new()
	card.fleet_index = idx
	card.ship_id = fs.ship_id
	card.custom_name = fs.custom_name
	card.deployment_state = fs.deployment_state
	card.is_active = (idx == active_idx)
	if fs.deployed_command != &"":
		var cmd := FleetCommand.get_command(fs.deployed_command)
		card.command_name = cmd.get("display_name", "") if not cmd.is_empty() else ""
	return card
