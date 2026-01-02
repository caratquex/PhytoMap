class_name GameManager
extends Node

# ---------------------------
# Singleton Pattern
# ---------------------------
static var instance: GameManager

# ---------------------------
# Exports
# ---------------------------
@export var time_limit: float = 120.0
@export var gridmap: GridMap
@export var radiation_tile_ids: Array[int] = []  # IDs for GrassRadiant2 and GrassRadiant3

# ---------------------------
# State
# ---------------------------
var total_radiation_count: int = 0
var time_remaining: float = 0.0
var game_active: bool = false

# ---------------------------
# Signals for UI binding
# ---------------------------
signal radiation_count_changed(new_count: int)
signal time_changed(time_remaining: float)
signal game_won()
signal game_lost()

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
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	# Count radiation targets
	_count_radiation_targets()
	
	# Initialize timer
	time_remaining = time_limit
	
	# Configure the Timer node
	if timer:
		timer.wait_time = 1.0
		timer.timeout.connect(_on_timer_timeout)
		timer.start()
	
	game_active = true
	
	# Update debug UI
	_update_debug_ui()
	
	print("GameManager initialized. Total radiation count: ", total_radiation_count)


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

