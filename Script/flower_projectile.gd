extends RigidBody3D

# ---------------------------
# Projectile Configuration
# ---------------------------
@export var initial_velocity: Vector3 = Vector3.ZERO
@export var max_range: float = 50.0
@export var bounce_damping: float = 0.6  # Reduce velocity on bounce
@export var min_velocity_to_bounce: float = 1.0
@export var ground_collision_mask: int = 1  # Match player's ground collision mask

# ---------------------------
# Projectile State
# ---------------------------
var distance_traveled: float = 0.0
var spawn_position: Vector3
var last_position: Vector3
var flower_scene: PackedScene
var has_landed: bool = false

# ---------------------------
# Node References
# ---------------------------
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	# Store spawn position
	spawn_position = global_position
	last_position = global_position
	
	# Apply initial velocity
	if initial_velocity != Vector3.ZERO:
		linear_velocity = initial_velocity
	
	# Enable contact monitoring for collision detection
	contact_monitor = true
	max_contacts_reported = 10
	
	# Configure physics
	gravity_scale = 1.0  # Use default gravity


func _physics_process(delta: float) -> void:
	if has_landed:
		return
	
	# Track distance traveled
	var current_distance = global_position.distance_to(last_position)
	distance_traveled += current_distance
	last_position = global_position
	
	# Check max range
	if distance_traveled > max_range:
		destroy_projectile()
		return
	
	# Check for collisions using get_colliding_bodies
	var colliding_bodies = get_colliding_bodies()
	if colliding_bodies.size() > 0:
		handle_collision(colliding_bodies)


func handle_collision(colliding_bodies: Array) -> void:
	if has_landed:
		return
	
	# Get collision information using raycast from last position to current
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		last_position,
		global_position
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return
	
	var normal = result.normal
	var current_velocity = linear_velocity
	
	# Check if hitting floor (normal pointing up)
	if normal.y > 0.7:  # Mostly upward normal = floor
		land_on_floor(result.position)
		return
	
	# Bounce off wall
	if current_velocity.length() > min_velocity_to_bounce:
		var reflected_velocity = current_velocity.bounce(normal) * bounce_damping
		linear_velocity = reflected_velocity
	else:
		# Too slow, fall straight down
		linear_velocity = Vector3(0, linear_velocity.y, 0)


func land_on_floor(impact_pos: Vector3) -> void:
	has_landed = true
	
	# Stop physics
	freeze = true
	linear_velocity = Vector3.ZERO
	
	# Raycast down to find exact floor
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		impact_pos + Vector3.UP * 0.5,
		impact_pos - Vector3.UP * 2.0
	)
	query.collision_mask = ground_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	
	var result = space_state.intersect_ray(query)
	
	if not result.is_empty():
		var floor_pos = result.position
		var collider = result.collider
		
		# Snap to grid if GridMap
		if collider is GridMap:
			var gridmap = collider as GridMap
			var local_hit = gridmap.to_local(floor_pos)
			var cell_coords = gridmap.local_to_map(local_hit)
			var cell_center_local = gridmap.map_to_local(cell_coords)
			var cell_center_global = gridmap.to_global(cell_center_local)
			floor_pos = Vector3(cell_center_global.x, floor_pos.y, cell_center_global.z)
		
		# Transform to flower
		transform_to_flower(floor_pos)
	else:
		# No floor found, just place at impact position
		transform_to_flower(impact_pos)


func transform_to_flower(flower_pos: Vector3) -> void:
	if not flower_scene:
		# Use the same Sunflower1.tscn scene that player uses for planting
		flower_scene = load("res://Scene/Sunflower1.tscn")
	
	if not flower_scene:
		push_error("Failed to load Sunflower1.tscn!")
		queue_free()
		return
	
	# Hide projectile
	visible = false
	
	# Spawn flower using Sunflower1.tscn
	var flower = flower_scene.instantiate()
	get_tree().current_scene.add_child(flower)
	flower.global_position = flower_pos
	
	# Remove projectile
	await get_tree().create_timer(0.1).timeout
	queue_free()


func destroy_projectile() -> void:
	queue_free()

