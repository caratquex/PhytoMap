extends Node3D

## Script for Sunflower1.tscn to handle shooting VFX
## VFX is enabled when shooting and disabled when touching the floor

# ---------------------------
# Configuration
# ---------------------------
@export var is_projectile: bool = false  ## Set to true when this sunflower is being shot
@export var ground_collision_mask: int = 1  ## Collision mask for ground detection

# ---------------------------
# State
# ---------------------------
var has_landed: bool = false
var velocity: Vector3 = Vector3.ZERO
var last_position: Vector3 = Vector3.ZERO

# ---------------------------
# Node References
# ---------------------------
@onready var shooting_vfx: Node3D = $ShootingVFX


func _ready() -> void:
	last_position = global_position
	
	# VFX is hidden by default in the scene
	# Only enable if this is a projectile
	if is_projectile:
		start_shooting_vfx()


func _physics_process(delta: float) -> void:
	if not is_projectile or has_landed:
		return
	
	# Calculate velocity from position change
	velocity = (global_position - last_position) / delta if delta > 0 else Vector3.ZERO
	last_position = global_position
	
	# Orient VFX in direction of travel (fireball leads, particles follow)
	if shooting_vfx and velocity.length() > 0.1:
		# Calculate rotation to face velocity direction
		var vel = velocity
		# Calculate pitch (rotation around X) and yaw (rotation around Y)
		var horizontal_length = Vector2(vel.x, vel.z).length()
		var pitch = atan2(-vel.y, horizontal_length)  # Negative because we rotate around X
		var yaw = atan2(vel.x, vel.z)  # Rotation around Y to face horizontal direction
		
		# Apply rotation (yaw first, then pitch)
		shooting_vfx.rotation = Vector3(pitch, yaw, 0)
	
	# Check for ground collision
	_check_ground_collision()


func _check_ground_collision() -> void:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.5,
		global_position - Vector3.UP * 0.1
	)
	query.collision_mask = ground_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	var result = space_state.intersect_ray(query)
	
	if not result.is_empty():
		# Check if we're moving downward (falling)
		if velocity.y < -0.5:
			land_on_floor(result.position)


func land_on_floor(floor_pos: Vector3) -> void:
	if has_landed:
		return
	
	has_landed = true
	is_projectile = false
	
	# Stop VFX
	stop_shooting_vfx()
	
	# Snap to floor position
	global_position.y = floor_pos.y


## Call this to enable shooting mode with VFX
func start_shooting(initial_velocity: Vector3 = Vector3.ZERO) -> void:
	is_projectile = true
	has_landed = false
	velocity = initial_velocity
	last_position = global_position
	start_shooting_vfx()


## Enable the shooting VFX
func start_shooting_vfx() -> void:
	if not shooting_vfx:
		shooting_vfx = get_node_or_null("ShootingVFX")
	
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


## Disable the shooting VFX (called when touching floor)
func stop_shooting_vfx() -> void:
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
