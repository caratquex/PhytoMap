@tool
extends Node3D

# Script to automatically scatter grass on GridMaps in the scene
# Attach this to the scene root or any Node3D parent

@export var grass_scene: PackedScene = preload("res://Tiles/grass.tscn")
@export var grass_density: float = 0.3  # Probability of placing grass on each cell (0.0 to 1.0)
@export var grass_height_offset: float = 0.5  # Height offset above the cell
@export var min_scale: float = 0.8  # Minimum random scale
@export var max_scale: float = 1.2  # Maximum random scale
@export var auto_scatter: bool = true  # Automatically scatter on _ready()
@export var scatter_on_gridmap_name: String = ""  # If set, only scatter on GridMaps with this name (empty = all)

func _ready():
	if auto_scatter:
		scatter_grass()

func scatter_grass():
	if not grass_scene:
		push_error("Grass scene not set!")
		return
	
	# Find all GridMaps in the scene
	var gridmaps = find_gridmaps(get_tree().root)
	print("Found ", gridmaps.size(), " GridMap(s)")
	
	if gridmaps.is_empty():
		print("No GridMaps found in the scene!")
		return
	
	# Use this node as parent for grass instances
	var grass_parent = self
	if get_child_count() == 0 or get_child(0).name != "ScatteredGrass":
		var new_parent = Node3D.new()
		new_parent.name = "ScatteredGrass"
		add_child(new_parent)
		grass_parent = new_parent
	
	var total_placed = 0
	
	# Process each GridMap
	for gridmap in gridmaps:
		# Filter by name if specified
		if scatter_on_gridmap_name != "" and gridmap.name != scatter_on_gridmap_name:
			continue
		
		print("Processing GridMap: ", gridmap.name)
		var placed = scatter_grass_on_gridmap(gridmap, grass_parent)
		total_placed += placed
		print("  Placed ", placed, " grass instances")
	
	print("Total grass instances placed: ", total_placed)

func find_gridmaps(node: Node) -> Array:
	var gridmaps = []
	
	if node is GridMap:
		gridmaps.append(node)
	
	for child in node.get_children():
		gridmaps.append_array(find_gridmaps(child))
	
	return gridmaps

func scatter_grass_on_gridmap(gridmap: GridMap, parent: Node3D) -> int:
	var placed_count = 0
	var used_cells = gridmap.get_used_cells()
	
	# Group cells by x,z to find the highest y for each position
	var cell_heights = {}
	for cell_pos in used_cells:
		var key = Vector2i(cell_pos.x, cell_pos.z)
		if not cell_heights.has(key) or cell_heights[key] < cell_pos.y:
			cell_heights[key] = cell_pos.y
	
	# Place grass on top of cells
	for key in cell_heights:
		# Random chance to place grass (based on density)
		if randf() > grass_density:
			continue
		
		var highest_y = cell_heights[key]
		var final_cell = Vector3i(key.x, highest_y, key.y)
		var final_world_pos = gridmap.map_to_local(final_cell)
		
		# Add height offset
		final_world_pos.y += grass_height_offset
		
		# Create grass instance
		var grass_instance = grass_scene.instantiate()
		grass_instance.global_position = final_world_pos
		
		# Random rotation for variety
		grass_instance.rotation.y = randf() * TAU
		
		# Random scale for variety
		var scale = randf_range(min_scale, max_scale)
		grass_instance.scale = Vector3(scale, scale, scale)
		
		parent.add_child(grass_instance)
		
		placed_count += 1
	
	return placed_count
