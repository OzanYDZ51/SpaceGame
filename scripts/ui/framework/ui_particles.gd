class_name UIParticles
extends Control

# =============================================================================
# UI Particles - Ambient holographic dust particles for screen backgrounds
# Lightweight 2D particle simulation (no GPUParticles overhead).
# =============================================================================

const PARTICLE_COUNT := 60
const DRIFT_SPEED := 15.0
const PARTICLE_ALPHA := 0.3
const PARTICLE_SIZE_MIN := 1.0
const PARTICLE_SIZE_MAX := 2.5

var _particles: Array[Dictionary] = []
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_particles()


func _init_particles() -> void:
	_particles.clear()
	for i in PARTICLE_COUNT:
		_particles.append(_make_particle(true))


func _make_particle(randomize_y: bool) -> Dictionary:
	var s := size
	if s.x < 1.0:
		s = Vector2(1920, 1080)
	return {
		"x": randf() * s.x,
		"y": randf() * s.y if randomize_y else s.y + randf() * 20.0,
		"speed": (0.3 + randf() * 0.7) * DRIFT_SPEED,
		"drift_x": (randf() - 0.5) * 8.0,
		"size": PARTICLE_SIZE_MIN + randf() * (PARTICLE_SIZE_MAX - PARTICLE_SIZE_MIN),
		"alpha": (0.3 + randf() * 0.7) * PARTICLE_ALPHA,
	}


func activate() -> void:
	if _active:
		return
	_active = true
	visible = true
	_init_particles()


func deactivate() -> void:
	_active = false
	visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	var s := size
	for p in _particles:
		p["y"] -= p["speed"] * delta
		p["x"] += p["drift_x"] * delta
		# Respawn at bottom when off-screen
		if p["y"] < -10.0 or p["x"] < -10.0 or p["x"] > s.x + 10.0:
			var np := _make_particle(false)
			p["x"] = np["x"]
			p["y"] = np["y"]
			p["speed"] = np["speed"]
			p["drift_x"] = np["drift_x"]
			p["size"] = np["size"]
			p["alpha"] = np["alpha"]
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var col := UITheme.PRIMARY
	for p in _particles:
		var c := Color(col.r, col.g, col.b, p["alpha"])
		var sz: float = p["size"]
		draw_rect(Rect2(p["x"] - sz * 0.5, p["y"] - sz * 0.5, sz, sz), c)
