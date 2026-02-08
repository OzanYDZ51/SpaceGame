class_name ProjectileDissipateEffect
extends MeshInstance3D

# Ultra-light fizzle when a projectile expires (timeout).
# No light, no particles — just a quick emissive billboard flash that fades.
# Designed to handle 60+ simultaneous instances without GPU impact.

const DURATION: float = 0.25

var _age: float = 0.0
var _mat: StandardMaterial3D = null

static var _shared_mesh: QuadMesh = null


func setup(_direction: Vector3, color: Color = Color(0.5, 0.7, 1.0)) -> void:
	if _shared_mesh == null:
		_shared_mesh = QuadMesh.new()
		_shared_mesh.size = Vector2(1.5, 1.5)

	mesh = _shared_mesh

	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.no_depth_test = true
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	material_override = _mat


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	var t := _age / DURATION
	# Quick scale-up then fade-out
	var s := 1.0 + t * 2.0
	scale = Vector3(s, s, s)
	if _mat:
		_mat.albedo_color.a = 0.8 * maxf(0.0, 1.0 - t * t)
