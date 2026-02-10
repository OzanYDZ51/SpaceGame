class_name FlightHUD
extends Control

# =============================================================================
# Flight HUD — Orchestrator
# Routes data to 10 modular components, manages animation timers and redraw
# =============================================================================

# --- Components ---
var _gauges: HudGauges = null
var _status_panels: HudStatusPanels = null
var _weapon_panel: HudWeaponPanel = null
var _targeting: HudTargeting = null
var _radar: HudRadar = null
var _nav_markers: HudNavMarkers = null
var _cockpit: HudCockpit = null
var _damage_feedback: HudDamageFeedback = null
var _prompts: HudPrompts = null
var _mining: HudMining = null
var _route: HudRoute = null

# --- Shared animation state ---
var _scan_line_y: float = 0.0
var _pulse_t: float = 0.0
var _warning_flash: float = 0.0
var _boot_alpha: float = 0.0
var _boot_done: bool = false

# --- HUD redraw throttle ---
const HUD_SLOW_INTERVAL: float = 0.1  # 10 Hz for panels/weapon/economy
var _slow_timer: float = 0.0
var _slow_dirty: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_components()
	GameManager.player_ship_rebuilt.connect(rewire_to_ship)


func _build_components() -> void:
	# Damage feedback (no visible control of its own, provides draw_hit_markers)
	_damage_feedback = HudDamageFeedback.new()
	_damage_feedback.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_damage_feedback)

	# Gauges: crosshair, speed arc, top bar, compass, warnings
	_gauges = HudGauges.new()
	_gauges.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_gauges.damage_feedback = _damage_feedback
	add_child(_gauges)

	# Status panels: left (systems/shields/energy), right (nav), economy
	_status_panels = HudStatusPanels.new()
	_status_panels.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_status_panels)

	# Weapon panel: silhouette + hardpoints + weapon list
	_weapon_panel = HudWeaponPanel.new()
	_weapon_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_weapon_panel)

	# Targeting: bracket, lead indicator, target info panel
	_targeting = HudTargeting.new()
	_targeting.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_targeting)

	# Radar: top-right tactical display
	_radar = HudRadar.new()
	_radar.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_radar)

	# Nav markers: BSGO-style POI indicators
	_nav_markers = HudNavMarkers.new()
	_nav_markers.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_nav_markers)

	# Cockpit overlay: fighter jet style HUD
	_cockpit = HudCockpit.new()
	_cockpit.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_cockpit.damage_feedback = _damage_feedback
	add_child(_cockpit)

	# Action prompts: dock, loot, gate, wormhole
	_prompts = HudPrompts.new()
	_prompts.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_prompts)

	# Mining: heat bar + extraction progress
	_mining = HudMining.new()
	_mining.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_mining)

	# Route: multi-system autopilot progress indicator
	_route = HudRoute.new()
	_route.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_route)


# =============================================================================
# SETTERS — same API as before, routes to components
# =============================================================================
func set_ship(s: ShipController) -> void:
	_gauges.ship = s
	_status_panels.ship = s
	_status_panels.invalidate_cache()
	_weapon_panel.ship = s
	_weapon_panel.invalidate_cache()
	_targeting.ship = s
	_radar.ship = s
	_nav_markers.ship = s
	_cockpit.ship = s


func set_health_system(h: HealthSystem) -> void:
	_gauges.health_system = h
	_status_panels.health_system = h
	_status_panels.invalidate_cache()
	_cockpit.health_system = h


func set_energy_system(e: EnergySystem) -> void:
	_status_panels.energy_system = e
	_weapon_panel.energy_system = e
	_cockpit.energy_system = e


func set_targeting_system(t: TargetingSystem) -> void:
	_gauges.targeting_system = t
	_targeting.targeting_system = t
	_cockpit.targeting_system = t


func set_weapon_manager(w: WeaponManager) -> void:
	_damage_feedback.set_weapon_manager(w)
	_weapon_panel.weapon_manager = w
	_weapon_panel.invalidate_cache()
	_cockpit.weapon_manager = w


func set_player_economy(pe: PlayerEconomy) -> void:
	_status_panels.player_economy = pe


func set_docking_system(d: DockingSystem) -> void:
	_prompts.docking_system = d


func set_loot_pickup_system(lps: LootPickupSystem) -> void:
	_prompts.loot_pickup = lps


func set_system_transition(st: SystemTransition) -> void:
	_prompts.system_transition = st
	_gauges.system_transition = st


func set_mining_system(ms: MiningSystem) -> void:
	_mining.mining_system = ms


## Called via GameManager.player_ship_rebuilt signal — rewires all ship-dependent refs.
func rewire_to_ship(ship: ShipController) -> void:
	set_ship(ship)
	set_health_system(ship.get_node_or_null("HealthSystem") as HealthSystem)
	set_energy_system(ship.get_node_or_null("EnergySystem") as EnergySystem)
	set_targeting_system(ship.get_node_or_null("TargetingSystem") as TargetingSystem)
	set_weapon_manager(ship.get_node_or_null("WeaponManager") as WeaponManager)


# =============================================================================
# PROCESS — animations + redraw scheduling
# =============================================================================
func _process(delta: float) -> void:
	# Advance shared animation timers
	_pulse_t += delta
	_scan_line_y = fmod(_scan_line_y + delta * 80.0, get_viewport_rect().size.y)
	_warning_flash += delta * 3.0

	# Throttle slow redraws
	_slow_timer += delta
	if _slow_timer >= HUD_SLOW_INTERVAL:
		_slow_timer -= HUD_SLOW_INTERVAL
		_slow_dirty = true

	# Boot animation
	if not _boot_done:
		_boot_alpha = min(_boot_alpha + delta * 0.8, 1.0)
		if _boot_alpha >= 1.0:
			_boot_done = true
		modulate.a = _boot_alpha

	# Propagate animation state to all components
	_gauges.pulse_t = _pulse_t
	_gauges.scan_line_y = _scan_line_y
	_gauges.warning_flash = _warning_flash
	_status_panels.pulse_t = _pulse_t
	_status_panels.scan_line_y = _scan_line_y
	_status_panels.warning_flash = _warning_flash
	_weapon_panel.pulse_t = _pulse_t
	_weapon_panel.scan_line_y = _scan_line_y
	_targeting.pulse_t = _pulse_t
	_targeting.scan_line_y = _scan_line_y
	_radar.pulse_t = _pulse_t
	_radar.scan_line_y = _scan_line_y
	_cockpit.pulse_t = _pulse_t
	_cockpit.scan_line_y = _scan_line_y
	_cockpit.warning_flash = _warning_flash
	_prompts.pulse_t = _pulse_t
	_mining.pulse_t = _pulse_t
	_route.pulse_t = _pulse_t

	# Detect cockpit mode
	var cam := get_viewport().get_camera_3d()
	var is_cockpit: bool = cam is ShipCamera and (cam as ShipCamera).camera_mode == ShipCamera.CameraMode.COCKPIT

	# Toggle HUD layers based on mode
	_gauges.set_cockpit_mode(is_cockpit)
	_status_panels.set_cockpit_mode(is_cockpit)
	_weapon_panel.set_cockpit_mode(is_cockpit)
	_cockpit.set_cockpit_mode(is_cockpit)

	# Update damage feedback (marker decay)
	_damage_feedback.update_markers(delta)

	# Update targeting (flash decay, signal tracking)
	_targeting.update(delta, is_cockpit)

	# --- Redraw scheduling ---
	# Fast: every frame (crosshair, warnings, compass, target overlay, nav markers, radar)
	_gauges.redraw_fast()
	_nav_markers.redraw()
	_radar.redraw()
	_cockpit.redraw()

	# Slow: 10 Hz (panels, speed arc, top bar, weapon panel, economy)
	if _slow_dirty:
		_gauges.redraw_slow()
		_status_panels.redraw_slow()
		_weapon_panel.redraw_slow()
		_slow_dirty = false

	# Prompts + mining + route (conditional visibility)
	_prompts.update_visibility()
	_mining.update_visibility()
	_route.update_visibility()
