class_name EnergySystem
extends Node

# =============================================================================
# Energy System - Pool + pip distribution (WEP/SHD/ENG)
# Pip multiplier: 0.25 at 0 pips, 2.0 at max (1.0)
# =============================================================================

signal energy_changed(current: float, max_energy: float)
signal distribution_changed(weapons: float, shields: float, engines: float)
signal boost_depleted

var energy_current: float = 100.0
var energy_max: float = 100.0
var energy_regen_base: float = 22.0

# Pips: 0.0 to 1.0 each, sum should equal 1.0
var pip_weapons: float = 0.333
var pip_shields: float = 0.333
var pip_engines: float = 0.334


func setup(ship_data: ShipData) -> void:
	energy_max = ship_data.energy_capacity
	energy_current = energy_max
	energy_regen_base = ship_data.energy_regen_rate
	pip_weapons = 0.333
	pip_shields = 0.333
	pip_engines = 0.334


func _process(delta: float) -> void:
	if energy_current < energy_max:
		energy_current = minf(energy_current + energy_regen_base * delta, energy_max)
		energy_changed.emit(energy_current, energy_max)


func consume_energy(amount: float) -> bool:
	var actual := amount / get_weapon_multiplier()  # More pips = more efficient
	if energy_current >= actual:
		energy_current -= actual
		energy_changed.emit(energy_current, energy_max)
		return true
	return false


func drain_engine_energy(amount: float) -> bool:
	var actual := amount / get_engine_multiplier()
	if energy_current >= actual:
		energy_current -= actual
		energy_changed.emit(energy_current, energy_max)
		return true
	energy_current = 0.0
	energy_changed.emit(energy_current, energy_max)
	boost_depleted.emit()
	return false


func get_weapon_multiplier() -> float:
	return 0.25 + pip_weapons * 1.75


func get_shield_multiplier() -> float:
	return 0.25 + pip_shields * 1.75


func get_engine_multiplier() -> float:
	return 0.25 + pip_engines * 1.75


func get_energy_ratio() -> float:
	return energy_current / energy_max if energy_max > 0.0 else 0.0


func increase_pip(target: StringName) -> void:
	var step := 0.1
	match target:
		&"weapons":
			if pip_weapons >= 1.0:
				return
			pip_weapons = minf(pip_weapons + step, 1.0)
			_redistribute_from(&"weapons")
		&"shields":
			if pip_shields >= 1.0:
				return
			pip_shields = minf(pip_shields + step, 1.0)
			_redistribute_from(&"shields")
		&"engines":
			if pip_engines >= 1.0:
				return
			pip_engines = minf(pip_engines + step, 1.0)
			_redistribute_from(&"engines")
	distribution_changed.emit(pip_weapons, pip_shields, pip_engines)


func reset_pips() -> void:
	pip_weapons = 0.333
	pip_shields = 0.333
	pip_engines = 0.334
	distribution_changed.emit(pip_weapons, pip_shields, pip_engines)


func _redistribute_from(increased: StringName) -> void:
	# After increasing one pip, reduce the others proportionally so sum = 1.0
	var total := pip_weapons + pip_shields + pip_engines
	if total <= 1.0:
		return
	var excess := total - 1.0
	match increased:
		&"weapons":
			var other_sum := pip_shields + pip_engines
			if other_sum > 0.0:
				pip_shields -= excess * (pip_shields / other_sum)
				pip_engines -= excess * (pip_engines / other_sum)
			else:
				pip_shields = 0.0
				pip_engines = 0.0
		&"shields":
			var other_sum := pip_weapons + pip_engines
			if other_sum > 0.0:
				pip_weapons -= excess * (pip_weapons / other_sum)
				pip_engines -= excess * (pip_engines / other_sum)
			else:
				pip_weapons = 0.0
				pip_engines = 0.0
		&"engines":
			var other_sum := pip_weapons + pip_shields
			if other_sum > 0.0:
				pip_weapons -= excess * (pip_weapons / other_sum)
				pip_shields -= excess * (pip_shields / other_sum)
			else:
				pip_weapons = 0.0
				pip_shields = 0.0
	pip_weapons = maxf(pip_weapons, 0.0)
	pip_shields = maxf(pip_shields, 0.0)
	pip_engines = maxf(pip_engines, 0.0)
