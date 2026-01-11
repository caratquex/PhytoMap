extends Node

# ---------------------------
# Singleton Pattern (accessed via autoload as GameManager.instance)
# ---------------------------
static var instance: Node

# ---------------------------
# Exports
# ---------------------------
@export var time_limit: float = 120.0
@export var gridmap: GridMap
@export var radiation_tile_ids: Array[int] = []  # IDs for GrassRadiant2 and GrassRadiant3

# ---------------------------
# Portal / Level Progression
# ---------------------------
@export_group("Level Progression")
@export var portal_scene: PackedScene = preload("res://Scene/NavigationPortal.tscn")
@export var portal_spawn_position: Vector3 = Vector3.ZERO  ## Where the portal appears when level is cleared
@export var next_level_path: String = ""  ## Path to next level (e.g., "res://Map/Level 2.tscn")

# ---------------------------
# Level Configuration (auto-detected based on current scene)
# ---------------------------
const LEVEL_CONFIG: Dictionary = {
	"res://Map/Level 1.tscn": {
		"next_level": "res://Map/Level 2.tscn"
	},
	"res://Map/Level 2.tscn": {
		"next_level": "res://Map/Level 3.tscn"
	},
	"res://Map/Level 3.tscn": {
		"next_level": ""  # Final level - no next level
	}
}

# ---------------------------
# State
# ---------------------------
var total_radiation_count: int = 0
var time_remaining: float = 0.0
var game_active: bool = false
var portal_spawned: bool = false

# ---------------------------
# Signals for UI binding
# ---------------------------
signal radiation_count_changed(new_count: int)
signal time_changed(time_remaining: float)
signal game_won()
signal game_lost()
signal portal_appeared()
signal all_levels_complete()

# ---------------------------
# Node References
# ---------------------------
@onready var timer: Timer = $Timer

# Debug UI References
@onready var time_label: Label = $DebugUI/Panel/VBox/TimeLabel
@onready var radiation_label: Label = $DebugUI/Panel/VBox/RadiationLabel
@onready var status_label: Label = $DebugUI/Panel/VBox/StatusLabel


func _ready() -> void:
	# Set up singleton
	instance = self
	
	# Connect to scene tree changes to reinitialize when scene changes
	get_tree().tree_changed.connect(_on_tree_changed)
	
	# Wait a frame for the scene to be fully loaded, then initialize
	call_deferred("_initialize_for_current_level")


func _initialize_for_current_level() -> void:
	# Reset state for new level
	portal_spawned = false
	game_active = false
	total_radiation_count = 0
	
	# Auto-detect level configuration
	_apply_level_config()
	
	# Count radiation targets
	_count_radiation_targets()
	
	# Initialize timer
	time_remaining = time_limit
	
	# Configure the Timer node
	if timer:
		if timer.timeout.is_connected(_on_timer_timeout):
			timer.timeout.disconnect(_on_timer_timeout)
		timer.wait_time = 1.0
		timer.timeout.connect(_on_timer_timeout)
		timer.start()
	
	game_active = true
	
	# Update debug UI
	_update_debug_ui()
	
	var scene_path = ""
	if get_tree().current_scene:
		scene_path = get_tree().current_scene.scene_file_path
	print("[GameManager] Initialized for level: %s. Radiation count: %d, Next level: %s" % [scene_path, total_radiation_count, next_level_path])


var _last_scene_path: String = ""

func _on_tree_changed() -> void:
	# Check if we've changed to a new scene
	if not get_tree() or not get_tree().current_scene:
		return
	
	var current_path = get_tree().current_scene.scene_file_path
	if current_path != _last_scene_path and current_path != "":
		_last_scene_path = current_path
		# Reinitialize for the new level
		call_deferred("_initialize_for_current_level")


func _apply_level_config() -> void:
	# Get current scene path
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	var scene_path = scene_root.scene_file_path
	print("[GameManager] Applying config for scene: %s" % scene_path)
	
	# Look up configuration for this level
	if scene_path in LEVEL_CONFIG:
		var config = LEVEL_CONFIG[scene_path]
		next_level_path = config.get("next_level", "")
		print("[GameManager] Level config applied - Next: %s" % [next_level_path])
	else:
		print("[GameManager] No config found for scene: %s (using defaults)" % scene_path)


func _count_radiation_targets() -> void:
	total_radiation_count = 0
	
	# Step A: Count all nodes in the "Radiation" group
	var radiation_nodes = get_tree().get_nodes_in_group("Radiation")
	var group_count = radiation_nodes.size()
	total_radiation_count += group_count
	print("  - Radiation group nodes: ", group_count)
	
	# Step B: Count GridMap cells matching radiation_tile_ids
	if gridmap and radiation_tile_ids.size() > 0:
		var gridmap_count = 0
		var used_cells = gridmap.get_used_cells()
		for cell in used_cells:
			var cell_item = gridmap.get_cell_item(cell)
			if cell_item in radiation_tile_ids:
				gridmap_count += 1
		total_radiation_count += gridmap_count
		print("  - GridMap radiation tiles: ", gridmap_count)
	
	# Emit initial count
	radiation_count_changed.emit(total_radiation_count)


func _on_timer_timeout() -> void:
	if not game_active:
		return
	
	time_remaining -= 1.0
	time_changed.emit(time_remaining)
	_update_debug_ui()
	
	# Check lose condition
	if time_remaining <= 0:
		_trigger_game_lost()


func _trigger_game_lost() -> void:
	if not game_active:
		return
	
	game_active = false
	if timer:
		timer.stop()
	print("GAME LOST - Time ran out!")
	game_lost.emit()
	_update_debug_ui()


func _trigger_game_won() -> void:
	if not game_active:
		return
	
	game_active = false
	if timer:
		timer.stop()
	print("GAME WON - All radiation cleared!")
	game_won.emit()
	_update_debug_ui()
	
	# Spawn the navigation portal
	_spawn_navigation_portal()


# ---------------------------
# Public Functions
# ---------------------------

## Call this when a radiation target is cleared (sunflower planted on it)
func on_radiation_cleared() -> void:
	if total_radiation_count <= 0:
		return
	
	total_radiation_count -= 1
	print("Radiation cleared! Remaining: ", total_radiation_count)
	radiation_count_changed.emit(total_radiation_count)
	_update_debug_ui()
	
	# Check win condition
	if total_radiation_count <= 0:
		_trigger_game_won()


## Check if a position is on a radiation location
## Returns true if the position overlaps with a Radiation group node or a radiation GridMap tile
func is_radiation_location(position: Vector3, collider: Node = null) -> bool:
	# Check if collider is in the Radiation group
	if collider and collider.is_in_group("Radiation"):
		return true
	
	# Check if position is on a radiation GridMap tile
	if gridmap and radiation_tile_ids.size() > 0:
		# Convert world position to GridMap local space
		var local_pos = gridmap.to_local(position)
		# Get the cell coordinates
		var cell_coords = gridmap.local_to_map(local_pos)
		# Get the item at this cell
		var cell_item = gridmap.get_cell_item(cell_coords)
		
		if cell_item in radiation_tile_ids:
			return true
	
	# Check proximity to Radiation group nodes
	var radiation_nodes = get_tree().get_nodes_in_group("Radiation")
	for node in radiation_nodes:
		if node is Node3D:
			var node_pos = (node as Node3D).global_position
			# Check if position is close to the radiation node (within 1 unit)
			if position.distance_to(node_pos) < 1.5:
				return true
	
	return false


## Get the current radiation count
func get_radiation_count() -> int:
	return total_radiation_count


## Get the remaining time
func get_time_remaining() -> float:
	return time_remaining


# ---------------------------
# Portal / Level Progression
# ---------------------------

func _spawn_navigation_portal() -> void:
	if portal_spawned:
		print("[GameManager] Portal already spawned")
		return
	
	if not portal_scene:
		print("[GameManager] ERROR: No portal scene assigned!")
		return
	
	portal_spawned = true
	
	# Instantiate the portal
	var portal_instance = portal_scene.instantiate()
	
	# Set the next level path
	if portal_instance.has_method("set") or "next_level_path" in portal_instance:
		portal_instance.next_level_path = next_level_path
	
	# Add to scene tree
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(portal_instance)
		portal_instance.global_position = portal_spawn_position
		print("[GameManager] Portal spawned at %s, next level: %s" % [portal_spawn_position, next_level_path])
		portal_appeared.emit()
	else:
		print("[GameManager] ERROR: No scene root found!")
		portal_instance.queue_free()


## Load the next level scene
func load_next_level(level_path: String) -> void:
	if level_path.is_empty():
		print("[GameManager] ERROR: No level path provided!")
		return
	
	print("[GameManager] Loading level: %s" % level_path)
	
	# Change to the next level
	# The _on_tree_changed callback will reinitialize for the new level
	get_tree().change_scene_to_file(level_path)


## Called when player completes the final level (no more levels to go)
func on_final_level_complete() -> void:
	print("[GameManager] ALL LEVELS COMPLETE! Victory!")
	all_levels_complete.emit()
	
	# Update status to show victory
	if status_label:
		status_label.text = "Status: VICTORY!"
		status_label.modulate = Color.GOLD


# ---------------------------
# Debug UI
# ---------------------------

func _update_debug_ui() -> void:
	# Update time label
	if time_label:
		var minutes = int(time_remaining) / 60
		var seconds = int(time_remaining) % 60
		time_label.text = "Time: %02d:%02d" % [minutes, seconds]
	
	# Update radiation label
	if radiation_label:
		radiation_label.text = "Radiation: %d" % total_radiation_count
	
	# Update status label
	if status_label:
		if not game_active:
			if total_radiation_count <= 0:
				status_label.text = "Status: WON!"
				status_label.modulate = Color.GREEN
			else:
				status_label.text = "Status: LOST!"
				status_label.modulate = Color.RED
		else:
			status_label.text = "Status: Playing"
			status_label.modulate = Color.WHITE
