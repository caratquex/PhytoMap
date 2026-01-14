@tool
extends Node3D

# The parent under which all your individual StaticBody3D rock nodes live
@export var rock_parent_path: NodePath = NodePath("Rocks")

# Folder where generated MultiMesh .tres files will be saved
@export var multimesh_save_folder: String = "res://Generated Multimesh/"

# Texture to apply onto each MultiMeshInstance
@export var rock_texture_path: String = "res://test_text.tres"

func _ready():
	# Uncomment to autoâ€'run in the editor:
	merge()
	pass

# Recursively find the first MeshInstance3D with a mesh in the node tree
func _find_mesh_instance_recursive(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			return child
		var result = _find_mesh_instance_recursive(child)
		if result:
			return result
	return null
func merge():
	print("ðŸ” Merging rocks into MultiMeshInstances + combined collisionâ€¦")

	# --- 0) Cleanup any previous merge output ---
	if has_node("MergedCollisions"):
		get_node("MergedCollisions").queue_free()
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()

	# --- 1) Gather all rock nodes under the parent ---
	var parent = get_node_or_null(rock_parent_path)
	if parent == null:
		push_error("âŒ Invalid parent node path.")
		return

	var rocks = parent.get_children()
	if rocks.is_empty():
		push_warning("âš ï¸ No rock children found.")
		return

	# --- 2) Group each rock's global_transform by its mesh resource ---
	var mesh_to_transforms = {}
	for rock in rocks:
		var mesh_instance = _find_mesh_instance_recursive(rock)
		if mesh_instance and mesh_instance.mesh:
			var mesh = mesh_instance.mesh
			if not mesh_to_transforms.has(mesh):
				mesh_to_transforms[mesh] = []  # plain Array of Transform3D
			mesh_to_transforms[mesh].append(rock.global_transform)

	if mesh_to_transforms.is_empty():
		push_error("âŒ Couldn't find any MeshInstance3D children with a mesh.")
		return

	# --- 3) Create a single StaticBody3D to hold all collisions ---
	var collision_body = StaticBody3D.new()
	collision_body.name = "MergedCollisions"
	add_child(collision_body)

	# Duplicate each rock's CollisionShape3D into the merged body
	for rock in rocks:
		if rock is StaticBody3D:
			for shape_node in rock.get_children():
				if shape_node is CollisionShape3D and shape_node.shape:
					var new_shape = CollisionShape3D.new()
					new_shape.shape = shape_node.shape.duplicate()
					collision_body.add_child(new_shape)
					new_shape.global_transform = shape_node.global_transform

	# --- 4) Build & add one MultiMeshInstance3D per unique mesh ---
	var total_instances = 0
	var mesh_index = 0

	# Preload the rock texture once
	var rock_tex = load(rock_texture_path)

	for mesh in mesh_to_transforms.keys():
		var transforms = mesh_to_transforms[mesh]
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()

		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])

		var mmi = MultiMeshInstance3D.new()
		mmi.name = "RockMultiMesh_%d" % mesh_index
		mmi.multimesh = mm
		add_child(mmi)

		# â”€â”€â”€ Apply the texture via a new StandardMaterial3D â”€â”€â”€
		if rock_tex:
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = rock_tex
			mmi.material_override = mat
		else:
			push_warning("âš ï¸ Could not load texture at '%s'." % rock_texture_path)

		# â”€â”€â”€ Save the MultiMesh resource to disk â”€â”€â”€
		var mesh_id = mesh.resource_path.get_file().get_basename()
		var save_path = multimesh_save_folder.path_join("multimesh_%s.tres" % mesh_id)
		var res = ResourceSaver.save(mm, save_path)
		if res != OK:
			push_error("âŒ Failed to save MultiMesh to %s" % save_path)
		else:
			print("ðŸ’¾ MultiMesh saved to %s" % save_path)

		total_instances += transforms.size()
		mesh_index += 1

	# --- 5) Remove original rock nodes ---
	for rock in rocks:
		rock.queue_free()

	print("âœ… %d rocks batched into %d MultiMeshInstance3Ds; collisions merged." %
		  [total_instances, mesh_to_transforms.size()])
