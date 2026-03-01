class_name ProjectilePool
extends Node

# =============================================================================
# Projectile Pool - Object pool for reusing projectiles instead of
# instantiate()/queue_free() to avoid GC spikes in combat.
# =============================================================================

# scene_path -> Array[BaseProjectile] (inactive pool)
var _pools: Dictionary = {}

# scene_path -> Dictionary[BaseProjectile, bool] (active set, O(1) add/remove)
var _active: Dictionary = {}

# scene_path -> Array[BaseProjectile] (ordered for FIFO steal)
var _active_order: Dictionary = {}

# scene_path -> int (next steal index, avoids pop_front O(n))
var _steal_idx: Dictionary = {}

# scene_path -> PackedScene
var _scenes: Dictionary = {}


func warm_pool(scene_path: String, count: int = 200) -> void:
	if not _pools.has(scene_path):
		_pools[scene_path] = []
		_active[scene_path] = {}
		_active_order[scene_path] = []
		_steal_idx[scene_path] = 0

	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		push_warning("ProjectilePool: Could not load '%s'" % scene_path)
		return
	_scenes[scene_path] = scene

	for i in count:
		var bolt = scene.instantiate()
		if bolt == null:
			continue
		bolt.set_meta("pool_scene_path", scene_path)
		add_child(bolt)
		_deactivate(bolt)
		_pools[scene_path].append(bolt)


func acquire(scene_path: String):
	# Ensure pool exists
	if not _pools.has(scene_path):
		_pools[scene_path] = []
		_active[scene_path] = {}
		_active_order[scene_path] = []
		_steal_idx[scene_path] = 0

	var pool: Array = _pools[scene_path]
	var bolt = null

	if not pool.is_empty():
		bolt = pool.pop_back()
	else:
		# Pool empty — steal oldest active (FIFO via index)
		var order: Array = _active_order[scene_path]
		var active_set: Dictionary = _active[scene_path]
		var idx: int = _steal_idx[scene_path]
		# Find next valid active bolt
		while idx < order.size():
			var candidate = order[idx]
			idx += 1
			if is_instance_valid(candidate) and active_set.has(candidate):
				bolt = candidate
				active_set.erase(candidate)
				_deactivate(bolt)
				break
		_steal_idx[scene_path] = idx
		# Compact if steal index gets too far
		if idx > 100 and idx * 2 > order.size():
			_compact_order(scene_path)
		# If steal failed (no valid candidates), create on the fly
		if bolt == null:
			var scene: PackedScene = _scenes.get(scene_path)
			if scene == null:
				scene = load(scene_path)
				if scene:
					_scenes[scene_path] = scene
			if scene:
				bolt = scene.instantiate()
				if bolt:
					bolt.set_meta("pool_scene_path", scene_path)
					add_child(bolt)

	if bolt == null or not is_instance_valid(bolt):
		return null

	# Activate
	_activate(bolt)
	_active[scene_path][bolt] = true
	_active_order[scene_path].append(bolt)
	return bolt


func release(bolt) -> void:
	if bolt == null or not is_instance_valid(bolt):
		return
	var scene_path: String = bolt.get_meta("pool_scene_path", "")
	if scene_path.is_empty():
		bolt.queue_free()
		return

	# Remove from active set — O(1) dictionary removal
	if _active.has(scene_path):
		_active[scene_path].erase(bolt)

	_deactivate(bolt)

	if not _pools.has(scene_path):
		_pools[scene_path] = []
	_pools[scene_path].append(bolt)


func _activate(bolt) -> void:
	bolt.visible = true
	if bolt is MissileProjectile:
		bolt.collision_layer = Constants.LAYER_MISSILES
		bolt.collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS | Constants.LAYER_TERRAIN
		bolt.set_deferred("monitorable", true)
	else:
		bolt.collision_layer = Constants.LAYER_PROJECTILES
		bolt.collision_mask = Constants.LAYER_SHIPS | Constants.LAYER_STATIONS | Constants.LAYER_ASTEROIDS | Constants.LAYER_TERRAIN | Constants.LAYER_MISSILES
	bolt.set_process(true)
	bolt.set_physics_process(true)
	bolt.set_deferred("monitoring", true)
	bolt._lifetime = 0.0


func _deactivate(bolt) -> void:
	bolt.visible = false
	bolt.set_process(false)
	bolt.set_physics_process(false)
	bolt.set_deferred("monitoring", false)
	bolt.global_position = Vector3(0, -99999, 0)


func _compact_order(scene_path: String) -> void:
	var order: Array = _active_order[scene_path]
	var active_set: Dictionary = _active[scene_path]
	var new_order: Array = []
	for b in order:
		if is_instance_valid(b) and active_set.has(b):
			new_order.append(b)
	_active_order[scene_path] = new_order
	_steal_idx[scene_path] = 0
