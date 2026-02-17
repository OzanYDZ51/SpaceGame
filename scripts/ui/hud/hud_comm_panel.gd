class_name HudCommPanel
extends Control

# =============================================================================
# HUD Comm Panel — Star Citizen-style radio transmission notification.
# Slides in from right, typewriter text, procedural portrait, interference FX.
# Queues up to 3 transmissions if one is already playing.
# =============================================================================

var pulse_t: float = 0.0
var scan_line_y: float = 0.0

var _panel: Control = null

enum State { IDLE, SLIDE_IN, TYPING, HOLDING, SLIDE_OUT }
var _state: int = State.IDLE
var _anim_t: float = 0.0
var _slide_progress: float = 0.0  # 0=offscreen, 1=visible

# Current transmission
var _commander: String = ""
var _title: String = ""
var _full_text: String = ""
var _typed_chars: int = 0
var _tier_color: Color = Color.WHITE
var _freq: String = ""
var _rank_chevrons: int = 0

# Queue
var _queue: Array[Dictionary] = []
const MAX_QUEUE: int = 3

# Timing
const SLIDE_IN_DUR: float = 0.4
const SLIDE_OUT_DUR: float = 0.4
const HOLD_DUR: float = 4.0
const TYPE_CPS: float = 30.0

# Layout
const PW: float = 284.0
const PH: float = 140.0
const MARGIN_R: float = 16.0
const PANEL_Y: float = 218.0

# Commander pool: [name, title, chevron_count]
const COMMANDERS: Array = [
	["CDR. VASQUEZ", "COMMANDEMENT DE SECTEUR", 4],
	["LT. MORIN", "SURVEILLANCE SPATIALE", 2],
	["CPT. DUVAL", "DEFENSE DE ZONE", 3],
	["ADM. CHEN", "ETAT-MAJOR CENTRAL", 5],
	["LT. NAKAMURA", "CONTROLE RADAR", 2],
	["CDR. OKAFOR", "OPERATIONS TACTIQUES", 4],
]

# Message pools
const MSG_TIER: Array = [
	[  # Tier 1
		"Alerte! Un convoi pirate a ete detecte dans ce secteur. Procedez avec prudence.",
		"Contact radar! Signatures pirates confirmees dans votre zone. Restez vigilant.",
		"Activite pirate detectee a proximite. Groupe leger, mais dangereux.",
	],
	[  # Tier 2
		"Convoi pirate lourd repere! Escortes armees confirmees. Approche deconseillee.",
		"Alerte elevee! Convoi renforce en transit. Engagement a vos risques.",
		"Signatures multiples detectees! Escorte lourde en approche.",
	],
	[  # Tier 3
		"ALERTE MAXIMALE! Armada pirate complete detectee. Renforts requis!",
		"URGENCE! Flotte pirate massive en approche! Toutes unites en alerte!",
		"DEFCON 1! Armada pirate confirmee. Evacuez ou engagez!",
	],
]
const MSG_COMPLETE: Array = [
	"Convoi neutralise. Excellent travail, pilote.",
	"Menace eliminee. Zone securisee. Bon travail.",
	"Cible detruite. Vous avez l'appreciation du commandement.",
]

# Interference state
var _signal_bars: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
var _glitch_offset_x: float = 0.0
var _noise_t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = HudDrawHelpers.make_ctrl(1.0, 0.0, 1.0, 0.0, 0, PANEL_Y, PW, PANEL_Y + PH)
	_panel.draw.connect(_draw_panel.bind(_panel))
	_panel.visible = false
	_panel.clip_contents = true
	add_child(_panel)


# =============================================================================
# PUBLIC API
# =============================================================================

func show_transmission(evt_tier: int, evt_color: Color) -> void:
	var tier_idx: int = clampi(evt_tier - 1, 0, 2)
	var pool: Array = MSG_TIER[tier_idx]
	_enqueue(evt_color, pool[randi() % pool.size()])


func show_completion(_evt_tier: int) -> void:
	_enqueue(UITheme.ACCENT, MSG_COMPLETE[randi() % MSG_COMPLETE.size()])


# =============================================================================
# QUEUE + STATE MACHINE
# =============================================================================

func _enqueue(col: Color, text: String) -> void:
	var data := {"color": col, "text": text}
	if _state == State.IDLE:
		_start_transmission(data)
	elif _queue.size() < MAX_QUEUE:
		_queue.append(data)


func _start_transmission(data: Dictionary) -> void:
	var cmd: Array = COMMANDERS[randi() % COMMANDERS.size()]
	_commander = cmd[0]
	_title = cmd[1]
	_rank_chevrons = cmd[2]
	_tier_color = data["color"]
	_full_text = data["text"]
	_typed_chars = 0
	_freq = "FREQ %d.%02d" % [randi_range(100, 399), randi_range(0, 99)]
	_anim_t = 0.0
	_slide_progress = 0.0
	_state = State.SLIDE_IN
	_panel.visible = true


func update(delta: float) -> void:
	if _state == State.IDLE:
		return

	_anim_t += delta
	_noise_t += delta

	# Signal bars fluctuation
	for i in 5:
		var base: float = 0.6 + 0.4 * sin(_noise_t * (1.5 + i * 0.3) + i * 1.7)
		if randf() < 0.02:
			base *= 0.2
		_signal_bars[i] = clampf(base, 0.0, 1.0)

	# Glitch (3% chance per frame)
	if randf() < 0.03:
		_glitch_offset_x = randf_range(-8.0, 8.0)
	else:
		_glitch_offset_x = move_toward(_glitch_offset_x, 0.0, delta * 60.0)

	match _state:
		State.SLIDE_IN:
			_slide_progress = _ease_out_cubic(minf(_anim_t / SLIDE_IN_DUR, 1.0))
			if _anim_t >= SLIDE_IN_DUR:
				_slide_progress = 1.0
				_anim_t = 0.0
				_state = State.TYPING
		State.TYPING:
			_typed_chars = int(_anim_t * TYPE_CPS)
			if _typed_chars >= _full_text.length():
				_typed_chars = _full_text.length()
				_anim_t = 0.0
				_state = State.HOLDING
		State.HOLDING:
			if _anim_t >= HOLD_DUR:
				_anim_t = 0.0
				_state = State.SLIDE_OUT
		State.SLIDE_OUT:
			_slide_progress = 1.0 - _ease_in_quad(minf(_anim_t / SLIDE_OUT_DUR, 1.0))
			if _anim_t >= SLIDE_OUT_DUR:
				_slide_progress = 0.0
				_state = State.IDLE
				_panel.visible = false
				if not _queue.is_empty():
					_start_transmission(_queue.pop_front())
				return

	# Update slide position
	var off_x: float = (PW + MARGIN_R) * (1.0 - _slide_progress)
	_panel.offset_left = -(PW + MARGIN_R) + off_x
	_panel.offset_right = -MARGIN_R + off_x
	_panel.queue_redraw()


# =============================================================================
# DRAWING
# =============================================================================

func _draw_panel(ctrl: Control) -> void:
	var font: Font = UITheme.get_font_medium()
	var font_sm: Font = UITheme.get_font()

	# Background
	ctrl.draw_rect(Rect2(Vector2.ZERO, ctrl.size), Color(0.005, 0.012, 0.03, 0.85))

	# Border + top accent
	ctrl.draw_rect(Rect2(Vector2.ZERO, ctrl.size), Color(_tier_color.r, _tier_color.g, _tier_color.b, 0.4), false, 1.5)
	ctrl.draw_rect(Rect2(0, 0, ctrl.size.x, 2), _tier_color)

	# Scanline
	var sl := UITheme.SCANLINE
	var sy: float = fmod(scan_line_y, ctrl.size.y)
	ctrl.draw_line(Vector2(0, sy), Vector2(ctrl.size.x, sy), Color(sl.r, sl.g, sl.b, sl.a * 2.0), 1.0)

	# --- Header ---
	var hx: float = 8.0
	var hy: float = 16.0
	var dot_alpha: float = 0.5 + 0.5 * sin(pulse_t * 4.0)
	ctrl.draw_circle(Vector2(hx + 4, hy - 4), 3.0, Color(_tier_color.r, _tier_color.g, _tier_color.b, dot_alpha))
	ctrl.draw_string(font, Vector2(hx + 14, hy), "TRANSMISSION ENTRANTE", HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE_TINY, _tier_color)
	ctrl.draw_string(font_sm, Vector2(ctrl.size.x - 8, hy), _freq, HORIZONTAL_ALIGNMENT_RIGHT, 100, UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	ctrl.draw_line(Vector2(4, 22), Vector2(ctrl.size.x - 4, 22), Color(_tier_color.r, _tier_color.g, _tier_color.b, 0.3), 1.0)

	# --- Portrait ---
	var px: float = 12.0
	var py: float = 30.0
	var pw: float = 56.0
	var ph: float = 60.0
	_draw_portrait(ctrl, px, py, pw, ph)

	# --- Commander info ---
	var tx: float = px + pw + 10.0
	var ty: float = py + 14.0
	var text_w: float = ctrl.size.x - tx - 8.0
	ctrl.draw_string(font, Vector2(tx, ty), _commander, HORIZONTAL_ALIGNMENT_LEFT, int(text_w), UITheme.FONT_SIZE_SMALL, _tier_color)
	ty += 14.0
	ctrl.draw_string(font_sm, Vector2(tx, ty), _title, HORIZONTAL_ALIGNMENT_LEFT, int(text_w), UITheme.FONT_SIZE_TINY, UITheme.TEXT_DIM)
	ty += 16.0

	# --- Typewriter text ---
	var display: String = _full_text.substr(0, _typed_chars)
	if _state == State.TYPING and fmod(pulse_t, 0.6) < 0.3:
		display += "|"
	ctrl.draw_multiline_string(font_sm, Vector2(tx, ty), display, HORIZONTAL_ALIGNMENT_LEFT, text_w, UITheme.FONT_SIZE_TINY, -1, UITheme.TEXT)

	# --- Signal bars (bottom-right) ---
	var bar_x: float = ctrl.size.x - 40.0
	var bar_y: float = ctrl.size.y - 14.0
	for i in 5:
		var bh: float = 4.0 + i * 2.0
		var alpha: float = _signal_bars[i] * 0.8 + 0.1
		ctrl.draw_rect(Rect2(bar_x + i * 6, bar_y - bh, 4, bh), Color(_tier_color.r, _tier_color.g, _tier_color.b, alpha))

	# --- Static noise ---
	for i in 25:
		var nx: float = randf() * ctrl.size.x
		var ny: float = randf() * ctrl.size.y
		ctrl.draw_rect(Rect2(nx, ny, randf_range(1, 3), 1), Color(1, 1, 1, randf() * 0.08))

	# --- Glitch line ---
	if absf(_glitch_offset_x) > 0.5:
		var gy: float = randf() * ctrl.size.y
		ctrl.draw_rect(Rect2(_glitch_offset_x, gy, ctrl.size.x, randf_range(1, 3)), Color(_tier_color.r, _tier_color.g, _tier_color.b, 0.15))


func _draw_portrait(ctrl: Control, x: float, y: float, w: float, h: float) -> void:
	# Background
	ctrl.draw_rect(Rect2(x, y, w, h), Color(0.02, 0.04, 0.08, 0.9))
	ctrl.draw_rect(Rect2(x, y, w, h), Color(_tier_color.r, _tier_color.g, _tier_color.b, 0.3), false, 1.0)

	var cx: float = x + w * 0.5
	var cy: float = y + h * 0.4
	var col := Color(_tier_color.r, _tier_color.g, _tier_color.b, 0.6)

	# Head (circle)
	var head_r: float = w * 0.2
	var pts: PackedVector2Array = []
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		pts.append(Vector2(cx + cos(a) * head_r, cy + sin(a) * head_r))
	ctrl.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.3))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, col, 1.5)

	# Shoulders (trapezoid)
	var sy_top: float = cy + head_r + 3.0
	var sy_bot: float = y + h - 4.0
	var sw_top: float = w * 0.35
	var sw_bot: float = w * 0.5
	var sh_pts := PackedVector2Array([
		Vector2(cx - sw_top, sy_top), Vector2(cx + sw_top, sy_top),
		Vector2(cx + sw_bot, sy_bot), Vector2(cx - sw_bot, sy_bot),
	])
	ctrl.draw_colored_polygon(sh_pts, Color(col.r, col.g, col.b, 0.2))
	sh_pts.append(sh_pts[0])
	ctrl.draw_polyline(sh_pts, col, 1.0)

	# Rank chevrons (bottom-left of portrait)
	var chev_y: float = y + h - 6.0
	for i in _rank_chevrons:
		HudDrawHelpers.draw_diamond(ctrl, Vector2(x + 4 + i * 7 + 3, chev_y), 2.5, Color(col.r, col.g, col.b, 0.8))

	# Portrait interference lines (scrolling)
	for i in 3:
		var ly: float = y + fmod((_noise_t * 40.0 + i * 20.0), h)
		ctrl.draw_line(Vector2(x + 1, ly), Vector2(x + w - 1, ly), Color(1, 1, 1, 0.06), 1.0)


# =============================================================================
# EASING
# =============================================================================

static func _ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


static func _ease_in_quad(t: float) -> float:
	return t * t
