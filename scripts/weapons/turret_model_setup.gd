class_name TurretModelSetup
extends Node3D

## Restructures an imported GLB turret model at runtime.
## Finds the rotating mesh node (by name) in the GLB hierarchy
## and reparents it under TurretGun so the Hardpoint system
## can separate fixed base from rotating gun.

@export var rotating_node_name: String = "TourelleRotation"


func _ready() -> void:
	var turret_gun := get_node_or_null("TurretGun") as Node3D
	var turret_base := get_node_or_null("TurretBase") as Node3D
	if not turret_gun or not turret_base:
		return

	# Find the rotating part deep in the GLB hierarchy under TurretBase
	var rotating_node := turret_base.find_child(rotating_node_name, true, false)
	if rotating_node and rotating_node is Node3D:
		rotating_node.reparent(turret_gun)
