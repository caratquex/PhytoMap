extends CharacterBody3D
class_name Player # Assuming you fixed the global class name conflict

static var instance: Player

# Movement Constants
var GRAVITY = get_gravity() # Project settings gravity, typically 9.8
@export var speed = 5.0
@export var jump_velocity = 4.5

# Node References (MUST be assigned in Inspector)
@export var camera: Camera3D
@export var model: Node3D
@export var animation_tree: AnimationTree 
@export var hand_muzzle: Node3D 

# Item/Projectile Scenes (MUST be assigned in Inspector)
@export var projectile_scene: PackedScene 
@export var grenade_scene: PackedScene 

# Dash Variables
const DASH_SPEED = 15.0
const DASH_DURATION = 0.5
var is_dashing = false
var dash_timer = 0.0
var dash_direction = Vector3.ZERO

# Action Variables
var is_aiming = false # NEW: Hold right click
var is_shooting = false
var is_throwing = false
var playback: AnimationNodeStateMachinePlayback # Used to control the Animation Tree

var spawn_position
var target_angle: float = PI

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
	
	spawn_position = position
	
	# Initialize Animation Playback
	if animation_tree and animation_tree.has_parameter("playback"):
		playback = animation_tree.get("parameters/playback")


func _process(delta: float) -> void:
	# ----------------------------------------------------
	# CAMERA/ROTATION LOGIC
	# ----------------------------------------------------
	var camera_angle = camera.global_rotation.y
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var input_angle = atan2(input_dir.x, input_dir.y)

	# ----------------------------------------------------
	# ACTION INPUT LOGIC
	# ----------------------------------------------------
	var can_act = not is_dashing and not is_shooting and not is_throwing

	# DASH INPUT
	if Input.is_action_just_pressed("dash") and input_dir != Vector2.ZERO and can_act: 
		start_dash(input_dir)

	# AIMING INPUT (Right Click)
	if Input.is_action_pressed("aim"):
		is_aiming = true
		# Optional: playback.travel("Aim")
	elif Input.is_action_just_released("aim"):
		is_aiming = false
		# Optional: Return to Idle/Run if input_dir is checked

	# SHOOTING/THROWING INPUT (Left Click)
	if Input.is_action_just_pressed("shoot") and can_act:
		if is_aiming:
			start_throw() # Aiming + Shoot = Throw
		else:
			start_shoot() # Shoot only
	
	# ----------------------------------------------------
	# MODEL ROTATION
	# ----------------------------------------------------
	if input_dir != Vector2.ZERO:
		target_angle = camera_angle + input_angle
	model.global_rotation.y = lerp_angle(model.global_rotation.y, target_angle, delta * 15)


func start_dash(input_dir: Vector2):
	is_dashing = true
	dash_timer = DASH_DURATION
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	dash_direction = direction.rotated(Vector3.UP, camera.global_rotation.y)
	velocity.x = dash_direction.x * DASH_SPEED
	velocity.z = dash_direction.z * DASH_SPEED
	velocity.y = 0.0

# ----------------------------------------------------
# NEW ACTION FUNCTIONS (Placeholder implementation)
# ----------------------------------------------------

func start_shoot():
	is_shooting = true
	if playback: playback.travel("Shoot")
	
	# Placeholder: Spawn bullet
	spawn_projectile(projectile_scene, hand_muzzle, 50.0) 
	
	# Use timer to wait for animation end (replace with Animation Method Track for production)
	var shoot_timer = get_tree().create_timer(0.3) 
	shoot_timer.timeout.connect(_on_shoot_animation_finished)

func start_throw():
	is_throwing = true
	if playback: playback.travel("Throw")
	
	# Placeholder: Throw grenade
	spawn_grenade(grenade_scene, hand_muzzle, 15.0) 
	
	var throw_timer = get_tree().create_timer(0.6) 
	throw_timer.timeout.connect(_on_throw_animation_finished)

func spawn_projectile(scene: PackedScene, spawn_point: Node3D, speed: float):
	# This is a conceptual function. You need to implement the actual spawning logic
	# as discussed previously, including instantiating and setting velocity.
	pass 

func spawn_grenade(scene: PackedScene, spawn_point: Node3D, force: float):
	# This is a conceptual function. You need to implement the actual spawning logic
	pass

func _on_shoot_animation_finished():
	is_shooting = false
	# Logic to return to Idle/Run state goes here
	pass 

func _on_throw_animation_finished():
	is_throwing = false
	# Logic to return to Idle/Run state goes here
	pass

# ----------------------------------------------------
# PHYSICS PROCESS
# ----------------------------------------------------

func _physics_process(delta: float) -> void:
	# ----------------------------------------------------
	# DASH HANDLING (Checks first to override normal movement)
	# ----------------------------------------------------
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			velocity.x = 0
			velocity.z = 0
		else:
			velocity.x = dash_direction.x * DASH_SPEED
			velocity.z = dash_direction.z * DASH_SPEED
			move_and_slide() # Execute movement and exit early
			return 
	
	# ----------------------------------------------------
	# GRAVITY
	# ----------------------------------------------------
	# Use the GRAVITY constant defined at the top
	if not is_on_floor():
		velocity.y -= GRAVITY * delta 

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# ----------------------------------------------------
	# MOVEMENT & DECELERATION
	# ----------------------------------------------------
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction = direction.rotated(Vector3.UP, camera.global_rotation.y)
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Deceleration logic
		velocity.x = move_toward(velocity.x, 0, speed) 
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
