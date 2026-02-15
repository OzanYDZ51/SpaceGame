class_name StationScreen
extends UIScreen

# =============================================================================
# Station Screen - Docked station interior UI
# Holographic station terminal with unlockable services.
# Central systems (danger <= 1) are pre-unlocked. Others require credits.
# =============================================================================

signal undock_requested
signal equipment_requested
signal commerce_requested
signal repair_requested
signal shipyard_requested
signal refinery_requested
signal storage_requested
signal station_equipment_requested
signal administration_requested

@export_group("Layout")
@export var button_width: float = 280.0
@export var button_height: float = 30.0
@export var button_gap: float = 4.0
@export var services_start_y: float = 240.0

var _station_name: String = "STATION"
var _service_buttons: Array[UIButton] = []
var _station_equip_button: UIButton = null
var _admin_button: UIButton = null
var _undock_button: UIButton = null
var _emblem_pulse: float = 0.0

# Service unlock state
var _services = null
var _system_id: int = -1
var _station_idx: int = 0
var _economy = null

# Service order: COMMERCE, RÉPARATIONS, ÉQUIPEMENT, CHANTIER NAVAL
const SERVICE_ORDER: Array[int] = [
	StationServices.Service.COMMERCE,
	StationServices.Service.REPAIR,
	StationServices.Service.EQUIPMENT,
	StationServices.Service.SHIPYARD,
	StationServices.Service.REFINERY,
	StationServices.Service.ENTREPOT,
]

const SERVICE_DESCRIPTIONS: Dictionary = {
	StationServices.Service.COMMERCE: "Acheter et vendre des marchandises",
	StationServices.Service.REPAIR: "Réparer la coque et les boucliers",
	StationServices.Service.EQUIPMENT: "Modifier l'armement du vaisseau",
	StationServices.Service.SHIPYARD: "Acheter et vendre des vaisseaux",
	StationServices.Service.REFINERY: "Raffiner les minerais en materiaux",
	StationServices.Service.ENTREPOT: "Stocker des ressources et du cargo",
}


func _ready() -> void:
	screen_title = "STATION"
	screen_mode = ScreenMode.OVERLAY
	super._ready()
	_create_buttons()


func set_station_name(sname: String) -> void:
	_station_name = sname
	screen_title = sname.to_upper()


func setup(services, system_id: int, station_idx: int, economy) -> void:
	_services = services
	_system_id = system_id
	_station_idx = station_idx
	_economy = economy
	_refresh_buttons()
	queue_redraw()


func _create_buttons() -> void:
	for i in SERVICE_ORDER.size():
		var svc: int = SERVICE_ORDER[i]
		var btn =UIButton.new()
		btn.text = StationServices.SERVICE_LABELS[svc]
		btn.enabled = false
		btn.visible = false
		add_child(btn)
		_service_buttons.append(btn)
		btn.pressed.connect(_on_service_pressed.bind(i))

	_station_equip_button = UIButton.new()
	_station_equip_button.text = "EQUIPEMENT STATION"
	_station_equip_button.accent_color = Color(0.4, 0.7, 1.0)
	_station_equip_button.visible = false
	_station_equip_button.pressed.connect(_on_station_equip_pressed)
	add_child(_station_equip_button)

	_admin_button = UIButton.new()
	_admin_button.text = "ADMINISTRATION"
	_admin_button.accent_color = Color(0.6, 0.4, 1.0)
	_admin_button.visible = false
	_admin_button.pressed.connect(_on_admin_pressed)
	add_child(_admin_button)

	_undock_button = UIButton.new()
	_undock_button.text = "QUITTER LE DOCK"
	_undock_button.accent_color = UITheme.WARNING
	_undock_button.visible = false
	_undock_button.pressed.connect(_on_undock_pressed)
	add_child(_undock_button)


func _refresh_buttons() -> void:
	for i in SERVICE_ORDER.size():
		var svc: int = SERVICE_ORDER[i]
		var btn: UIButton = _service_buttons[i]
		var unlocked: bool = _services != null and _services.is_unlocked(_system_id, _station_idx, svc)
		btn.enabled = true  # Always clickable
		if unlocked:
			btn.text = StationServices.SERVICE_LABELS[svc]
			btn.accent_color = UITheme.PRIMARY
		else:
			var price: int = StationServices.SERVICE_PRICES[svc]
			btn.text = "%s — %s CR" % [StationServices.SERVICE_LABELS[svc], PlayerEconomy.format_credits(price)]
			btn.accent_color = UITheme.TEXT_DIM
	queue_redraw()


func _on_service_pressed(button_index: int) -> void:
	var svc: int = SERVICE_ORDER[button_index]
	var unlocked: bool = _services != null and _services.is_unlocked(_system_id, _station_idx, svc)

	if unlocked:
		match svc:
			StationServices.Service.COMMERCE:
				commerce_requested.emit()
			StationServices.Service.REPAIR:
				repair_requested.emit()
			StationServices.Service.EQUIPMENT:
				equipment_requested.emit()
			StationServices.Service.SHIPYARD:
				shipyard_requested.emit()
			StationServices.Service.REFINERY:
				refinery_requested.emit()
			StationServices.Service.ENTREPOT:
				storage_requested.emit()
	else:
		_try_unlock(svc)


func _try_unlock(svc: int) -> void:
	if _services == null or _economy == null:
		return

	var price: int = StationServices.SERVICE_PRICES[svc]
	if _economy.credits < price:
		if GameManager._notif:
			GameManager._notif.general.insufficient_credits(PlayerEconomy.format_credits(price))
		return

	if _services.unlock(_system_id, _station_idx, svc, _economy):
		_refresh_buttons()
		if GameManager._notif:
			GameManager._notif.general.service_unlocked(StationServices.SERVICE_LABELS[svc])


func _on_opened() -> void:
	_refresh_buttons()
	_layout_buttons()
	for btn in _service_buttons:
		btn.visible = true
	_station_equip_button.visible = true
	_admin_button.visible = true
	_undock_button.visible = true


func _on_closed() -> void:
	for btn in _service_buttons:
		btn.visible = false
	_station_equip_button.visible = false
	_admin_button.visible = false
	_undock_button.visible = false


func _on_undock_pressed() -> void:
	undock_requested.emit()


func _on_station_equip_pressed() -> void:
	station_equipment_requested.emit()


func _on_admin_pressed() -> void:
	administration_requested.emit()


func _layout_buttons() -> void:
	var s: Vector2 = size
	var cx: float = s.x * 0.5

	for i in _service_buttons.size():
		var btn: UIButton = _service_buttons[i]
		btn.position = Vector2(cx - button_width * 0.5, services_start_y + i * (button_height + button_gap))
		btn.size = Vector2(button_width, button_height)

	# Station equipment button — after service buttons
	var station_equip_y: float = services_start_y + _service_buttons.size() * (button_height + button_gap) + 12
	_station_equip_button.position = Vector2(cx - button_width * 0.5, station_equip_y)
	_station_equip_button.size = Vector2(button_width, button_height)

	# Administration button — after station equipment
	var admin_y: float = station_equip_y + button_height + button_gap
	_admin_button.position = Vector2(cx - button_width * 0.5, admin_y)
	_admin_button.size = Vector2(button_width, button_height)

	_undock_button.position = Vector2(cx - button_width * 0.5, s.y - 72)
	_undock_button.size = Vector2(button_width, button_height)


func _process(delta: float) -> void:
	_emblem_pulse += delta


func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.4))

	var edge_col =Color(0.0, 0.0, 0.02, 0.5)
	draw_rect(Rect2(0, 0, s.x, 50), edge_col)
	draw_rect(Rect2(0, s.y - 40, s.x, 40), edge_col)

	_draw_title(s)

	if not _is_open:
		return

	var font: Font = UITheme.get_font()
	var cx: float = s.x * 0.5

	# =========================================================================
	# STATION EMBLEM
	# =========================================================================
	var emblem_y: float = 90.0
	var emblem_r: float = 22.0
	_draw_station_emblem(Vector2(cx, emblem_y), emblem_r)

	draw_string(font, Vector2(0, emblem_y + emblem_r + 18), _station_name.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)

	draw_string(font, Vector2(0, emblem_y + emblem_r + 32), "TERMINAL DE STATION",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# =========================================================================
	# INFO PANEL
	# =========================================================================
	var info_x: float = cx - 140.0
	var info_y: float = emblem_y + emblem_r + 44
	var info_w: float = 280.0

	draw_line(Vector2(info_x, info_y), Vector2(info_x + info_w, info_y), UITheme.BORDER, 1.0)
	info_y += 14

	_draw_info_row(font, info_x, info_y, info_w, "TYPE", "Station orbitale")
	info_y += UITheme.ROW_HEIGHT
	_draw_info_row(font, info_x, info_y, info_w, "FACTION", "Neutre")
	info_y += UITheme.ROW_HEIGHT

	# Services count
	var unlocked_count: int = 0
	if _services:
		unlocked_count = _services.get_unlocked_count(_system_id, _station_idx)
	_draw_info_row(font, info_x, info_y, info_w, "SERVICES", "%d / %d actifs" % [unlocked_count, SERVICE_ORDER.size()])
	info_y += UITheme.ROW_HEIGHT + 8

	draw_line(Vector2(info_x, info_y), Vector2(info_x + info_w, info_y), UITheme.BORDER, 1.0)

	# =========================================================================
	# SERVICE SECTION HEADER
	# =========================================================================
	var svc_header_y: float = 224.0
	var header_x: float = cx - 140.0
	draw_rect(Rect2(header_x, svc_header_y, 2, 12), UITheme.PRIMARY)
	draw_string(font, Vector2(header_x + 8, svc_header_y + 10), "SERVICES",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)
	var header_text_w: float = font.get_string_size("SERVICES", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL).x
	draw_line(
		Vector2(header_x + 12 + header_text_w, svc_header_y + 5),
		Vector2(cx + 140.0, svc_header_y + 5),
		UITheme.BORDER, 1.0
	)

	# =========================================================================
	# UNDOCK SECTION
	# =========================================================================
	var undock_y: float = s.y - 100.0
	draw_line(Vector2(cx - 140, undock_y), Vector2(cx + 140, undock_y), UITheme.BORDER, 1.0)

	# =========================================================================
	# CORNER DECORATIONS
	# =========================================================================
	var m: float = 30.0
	var cl: float = 20.0
	var cc: Color = UITheme.CORNER
	draw_line(Vector2(m, m), Vector2(m + cl, m), cc, 1.5)
	draw_line(Vector2(m, m), Vector2(m, m + cl), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m - cl, m), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + cl), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m + cl, s.y - m), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - cl), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - cl, s.y - m), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - cl), cc, 1.5)

	# =========================================================================
	# SCANLINE
	# =========================================================================
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	var scan_col =Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y), scan_col, 1.0)


func _draw_station_emblem(center: Vector2, radius: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in 7:
		var angle: float = TAU * float(i) / 6.0 - PI * 0.5
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	var glow_alpha: float = 0.1 + sin(_emblem_pulse * 1.5) * 0.06
	var glow_col =Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, glow_alpha)
	for i in 6:
		var angle: float = TAU * float(i) / 6.0 - PI * 0.5
		var outer: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius + 4)
		var angle2: float = TAU * float(i + 1) / 6.0 - PI * 0.5
		var outer2: Vector2 = center + Vector2(cos(angle2), sin(angle2)) * (radius + 4)
		draw_line(outer, outer2, glow_col, 1.0)

	draw_polyline(points, UITheme.PRIMARY, 1.0)

	var ir: float = radius * 0.4
	var inner_pts: PackedVector2Array = PackedVector2Array()
	inner_pts.append(center + Vector2(0, -ir))
	inner_pts.append(center + Vector2(ir, 0))
	inner_pts.append(center + Vector2(0, ir))
	inner_pts.append(center + Vector2(-ir, 0))
	inner_pts.append(center + Vector2(0, -ir))
	draw_polyline(inner_pts, UITheme.PRIMARY_DIM, 1.0)

	draw_circle(center, 2.0, UITheme.PRIMARY)


func _draw_info_row(font: Font, x: float, y: float, w: float, key: String, value: String) -> void:
	draw_string(font, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1,
		UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(x + 80, y), value, HORIZONTAL_ALIGNMENT_LEFT, int(w - 80),
		UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
