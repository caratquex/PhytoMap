class_name NavigationPortal
extends Area3D

# ---------------------------
# Exports - Configurable in Inspector
# ---------------------------
@export var next_level_path: String = ""  ## Path to the next level scene (e.g., "res://Map/Level 2.tscn")
@export var light_color: Color = Color(0.1, 0.8, 0.4, 1.0)  ## Green glow color
@export var light_energy: float = 2.0  ## Intensity of the light
@export var light_range: float = 10.0  ## How far the light reaches
@export var pulse_speed: float = 2.0  ## Speed of the pulsing effect
@export var pulse_intensity: float = 0.5  ## How much the light pulses (0-1)
@export var debug_enabled: bool = true  ## Enable debug prints

# ---------------------------
# State
# ---------------------------
var is_transitioning: bool = false
var pulse_time: float = 0.0

# ---------------------------
# Node References
# ---------------------------
@onready var omni_light: OmniLight3D = $OmniLight3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var zone_visual: MeshInstance3D = $ZoneVisual


func _ready() -> void:
	# Connect body_entered signal to detect player
	body_entered.connect(_on_body_entered)
	
	# Apply initial settings
	_update_light_settings()
	
	_debug_print("NavigationPortal initialized at %s. Next level: %s" % [global_position, next_level_path])


func _process(delta: float) -> void:
	# Pulse the light for visual effect
	pulse_time += delta * pulse_speed
	
	if omni_light:
		var pulse_value = (sin(pulse_time) + 1.0) / 2.0  # Normalize to 0-1
		var energy_variation = pulse_intensity * pulse_value
		omni_light.light_energy = light_energy + energy_variation


func _debug_print(message: String) -> void:
	if debug_enabled:
		print("[NavigationPortal] ", message)


func _update_light_settings() -> void:
	if omni_light:
		omni_light.light_color = light_color
		omni_light.light_energy = light_energy
		omni_light.omni_range = light_range


func _on_body_entered(body: Node3D) -> void:
	# Check if the body is the player
	if not _is_player(body):
		return
	
	if is_transitioning:
		return
	
	_debug_print("Player entered portal! Loading next level: %s" % next_level_path)
	
	# Trigger level transition
	_start_level_transition()


func _is_player(node: Node3D) -> bool:
	# Check by class name
	if node.get_class() == "CharacterBody3D":
		# Check by script or node name
		if "Player" in node.name or "player" in node.name.to_lower():
			return true
		# Check if it has the player script
		if node.get_script() and "player" in node.get_script().resource_path.to_lower():
			return true
	return false


func _start_level_transition() -> void:
	is_transitioning = true
	
	if next_level_path.is_empty():
		_debug_print("No next level path set - this is the final level!")
		# Notify GameManager of victory
		if GameManager.instance:
			GameManager.instance.on_final_level_complete()
		return
	
	# Visual feedback - brighten the portal
	if omni_light:
		var tween = create_tween()
		tween.tween_property(omni_light, "light_energy", light_energy * 3.0, 0.3)
		tween.tween_callback(_load_next_level)
	else:
		_load_next_level()


func _load_next_level() -> void:
	_debug_print("Loading level: %s" % next_level_path)
	
	# Use GameManager to load the next level
	if GameManager.instance:
		GameManager.instance.load_next_level(next_level_path)
	else:
		# Fallback: directly change scene
		get_tree().change_scene_to_file(next_level_path)
