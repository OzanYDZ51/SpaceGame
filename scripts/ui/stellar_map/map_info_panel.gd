class_name MapInfoPanel
extends Control

# =============================================================================
# Map Info Panel - Right-side panel showing selected entity details
# Custom-drawn for holographic aesthetic, dynamic height
# =============================================================================

var camera = null
var _selected_id: String = ""
var _player_id: String = ""
var _pulse_t: float = 0.0
var preview_entities: Dictionary = {}  # When non-empty, overrides EntityRegistry

const PANEL_WIDTH: float = 260.0
const PANEL_MARGIN: float = 16.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_pulse_t += delta


func set_selected(id: String) -> void:
	_selected_id = id


func _draw() -> void:
	if camera == null or _selected_id == "":
		return

	var ent: Dictionary = preview_entities.get(_selected_id, {}) if not preview_entities.is_empty() else EntityRegistry.get_entity(_selected_id)
	if ent.is_empty():
		_selected_id = ""
		return

	var font: Font = UITheme.get_font()
	var extra: Dictionary = ent.get("extra", {})

	# Count rows for dynamic panel height
	var row_count: int = 3  # name header + type + position (always shown)
	if _player_id != "" and _selected_id != _player_id:
		row_count += 1  # distance
	var vel_x: float = ent["vel_x"]
	var vel_z: float = ent["vel_z"]
	var speed: float = sqrt(vel_x * vel_x + vel_z * vel_z)
	if speed > 0.5:
		row_count += 1  # speed
	if ent["orbital_radius"] > 0.0:
		row_count += 1  # orbit
	if ent["orbital_period"] > 0.0:
		row_count += 1  # period
	# Extra rows
	if extra.has("spectral_class"): row_count += 1
	if extra.has("temperature"): row_count += 1
	if extra.has("planet_type"): row_count += 1
	if extra.has("station_type"): row_count += 1
	if extra.has("dominant_resource"): row_count += 1
	if extra.has("secondary_resource") and extra["secondary_resource"] != "": row_count += 1
	if extra.has("zone"): row_count += 1
	if extra.has("faction"): row_count += 1
	if extra.has("ship_class"): row_count += 1
	if extra.has("event_tier"): row_count += 1
	if extra.has("event_id"): row_count += 1

	var panel_h: float = 50.0 + row_count * 18.0

	# Panel background
	var panel_x: float = size.x - PANEL_WIDTH - PANEL_MARGIN
	var panel_y: float = 60.0
	var panel_rect =Rect2(panel_x, panel_y, PANEL_WIDTH, panel_h)
	draw_rect(panel_rect, MapColors.BG_PANEL)

	# Border
	draw_rect(panel_rect, MapColors.PANEL_BORDER, false, 1.0)

	# Corner accents
	var cl: float = 12.0
	var cc: Color = MapColors.CORNER
	draw_line(Vector2(panel_x, panel_y), Vector2(panel_x + cl, panel_y), cc, 1.5)
	draw_line(Vector2(panel_x, panel_y), Vector2(panel_x, panel_y + cl), cc, 1.5)
	draw_line(Vector2(panel_x + PANEL_WIDTH, panel_y), Vector2(panel_x + PANEL_WIDTH - cl, panel_y), cc, 1.5)
	draw_line(Vector2(panel_x + PANEL_WIDTH, panel_y), Vector2(panel_x + PANEL_WIDTH, panel_y + cl), cc, 1.5)

	var x: float = panel_x + 14.0
	var y: float = panel_y + 22.0
	var value_x: float = panel_x + 90.0

	# Header: entity name
	var name_text: String = ent.get("name", "INCONNU")
	draw_string(font, Vector2(x, y), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_BODY, MapColors.PANEL_HEADER)
	y += 6
	draw_line(Vector2(x, y), Vector2(panel_x + PANEL_WIDTH - 14, y), MapColors.PANEL_BORDER, 1.0)
	y += 16

	# Type
	var type_text: String = _type_to_string(ent["type"])
	_draw_row(font, x, value_x, y, "TYPE", type_text)
	y += 18

	# Position
	var pos_text: String = "%.0f, %.0f" % [ent["pos_x"], ent["pos_z"]]
	_draw_row(font, x, value_x, y, "POS", pos_text)
	y += 18

	# Distance from player (skip in preview mode — no live player)
	if _player_id != "" and _selected_id != _player_id and preview_entities.is_empty():
		var player: Dictionary = EntityRegistry.get_entity(_player_id)
		if not player.is_empty():
			var dx: float = ent["pos_x"] - player["pos_x"]
			var dz: float = ent["pos_z"] - player["pos_z"]
			var dist: float = sqrt(dx * dx + dz * dz)
			_draw_row(font, x, value_x, y, "DIST", camera.format_distance(dist))
			y += 18

	# Speed (for ships)
	if speed > 0.5:
		_draw_row(font, x, value_x, y, "VIT", "%.1f m/s" % speed)
		y += 18

	# Orbital info (for planets)
	if ent["orbital_radius"] > 0.0:
		_draw_row(font, x, value_x, y, "ORBITE", camera.format_distance(ent["orbital_radius"]))
		y += 18
		if ent["orbital_period"] > 0.0:
			var period_min: float = ent["orbital_period"] / 60.0
			if period_min > 60.0:
				_draw_row(font, x, value_x, y, "PÉRIODE", "%.1f h" % (period_min / 60.0))
			else:
				_draw_row(font, x, value_x, y, "PÉRIODE", "%.0f min" % period_min)
			y += 18

	# Type-specific extras
	if extra.has("spectral_class"):
		_draw_row(font, x, value_x, y, "CLASSE", extra["spectral_class"])
		y += 18
	if extra.has("temperature"):
		_draw_row(font, x, value_x, y, "TEMP", "%d K" % int(extra["temperature"]))
		y += 18
	if extra.has("planet_type"):
		_draw_row(font, x, value_x, y, "CORPS", _planet_type_to_french(extra["planet_type"]))
		y += 18
	if extra.has("station_type"):
		_draw_row(font, x, value_x, y, "SERVICE", _station_type_to_french(extra["station_type"]))
		y += 18
	if extra.has("dominant_resource"):
		_draw_row(font, x, value_x, y, "RESSOURCE", _resource_label(extra["dominant_resource"]))
		y += 18
	if extra.has("secondary_resource") and extra["secondary_resource"] != "":
		_draw_row(font, x, value_x, y, "SECONDAIRE", _resource_label(extra["secondary_resource"]))
		y += 18
	if extra.has("zone"):
		_draw_row(font, x, value_x, y, "ZONE", _zone_to_french(extra["zone"]))
		y += 18

	# NPC ship extras: faction + class
	if extra.has("faction"):
		_draw_row(font, x, value_x, y, "FACTION", _faction_to_label(extra["faction"]))
		y += 18
	if extra.has("ship_class"):
		_draw_row(font, x, value_x, y, "CLASSE", extra["ship_class"])
		y += 18
	if extra.has("event_tier"):
		var tier_labels: Array = ["", "FACILE", "MOYEN", "DIFFICILE"]
		var tier_val: int = clampi(int(extra["event_tier"]), 1, 3)
		_draw_row(font, x, value_x, y, "DANGER", tier_labels[tier_val])
		y += 18
	if extra.has("event_id"):
		var evt_mgr = GameManager.get_node_or_null("GameplayIntegrator")
		if evt_mgr:
			evt_mgr = evt_mgr.get_node_or_null("EventManager")
		if evt_mgr and evt_mgr.has_method("get_event"):
			var evt: EventData = evt_mgr.get_event(extra["event_id"])
			if evt:
				var remaining: float = evt.get_time_remaining()
				var mins: int = int(remaining) / 60
				var secs: int = int(remaining) % 60
				_draw_row(font, x, value_x, y, "TEMPS", "%d:%02d" % [mins, secs])
				y += 18

	# Scanline decoration
	var local_scan_y: float = fmod(_pulse_t * 40.0, panel_h)
	if local_scan_y > 0:
		draw_line(
			Vector2(panel_x, panel_y + local_scan_y),
			Vector2(panel_x + PANEL_WIDTH, panel_y + local_scan_y),
			MapColors.SCANLINE, 1.0
		)


func _draw_row(font: Font, x: float, vx: float, y: float, key: String, value: String) -> void:
	draw_string(font, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, MapColors.LABEL_KEY)
	draw_string(font, Vector2(vx, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_SMALL, MapColors.LABEL_VALUE)


func _type_to_string(type: int) -> String:
	match type:
		EntityRegistrySystem.EntityType.STAR: return "ÉTOILE"
		EntityRegistrySystem.EntityType.PLANET: return "PLANÈTE"
		EntityRegistrySystem.EntityType.STATION: return "STATION"
		EntityRegistrySystem.EntityType.SHIP_PLAYER: return "VAISSEAU JOUEUR"
		EntityRegistrySystem.EntityType.SHIP_NPC: return "VAISSEAU PNJ"
		EntityRegistrySystem.EntityType.ASTEROID_BELT: return "CEINTURE D'ASTÉROÏDES"
		EntityRegistrySystem.EntityType.JUMP_GATE: return "PORTAIL HYPERSPATIAL"
		EntityRegistrySystem.EntityType.EVENT: return "ÉVÉNEMENT"
	return "INCONNU"


func _planet_type_to_french(ptype: String) -> String:
	match ptype:
		"rocky": return "Rocheux"
		"gas_giant": return "Géante gazeuse"
		"ice": return "Glacé"
		"ocean": return "Océanique"
		"lava": return "Volcanique"
	return ptype


func _faction_to_label(f: String) -> String:
	match f:
		"hostile": return "Hostile"
		"friendly": return "Allié"
	return "Neutre"


func _station_type_to_french(stype: String) -> String:
	match stype:
		"repair": return "Réparation"
		"trade": return "Commerce"
		"military": return "Militaire"
		"mining": return "Extraction"
	return stype.capitalize()


func _resource_label(res_id: String) -> String:
	match res_id:
		"ice": return "Glace"
		"iron": return "Fer"
		"copper": return "Cuivre"
		"titanium": return "Titane"
		"gold": return "Or"
		"crystal": return "Cristal"
		"uranium": return "Uranium"
		"platinum": return "Platine"
	return res_id.capitalize()


func _zone_to_french(zone: String) -> String:
	match zone:
		"inner": return "Intérieure"
		"mid": return "Médiane"
		"outer": return "Extérieure"
	return zone.capitalize()
