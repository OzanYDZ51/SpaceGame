class_name StationScreen
extends UIScreen

# =============================================================================
# Station Screen - Docked station interior UI
# Holographic station terminal with services menu.
# Services are placeholder buttons for now (Phase 4 will implement trading).
# =============================================================================

signal undock_requested
signal equipment_requested

@export_group("Layout")
@export var button_width: float = 280.0
@export var button_height: float = 30.0
@export var button_gap: float = 4.0
@export var services_start_y: float = 240.0

var _station_name: String = "STATION"
var _service_buttons: Array[UIButton] = []
var _undock_button: UIButton = null
var _emblem_pulse: float = 0.0

# Service definitions: [name, description, enabled]
const SERVICES: Array[Array] = [
	["COMMERCE", "Acheter et vendre des marchandises", false],
	["RÉPARATIONS", "Réparer la coque et les boucliers", false],
	["ÉQUIPEMENT", "Modifier l'armement du vaisseau", true],
	["RAVITAILLEMENT", "Recharger carburant et munitions", false],
	["MISSIONS", "Consulter les contrats disponibles", false],
]


func _ready() -> void:
	screen_title = "STATION"
	screen_mode = ScreenMode.OVERLAY
	super._ready()
	_create_buttons()


func set_station_name(sname: String) -> void:
	_station_name = sname
	screen_title = sname.to_upper()


func _create_buttons() -> void:
	for i in SERVICES.size():
		var svc: Array = SERVICES[i]
		var btn := UIButton.new()
		btn.text = svc[0]
		btn.enabled = svc[2]
		btn.visible = false
		add_child(btn)
		_service_buttons.append(btn)
		# Connect equipment button (index 2)
		if i == 2:
			btn.pressed.connect(_on_equipment_pressed)

	_undock_button = UIButton.new()
	_undock_button.text = "QUITTER LE DOCK"
	_undock_button.accent_color = UITheme.WARNING
	_undock_button.visible = false
	_undock_button.pressed.connect(_on_undock_pressed)
	add_child(_undock_button)


func _on_opened() -> void:
	_layout_buttons()
	for btn in _service_buttons:
		btn.visible = true
	_undock_button.visible = true


func _on_closed() -> void:
	for btn in _service_buttons:
		btn.visible = false
	_undock_button.visible = false
	# Closing the terminal returns to hangar view (does NOT undock)


func _on_equipment_pressed() -> void:
	equipment_requested.emit()


func _on_undock_pressed() -> void:
	# Undock button explicitly requests leaving the station
	undock_requested.emit()


func _layout_buttons() -> void:
	var s: Vector2 = size
	var cx: float = s.x * 0.5

	for i in _service_buttons.size():
		var btn: UIButton = _service_buttons[i]
		btn.position = Vector2(cx - button_width * 0.5, services_start_y + i * (button_height + button_gap))
		btn.size = Vector2(button_width, button_height)

	# Undock button at the bottom
	_undock_button.position = Vector2(cx - button_width * 0.5, s.y - 72)
	_undock_button.size = Vector2(button_width, button_height)


func _process(delta: float) -> void:
	super._process(delta)
	_emblem_pulse += delta


func _draw() -> void:
	# Semi-transparent background (hangar 3D visible through)
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.01, 0.03, 0.4))

	# Vignette edges (darker at borders for focus)
	var edge_col := Color(0.0, 0.0, 0.02, 0.5)
	draw_rect(Rect2(0, 0, s.x, 50), edge_col)
	draw_rect(Rect2(0, s.y - 40, s.x, 40), edge_col)

	# Title
	_draw_title(s)

	if not _is_open:
		return

	var font: Font = UITheme.get_font()
	var cx: float = s.x * 0.5

	# =========================================================================
	# STATION EMBLEM (geometric hexagon with pulsing glow)
	# =========================================================================
	var emblem_y: float = 90.0
	var emblem_r: float = 22.0
	_draw_station_emblem(Vector2(cx, emblem_y), emblem_r)

	# Station name below emblem
	draw_string(font, Vector2(0, emblem_y + emblem_r + 18), _station_name.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_HEADER, UITheme.TEXT)

	# Subtitle
	draw_string(font, Vector2(0, emblem_y + emblem_r + 32), "TERMINAL DE STATION",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)

	# =========================================================================
	# INFO PANEL (left of center)
	# =========================================================================
	var info_x: float = cx - 140.0
	var info_y: float = emblem_y + emblem_r + 44
	var info_w: float = 280.0

	# Separator line
	draw_line(Vector2(info_x, info_y), Vector2(info_x + info_w, info_y), UITheme.BORDER, 1.0)
	info_y += 14

	# Info rows
	_draw_info_row(font, info_x, info_y, info_w, "TYPE", "Station orbitale")
	info_y += UITheme.ROW_HEIGHT
	_draw_info_row(font, info_x, info_y, info_w, "FACTION", "Neutre")
	info_y += UITheme.ROW_HEIGHT
	_draw_info_row(font, info_x, info_y, info_w, "SERVICES", "%d disponibles" % SERVICES.size())
	info_y += UITheme.ROW_HEIGHT + 8

	# Separator before services
	draw_line(Vector2(info_x, info_y), Vector2(info_x + info_w, info_y), UITheme.BORDER, 1.0)

	# =========================================================================
	# SERVICE SECTION HEADER
	# =========================================================================
	var svc_header_y: float = 224.0
	var header_x: float = cx - 140.0
	# Accent bar
	draw_rect(Rect2(header_x, svc_header_y, 2, 12), UITheme.PRIMARY)
	draw_string(font, Vector2(header_x + 8, svc_header_y + 10), "SERVICES",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_LABEL, UITheme.TEXT_HEADER)
	# Extending line
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
	# Top-left
	draw_line(Vector2(m, m), Vector2(m + cl, m), cc, 1.5)
	draw_line(Vector2(m, m), Vector2(m, m + cl), cc, 1.5)
	# Top-right
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m - cl, m), cc, 1.5)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + cl), cc, 1.5)
	# Bottom-left
	draw_line(Vector2(m, s.y - m), Vector2(m + cl, s.y - m), cc, 1.5)
	draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - cl), cc, 1.5)
	# Bottom-right
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - cl, s.y - m), cc, 1.5)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - cl), cc, 1.5)

	# =========================================================================
	# SCANLINE
	# =========================================================================
	var scan_y: float = fmod(UITheme.scanline_y, s.y)
	var scan_col := Color(UITheme.SCANLINE.r, UITheme.SCANLINE.g, UITheme.SCANLINE.b, 0.03)
	draw_line(Vector2(0, scan_y), Vector2(s.x, scan_y), scan_col, 1.0)


func _draw_station_emblem(center: Vector2, radius: float) -> void:
	# Hexagonal emblem with glow
	var points: PackedVector2Array = PackedVector2Array()
	for i in 7:
		var angle: float = TAU * float(i) / 6.0 - PI * 0.5
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	# Glow ring (pulsing)
	var glow_alpha: float = 0.1 + sin(_emblem_pulse * 1.5) * 0.06
	var glow_col := Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, glow_alpha)
	for i in 6:
		var angle: float = TAU * float(i) / 6.0 - PI * 0.5
		var outer: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius + 4)
		var angle2: float = TAU * float(i + 1) / 6.0 - PI * 0.5
		var outer2: Vector2 = center + Vector2(cos(angle2), sin(angle2)) * (radius + 4)
		draw_line(outer, outer2, glow_col, 1.0)

	# Hexagon outline
	draw_polyline(points, UITheme.PRIMARY, 1.0)

	# Inner diamond
	var ir: float = radius * 0.4
	var inner_pts: PackedVector2Array = PackedVector2Array()
	inner_pts.append(center + Vector2(0, -ir))
	inner_pts.append(center + Vector2(ir, 0))
	inner_pts.append(center + Vector2(0, ir))
	inner_pts.append(center + Vector2(-ir, 0))
	inner_pts.append(center + Vector2(0, -ir))
	draw_polyline(inner_pts, UITheme.PRIMARY_DIM, 1.0)

	# Center dot
	draw_circle(center, 2.0, UITheme.PRIMARY)


func _draw_info_row(font: Font, x: float, y: float, w: float, key: String, value: String) -> void:
	draw_string(font, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1,
		UITheme.FONT_SIZE_TINY, UITheme.LABEL_KEY)
	draw_string(font, Vector2(x + 80, y), value, HORIZONTAL_ALIGNMENT_LEFT, int(w - 80),
		UITheme.FONT_SIZE_SMALL, UITheme.LABEL_VALUE)
