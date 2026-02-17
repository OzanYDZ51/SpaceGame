class_name FactionManager
extends Node

# =============================================================================
# Faction Manager — Manages faction registry + player reputation.
# Added as a child of GameManager.
# =============================================================================

## Emitted when the player's reputation with a faction changes.
signal reputation_changed(faction_id: StringName, new_value: float, old_value: float)

const FACTIONS_DIR: String = "res://data/factions/"

# --- Faction registry ---
var _factions: Dictionary = {}  # faction_id -> FactionResource

# --- Player reputation ---
var _reputation: Dictionary = {}  # faction_id -> float (-100.0 to +100.0)

# --- Player faction ---
var player_faction: StringName = &""


func set_player_faction(faction_id: StringName) -> void:
	var faction: FactionResource = get_faction(faction_id)
	if faction == null or not faction.is_playable:
		push_warning("FactionManager: Invalid player faction '%s'" % faction_id)
		return
	player_faction = faction_id


func get_player_faction_resource() -> FactionResource:
	return get_faction(player_faction)


func _ready() -> void:
	_load_factions()


# =============================================================================
# FACTION REGISTRY
# =============================================================================

## Register a faction resource into the manager.
func register_faction(res: FactionResource) -> void:
	if res == null or res.faction_id == &"":
		push_warning("FactionManager: Cannot register faction with empty id")
		return
	_factions[res.faction_id] = res
	# Initialize reputation if not already set
	if not _reputation.has(res.faction_id):
		_reputation[res.faction_id] = 0.0
	print("FactionManager: Registered faction '%s' (%s)" % [res.faction_name, res.faction_id])


## Get a faction resource by id. Returns null if not found.
func get_faction(id: StringName) -> FactionResource:
	return _factions.get(id) as FactionResource


## Get all registered factions.
func get_all_factions() -> Array[FactionResource]:
	var result: Array[FactionResource] = []
	for faction in _factions.values():
		result.append(faction as FactionResource)
	return result


## Load all faction .tres files from the factions data directory.
func _load_factions() -> void:
	if not DirAccess.dir_exists_absolute(FACTIONS_DIR):
		push_warning("FactionManager: Factions directory not found: %s" % FACTIONS_DIR)
		return

	var dir: DirAccess = DirAccess.open(FACTIONS_DIR)
	if dir == null:
		push_warning("FactionManager: Cannot open factions directory: %s" % FACTIONS_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path: String = FACTIONS_DIR + file_name
			if not ResourceLoader.exists(path):
				file_name = dir.get_next()
				continue
			var res: Resource = ResourceLoader.load(path)
			if res is FactionResource:
				register_faction(res as FactionResource)
			else:
				push_warning("FactionManager: %s is not a FactionResource" % path)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("FactionManager: Loaded %d factions" % _factions.size())


# =============================================================================
# PLAYER REPUTATION
# =============================================================================

## Get the player's reputation with a faction. Returns 0.0 if unknown.
func get_reputation(faction_id: StringName) -> float:
	return _reputation.get(faction_id, 0.0) as float


## Modify the player's reputation with a faction.
## When increasing rep with one playable faction, the opposing playable faction
## loses 50% of the amount (zero-sum-ish between Nova Terra and Kharsis).
func modify_reputation(faction_id: StringName, amount: float) -> void:
	var old_value: float = get_reputation(faction_id)
	var new_value: float = clampf(old_value + amount, -100.0, 100.0)
	_reputation[faction_id] = new_value

	if old_value != new_value:
		reputation_changed.emit(faction_id, new_value, old_value)

	# Zero-sum between playable factions: increasing one decreases opposing
	if amount > 0.0:
		var faction: FactionResource = get_faction(faction_id)
		if faction != null and faction.is_playable:
			var opposing_amount: float = -amount * 0.5
			for enemy_id in faction.enemy_faction_ids:
				var enemy_faction: FactionResource = get_faction(enemy_id)
				if enemy_faction != null and enemy_faction.is_playable:
					var enemy_old: float = get_reputation(enemy_id)
					var enemy_new: float = clampf(enemy_old + opposing_amount, -100.0, 100.0)
					_reputation[enemy_id] = enemy_new
					if enemy_old != enemy_new:
						reputation_changed.emit(enemy_id, enemy_new, enemy_old)
	elif amount < 0.0:
		# Losing rep with one playable faction slightly benefits the opposing one
		var faction: FactionResource = get_faction(faction_id)
		if faction != null and faction.is_playable:
			var opposing_amount: float = -amount * 0.5
			for enemy_id in faction.enemy_faction_ids:
				var enemy_faction: FactionResource = get_faction(enemy_id)
				if enemy_faction != null and enemy_faction.is_playable:
					var enemy_old: float = get_reputation(enemy_id)
					var enemy_new: float = clampf(enemy_old + opposing_amount, -100.0, 100.0)
					_reputation[enemy_id] = enemy_new
					if enemy_old != enemy_new:
						reputation_changed.emit(enemy_id, enemy_new, enemy_old)


## Get a standing label based on reputation value.
func get_standing(faction_id: StringName) -> StringName:
	var rep: float = get_reputation(faction_id)
	if rep >= 75.0:
		return &"allied"
	elif rep >= 25.0:
		return &"friendly"
	elif rep >= -25.0:
		return &"neutral"
	elif rep >= -75.0:
		return &"hostile"
	else:
		return &"enemy"


## Check if two factions are enemies (based on FactionResource.enemy_faction_ids).
func are_enemies(faction_a: StringName, faction_b: StringName) -> bool:
	if faction_a == faction_b:
		return false
	var fa: FactionResource = get_faction(faction_a)
	if fa != null and faction_b in fa.enemy_faction_ids:
		return true
	var fb: FactionResource = get_faction(faction_b)
	if fb != null and faction_a in fb.enemy_faction_ids:
		return true
	return false


## Get a color representing the player's standing with a faction.
func get_reputation_color(faction_id: StringName) -> Color:
	var standing: StringName = get_standing(faction_id)
	match standing:
		&"allied":
			return Color(0.2, 0.9, 0.2)    # Green
		&"friendly":
			return Color(0.5, 0.9, 0.5)    # Light green
		&"neutral":
			return Color(0.6, 0.6, 0.6)    # Gray
		&"hostile":
			return Color(1.0, 0.6, 0.1)    # Orange
		&"enemy":
			return Color(0.9, 0.15, 0.15)  # Red
		_:
			return Color(0.6, 0.6, 0.6)


# =============================================================================
# SERIALIZATION (save/load)
# =============================================================================

## Serialize reputation data for saving.
func serialize() -> Dictionary:
	var data: Dictionary = {"player_faction": String(player_faction)}
	for faction_id in _reputation:
		data[String(faction_id)] = _reputation[faction_id]
	return data


## Deserialize reputation data from a save.
func deserialize(data: Dictionary) -> void:
	if data.has("player_faction"):
		player_faction = StringName(data["player_faction"])
	for key in data:
		if key == "player_faction":
			continue
		var faction_id: StringName = StringName(key)
		_reputation[faction_id] = clampf(float(data[key]), -100.0, 100.0)
