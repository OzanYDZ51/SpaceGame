class_name MotionBlur
extends MeshInstance3D

# =============================================================================
# Motion Blur — Camera-velocity screen-space blur
# Child of Camera3D. Computes camera linear + angular velocity each frame
# using quaternion differentiation, passes to the spatial shader.
# Ported from Bauxitedev/godot-motion-blur (Godot 3 → 4.6).
#
# VFXManager controls `speed_multiplier` based on ship speed:
#   normal flight → 0.5 (subtle on turns)
#   boost         → 1.5 (moderate)
#   cruise        → 2.5 (strong)
#   warp          → 4.0 (maximum)
# =============================================================================

var _shader_mat: ShaderMaterial = null
var _cam_pos_prev: Vector3 = Vector3.ZERO
var _cam_rot_prev: Quaternion = Quaternion.IDENTITY
var _initialized: bool = false

## Base blur strength (shader uniform)
var base_intensity: float = 0.25
## Dynamic multiplier from VFXManager (amplifies velocity at high speed)
var speed_multiplier: float = 1.0


func _ready() -> void:
	# Fullscreen quad: size (2,2) maps VERTEX.xy to [-1,1] clip space
	var quad =QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad

	var shader =load("res://shaders/motion_blur.gdshader") as Shader
	if shader == null:
		push_warning("MotionBlur: shader not found")
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.render_priority = 100
	_shader_mat.set_shader_parameter("iteration_count", 15)
	_shader_mat.set_shader_parameter("intensity", base_intensity)
	_shader_mat.set_shader_parameter("start_radius", 0.5)
	material_override = _shader_mat

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Prevent frustum culling
	extra_cull_margin = 16384.0


func _process(_delta: float) -> void:
	if _shader_mat == null:
		return

	var cam =get_parent() as Camera3D
	if cam == null:
		return

	if not _initialized:
		_cam_pos_prev = cam.global_position
		_cam_rot_prev = Quaternion(cam.global_basis)
		_initialized = true
		return

	var cam_pos =cam.global_position
	var cam_rot =Quaternion(cam.global_basis)

	# Linear velocity (world units/frame)
	var linear_vel =cam_pos - _cam_pos_prev

	# Angular velocity via quaternion differentiation:
	#   omega ≈ 2 * (q_current - q_prev) * conjugate(q_current)
	var rot_diff =cam_rot - _cam_rot_prev

	# Quaternion double-cover fix: q and -q are the same rotation
	if cam_rot.dot(_cam_rot_prev) < 0.0:
		rot_diff = Quaternion(-rot_diff.x, -rot_diff.y, -rot_diff.z, -rot_diff.w)

	# conjugate of unit quaternion = inverse
	var cam_rot_inv =cam_rot.inverse()
	var scaled_diff =Quaternion(rot_diff.x * 2.0, rot_diff.y * 2.0, rot_diff.z * 2.0, rot_diff.w * 2.0)
	var ang_vel_q: Quaternion = scaled_diff * cam_rot_inv
	var ang_vel =Vector3(ang_vel_q.x, ang_vel_q.y, ang_vel_q.z)

	# Pass to shader, amplified by speed_multiplier
	var mult =speed_multiplier
	_shader_mat.set_shader_parameter("linear_velocity", linear_vel * mult)
	_shader_mat.set_shader_parameter("angular_velocity", ang_vel * mult)
	_shader_mat.set_shader_parameter("intensity", base_intensity * clampf(mult, 0.1, 4.0))

	_cam_pos_prev = cam_pos
	_cam_rot_prev = cam_rot
