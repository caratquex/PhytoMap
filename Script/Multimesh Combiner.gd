@tool
extends Node3D

# The parent under which all your individual StaticBody3D rock nodes live
@export var rock_parent_path: NodePath = NodePath("Rocks")

# Folder where generated MultiMesh scene files will be saved
@export var multimesh_save_folder: String = "res://Generated Multimesh/"

# Texture to apply onto each MultiMeshInstance
@export var rock_texture_path: String = "res://test_text.tres"

func _ready():
	# Uncomment to auto-run in the editor:
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
	print("🔄 Merging rocks into MultiMeshInstances + collision scenes…")

	# --- 0) Cleanup any previous merge output ---
	if has_node("MergedCollisions"):
		get_node("MergedCollisions").queue_free()
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()

	# --- 1) Gather all rock nodes under the parent ---
	var parent = get_node_or_null(rock_parent_path)
	if parent == null:
		push_error("❌ Invalid parent node path.")
		return

	var rocks = parent.get_children()
	if rocks.is_empty():
		push_warning("⚠️ No rock children found.")
		return

	# --- 2) Group each rock's transform by its mesh resource ---
	var mesh_to_transforms = {}
	for rock in rocks:
		var mesh_instance = _find_mesh_instance_recursive(rock)
		if mesh_instance and mesh_instance.mesh:
			var mesh = mesh_instance.mesh
			if not mesh_to_transforms.has(mesh):
				mesh_to_transforms[mesh] = []
			mesh_to_transforms[mesh].append(rock.global_transform)

	if mesh_to_transforms.is_empty():
		push_error("❌ Couldn't find any MeshInstance3D children with a mesh.")
		return

	# --- 3) Build & add one MultiMeshInstance3D per unique mesh + save scene ---
	var total_instances = 0
	var mesh_index = 0

	# Preload the rock texture once
	var rock_tex = load(rock_texture_path)

	for mesh in mesh_to_transforms.keys():
		var transforms = mesh_to_transforms[mesh]
		
		# Create the MultiMesh
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()

		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])

		# Create MultiMeshInstance3D for the current scene
		var mmi = MultiMeshInstance3D.new()
		mmi.name = "RockMultiMesh_%d" % mesh_index
		mmi.multimesh = mm
		add_child(mmi)

		# Apply the texture via a new StandardMaterial3D
		if rock_tex:
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = rock_tex
			mmi.material_override = mat
		else:
			push_warning("⚠️ Could not load texture at '%s'." % rock_texture_path)

		# --- Save as a complete scene with collision ---
		var scene_root = Node3D.new()
		scene_root.name = "MultiMeshWithCollision"
		
		# Create MultiMeshInstance3D for the saved scene
		var saved_mmi = MultiMeshInstance3D.new()
		saved_mmi.name = "MultiMeshInstance"
		saved_mmi.multimesh = mm
		if rock_tex:
			var saved_mat = StandardMaterial3D.new()
			saved_mat.albedo_texture = rock_tex
			saved_mmi.material_override = saved_mat
		scene_root.add_child(saved_mmi)
		saved_mmi.owner = scene_root
		
		# Create convex collision shape from mesh
		var collision_shape: Shape3D = null
		if mesh is ArrayMesh:
			collision_shape = mesh.create_convex_shape()
		elif mesh.has_method("create_convex_shape"):
			collision_shape = mesh.create_convex_shape()
		
		if collision_shape:
			# Create StaticBody3D with collision for each instance
			for i in range(transforms.size()):
				var static_body = StaticBody3D.new()
				static_body.name = "StaticBody_%d" % i
				var coll_shape = CollisionShape3D.new()
				coll_shape.name = "CollisionShape"
				coll_shape.shape = collision_shape
				static_body.add_child(coll_shape)
				coll_shape.owner = scene_root
				scene_root.add_child(static_body)
				static_body.owner = scene_root
				static_body.transform = transforms[i]
		else:
			push_warning("⚠️ Could not create convex collision shape from mesh.")
		
		# Pack and save the scene
		var packed_scene = PackedScene.new()
		var pack_result = packed_scene.pack(scene_root)
		if pack_result == OK:
			var mesh_id = mesh.resource_path.get_file().get_basename()
			if mesh_id.is_empty():
				mesh_id = "mesh_%d" % mesh_index
			var save_path = multimesh_save_folder.path_join("multimesh_%s.tscn" % mesh_id)
			var save_result = ResourceSaver.save(packed_scene, save_path)
			if save_result != OK:
				push_error("❌ Failed to save scene to %s" % save_path)
			else:
				print("💾 Scene with collision saved to %s" % save_path)
		else:
			push_error("❌ Failed to pack scene for mesh %d" % mesh_index)
		
		# Cleanup temporary scene root
		scene_root.queue_free()

		total_instances += transforms.size()
		mesh_index += 1

	# --- 4) Remove original rock nodes ---
	for rock in rocks:
		rock.queue_free()

	print("✅ %d rocks batched into %d MultiMesh scenes with collision." %
		  [total_instances, mesh_to_transforms.size()])
