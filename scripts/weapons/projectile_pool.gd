class_name ProjectilePool
extends Node

# =============================================================================
# Projectile Pool - Object pool for reusing projectiles instead of
# instantiate()/queue_free() to avoid GC spikes in combat.
# =============================================================================

# scene_path -> Array[BaseProjectile] (inactive pool)
var _pools: Dictionary = {}

# scene_path -> Array[BaseProjectile] (active, for FIFO steal)
var _active: Dictionary = {}

# scene_path -> PackedScene
var _scenes: Dictionary = {}


func warm_pool(scene_path: String, count: int = 200) -> void:
	if not _pools.has(scene_path):
		_pools[scene_path] = []
		_active[scene_path] = []

	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		push_warning("ProjectilePool: Could not load '%s'" % scene_path)
		return
	_scenes[scene_path] = scene

	for i in count:
		var bolt: BaseProjectile = scene.instantiate() as BaseProjectile
		if bolt == null:
			continue
		bolt.set_meta("pool_scene_path", scene_path)
		_deactivate(bolt)
		add_child(bolt)
		_pools[scene_path].append(bolt)


func acquire(scene_path: String) -> BaseProjectile:
	# Ensure pool exists
	if not _pools.has(scene_path):
		_pools[scene_path] = []
		_active[scene_path] = []

	var pool: Array = _pools[scene_path]
	var bolt: BaseProjectile = null

	if not pool.is_empty():
		bolt = pool.pop_back() as BaseProjectile
	else:
		# Pool empty — steal oldest active (FIFO)
		var active_list: Array = _active[scene_path]
		if not active_list.is_empty():
			bolt = active_list.pop_front() as BaseProjectile
			if bolt and is_instance_valid(bolt):
				_deactivate(bolt)
		else:
			# No pooled instances at all — create on the fly
			var scene: PackedScene = _scenes.get(scene_path) as PackedScene
			if scene == null:
				scene = load(scene_path) as PackedScene
				if scene:
					_scenes[scene_path] = scene
			if scene:
				bolt = scene.instantiate() as BaseProjectile
				if bolt:
					bolt.set_meta("pool_scene_path", scene_path)
					add_child(bolt)

	if bolt == null or not is_instance_valid(bolt):
		return null

	# Activate
	_activate(bolt)
	_active[scene_path].append(bolt)
	return bolt


func release(bolt: BaseProjectile) -> void:
	if bolt == null or not is_instance_valid(bolt):
		return
	var scene_path: String = bolt.get_meta("pool_scene_path", "")
	if scene_path.is_empty():
		bolt.queue_free()
		return

	# Remove from active list
	if _active.has(scene_path):
		_active[scene_path].erase(bolt)

	_deactivate(bolt)

	if not _pools.has(scene_path):
		_pools[scene_path] = []
	_pools[scene_path].append(bolt)


func _activate(bolt: BaseProjectile) -> void:
	bolt.visible = true
	bolt.set_process(true)
	bolt.set_physics_process(true)
	bolt.monitoring = true
	bolt._lifetime = 0.0


func _deactivate(bolt: BaseProjectile) -> void:
	bolt.visible = false
	bolt.set_process(false)
	bolt.set_physics_process(false)
	bolt.monitoring = false
	bolt.global_position = Vector3(0, -99999, 0)
