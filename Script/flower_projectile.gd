extends RigidBody3D

# ---------------------------
# Projectile Configuration
# ---------------------------
@export var initial_velocity: Vector3 = Vector3.ZERO
@export var max_range: float = 150.0  # Increased range for longer shooting distance
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
@onready var shooting_vfx: Node3D = $ShootingVFX


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
	
	# Enable shooting VFX on spawn
	_start_shooting_vfx()


func _physics_process(delta: float) -> void:
	if has_landed:
		return
	
	# Track distance traveled
	var current_distance = global_position.distance_to(last_position)
	distance_traveled += current_distance
	last_position = global_position
	
	# Orient VFX in direction of travel
	if shooting_vfx and linear_velocity.length() > 0.1:
		var velocity_dir = linear_velocity.normalized()
		# Use a safe up vector that's not parallel to velocity
		var up_vector = Vector3.UP
		if abs(velocity_dir.dot(Vector3.UP)) > 0.99:
			up_vector = Vector3.RIGHT
		shooting_vfx.look_at(global_position + velocity_dir, up_vector)
	
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
	
	# Stop VFX particles
	_stop_shooting_vfx()
	
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


const FLOWER_LIFETIME: float = 15.0  # Seconds before flower disappears

func transform_to_flower(flower_pos: Vector3) -> void:
	if not flower_scene:
		# Use the same Sunflower1.tscn scene that player uses for planting
		flower_scene = load("res://Scene/Sunflower1.tscn")
	
	if not flower_scene:
		push_error("Failed to load Sunflower1.tscn!")
		queue_free()
		return
	
	# Wait 1 second before transforming into flower
	await get_tree().create_timer(1.0).timeout
	
	# Spawn flower using Sunflower1.tscn
	var flower = flower_scene.instantiate()
	get_tree().current_scene.add_child(flower)
	flower.global_position = flower_pos
	
	# Auto-delete flower after 15 seconds to improve performance
	_setup_flower_auto_delete(flower)
	
	# Remove projectile after transformation
	queue_free()


func _setup_flower_auto_delete(flower: Node3D) -> void:
	"""Set up a timer to automatically delete the flower after FLOWER_LIFETIME seconds."""
	if not flower or not is_instance_valid(flower):
		return
	
	# Create and configure the timer
	var timer = Timer.new()
	timer.wait_time = FLOWER_LIFETIME
	timer.one_shot = true
	timer.autostart = true
	flower.add_child(timer)
	
	# Connect timeout to delete the flower
	timer.timeout.connect(func(): 
		if flower and is_instance_valid(flower):
			flower.queue_free()
	)


func _start_shooting_vfx() -> void:
	if not shooting_vfx:
		return
	
	# Make VFX visible
	shooting_vfx.visible = true
	
	# Start GPU particles emitting
	var particles = shooting_vfx.get_node_or_null("GPUParticles3D")
	if particles and particles is GPUParticles3D:
		particles.emitting = true
	
	# Show the fireball mesh
	var fireball = shooting_vfx.get_node_or_null("Fireballmeshobj")
	if fireball:
		fireball.visible = true


func _stop_shooting_vfx() -> void:
	if not shooting_vfx:
		return
	
	# Hide entire VFX node
	shooting_vfx.visible = false
	
	# Stop GPU particles emitting
	var particles = shooting_vfx.get_node_or_null("GPUParticles3D")
	if particles and particles is GPUParticles3D:
		particles.emitting = false
	
	# Hide the fireball mesh
	var fireball = shooting_vfx.get_node_or_null("Fireballmeshobj")
	if fireball:
		fireball.visible = false


func destroy_projectile() -> void:
	queue_free()
