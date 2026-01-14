@tool
extends MultiMeshInstance3D

## Automatically creates StaticBody3D collision for each MultiMesh instance.
## Attach this script to any MultiMeshInstance3D node.

@export var create_on_ready: bool = true
@export var collision_layer: int = 1
@export var collision_mask: int = 1

var _collision_parent: Node3D = null

func _ready():
	if create_on_ready:
		create_collisions()

func create_collisions():
	# Clear any existing collisions
	clear_collisions()
	
	if not multimesh:
		push_error("❌ No MultiMesh assigned.")
		return
	
	var mesh_res = multimesh.mesh
	if not mesh_res:
		push_error("❌ MultiMesh has no mesh.")
		return
	
	# Create a parent node to hold all collision bodies
	_collision_parent = Node3D.new()
	_collision_parent.name = "Collisions"
	add_child(_collision_parent)
	
	# Create one convex shape for all instances to share
	var shape: Shape3D = null
	if mesh_res is ArrayMesh:
		shape = mesh_res.create_convex_shape()
	elif mesh_res.has_method("create_convex_shape"):
		shape = mesh_res.create_convex_shape()
	
	if not shape:
		push_warning("⚠️ Could not create convex shape from mesh.")
		return
	
	# Create StaticBody3D with collision for each instance
	for i in range(multimesh.instance_count):
		var static_body = StaticBody3D.new()
		static_body.name = "Body_%d" % i
		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		
		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = shape
		static_body.add_child(collision_shape)
		
		_collision_parent.add_child(static_body)
		
		# Move the body to the instance's position
		static_body.transform = multimesh.get_instance_transform(i)
	
	print("✅ Created %d collision bodies for MultiMesh." % multimesh.instance_count)

func clear_collisions():
	if _collision_parent:
		_collision_parent.queue_free()
		_collision_parent = null
	
	# Also check for any existing Collisions node
	if has_node("Collisions"):
		get_node("Collisions").queue_free()
