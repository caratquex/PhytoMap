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
@export_group("Reversed Mechanics")
@export var force_reversed_mechanics: bool = false  ## Override to force reversed HP mechanics for this level

# ---------------------------
# Dialogue System
# ---------------------------
@export_group("Dialogue")
@export var intro_lines: Array[String] = []  ## Lines shown at level start
@export var outro_lines: Array[String] = []  ## Lines shown before transitioning to next level
@export var dialogue_ui: PackedScene  ## The dialogue overlay scene

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
		"next_level": "res://Map/Level 2.tscn",
		"reversed_mechanics": false,
		"time_limit": 120.0,
		"portal_spawn_position": Vector3(0.187, 0, -47),
		"gridmap_path": "",
		"intro_lines": ["They really sent me alone for this huh?", "No partner? A manual? Or even carrots?", "Great…I'm lost. Where should I head first?"],
		"outro_lines": ["…Hey. It worked. The land looks alive again.", "My face feels… warm? Probably fine.", "Alright. Next island."]
	},
	"res://Map/Level 2.tscn": {
		"next_level": "res://Map/Level 3.tscn",
		"reversed_mechanics": false,
		"time_limit": 240.0,
		"portal_spawn_position": Vector3(-33, 2.2, -87),
		"gridmap_path": "GridMap",
		"intro_lines": ["Oh hey the islands are floating. I'm definitely not scared of heights.", "The radiation feels stronger here… Like it knows I'm coming.", "Let's stay close. I don't want to fall."],
		"outro_lines": ["That's another one cleaned. Good job…", "The radiation here really got into my skin.Why does my face suddenly feel so itchy?", "Anyway, let's move before this place starts moving too."]
	},
	"res://Map/Level 3.tscn": {
		"next_level": "",  # Final level - no next level
		"reversed_mechanics": true,
		"time_limit": 360.0,
		"portal_spawn_position": Vector3(-6, 90, 97),
		"gridmap_path": "GridMap",
		"intro_lines": ["These islands get weirder the higher I go. Feels like I'm climbing into someone's nightmare.", "My chest is heavy… and something's shifting under my skin.", "I can't see the radiation now... Why?", "Whatever happens next… let's finish it."],
		"outro_lines": ["…It's done. But… Why do I feel less like myself?", "Every time I plant a seed, my body feels weaker (?) That can't be normal...", ""]
	}
}

# ---------------------------
# State
# ---------------------------
var total_radiation_count: int = 0
var time_remaining: float = 0.0
var game_active: bool = false
var portal_spawned: bool = false
var dialogue_ui_instance: Node = null  ## Active dialogue UI instance
var reversed_mechanics: bool = false  ## Whether current level uses reversed HP rules

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
@onready var debug_ui: CanvasLayer = $DebugUI

# Debug UI References
@onready var time_label: Label = $DebugUI/Panel/VBox/TimeLabel
@onready var radiation_label: Label = $DebugUI/Panel/VBox/RadiationLabel
@onready var hp_label: Label = $DebugUI/Panel/VBox/HPLabel
@onready var status_label: Label = $DebugUI/Panel/VBox/StatusLabel


func _ready() -> void:
	# Check if this is a scene instance (not the autoload)
	# Scene instances have a parent that is the scene root, autoload's parent is root
	if instance != null and instance != self:
		# This is a scene instance - copy its settings to the autoload and remove self
		_copy_settings_to_autoload()
		queue_free()
		return
	
	# Set up singleton (this is the autoload)
	instance = self
	
	# Wait a frame for the scene to be fully loaded, then initialize
	call_deferred("_initialize_for_current_level")


func _copy_settings_to_autoload() -> void:
	# Copy exported settings from this scene instance to the autoload
	if instance == null:
		return
	
	# Copy level-specific settings
	instance.time_limit = time_limit
	instance.portal_spawn_position = portal_spawn_position
	instance.force_reversed_mechanics = force_reversed_mechanics
	instance.intro_lines = intro_lines.duplicate()
	instance.outro_lines = outro_lines.duplicate()
	instance.gridmap = gridmap
	instance.dialogue_ui = dialogue_ui
	instance.radiation_tile_ids = radiation_tile_ids.duplicate()
	
	# Trigger reinitialization on the autoload for this level
	instance.call_deferred("_initialize_for_current_level")


func _initialize_for_current_level() -> void:
	# Check if tree is available
	if not is_inside_tree():
		# Tree not ready yet, try again next frame
		call_deferred("_initialize_for_current_level")
		return
	
	# Check if we're on a gameplay level
	var current_scene_path = ""
	if get_tree() and get_tree().current_scene:
		current_scene_path = get_tree().current_scene.scene_file_path
	
	# Hide debug UI if not on a gameplay level
	var is_gameplay_level = current_scene_path in LEVEL_CONFIG
	if debug_ui:
		debug_ui.visible = is_gameplay_level
	
	# Don't initialize gameplay systems if not on a gameplay level
	if not is_gameplay_level:
		return
	
	# Reset state for new level
	portal_spawned = false
	game_active = false
	total_radiation_count = 0
	reversed_mechanics = false
	
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
	
	# Update debug UI
	_update_debug_ui()
	
	var scene_path = ""
	if get_tree() and get_tree().current_scene:
		scene_path = get_tree().current_scene.scene_file_path
	print("[GameManager] Initialized for level: %s. Radiation count: %d, Next level: %s" % [scene_path, total_radiation_count, next_level_path])
	
	# Show intro dialogue if configured
	if intro_lines.size() > 0 and dialogue_ui:
		_show_intro_dialogue()
	else:
		# No intro, start game immediately
		_start_gameplay()


func _show_intro_dialogue() -> void:
	# Wait for player to land on floor first
	_wait_for_player_landing()


func _wait_for_player_landing() -> void:
	# Get player instance
	var player: CharacterBody3D = _find_player()
	
	# If player exists and is on floor, show dialogue immediately
	if player and player.is_on_floor():
		_show_intro_dialogue_now()
		return
	
	# Otherwise, poll until player lands
	var timer = Timer.new()
	timer.wait_time = 0.05  # Check every 50ms
	timer.one_shot = false
	add_child(timer)
	
	timer.timeout.connect(func():
		var p: CharacterBody3D = _find_player()
		if p and p.is_on_floor():
			timer.stop()
			timer.queue_free()
			_show_intro_dialogue_now()
	)
	timer.start()


## Find the player node in the scene
func _find_player() -> CharacterBody3D:
	# Try player group first
	var player_nodes = get_tree().get_nodes_in_group("player")
	if player_nodes.size() > 0:
		return player_nodes[0] as CharacterBody3D
	
	# Find by name (Player node is a CharacterBody3D named "Player")
	var scene_root = get_tree().current_scene
	if scene_root:
		var player = scene_root.find_child("Player", true, false)
		if player and player is CharacterBody3D:
			return player as CharacterBody3D
	
	return null


func _show_intro_dialogue_now() -> void:
	# Instantiate dialogue UI
	_ensure_dialogue_ui()
	
	# Pause the game
	get_tree().paused = true
	
	# Show intro text
	if dialogue_ui_instance and dialogue_ui_instance.has_method("show_text"):
		dialogue_ui_instance.show_text(intro_lines, _on_intro_complete)
	else:
		# Fallback if dialogue UI is missing
		_on_intro_complete()


func _on_intro_complete() -> void:
	# Unpause the game
	get_tree().paused = false
	
	# Start gameplay
	_start_gameplay()


func _start_gameplay() -> void:
	game_active = true
	
	# Start the timer
	if timer:
		timer.start()


func _apply_level_config() -> void:
	# Check if tree is available
	if not is_inside_tree() or not get_tree():
		print("[GameManager] _apply_level_config: Tree not ready")
		return
	
	# Get current scene path
	var scene_root = get_tree().current_scene
	if not scene_root:
		print("[GameManager] _apply_level_config: No scene root")
		return
	
	var scene_path = scene_root.scene_file_path
	print("[GameManager] Applying config for scene: '%s'" % scene_path)
	print("[GameManager] Available configs: %s" % str(LEVEL_CONFIG.keys()))
	
	# Look up configuration for this level
	if scene_path in LEVEL_CONFIG:
		var config = LEVEL_CONFIG[scene_path]
		next_level_path = config.get("next_level", "")
		reversed_mechanics = config.get("reversed_mechanics", false)
		time_limit = config.get("time_limit", 120.0)
		portal_spawn_position = config.get("portal_spawn_position", Vector3.ZERO)
		
		# Apply intro/outro lines
		intro_lines.clear()
		for line in config.get("intro_lines", []):
			intro_lines.append(line)
		outro_lines.clear()
		for line in config.get("outro_lines", []):
			outro_lines.append(line)
		
		# Find gridmap by path if specified
		var gridmap_path = config.get("gridmap_path", "")
		if gridmap_path != "":
			gridmap = scene_root.get_node_or_null(gridmap_path)
			if gridmap:
				print("[GameManager] Found GridMap: %s" % gridmap_path)
			else:
				print("[GameManager] WARNING: GridMap not found at path: %s" % gridmap_path)
		else:
			gridmap = null
		
		# Load dialogue UI if not already set
		if not dialogue_ui:
			dialogue_ui = load("res://Scene/dialogue.tscn")
		
		print("[GameManager] Level config applied - Next: %s, Time: %.0f" % [next_level_path, time_limit])
		print("[GameManager] Reversed mechanics from config: %s" % reversed_mechanics)
	else:
		print("[GameManager] No config found for scene: '%s' (using defaults)" % scene_path)
	
	# Check inspector override
	if force_reversed_mechanics:
		print("[GameManager] force_reversed_mechanics is ON (inspector override)")
	
	print("[GameManager] Final is_reversed_mechanics_level(): %s" % is_reversed_mechanics_level())


func _count_radiation_targets() -> void:
	total_radiation_count = 0
	
	# Check if tree is available
	if not is_inside_tree() or not get_tree():
		return
	
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


## Check if the current level has reversed HP mechanics
func is_reversed_mechanics_level() -> bool:
	# Inspector override takes priority
	if force_reversed_mechanics:
		return true
	return reversed_mechanics


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
	
	# Show outro dialogue if configured
	if outro_lines.size() > 0 and dialogue_ui:
		_show_outro_dialogue(level_path)
	else:
		# No outro, proceed directly
		_perform_level_transition(level_path)


func _show_outro_dialogue(level_path: String) -> void:
	# Ensure dialogue UI exists
	_ensure_dialogue_ui()
	
	# Pause the game
	get_tree().paused = true
	
	# Show outro text
	if dialogue_ui_instance and dialogue_ui_instance.has_method("show_text"):
		dialogue_ui_instance.show_text(outro_lines, func(): _on_outro_complete(level_path))
	else:
		# Fallback if dialogue UI is missing
		_on_outro_complete(level_path)


func _on_outro_complete(level_path: String) -> void:
	# Unpause before scene transition
	get_tree().paused = false
	
	# Proceed with level transition
	_perform_level_transition(level_path)


func _perform_level_transition(level_path: String) -> void:
	# Store tree reference before scene change
	var tree = get_tree()
	if not tree:
		print("[GameManager] ERROR: No tree available!")
		return
	
	# Clean up dialogue UI before scene change
	if dialogue_ui_instance and is_instance_valid(dialogue_ui_instance):
		dialogue_ui_instance.queue_free()
		dialogue_ui_instance = null
	
	# Change to the next level
	tree.change_scene_to_file(level_path)
	
	# Wait for scene to load using a timer, then reinitialize
	var wait_timer = Timer.new()
	wait_timer.wait_time = 0.1
	wait_timer.one_shot = true
	add_child(wait_timer)
	wait_timer.timeout.connect(func():
		wait_timer.queue_free()
		_initialize_for_current_level()
	)
	wait_timer.start()


## Ensures the dialogue UI instance exists
func _ensure_dialogue_ui() -> void:
	if dialogue_ui_instance and is_instance_valid(dialogue_ui_instance):
		return
	
	if not dialogue_ui:
		print("[GameManager] WARNING: No dialogue_ui PackedScene assigned!")
		return
	
	dialogue_ui_instance = dialogue_ui.instantiate()
	add_child(dialogue_ui_instance)


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
	
	# Update HP label
	if hp_label:
		# Access player instance via the script path
		var player_script = load("res://Script/player.gd")
		if player_script and player_script.has_method("get") and player_script.get("instance"):
			var player_instance = player_script.get("instance")
			if player_instance and is_instance_valid(player_instance) and player_instance.has_method("get_current_hp") and player_instance.has_method("get_max_hp"):
				var current_hp = player_instance.get_current_hp()
				var max_hp = player_instance.get_max_hp()
				hp_label.text = "HP: %d/%d" % [current_hp, max_hp]
				
				# Change color based on HP level
				if current_hp <= 1:
					hp_label.modulate = Color.RED
				elif current_hp <= 2:
					hp_label.modulate = Color.ORANGE
				else:
					hp_label.modulate = Color.WHITE
			else:
				hp_label.text = "HP: --"
				hp_label.modulate = Color.WHITE
		else:
			# Try direct access via scene tree
			var player_nodes = get_tree().get_nodes_in_group("player")
			if player_nodes.size() > 0:
				var player = player_nodes[0]
				if player.has_method("get_current_hp") and player.has_method("get_max_hp"):
					var current_hp = player.get_current_hp()
					var max_hp = player.get_max_hp()
					hp_label.text = "HP: %d/%d" % [current_hp, max_hp]
					
					# Change color based on HP level
					if current_hp <= 1:
						hp_label.modulate = Color.RED
					elif current_hp <= 2:
						hp_label.modulate = Color.ORANGE
					else:
						hp_label.modulate = Color.WHITE
				else:
					hp_label.text = "HP: --"
					hp_label.modulate = Color.WHITE
			else:
				hp_label.text = "HP: --"
				hp_label.modulate = Color.WHITE
	
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
