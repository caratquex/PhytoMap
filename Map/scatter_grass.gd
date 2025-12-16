@tool
extends EditorScript

# Script to scatter grass on GridMaps
# Run this from the Editor: Script > Run Script

const GRASS_SCENE = preload("res://Tiles/grass.tscn")
const GRASS_DENSITY = 0.3  # Probability of placing grass on each cell (0.0 to 1.0)
const GRASS_HEIGHT_OFFSET = 0.5  # Height offset above the cell

func _run():
	
	# Get the currently edited scene
	var scene = EditorInterface.get_edited_scene_root()
	if not scene:
		print("No scene loaded!")
		return
	
	# Find all GridMaps in the scene
	var gridmaps = find_gridmaps(scene)
	print("Found ", gridmaps.size(), " GridMap(s)")
	
	if gridmaps.is_empty():
		print("No GridMaps found in the scene!")
		return
	
	# Create a parent node for all grass instances
	var grass_parent = scene.get_node_or_null("ScatteredGrass")
	if not grass_parent:
		grass_parent = Node3D.new()
		grass_parent.name = "ScatteredGrass"
		scene.add_child(grass_parent)
		grass_parent.owner = scene
	
	var total_placed = 0
	
	# Process each GridMap
	for gridmap in gridmaps:
		print("Processing GridMap: ", gridmap.name)
		var placed = scatter_grass_on_gridmap(gridmap, grass_parent)
		total_placed += placed
		print("  Placed ", placed, " grass instances")
	
	print("Total grass instances placed: ", total_placed)
	print("Done!")

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
	
	for cell_pos in used_cells:
		# Random chance to place grass (based on density)
		if randf() > GRASS_DENSITY:
			continue
		
		# Get the world position of the cell
		var world_pos = gridmap.map_to_local(cell_pos)
		
		# Get the cell's top surface position
		# We need to find the highest cell at this x,z position
		var highest_y = cell_pos.y
		for check_cell in used_cells:
			if check_cell.x == cell_pos.x and check_cell.z == cell_pos.z:
				if check_cell.y > highest_y:
					highest_y = check_cell.y
		
		# Calculate final position (on top of the highest cell)
		var final_cell = Vector3i(cell_pos.x, highest_y, cell_pos.z)
		var final_world_pos = gridmap.map_to_local(final_cell)
		
		# Add height offset
		final_world_pos.y += GRASS_HEIGHT_OFFSET
		
		# Create grass instance
		var grass_instance = GRASS_SCENE.instantiate()
		grass_instance.global_position = final_world_pos
		
		# Random rotation for variety
		grass_instance.rotation.y = randf() * TAU
		
		# Random scale for variety (0.8 to 1.2)
		var scale = randf_range(0.8, 1.2)
		grass_instance.scale = Vector3(scale, scale, scale)
		
		parent.add_child(grass_instance)
		grass_instance.owner = parent.owner
		
		placed_count += 1
	
	return placed_count
