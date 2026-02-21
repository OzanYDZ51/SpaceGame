class_name WeaponAudio
extends Node3D

# =============================================================================
# Weapon Audio Manager
# Handles 3D positional audio for weapon fire with pitch variation,
# attenuation, and pooling to avoid GC spikes from spawning nodes each shot.
# =============================================================================

const POOL_SIZE: int = 12  # Pre-allocated audio players (supports 6 shots/sec comfortably)

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0
var _fire_stream: AudioStream = null


func _ready() -> void:
	var path := "res://assets/sounds/laser_fire.mp3"
	if not ResourceLoader.exists(path):
		return
	_fire_stream = load(path)
	if _fire_stream == null:
		return

	# Pre-allocate audio player pool
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.stream = _fire_stream
		player.volume_db = -3.0
		player.max_db = 6.0
		player.unit_size = 500.0         # Son plein volume jusqu'à ~500m (portée de combat)
		player.max_distance = 3000.0     # Audible jusqu'à 3km
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.bus = &"SFX"
		player.autoplay = false
		player.name = "ShotAudio_%d" % i
		add_child(player)
		_pool.append(player)


## Play fire sound at a world position with slight pitch randomization
func play_fire(world_position: Vector3) -> void:
	if _fire_stream == null:
		return

	var player: AudioStreamPlayer3D = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE

	# Stop if still playing (shouldn't happen with pool size >= fire rate * sound duration)
	if player.playing:
		player.stop()

	player.global_position = world_position
	player.pitch_scale = randf_range(0.92, 1.08)
	player.play()
