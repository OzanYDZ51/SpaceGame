class_name HeightmapOverride
extends RefCounted

# =============================================================================
# Heightmap Override — Reads height from a Texture2D for hand-crafted planets
# The texture maps sphere UVs to height values. Blends with procedural noise.
# =============================================================================

var _image: Image = null
var _width: int = 0
var _height: int = 0
var _blend_factor: float = 0.8  # 1.0 = full override, 0.0 = full procedural


func setup(texture: Texture2D, blend: float = 0.8) -> void:
	if texture == null:
		return
	_image = texture.get_image()
	if _image == null:
		return
	_width = _image.get_width()
	_height = _image.get_height()
	_blend_factor = clampf(blend, 0.0, 1.0)


func is_valid() -> bool:
	return _image != null and _width > 0 and _height > 0


## Sample height from the heightmap at a unit sphere point.
## Returns height in [0, 1] range (red channel of the image).
func sample(sphere_point: Vector3) -> float:
	if not is_valid():
		return 0.0

	# Convert sphere point to equirectangular UV
	var u: float = (atan2(sphere_point.z, sphere_point.x) / TAU) + 0.5
	var v: float = 0.5 - (asin(clampf(sphere_point.y, -1.0, 1.0)) / PI)

	# Sample with bilinear interpolation
	var px: float = u * float(_width - 1)
	var py: float = v * float(_height - 1)
	var ix: int = int(px)
	var iy: int = int(py)
	var fx: float = px - float(ix)
	var fy: float = py - float(iy)

	ix = clampi(ix, 0, _width - 2)
	iy = clampi(iy, 0, _height - 2)

	var c00: float = _image.get_pixel(ix, iy).r
	var c10: float = _image.get_pixel(ix + 1, iy).r
	var c01: float = _image.get_pixel(ix, iy + 1).r
	var c11: float = _image.get_pixel(ix + 1, iy + 1).r

	var top: float = lerpf(c00, c10, fx)
	var bot: float = lerpf(c01, c11, fx)
	return lerpf(top, bot, fy)


## Get blend factor (how much override vs procedural).
func get_blend() -> float:
	return _blend_factor
