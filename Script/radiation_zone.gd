class_name RadiationZone
extends Area3D

# ---------------------------
# Exports - Configurable in Inspector
# ---------------------------
@export var required_sunflowers: int = 3  ## Number of sunflowers needed to clear this zone
@export var zone_radius: float = 5.0  ## Radius of the zone (updates CollisionShape3D)
@export var light_color: Color = Color(0.873, 0.845, 0.136, 1.0)  ## Spooky red glow color
@export var light_energy: float = 2.0  ## Intensity of the light
@export var light_range: float = 10.0  ## How far the light reaches
@export var scan_interval: float = 0.5  ## How often to scan for sunflowers (seconds)
@export var debug_enabled: bool = true  ## Enable debug prints

# ---------------------------
# State
# ---------------------------
var current_sunflowers: int = 0
var is_cleared: bool = false
var tracked_sunflowers: Array[Node3D] = []  # Track which sunflowers are in the zone
var scan_timer: float = 0.0

# ---------------------------
# Signals
# ---------------------------
signal zone_cleared()
signal sunflower_count_changed(current: int, required: int)

# ---------------------------
# Node References
# ---------------------------
@onready var omni_light: OmniLight3D = $OmniLight3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var zone_visual: MeshInstance3D = $ZoneVisual


func _ready() -> void:
	# Add to Radiation group for GameManager compatibility
	add_to_group("Radiation")
	
	# Apply initial settings
	_update_light_settings()
	_update_collision_shape()
	
	# Emit initial count
	sunflower_count_changed.emit(current_sunflowers, required_sunflowers)
	
	_debug_print("RadiationZone initialized at %s. Required sunflowers: %d, Zone radius: %.1f" % [global_position, required_sunflowers, zone_radius])


func _process(delta: float) -> void:
	if is_cleared:
		return
	
	# Periodically scan for sunflowers
	scan_timer += delta
	if scan_timer >= scan_interval:
		scan_timer = 0.0
		_scan_for_sunflowers()


func _debug_print(message: String) -> void:
	if debug_enabled:
		print("[RadiationZone] ", message)


func _update_light_settings() -> void:
	if omni_light:
		omni_light.light_color = light_color
		omni_light.light_energy = light_energy
		omni_light.omni_range = light_range


func _scan_for_sunflowers() -> void:
	# Get all nodes in the scene
	var scene_root = get_tree().current_scene
	if not scene_root:
		_debug_print("WARNING: No scene root found!")
		return
	
	# Find all sunflower nodes in the scene
	var found_sunflowers: Array[Node3D] = []
	_find_sunflowers_recursive(scene_root, found_sunflowers)
	
	# Check which sunflowers are within the zone radius
	var sunflowers_in_zone: Array[Node3D] = []
	var zone_pos = global_position
	
	for sunflower in found_sunflowers:
		var distance = sunflower.global_position.distance_to(zone_pos)
		var is_inside = distance <= zone_radius
		
		if is_inside:
			sunflowers_in_zone.append(sunflower)
			if sunflower not in tracked_sunflowers:
				_debug_print("NEW Sunflower ENTERED zone! '%s' at %s (distance: %.2f)" % [sunflower.name, sunflower.global_position, distance])
	
	# Check for sunflowers that left the zone
	for tracked in tracked_sunflowers:
		if tracked not in sunflowers_in_zone:
			if is_instance_valid(tracked):
				_debug_print("Sunflower LEFT zone: '%s'" % tracked.name)
			else:
				_debug_print("Sunflower was deleted")
	
	# Update tracking
	var old_count = current_sunflowers
	tracked_sunflowers = sunflowers_in_zone
	current_sunflowers = tracked_sunflowers.size()
	
	# Debug: Always print current state
	if debug_enabled and (current_sunflowers != old_count or scan_timer == 0.0):
		_debug_print("=== SCAN RESULT === Sunflowers in zone: %d/%d" % [current_sunflowers, required_sunflowers])
		for i in range(tracked_sunflowers.size()):
			var sf = tracked_sunflowers[i]
			_debug_print("  [%d] %s at %s" % [i + 1, sf.name, sf.global_position])
	
	# Emit signal if count changed
	if current_sunflowers != old_count:
		sunflower_count_changed.emit(current_sunflowers, required_sunflowers)
		_check_clear_condition()


func _find_sunflowers_recursive(node: Node, result: Array[Node3D]) -> void:
	# Check if this node is a sunflower
	if node is Node3D and _is_sunflower(node as Node3D):
		result.append(node as Node3D)
		return  # Don't check children of a sunflower
	
	# Recursively check children
	for child in node.get_children():
		_find_sunflowers_recursive(child, result)


func _update_collision_shape() -> void:
	if collision_shape and collision_shape.shape:
		if collision_shape.shape is SphereShape3D:
			(collision_shape.shape as SphereShape3D).radius = zone_radius
		elif collision_shape.shape is BoxShape3D:
			# For box shape, use zone_radius as half-extents
			(collision_shape.shape as BoxShape3D).size = Vector3(zone_radius * 2, zone_radius, zone_radius * 2)
	
	# Update visual mesh to match collision shape
	if zone_visual and zone_visual.mesh:
		if zone_visual.mesh is SphereMesh:
			(zone_visual.mesh as SphereMesh).radius = zone_radius
			(zone_visual.mesh as SphereMesh).height = zone_radius * 2


func _is_sunflower(node: Node3D) -> bool:
	# Check by scene filename (most reliable)
	if node.scene_file_path.ends_with("Sunflower1.tscn"):
		_debug_print("  Found sunflower by scene path: %s" % node.name)
		return true
	
	# Check by node name containing "Sunflower"
	if "Sunflower" in node.name or "sunflower" in node.name.to_lower():
		_debug_print("  Found sunflower by name: %s" % node.name)
		return true
	
	return false


func _check_clear_condition() -> void:
	if current_sunflowers >= required_sunflowers and not is_cleared:
		clear_zone()


func clear_zone() -> void:
	is_cleared = true
	
	# Turn off the light with fade effect
	if omni_light:
		var light_tween = create_tween()
		light_tween.tween_property(omni_light, "light_energy", 0.0, 0.5)
		light_tween.tween_callback(func(): omni_light.visible = false)
	
	# Fade out the visual mesh
	if zone_visual and zone_visual.mesh:
		var mesh_material = zone_visual.mesh.surface_get_material(0)
		if mesh_material and mesh_material is StandardMaterial3D:
			var visual_tween = create_tween()
			visual_tween.tween_property(mesh_material, "albedo_color:a", 0.0, 0.5)
			visual_tween.tween_callback(func(): zone_visual.visible = false)
	
	# Remove from Radiation group
	remove_from_group("Radiation")
	
	# Emit zone cleared signal
	zone_cleared.emit()
	
	# Notify GameManager
	if GameManager.instance:
		GameManager.instance.on_radiation_cleared()
	
	_debug_print("=== ZONE CLEARED! === All %d sunflowers planted!" % required_sunflowers)


# ---------------------------
# Public API
# ---------------------------

## Get current progress as a string (e.g., "2/5")
func get_progress_text() -> String:
	return "%d/%d" % [current_sunflowers, required_sunflowers]


## Get current progress as a percentage (0.0 to 1.0)
func get_progress_percent() -> float:
	if required_sunflowers <= 0:
		return 1.0
	return float(current_sunflowers) / float(required_sunflowers)


## Check if zone is cleared
func is_zone_cleared() -> bool:
	return is_cleared


## Manually set the required sunflower count (useful for dynamic difficulty)
func set_required_sunflowers(count: int) -> void:
	required_sunflowers = max(1, count)
	sunflower_count_changed.emit(current_sunflowers, required_sunflowers)
	
	# Re-check clear condition in case we lowered the requirement
	if not is_cleared:
		_check_clear_condition()
