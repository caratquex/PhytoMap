@tool
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
# Grass Conversion Settings
# ---------------------------
@export_group("Grass Conversion")
@export var convert_grass_on_clear: bool = true  ## Convert RadiantGrass to normal Grass when cleared
@export var normal_grass_texture: Texture2D  ## The normal grass albedo texture (grass_albedo.tres)
@export var grass_conversion_duration: float = 1.0  ## Duration of the grass color transition

# ---------------------------
# Tree Conversion Settings
# ---------------------------
@export_group("Tree Conversion")
@export var convert_trees_on_clear: bool = true  ## Convert RadiantTrees to normal Trees when cleared
@export var normal_tree1_texture: Texture2D  ## Normal Tree1 trunk texture (Tree1_Trunk Base Color.png)
@export var normal_tree2_texture: Texture2D  ## Normal Tree2 trunk texture (Tree2_Trunk Base Color.png)
@export var tree_conversion_duration: float = 1.0  ## Duration of the tree texture transition

# ---------------------------
# SimpleGrassTextured Conversion Settings
# ---------------------------
@export_group("SimpleGrassTextured Conversion")
@export var convert_simple_grass_on_clear: bool = true  ## Convert SimpleGrassTextured textures when cleared
@export var normal_simple_grass_texture: Texture2D  ## Normal grass texture for SimpleGrassTextured

# ---------------------------
# GridMap Conversion Settings
# ---------------------------
@export_group("GridMap Conversion")
@export var gridmap: GridMap  ## Reference to the GridMap
@export var radiation_tile_ids: Array[int] = []  ## Tile IDs for RadiantGrass (e.g., [1, 2])
@export var normal_grass_tile_id: int = 0  ## Tile ID for normal Grass block
@export var ignore_zone_bounds: bool = false  ## If true, convert all radiation tiles regardless of zone position (for testing)

# ---------------------------
# Grass Spawning Settings
# ---------------------------
@export_group("Grass Spawning")
@export var spawn_grass_on_clear: bool = true  ## Enable/disable grass spawning when zone is cleared
@export var grass_scene: PackedScene = preload("res://Map/Grass.tscn")  ## Reference to Grass.tscn
@export var grass_spawn_count: int = 4  ## Number of grass instances to spawn (3-5 range)
@export var grass_spawn_radius: float = 0.8  ## Multiplier for spawn area (0.8 = 80% of zone radius)
@export var grass_height_offset: float = 0.5  ## Height offset above ground

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
	
	# Get and display scaled bounds for debugging
	var bounds = _get_scaled_zone_bounds()
	var node_scale = global_transform.basis.get_scale()
	
	_debug_print("RadiationZone initialized at %s" % global_position)
	_debug_print("  Node scale: %s" % node_scale)
	if bounds.is_box:
		_debug_print("  Box shape - Scaled half size: %s" % bounds.half_size)
		_debug_print("  Effective box dimensions: %s" % (bounds.half_size * 2))
	else:
		_debug_print("  Sphere shape - Scaled radius: %.2f" % bounds.radius)
	_debug_print("  Required sunflowers: %d" % required_sunflowers)


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


## Get the zone bounds accounting for node scale
## Returns a Dictionary with: is_box (bool), half_size (Vector3), radius (float)
func _get_scaled_zone_bounds() -> Dictionary:
	var result = {
		"is_box": false,
		"half_size": Vector3.ZERO,
		"radius": zone_radius
	}
	
	# Get the node's global scale
	var node_scale = global_transform.basis.get_scale()
	
	if collision_shape and collision_shape.shape:
		if collision_shape.shape is BoxShape3D:
			result.is_box = true
			var box_size = (collision_shape.shape as BoxShape3D).size
			# Apply scale to box size
			result.half_size = Vector3(
				box_size.x * 0.5 * node_scale.x,
				box_size.y * 0.5 * node_scale.y,
				box_size.z * 0.5 * node_scale.z
			)
		elif collision_shape.shape is SphereShape3D:
			var sphere_radius = (collision_shape.shape as SphereShape3D).radius
			# For sphere, use the largest scale component
			result.radius = sphere_radius * max(node_scale.x, max(node_scale.y, node_scale.z))
	else:
		# Fallback to zone_radius with scale
		result.radius = zone_radius * max(node_scale.x, max(node_scale.y, node_scale.z))
	
	return result


## Check if a world-space point is inside the zone bounds
func _is_point_inside_zone(world_pos: Vector3, bounds: Dictionary = {}) -> bool:
	if bounds.is_empty():
		bounds = _get_scaled_zone_bounds()
	
	var zone_pos = global_position
	
	if bounds.is_box:
		# Box detection: check if point is within scaled box bounds
		var diff = world_pos - zone_pos
		return (
			abs(diff.x) <= bounds.half_size.x and
			abs(diff.y) <= bounds.half_size.y and
			abs(diff.z) <= bounds.half_size.z
		)
	else:
		# Sphere detection: use distance check with scaled radius
		var distance = world_pos.distance_to(zone_pos)
		return distance <= bounds.radius


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
	
	# Get the scaled bounds for detection
	var bounds = _get_scaled_zone_bounds()
	var is_box_shape = bounds.is_box
	var box_half_size = bounds.half_size
	var effective_radius = bounds.radius
	
	# Check which sunflowers are within the zone bounds
	var sunflowers_in_zone: Array[Node3D] = []
	var zone_pos = global_position
	
	for sunflower in found_sunflowers:
		var is_inside: bool = false
		var sunflower_pos = sunflower.global_position
		
		if is_box_shape:
			# Box detection: check if point is within scaled box bounds
			# Use world-space distance comparison to account for scale
			var diff = sunflower_pos - zone_pos
			is_inside = (
				abs(diff.x) <= box_half_size.x and
				abs(diff.y) <= box_half_size.y and
				abs(diff.z) <= box_half_size.z
			)
		else:
			# Sphere detection: use distance check with scaled radius
			var distance = sunflower_pos.distance_to(zone_pos)
			is_inside = distance <= effective_radius
		
		if is_inside:
			sunflowers_in_zone.append(sunflower)
			if sunflower not in tracked_sunflowers:
				_debug_print("NEW Sunflower ENTERED zone! '%s' at %s" % [sunflower.name, sunflower_pos])
	
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
	# Only update sphere shapes from zone_radius
	# For box shapes, use the actual BoxShape3D size set in the editor
	if collision_shape and collision_shape.shape:
		if collision_shape.shape is SphereShape3D:
			(collision_shape.shape as SphereShape3D).radius = zone_radius
			# Update visual mesh to match
			if zone_visual and zone_visual.mesh is SphereMesh:
				(zone_visual.mesh as SphereMesh).radius = zone_radius
				(zone_visual.mesh as SphereMesh).height = zone_radius * 2
		elif collision_shape.shape is BoxShape3D:
			# For box: sync visual mesh to match collision shape (don't override from zone_radius)
			var box_size = (collision_shape.shape as BoxShape3D).size
			if zone_visual and zone_visual.mesh is BoxMesh:
				(zone_visual.mesh as BoxMesh).size = box_size


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
	_debug_print("=== CLEAR_ZONE CALLED ===")
	
	# Turn off the light with fade effect
	if omni_light:
		var light_tween = create_tween()
		light_tween.tween_property(omni_light, "light_energy", 0.0, 0.5)
		light_tween.tween_callback(func(): omni_light.visible = false)
	
	# Fade out the visual mesh (use unique material to avoid affecting other zones)
	if zone_visual and zone_visual.mesh:
		var mesh_material = zone_visual.get_surface_override_material(0)
		if not mesh_material:
			# No override yet - create a unique copy from the mesh's material
			var original_mat = zone_visual.mesh.surface_get_material(0)
			if original_mat and original_mat is StandardMaterial3D:
				mesh_material = original_mat.duplicate() as StandardMaterial3D
				zone_visual.set_surface_override_material(0, mesh_material)
		
		if mesh_material and mesh_material is StandardMaterial3D:
			var visual_tween = create_tween()
			visual_tween.tween_property(mesh_material, "albedo_color:a", 0.0, 0.5)
			visual_tween.tween_callback(func(): zone_visual.visible = false)
	
	# Convert RadiantGrass blocks to normal grass
	if convert_grass_on_clear:
		_convert_radiant_grass_in_zone()
	
	# Convert RadiantTrees to normal trees
	if convert_trees_on_clear:
		_convert_radiant_trees_in_zone()
	
	# Convert SimpleGrassTextured textures
	if convert_simple_grass_on_clear:
		_convert_simple_grass_textured_in_zone()
	
	# Convert GridMap tiles to normal grass
	if gridmap and radiation_tile_ids.size() > 0:
		_convert_gridmap_tiles_in_zone()
	
	# Spawn grass instances in the cleared zone
	if spawn_grass_on_clear:
		_spawn_grass_in_zone()
	
	# Remove from Radiation group
	remove_from_group("Radiation")
	
	# Emit zone cleared signal
	zone_cleared.emit()
	
	# Notify GameManager
	if GameManager.instance:
		GameManager.instance.on_radiation_cleared()
	
	_debug_print("=== ZONE CLEARED! === All %d sunflowers planted!" % required_sunflowers)


# ---------------------------
# RadiantGrass Conversion
# ---------------------------

func _convert_radiant_grass_in_zone() -> void:
	# Load normal grass texture if not set
	var grass_texture = normal_grass_texture
	if not grass_texture:
		grass_texture = load("res://Map Asset/grass_albedo.tres")
		if not grass_texture:
			_debug_print("WARNING: Could not load normal grass texture!")
			return
	
	# Find all RadiantGrass blocks in the scene
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	var radiant_grass_blocks: Array[Node3D] = []
	_find_radiant_grass_recursive(scene_root, radiant_grass_blocks)
	
	_debug_print("Found %d RadiantGrass blocks in scene" % radiant_grass_blocks.size())
	
	# Get scaled bounds for detection
	var bounds = _get_scaled_zone_bounds()
	var zone_pos = global_position
	var converted_count = 0
	
	for grass_block in radiant_grass_blocks:
		var grass_pos = grass_block.global_position
		var is_inside = _is_point_inside_zone(grass_pos, bounds)
		
		if is_inside:
			_convert_single_grass_block(grass_block, grass_texture)
			converted_count += 1
			_debug_print("Converted RadiantGrass '%s' at %s" % [grass_block.name, grass_pos])
	
	_debug_print("Converted %d RadiantGrass blocks to normal grass" % converted_count)


func _find_radiant_grass_recursive(node: Node, result: Array[Node3D]) -> void:
	# Check if this node is a RadiantGrass block
	if node is Node3D and _is_radiant_grass(node as Node3D):
		result.append(node as Node3D)
		return  # Don't check children
	
	# Recursively check children
	for child in node.get_children():
		_find_radiant_grass_recursive(child, result)


func _is_radiant_grass(node: Node3D) -> bool:
	# Check by scene filename
	var scene_path = node.scene_file_path.to_lower()
	if "radiantgrass" in scene_path or "grassradiant" in scene_path:
		return true
	
	# Check by node name
	var node_name = node.name.to_lower()
	if "radiantgrass" in node_name or "grassradiant" in node_name:
		return true
	
	return false


func _convert_single_grass_block(grass_block: Node3D, new_texture: Texture2D) -> void:
	# Find all MeshInstance3D children with ShaderMaterial
	var mesh_instances: Array[MeshInstance3D] = []
	_find_mesh_instances_recursive(grass_block, mesh_instances)
	
	for mesh_instance in mesh_instances:
		_convert_mesh_material(mesh_instance, new_texture)
	
	# Find and disable GPUParticles3D
	var particles: Array[GPUParticles3D] = []
	_find_particles_recursive(grass_block, particles)
	
	for particle in particles:
		# Fade out particles then disable
		var tween = create_tween()
		tween.tween_property(particle, "amount_ratio", 0.0, grass_conversion_duration * 0.5)
		tween.tween_callback(func(): particle.emitting = false)
		_debug_print("  Disabled particles: %s" % particle.name)


func _find_mesh_instances_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	
	for child in node.get_children():
		_find_mesh_instances_recursive(child, result)


func _find_particles_recursive(node: Node, result: Array[GPUParticles3D]) -> void:
	if node is GPUParticles3D:
		result.append(node as GPUParticles3D)
	
	for child in node.get_children():
		_find_particles_recursive(child, result)


func _convert_mesh_material(mesh_instance: MeshInstance3D, new_texture: Texture2D) -> void:
	# Check surface override materials first
	for i in range(mesh_instance.get_surface_override_material_count()):
		var material = mesh_instance.get_surface_override_material(i)
		if material and material is ShaderMaterial:
			_update_shader_material(material as ShaderMaterial, new_texture)
			_debug_print("  Updated surface override material %d on %s" % [i, mesh_instance.name])
			return
	
	# Check mesh materials
	if mesh_instance.mesh:
		for i in range(mesh_instance.mesh.get_surface_count()):
			var material = mesh_instance.mesh.surface_get_material(i)
			if material and material is ShaderMaterial:
				# Create a copy to avoid modifying shared resources
				var mat_copy = material.duplicate() as ShaderMaterial
				_update_shader_material(mat_copy, new_texture)
				mesh_instance.set_surface_override_material(i, mat_copy)
				_debug_print("  Updated mesh material %d on %s" % [i, mesh_instance.name])
				return


func _update_shader_material(material: ShaderMaterial, new_texture: Texture2D) -> void:
	# Update the albedo_texture shader parameter
	if material.get_shader_parameter("albedo_texture") != null:
		material.set_shader_parameter("albedo_texture", new_texture)


# ---------------------------
# RadiantTree Conversion
# ---------------------------

func _convert_radiant_trees_in_zone() -> void:
	# Load normal tree textures if not set
	var tree1_texture = normal_tree1_texture
	if not tree1_texture:
		tree1_texture = load("res://Map Asset/Tree1_Trunk Base Color.png")
		if not tree1_texture:
			_debug_print("WARNING: Could not load Tree1 trunk texture!")
	
	var tree2_texture = normal_tree2_texture
	if not tree2_texture:
		tree2_texture = load("res://Map Asset/Tree2_Trunk Base Color.png")
		if not tree2_texture:
			_debug_print("WARNING: Could not load Tree2 trunk texture!")
	
	if not tree1_texture and not tree2_texture:
		_debug_print("WARNING: No normal tree textures available!")
		return
	
	# Find all RadiantTree blocks in the scene
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	var radiant_trees: Array[Node3D] = []
	_find_radiant_trees_recursive(scene_root, radiant_trees)
	
	_debug_print("Found %d RadiantTree blocks in scene" % radiant_trees.size())
	
	# Get scaled bounds for detection
	var bounds = _get_scaled_zone_bounds()
	var converted_count = 0
	
	for tree in radiant_trees:
		var tree_pos = tree.global_position
		var is_inside = _is_point_inside_zone(tree_pos, bounds)
		
		if is_inside:
			# Determine which texture to use based on tree type
			var target_texture: Texture2D = null
			var is_tree1: bool = false
			if _is_tree_radiant1(tree):
				target_texture = tree1_texture
				is_tree1 = true
			elif _is_tree_radiant2(tree):
				target_texture = tree2_texture
				is_tree1 = false
			
			if target_texture:
				_convert_single_tree(tree, target_texture, is_tree1)
				converted_count += 1
				_debug_print("Converted RadiantTree '%s' at %s" % [tree.name, tree_pos])
	
	_debug_print("Converted %d RadiantTree blocks to normal trees" % converted_count)


func _find_radiant_trees_recursive(node: Node, result: Array[Node3D]) -> void:
	# Check if this node is a RadiantTree
	if node is Node3D and _is_radiant_tree(node as Node3D):
		result.append(node as Node3D)
		return  # Don't check children
	
	# Recursively check children
	for child in node.get_children():
		_find_radiant_trees_recursive(child, result)


func _is_radiant_tree(node: Node3D) -> bool:
	# Check by scene filename
	var scene_path = node.scene_file_path.to_lower()
	if "treeradiant" in scene_path:
		return true
	
	# Check by node name
	var node_name = node.name.to_lower()
	if "treeradiant" in node_name:
		return true
	
	return false


func _is_tree_radiant1(node: Node3D) -> bool:
	var scene_path = node.scene_file_path.to_lower()
	var node_name = node.name.to_lower()
	return "treeradiant1" in scene_path or "treeradiant1" in node_name


func _is_tree_radiant2(node: Node3D) -> bool:
	var scene_path = node.scene_file_path.to_lower()
	var node_name = node.name.to_lower()
	return "treeradiant2" in scene_path or "treeradiant2" in node_name


func _convert_single_tree(tree: Node3D, new_texture: Texture2D, is_tree1: bool) -> void:
	# Find all MeshInstance3D children
	var mesh_instances: Array[MeshInstance3D] = []
	_find_mesh_instances_recursive(tree, mesh_instances)
	
	for mesh_instance in mesh_instances:
		_convert_tree_material(mesh_instance, new_texture, is_tree1)


func _convert_tree_material(mesh_instance: MeshInstance3D, new_texture: Texture2D, is_tree1: bool) -> void:
	if not mesh_instance.mesh:
		return
	
	var surface_count = mesh_instance.mesh.get_surface_count()
	
	# Determine which surfaces to convert based on tree type
	var surfaces_to_convert: Array[int] = []
	if is_tree1:
		# TreeRadiant1: Change Surface 1 & 2, Surface 0 don't change
		if surface_count > 1:
			surfaces_to_convert.append(1)
		if surface_count > 2:
			surfaces_to_convert.append(2)
	else:
		# TreeRadiant2: Change Surface 0 & 2, Surface 1 don't change
		if surface_count > 0:
			surfaces_to_convert.append(0)
		if surface_count > 2:
			surfaces_to_convert.append(2)
	
	# Convert the specified surfaces
	for surface_idx in surfaces_to_convert:
		if surface_idx >= surface_count:
			continue
		
		# Check if there's already a surface override material
		var existing_override = mesh_instance.get_surface_override_material(surface_idx)
		var material: StandardMaterial3D = null
		
		if existing_override and existing_override is StandardMaterial3D:
			# Use existing override material
			material = existing_override as StandardMaterial3D
		else:
			# Get material from mesh
			var mesh_material = mesh_instance.mesh.surface_get_material(surface_idx)
			if mesh_material and mesh_material is StandardMaterial3D:
				material = mesh_material as StandardMaterial3D
		
		if material:
			# Create a copy to avoid modifying shared resources
			var mat_copy = material.duplicate() as StandardMaterial3D
			mat_copy.albedo_texture = new_texture
			mesh_instance.set_surface_override_material(surface_idx, mat_copy)
			_debug_print("  Updated tree surface %d material on %s" % [surface_idx, mesh_instance.name])


# ---------------------------
# SimpleGrassTextured Conversion
# ---------------------------

func _convert_simple_grass_textured_in_zone() -> void:
	# Load normal grass texture if not set
	var grass_texture = normal_simple_grass_texture
	if not grass_texture:
		# Try to load a default normal grass texture
		grass_texture = load("res://Map Asset/grass_albedo.tres")
		if not grass_texture:
			_debug_print("WARNING: Could not load normal SimpleGrassTextured texture!")
			return
	
	# Find all SimpleGrassTextured nodes in the scene
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	var simple_grass_nodes: Array[MultiMeshInstance3D] = []
	_find_simple_grass_textured_recursive(scene_root, simple_grass_nodes)
	
	_debug_print("Found %d SimpleGrassTextured nodes in scene" % simple_grass_nodes.size())
	
	# Get scaled bounds for detection
	var bounds = _get_scaled_zone_bounds()
	var converted_count = 0
	
	for grass_node in simple_grass_nodes:
		var grass_pos = grass_node.global_position
		var is_inside = _is_point_inside_zone(grass_pos, bounds)
		
		if is_inside:
			# Change the texture_albedo property (the setter will handle the material update)
			grass_node.texture_albedo = grass_texture
			converted_count += 1
			_debug_print("Converted SimpleGrassTextured '%s' at %s" % [grass_node.name, grass_pos])
	
	_debug_print("Converted %d SimpleGrassTextured nodes to normal grass texture" % converted_count)


func _find_simple_grass_textured_recursive(node: Node, result: Array[MultiMeshInstance3D]) -> void:
	# Check if this node is a SimpleGrassTextured (MultiMeshInstance3D with meta)
	if node is MultiMeshInstance3D:
		var multi_mesh = node as MultiMeshInstance3D
		if multi_mesh.has_meta("SimpleGrassTextured"):
			result.append(multi_mesh)
			return  # Don't check children
	
	# Recursively check children
	for child in node.get_children():
		_find_simple_grass_textured_recursive(child, result)


# ---------------------------
# GridMap Tile Conversion
# ---------------------------

func _convert_gridmap_tiles_in_zone() -> void:
	if not gridmap:
		_debug_print("WARNING: GridMap not assigned!")
		return
	
	if radiation_tile_ids.size() == 0:
		_debug_print("WARNING: No radiation_tile_ids configured!")
		return
	
	_debug_print("=== GRIDMAP CONVERSION START ===")
	_debug_print("Zone position: %s" % global_position)
	_debug_print("Zone radius: %.2f" % zone_radius)
	_debug_print("Radiation tile IDs configured: %s" % str(radiation_tile_ids))
	_debug_print("Normal grass tile ID: %d" % normal_grass_tile_id)
	_debug_print("GridMap name: %s" % gridmap.name)
	_debug_print("GridMap global position: %s" % gridmap.global_position)
	
	# Get all used cells from GridMap
	var used_cells = gridmap.get_used_cells()
	_debug_print("Found %d cells in GridMap" % used_cells.size())
	
	if used_cells.size() == 0:
		_debug_print("WARNING: No cells found in GridMap! Is the GridMap populated?")
		return
	
	var zone_pos = global_position
	var converted_count = 0
	
	# Get scaled bounds for detection
	var bounds = _get_scaled_zone_bounds()
	
	# Process each cell
	var radiation_tiles_found = 0
	var all_tile_items: Dictionary = {}  # Track all unique tile items found
	
	for cell_coords in used_cells:
		# Get the tile item at this cell
		var tile_item = gridmap.get_cell_item(cell_coords)
		
		# Skip invalid tiles
		if tile_item < 0:
			continue
		
		# Track all tile items for debugging
		if not all_tile_items.has(tile_item):
			all_tile_items[tile_item] = 0
		all_tile_items[tile_item] += 1
		
		# Debug: show first few cells
		if used_cells.find(cell_coords) < 5:
			_debug_print("  Sample cell %s: tile_item = %d" % [cell_coords, tile_item])
		
		# Check if this is a radiation tile
		if tile_item in radiation_tile_ids:
			# Skip if this tile ID is the same as normal grass (would convert to itself)
			if tile_item == normal_grass_tile_id:
				_debug_print("  Skipping tile ID %d - same as normal_grass_tile_id!" % tile_item)
				continue
			
			radiation_tiles_found += 1
			# Convert cell coordinates to world position
			# map_to_local converts cell coords to GridMap's local space
			var local_pos = gridmap.map_to_local(cell_coords)
			# to_global converts to world space
			var world_pos = gridmap.to_global(local_pos)
			
			_debug_print("  Found radiation tile ID %d at cell %s -> world pos %s" % [tile_item, cell_coords, world_pos])
			
			# Check if within zone bounds (sphere or box)
			var is_inside: bool = false
			if ignore_zone_bounds:
				# Test mode: convert all radiation tiles
				is_inside = true
				_debug_print("  IGNORE_ZONE_BOUNDS enabled - converting regardless of position")
			else:
				is_inside = _is_point_inside_zone(world_pos, bounds)
				if is_inside:
					_debug_print("  Cell %s at %s is INSIDE zone" % [cell_coords, world_pos])
			
			if is_inside:
				# Get the cell's orientation to preserve it
				var orientation = gridmap.get_cell_item_orientation(cell_coords)
				
				# Replace with normal grass tile
				gridmap.set_cell_item(cell_coords, normal_grass_tile_id, orientation)
				converted_count += 1
				_debug_print("✓ Converted GridMap tile at %s from ID %d to %d" % [cell_coords, tile_item, normal_grass_tile_id])
			else:
				_debug_print("✗ Radiation tile at %s is OUTSIDE zone" % cell_coords)
	
	_debug_print("=== GRIDMAP CONVERSION SUMMARY ===")
	_debug_print("Total radiation tiles found: %d" % radiation_tiles_found)
	_debug_print("Converted: %d tiles" % converted_count)
	_debug_print("All tile IDs found in GridMap: %s" % str(all_tile_items.keys()))
	_debug_print("Tile ID counts: %s" % str(all_tile_items))
	
	# Check if radiation tile IDs match any found tiles
	var matching_ids = []
	for tile_id in radiation_tile_ids:
		if all_tile_items.has(tile_id):
			matching_ids.append(tile_id)
	
	if matching_ids.size() == 0:
		_debug_print("⚠️ WARNING: None of the configured radiation_tile_ids (%s) match any tiles in the GridMap!" % str(radiation_tile_ids))
		_debug_print("   Available tile IDs in GridMap: %s" % str(all_tile_items.keys()))
	else:
		_debug_print("✓ Found matching radiation tile IDs: %s" % str(matching_ids))
	
	_debug_print("================================")


# ---------------------------
# Grass Spawning
# ---------------------------

func _spawn_grass_in_zone() -> void:
	if not spawn_grass_on_clear:
		return
	
	if not grass_scene:
		_debug_print("WARNING: Grass scene not set! Cannot spawn grass.")
		return
	
	var scene_root = get_tree().current_scene
	if not scene_root:
		_debug_print("WARNING: No scene root found! Cannot spawn grass.")
		return
	
	_debug_print("=== SPAWNING GRASS IN ZONE ===")
	
	var zone_pos = global_position
	var spawned_count = 0
	
	# Get scaled bounds for spawning
	var bounds = _get_scaled_zone_bounds()
	
	# Get space state for raycasting
	var space_state = get_world_3d().direct_space_state
	
	# Spawn grass instances
	for i in range(grass_spawn_count):
		# Generate random position within spawn area
		var random_pos: Vector3
		
		if bounds.is_box:
			# For box: random position within scaled box bounds (using spawn_radius multiplier)
			var spawn_half_size = bounds.half_size * grass_spawn_radius
			random_pos = zone_pos + Vector3(
				randf_range(-spawn_half_size.x, spawn_half_size.x),
				0.0,  # Will be adjusted by raycast
				randf_range(-spawn_half_size.z, spawn_half_size.z)
			)
		else:
			# For sphere: random position within scaled circle
			var spawn_radius = bounds.radius * grass_spawn_radius
			var angle = randf() * TAU
			var distance = randf() * spawn_radius
			random_pos = zone_pos + Vector3(
				cos(angle) * distance,
				0.0,  # Will be adjusted by raycast
				sin(angle) * distance
			)
		
		# Raycast downward to find ground
		var ray_start = random_pos + Vector3.UP * 10.0  # Start above
		var ray_end = random_pos - Vector3.UP * 20.0  # Cast downward
		
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 1  # Ground collision layer
		query.collide_with_bodies = true
		query.collide_with_areas = false
		
		var result = space_state.intersect_ray(query)
		
		if result.is_empty():
			_debug_print("  No ground found at position %s, skipping grass spawn" % random_pos)
			continue
		
		# Get ground position and add offset
		var ground_pos = result.position
		ground_pos.y += grass_height_offset
		
		# Instantiate grass
		var grass_instance = grass_scene.instantiate()
		scene_root.add_child(grass_instance)
		grass_instance.global_position = ground_pos
		
		# Random rotation for variety
		grass_instance.rotation.y = randf() * TAU
		
		# Random scale for variety (0.9 to 1.1)
		var random_scale = randf_range(0.9, 1.1)
		grass_instance.scale = Vector3(random_scale, random_scale, random_scale)
		
		spawned_count += 1
		_debug_print("  Spawned grass %d at %s" % [i + 1, ground_pos])
	
	_debug_print("Spawned %d/%d grass instances in zone" % [spawned_count, grass_spawn_count])
	_debug_print("================================")


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
