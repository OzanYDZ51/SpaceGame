class_name GForceEffects
extends CanvasLayer

# =============================================================================
# G-Force Effects - Blackout/redout vignette overlay driven by acceleration
# Uses exponential smoothing on velocity delta to filter frame jitter.
# Thresholds calibrated for space combat (boost maneuvers, not cruise).
# CanvasLayer 1, above speed effects but below UI.
# =============================================================================

var _rect: ColorRect = null
var _shader_mat: ShaderMaterial = null
var _ship = null

var _prev_velocity: Vector3 = Vector3.ZERO
var _smoothed_accel: Vector3 = Vector3.ZERO
var _blackout: float = 0.0
var _redout: float = 0.0

const ACCEL_SMOOTH: float = 0.15      # Exponential smoothing factor (lower = smoother)
const G_THRESHOLD: float = 5.0        # G-force before visual kicks in (tuned for space combat)
const G_MAX: float = 18.0             # Full blackout/redout
const ONSET_SPEED: float = 1.5        # How fast effects build
const RECOVERY_SPEED: float = 2.5     # How fast effects fade


func _ready() -> void:
	layer = 1

	var shader =load("res://shaders/gforce_overlay.gdshader") as Shader
	if shader == null:
		push_warning("GForceEffects: shader not found")
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader

	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _shader_mat
	_rect.visible = false
	add_child(_rect)


func set_ship(ship) -> void:
	_ship = ship
	_prev_velocity = ship.linear_velocity if ship else Vector3.ZERO
	_smoothed_accel = Vector3.ZERO
	_blackout = 0.0
	_redout = 0.0


func _process(delta: float) -> void:
	if _shader_mat == null or _ship == null:
		return

	# Skip during cruise warp (massive velocity = meaningless G)
	if _ship.cruise_warp_active:
		_prev_velocity = _ship.linear_velocity
		_blackout = maxf(_blackout - RECOVERY_SPEED * delta, 0.0)
		_redout = maxf(_redout - RECOVERY_SPEED * delta, 0.0)
		_update_visibility()
		return

	# Calculate raw acceleration from velocity delta
	var current_vel: Vector3 = _ship.linear_velocity
	var raw_accel: Vector3 = (current_vel - _prev_velocity) / maxf(delta, 0.001)
	_prev_velocity = current_vel

	# Exponential smoothing to filter frame-to-frame jitter
	_smoothed_accel = _smoothed_accel.lerp(raw_accel, ACCEL_SMOOTH)

	var g_force: float = _smoothed_accel.length() / 9.81

	# Determine direction: dot with ship forward (-Z)
	var target_blackout: float = 0.0
	var target_redout: float = 0.0

	if g_force > G_THRESHOLD:
		var ratio: float = clampf((g_force - G_THRESHOLD) / (G_MAX - G_THRESHOLD), 0.0, 1.0)
		var ship_fwd: Vector3 = -_ship.global_transform.basis.z
		var accel_dot: float = _smoothed_accel.normalized().dot(ship_fwd)

		# Hard turns (lateral) + forward accel -> blackout
		if accel_dot >= -0.3:
			target_blackout = ratio
		else:
			# Sudden braking -> redout
			target_redout = ratio

	# Smooth transitions
	if target_blackout > _blackout:
		_blackout = minf(_blackout + ONSET_SPEED * delta, target_blackout)
	else:
		_blackout = maxf(_blackout - RECOVERY_SPEED * delta, 0.0)

	if target_redout > _redout:
		_redout = minf(_redout + ONSET_SPEED * delta, target_redout)
	else:
		_redout = maxf(_redout - RECOVERY_SPEED * delta, 0.0)

	_update_visibility()


func _update_visibility() -> void:
	var any_effect: bool = _blackout > 0.01 or _redout > 0.01
	_rect.visible = any_effect
	if not any_effect:
		return
	_shader_mat.set_shader_parameter("blackout_intensity", _blackout)
	_shader_mat.set_shader_parameter("redout_intensity", _redout)
