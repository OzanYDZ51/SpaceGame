class_name VegetationMeshLib
extends RefCounted

# =============================================================================
# Vegetation Mesh Library — Procedural ArrayMesh generation via SurfaceTool.
# Two LOD levels: HIGH (detailed, close range) and LOW (simplified, mid range).
# All meshes use vertex colors for natural look, no textures.
# Meshes are cached statically — generated once, shared by all MultiMesh users.
# =============================================================================

enum VegType { CONIFER, BROADLEAF, PALM, BUSH, ROCK, GRASS }
enum LOD { HIGH, LOW }

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


static func get_mesh(vtype: int, lod: int) -> ArrayMesh:
	var key: int = vtype * 2 + lod
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := _build(vtype, lod)
	_mesh_cache[key] = m
	return m


static func get_material(vtype: int) -> StandardMaterial3D:
	if _mat_cache.has(vtype):
		return _mat_cache[vtype]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92 if vtype == VegType.ROCK else 0.82
	if vtype == VegType.GRASS:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[vtype] = mat
	return mat


static func _build(vtype: int, lod: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + vtype * 1013 + lod * 97
	match vtype:
		VegType.CONIFER: _mk_conifer(st, rng, lod)
		VegType.BROADLEAF: _mk_broadleaf(st, rng, lod)
		VegType.PALM: _mk_palm(st, rng, lod)
		VegType.BUSH: _mk_bush(st, rng, lod)
		VegType.ROCK: _mk_rock(st, rng, lod)
		VegType.GRASS: _mk_grass(st, rng, lod)
	st.generate_normals()
	return st.commit()


# =========================================================================
# Primitives
# =========================================================================

## Tapered cylinder between two points with vertex noise.
static func _cylinder(st: SurfaceTool, base: Vector3, top: Vector3, rb: float, rt: float,
		segs: int, cb: Color, ct: Color, rng: RandomNumberGenerator, noise: float) -> void:
	var axis := top - base
	var up := axis.normalized()
	var perp := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := up.cross(perp).normalized()
	var fwd := right.cross(up)
	for i in segs:
		var a0 := TAU * i / float(segs)
		var a1 := TAU * (i + 1) / float(segs)
		var d0 := right * cos(a0) + fwd * sin(a0)
		var d1 := right * cos(a1) + fwd * sin(a1)
		var b0 := base + d0 * (rb + rng.randf_range(-noise, noise))
		var b1 := base + d1 * (rb + rng.randf_range(-noise, noise))
		var t0 := top + d0 * (rt + rng.randf_range(-noise, noise))
		var t1 := top + d1 * (rt + rng.randf_range(-noise, noise))
		_tri(st, b0, b1, t1, cb, cb, ct)
		_tri(st, b0, t1, t0, cb, ct, ct)


## Cone from ring base to single apex — foliage layers, tree tops.
static func _cone(st: SurfaceTool, base: Vector3, apex: Vector3, radius: float,
		segs: int, cb: Color, ca: Color, rng: RandomNumberGenerator, noise: float) -> void:
	var axis := apex - base
	var up := axis.normalized()
	var perp := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := up.cross(perp).normalized()
	var fwd := right.cross(up)
	for i in segs:
		var a0 := TAU * i / float(segs)
		var a1 := TAU * (i + 1) / float(segs)
		var d0 := right * cos(a0) + fwd * sin(a0)
		var d1 := right * cos(a1) + fwd * sin(a1)
		var r0 := radius + rng.randf_range(-noise, noise)
		var r1 := radius + rng.randf_range(-noise, noise)
		var droop := -up * rng.randf_range(0.0, noise * 0.5)
		_tri(st, base + d0 * r0 + droop, base + d1 * r1 + droop, apex,
			_vary(cb, rng, 0.03), _vary(cb, rng, 0.03), ca)


## Deformed sphere blob — canopy, bushes, rocks.
static func _sphere(st: SurfaceTool, center: Vector3, radius: float, rings: int,
		segs: int, col: Color, rng: RandomNumberGenerator, noise: float, squash_y: float = 1.0) -> void:
	for r in rings:
		var lat0 := PI * r / float(rings) - PI * 0.5
		var lat1 := PI * (r + 1) / float(rings) - PI * 0.5
		for s in segs:
			var lon0 := TAU * s / float(segs)
			var lon1 := TAU * (s + 1) / float(segs)
			var p00 := _sph(center, radius, lat0, lon0, squash_y, rng, noise)
			var p10 := _sph(center, radius, lat1, lon0, squash_y, rng, noise)
			var p01 := _sph(center, radius, lat0, lon1, squash_y, rng, noise)
			var p11 := _sph(center, radius, lat1, lon1, squash_y, rng, noise)
			var c := _vary(col, rng, 0.04)
			_tri(st, p00, p10, p11, c, c, c)
			_tri(st, p00, p11, p01, c, c, c)


static func _sph(ctr: Vector3, r: float, lat: float, lon: float, sq: float,
		rng: RandomNumberGenerator, n: float) -> Vector3:
	var rd := r + rng.randf_range(-n, n)
	return ctr + Vector3(cos(lat) * cos(lon) * rd, sin(lat) * rd * sq, cos(lat) * sin(lon) * rd)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cb); st.add_vertex(b)
	st.set_color(cc); st.add_vertex(c)


static func _vary(col: Color, rng: RandomNumberGenerator, amt: float) -> Color:
	return Color(
		clampf(col.r + rng.randf_range(-amt, amt), 0.0, 1.0),
		clampf(col.g + rng.randf_range(-amt, amt), 0.0, 1.0),
		clampf(col.b + rng.randf_range(-amt, amt), 0.0, 1.0))


# =========================================================================
# Mesh Builders
# =========================================================================

static func _mk_conifer(st: SurfaceTool, rng: RandomNumberGenerator, lod: int) -> void:
	var segs := 14 if lod == LOD.HIGH else 6
	var fsegs := 18 if lod == LOD.HIGH else 8
	var bark := Color(0.32, 0.20, 0.09)
	var bark_t := Color(0.38, 0.24, 0.11)
	# Trunk — 12m, tapers 0.35 → 0.08
	_cylinder(st, Vector3.ZERO, Vector3(0, 12, 0), 0.35, 0.08, segs, bark, bark_t, rng, 0.025)
	# 5 foliage cone layers, drooping at outer edge, noisy silhouette
	var layers := 5 if lod == LOD.HIGH else 3
	for i in layers:
		var y := 2.5 + float(i) * 1.9
		var r := 3.8 - float(i) * 0.7
		var n := 0.45 if lod == LOD.HIGH else 0.15
		var g := Color(0.06 + float(i) * 0.012, 0.28 + float(i) * 0.035, 0.04)
		var gt := Color(0.10 + float(i) * 0.015, 0.38 + float(i) * 0.025, 0.06)
		_cone(st, Vector3(0, y - 0.6, 0), Vector3(0, y + 2.0, 0), r, fsegs, g, gt, rng, n)
	# Pointed leader at top
	var tg := Color(0.10, 0.36, 0.06)
	_cone(st, Vector3(0, 11, 0), Vector3(0, 14, 0), 0.9, fsegs, tg, Color(0.14, 0.42, 0.08), rng, 0.2)


static func _mk_broadleaf(st: SurfaceTool, rng: RandomNumberGenerator, lod: int) -> void:
	var segs := 12 if lod == LOD.HIGH else 6
	var bark := Color(0.28, 0.17, 0.07)
	# Trunk — 6m, tapers 0.5 → 0.25
	_cylinder(st, Vector3.ZERO, Vector3(0, 6, 0), 0.5, 0.25, segs, bark, bark, rng, 0.03)
	# Branch forks (HIGH only)
	if lod == LOD.HIGH:
		_cylinder(st, Vector3(0, 4.5, 0), Vector3(2.0, 7.5, 0.5), 0.2, 0.08, 8, bark, bark, rng, 0.02)
		_cylinder(st, Vector3(0, 5, 0), Vector3(-1.2, 8, 1.2), 0.18, 0.07, 8, bark, bark, rng, 0.02)
		_cylinder(st, Vector3(0, 5.5, 0), Vector3(0.5, 8.5, -1.5), 0.15, 0.06, 8, bark, bark, rng, 0.02)
	# Canopy — overlapping deformed spheres
	var sr := 9 if lod == LOD.HIGH else 5
	var ss := 14 if lod == LOD.HIGH else 7
	var n := 0.6 if lod == LOD.HIGH else 0.2
	var g := Color(0.07, 0.30, 0.05)
	_sphere(st, Vector3(0, 8, 0), 3.8, sr, ss, g, rng, n, 0.6)
	if lod == LOD.HIGH:
		_sphere(st, Vector3(2.0, 7.5, 0.5), 2.8, 7, 10, Color(0.05, 0.26, 0.04), rng, n, 0.55)
		_sphere(st, Vector3(-1.2, 8.5, 1.2), 2.5, 7, 10, Color(0.09, 0.34, 0.06), rng, n, 0.55)
		_sphere(st, Vector3(0.5, 9, -1.5), 2.2, 6, 9, Color(0.11, 0.36, 0.07), rng, n * 0.8, 0.5)


static func _mk_palm(st: SurfaceTool, rng: RandomNumberGenerator, lod: int) -> void:
	var segs := 10 if lod == LOD.HIGH else 6
	var bark := Color(0.52, 0.38, 0.22)
	# Curved trunk — segments along a quadratic curve
	var trunk_segs := 7 if lod == LOD.HIGH else 3
	for i in trunk_segs:
		var t0 := float(i) / trunk_segs
		var t1 := float(i + 1) / trunk_segs
		var lean := 1.8
		var b := Vector3(lean * t0 * t0, 10.0 * t0, 0)
		var t := Vector3(lean * t1 * t1, 10.0 * t1, 0)
		_cylinder(st, b, t, lerpf(0.35, 0.12, t0), lerpf(0.35, 0.12, t1), segs, bark, bark, rng, 0.02)
	# Frond leaves fanning from crown
	var crown := Vector3(1.8, 10, 0)
	var leaf_n := 8 if lod == LOD.HIGH else 4
	for i in leaf_n:
		var ang := TAU * i / float(leaf_n) + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var droop := Vector3(0, -3.0, 0)
		var mid := crown + dir * 2.0 + Vector3(0, 0.8, 0)
		var tip := crown + dir * 4.5 + droop
		var perp := dir.cross(Vector3.UP).normalized()
		var w := 0.5
		var gc := _vary(Color(0.12, 0.42, 0.06), rng, 0.04)
		_tri(st, crown - perp * 0.2, crown + perp * 0.2, mid + perp * w, gc, gc, gc)
		_tri(st, crown - perp * 0.2, mid + perp * w, mid - perp * w, gc, gc, gc)
		_tri(st, mid - perp * w, mid + perp * w, tip, gc, gc, gc)


static func _mk_bush(st: SurfaceTool, rng: RandomNumberGenerator, lod: int) -> void:
	var sr := 8 if lod == LOD.HIGH else 4
	var ss := 12 if lod == LOD.HIGH else 6
	var n := 0.3 if lod == LOD.HIGH else 0.12
	var g := Color(0.10, 0.32, 0.06)
	_sphere(st, Vector3(0, 1.2, 0), 1.5, sr, ss, g, rng, n, 0.7)
	if lod == LOD.HIGH:
		_sphere(st, Vector3(0.6, 0.9, 0.4), 1.1, 6, 8, Color(0.08, 0.28, 0.05), rng, n, 0.65)
		_sphere(st, Vector3(-0.5, 1.3, -0.3), 1.0, 6, 8, Color(0.13, 0.36, 0.07), rng, n, 0.6)


static func _mk_rock(st: SurfaceTool, rng: RandomNumberGenerator, lod: int) -> void:
	var sr := 9 if lod == LOD.HIGH else 5
	var ss := 14 if lod == LOD.HIGH else 7
	var n := 0.5 if lod == LOD.HIGH else 0.25
	_sphere(st, Vector3(0, 0.8, 0), 1.5, sr, ss, Color(0.36, 0.34, 0.30), rng, n, 0.7)


static func _mk_grass(st: SurfaceTool, rng: RandomNumberGenerator, _lod: int) -> void:
	var blade_count := 5
	for i in blade_count:
		var ang := TAU * i / float(blade_count) + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(0.05, 0.15)
		var base_pos := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var h := rng.randf_range(0.35, 0.75)
		var w := rng.randf_range(0.04, 0.09)
		var lean_dir := Vector3(cos(ang), 0, sin(ang))
		var lean := lean_dir * rng.randf_range(0.0, 0.12)
		var perp := lean_dir.cross(Vector3.UP).normalized()
		var tip := base_pos + Vector3(0, h, 0) + lean
		var bl := base_pos - perp * w
		var br := base_pos + perp * w
		var gc := _vary(Color(0.15, 0.40, 0.08), rng, 0.04)
		var gt := _vary(Color(0.30, 0.50, 0.12), rng, 0.04)
		_tri(st, bl, br, tip, gc, gc, gt)
		_tri(st, br, bl, tip, gc, gc, gt)  # Back face
