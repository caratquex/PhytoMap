extends CharacterBody3D
# ما في class_name عشان ما يصير تعارض

static var instance: CharacterBody3D

# ---------------------------
# FLOWER PROJECTILE CLASS
# ---------------------------
class FlowerProjectile extends RigidBody3D:
	# Projectile Configuration
	@export var initial_velocity: Vector3 = Vector3.ZERO
	@export var max_range: float = 500.0  # Increased range for longer shooting distance
	@export var bounce_damping: float = 0.6  # Reduce velocity on bounce
	@export var min_velocity_to_bounce: float = 1.0
	@export var ground_collision_mask: int = 1  # Match player's ground collision mask
	
	# Projectile State
	var distance_traveled: float = 0.0
	var spawn_position: Vector3
	var last_position: Vector3
	var flower_scene: PackedScene
	var has_landed: bool = false
	var landing_collider: Node = null  # Store the collider we landed on for radiation check
	var weapon_type: WeaponType = WeaponType.GUN  # Track which weapon created this projectile
	var explosion_radius: float = 5.0  # Configurable explosion radius
	var explosion_force: float = 0.0  # Will be calculated as 3x jump_velocity
	var player_instance: CharacterBody3D = null  # Reference to player instance
	
	# Node References
	var flower_instance: Node3D = null  # The instantiated Sunflower1.tscn
	
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
		
		# Instantiate Sunflower1.tscn as child
		var scene_to_use = flower_scene
		if not scene_to_use:
			scene_to_use = load("res://Scene/Sunflower1.tscn")
		
		if scene_to_use:
			flower_instance = scene_to_use.instantiate()
			add_child(flower_instance)
		else:
			push_error("Failed to load Sunflower1.tscn for projectile!")
		
		# Add collision shape for the RigidBody3D (approximate sunflower size)
		var collision_shape = CollisionShape3D.new()
		var capsule_shape = CapsuleShape3D.new()
		capsule_shape.radius = 0.3
		capsule_shape.height = 1.2
		collision_shape.shape = capsule_shape
		collision_shape.position = Vector3(0, 0.6, 0)  # Center at half height
		add_child(collision_shape)
	
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
		
		# Check if this is a grenade - trigger explosion on any collision
		if weapon_type == WeaponType.GRENADE:
			trigger_explosion(result.position)
			# Still land on floor to transform into flower
			land_on_floor(result.position)
			return
		
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
		
		var floor_pos: Vector3
		if not result.is_empty():
			floor_pos = result.position
			var collider = result.collider
			
			# Store the collider for radiation check
			landing_collider = collider
			
			# Snap to grid if GridMap
			if collider is GridMap:
				var gridmap = collider as GridMap
				var local_hit = gridmap.to_local(floor_pos)
				var cell_coords = gridmap.local_to_map(local_hit)
				var cell_center_local = gridmap.map_to_local(cell_coords)
				var cell_center_global = gridmap.to_global(cell_center_local)
				floor_pos = Vector3(cell_center_global.x, floor_pos.y, cell_center_global.z)
		else:
			# No floor found, just use impact position
			floor_pos = impact_pos
			landing_collider = null
		
		# Place the flower directly (it's already instantiated as a child)
		if flower_instance and is_instance_valid(flower_instance):
			# Remove the flower from this RigidBody3D
			remove_child(flower_instance)
			
			# Add it to the scene root at the landing position
			if get_tree() and get_tree().current_scene:
				get_tree().current_scene.add_child(flower_instance)
				flower_instance.global_position = floor_pos
				
				# Check if planted on radiation location and notify GameManager
				if GameManager.instance and GameManager.instance.is_radiation_location(floor_pos, landing_collider):
					GameManager.instance.on_radiation_cleared()
			else:
				push_error("Cannot place flower - no scene tree!")
		
		# Remove projectile after placing flower
		queue_free()
	
	func destroy_projectile() -> void:
		queue_free()
	
	func trigger_explosion(explosion_pos: Vector3) -> void:
		# Check if player instance exists and is within explosion radius
		if not player_instance:
			return
		
		# Calculate distance from explosion to player
		var distance_to_player = explosion_pos.distance_to(player_instance.global_position)
		
		# Only affect player if within explosion radius
		if distance_to_player > explosion_radius:
			return
		
		# Calculate direction from grenade to player
		var direction_to_player = (player_instance.global_position - explosion_pos).normalized()
		
		# Apply explosion force to player
		if player_instance.has_method("apply_explosion_force"):
			player_instance.apply_explosion_force(direction_to_player, explosion_force)


# Factory method to create FlowerProjectile instances
static func create_flower_projectile() -> FlowerProjectile:
	return FlowerProjectile.new()

# ---------------------------
# Weapon System
# ---------------------------
enum WeaponType { GUN = 1, GRENADE = 2, SHOVEL = 3 }
var current_weapon: WeaponType = WeaponType.SHOVEL  # Default is Shovel (Plant)

# ---------------------------
# Flower Planting
# ---------------------------
var sunflower_scene: PackedScene = null
@export var plant_ray_length: float = 100.0
@export var max_plant_distance: float = 10.0  # Maximum distance player can plant flowers
@export var ground_collision_mask: int = 1  # Set to match your ground/gridmap collision layer
@export var flower_y_offset: float = 0.0  # Fine-tune flower height (0 = exactly at player's floor level)

# ---------------------------
# Floor Indicator (3D square outline snapped to grid)
# ---------------------------
@export var show_floor_indicator: bool = true
@export var indicator_color: Color = Color(0.463, 0.94, 0.207, 1.0)  # Yellow like in the image
@export var indicator_line_width: float = 0.05  # Width of the outline
var floor_indicator: Node3D  # Parent node for the outline
var floor_indicator_material: StandardMaterial3D
var current_grid_cell: Vector3i = Vector3i(-99999, -99999, -99999)  # Track current cell


# ---------------------------
# Movement
# ---------------------------
@export var gravity: float = 12.0  # جاذبية أسرع قليلاً من الأصل
@export var fall_multiplier: float = 1.2  # تسريع السقوط خفيف جداً
@export var speed: float = 4.0
@export var jump_velocity: float = 8.5      # نطة قريبة من الأصل
@export var double_jump_velocity: float = 7.0  # Double jump velocity (slightly lower than regular jump)
@export var rotation_speed: float = 5.0     # سرعة لف الأرنب
@export var acceleration: float = 50.0       # سرعة التسارع عند الحركة (زيادة للاستجابة)
@export var friction: float = 60.0           # سرعة التباطؤ عند التوقف (زيادة للاستجابة)
var has_double_jump: bool = true  # Track if double jump is available

# ---------------------------
# Nodes (عيّنها من الـ Inspector)
# ---------------------------w
@export var camera: Camera3D
@export var raycast_camera: Camera3D  # Camera for raycasting (use SpringArm3D/Camera3D)
@export var model: Node3D
@export var animation_tree: AnimationTree

@export var gun_model: Node3D
@export var grenade_model: Node3D
@export var shovel_model: Node3D

# ---------------------------
# Projectile System
# ---------------------------
@export var gun_projectile_speed: float = 20.0
@export var grenade_projectile_speed: float = 12.0
@export var gun_projectile_arc: float = 0.2  # Slight upward arc
@export var grenade_projectile_arc: float = 0.3  # Higher arc

# ---------------------------
# Dash Variables
# ---------------------------
const DASH_SPEED: float = 15.0
const DASH_DURATION: float = 0.5
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

# ---------------------------
# Action Flags
# ---------------------------
var is_acting: bool = false  # للأكشن الحالي (شوت/رمي/حفر)
var is_clinging: bool = false      # الأرنب ماسك في المكعب / الجدار
var is_hurting: bool = false  # للأنيميشن الضرر

var playback: AnimationNodeStateMachinePlayback
var target_angle: float = PI

# Track previous key states for numpad detection
var prev_kp_1: bool = false
var prev_kp_2: bool = false
var prev_kp_3: bool = false

# ---------------------------
# Hurt Animation
# ---------------------------
@export var hurt_angle: float = 10.0  # درجة الميلان عند الضرر
@export var hurt_duration: float = 0.3  # مدة الأنيميشن
@export var hurt_color: Color = Color(1.0, 0.3, 0.3)  # اللون الأحمر عند الضرر
var hurt_tween: Tween
var color_tween: Tween
var original_materials: Array = []  # لحفظ الماتيريال الأصلية

# ---------------------------
# First-Person Camera Mode
# ---------------------------
@export var spring_arm: SpringArm3D  # Reference to SpringArm3D node (set in Inspector)
@export var first_person_height: float = 1.6  # Height offset for first-person (head/eye level)
@export var camera_transition_speed: float = 5.0  # Speed of smooth transition
var default_spring_arm_position: Vector3  # Store default SpringArm3D position
var default_spring_length: float = 5.0  # Store default spring length
var target_spring_arm_position: Vector3  # Target position for smooth transition
var target_spring_length: float  # Target spring length for smooth transition
var camera_tween: Tween  # Tween for smooth camera movement
var spring_length_tween: Tween  # Tween for spring length transition

# ---------------------------
# SFX
# ---------------------------
@onready var drop: AudioStreamPlayer = $"../SFX/Drop"
@onready var jump: AudioStreamPlayer = $"../SFX/Jump"
@onready var walking_on_grass_ver_1_: AudioStreamPlayer = $"../SFX/WalkingOnGrass(ver1)"
@onready var dash_1: AudioStreamPlayer = $"../SFX/Dash1"
@onready var planting_seed: AudioStreamPlayer = $"../SFX/PlantingSeed"
@onready var shoot_out_flower: AudioStreamPlayer = $"../SFX/ShootOutFlower"
@onready var throw_plant_grenade: AudioStreamPlayer = $"../SFX/ThrowPlantGrenade"
@onready var shovel_sfx: AudioStreamPlayer = $"../SFX/ShovelSfx"
@onready var hotbar_switching_2: AudioStreamPlayer = $"../SFX/HotbarSwitching2"
@onready var got_hurt: AudioStreamPlayer = $"../SFX/GotHurt"
var prev_on_floor: bool = false

# ---------------------------
# Timer Function for SFX
# ---------------------------
func play_sfx_delayed(
	player: AudioStreamPlayer,
	delay: float = 0.0,
	restart: bool = true
) -> void:
	if not player:
		return

	if restart and player.playing:
		player.stop()

	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	player.play()

# ---------------------------

func _ready() -> void:
	# Singleton بسيط
	if instance == null:
		instance = self
	else:
		queue_free()
		return

	# AnimationTree
	if animation_tree:
		animation_tree.active = true
		playback = animation_tree.get("parameters/playback")

	# نخفي كل الأسلحة في البداية
	hide_all_weapons()
	# نظهر السلاح الافتراضي (Shovel)
	switch_weapon(WeaponType.SHOVEL)
	
	# Load sunflower scene for planting
	sunflower_scene = load("res://Scene/Sunflower1.tscn")
	if not sunflower_scene:
		push_error("Failed to load Sunflower1.tscn!")
	
	# Initialize SpringArm3D for first-person camera mode
	if not spring_arm:
		spring_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	if spring_arm:
		default_spring_arm_position = spring_arm.position
		default_spring_length = spring_arm.spring_length
		target_spring_arm_position = default_spring_arm_position
		target_spring_length = default_spring_length
	else:
		push_warning("SpringArm3D not found! First-person camera mode will not work.")
	
	# Create planting cursor UI
	_create_plant_cursor()


func hide_all_weapons() -> void:
	if gun_model:
		gun_model.visible = false
	if grenade_model:
		grenade_model.visible = false
	if shovel_model:
		shovel_model.visible = false


func switch_weapon(weapon: WeaponType) -> void:
	current_weapon = weapon
	hide_all_weapons()
	
	# نظهر السلاح المختار
	match current_weapon:
		WeaponType.GUN:
			if gun_model:
				gun_model.visible = true
		WeaponType.GRENADE:
			if grenade_model:
				grenade_model.visible = true
		WeaponType.SHOVEL:
			if shovel_model:
				shovel_model.visible = true


func _process(delta: float) -> void:
	# نتحقق إذا الأنيميشن خلصت
	if is_acting and playback:
		var current_state: String = playback.get_current_node()
		var action_states: Array = ["Plant", "Throw Grenade", "Shoot"]
		
		# لو الأنيميشن من الأكشنات، نتحقق إذا خلصت
		if current_state in action_states:
			var pos: float = playback.get_current_play_position()
			var length: float = playback.get_current_length()
			# لو وصلنا لآخر الأنيميشن (مع هامش صغير)
			if length > 0 and pos >= length - 0.05:
				reset_action_state()
		# لو رجعنا للـ idle أو Run يعني الأنيميشن خلصت
		elif current_state == "idle" or current_state == "Run":
			reset_action_state()

	# تبديل السلاح بالأرقام 1، 2، 3 (regular keys or numpad)
	var kp_1_pressed = Input.is_key_pressed(KEY_KP_1)
	var kp_2_pressed = Input.is_key_pressed(KEY_KP_2)
	var kp_3_pressed = Input.is_key_pressed(KEY_KP_3)
	
	if Input.is_action_just_pressed("gun") or (kp_1_pressed and not prev_kp_1):
		switch_weapon(WeaponType.GUN)
		if hotbar_switching_2: hotbar_switching_2.play()
	elif Input.is_action_just_pressed("grenade") or (kp_2_pressed and not prev_kp_2):
		switch_weapon(WeaponType.GRENADE)
		if hotbar_switching_2: hotbar_switching_2.play()
	elif Input.is_action_just_pressed("shovel") or (kp_3_pressed and not prev_kp_3):
		switch_weapon(WeaponType.SHOVEL)
		if hotbar_switching_2: hotbar_switching_2.play()
	
	# Update previous key states
	prev_kp_1 = kp_1_pressed
	prev_kp_2 = kp_2_pressed
	prev_kp_3 = kp_3_pressed

	# اتجاه الإدخال (WASD)
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	# دوران الأرنب حسب الكاميرا + الحركة
	if camera:
		var camera_angle: float = camera.global_rotation.y
		var input_angle: float = atan2(input_dir.x, input_dir.y)
		if input_dir != Vector2.ZERO:
			target_angle = camera_angle + input_angle

	if model:
		model.global_rotation.y = lerp_angle(
			model.global_rotation.y,
			target_angle,
			delta * rotation_speed
		)

	var can_act: bool = (not is_dashing) and (not is_acting)

	# Dash (ما يندفع لو هو ماسك في الجدار)
	if Input.is_action_just_pressed("dash") and input_dir != Vector2.ZERO and can_act and not is_clinging:
		start_dash(input_dir)
		if dash_1: dash_1.play()

	# Left Click - يعمل الأكشن حسب السلاح المختار
	if Input.is_action_just_pressed("shoot") and can_act:
		perform_weapon_action()
	
	# Right Click - Grenade boost OR throw grenade
	if Input.is_action_just_pressed("grenade jump") and current_weapon == WeaponType.GRENADE and can_act:
		# Check if player is on floor - if yes, do grenade jump, if no, throw grenade
		if is_on_floor():
			# Apply 3x jump height upward velocity
			velocity.y = jump_velocity * 3.0
			if jump: jump.play()
		else:
			# Throw grenade when in air
			perform_weapon_action()
	
	# Hurt Animation (H key)
	if Input.is_action_just_pressed("hurt") and not is_hurting:
		play_hurt_animation()
		if got_hurt: got_hurt.play()
	
	# Update planting cursor position
	_update_plant_cursor()


# ---------------------------
# WEAPON ACTION (Left Click)
# ---------------------------
func perform_weapon_action() -> void:
	is_acting = true
	
	match current_weapon:
		WeaponType.GUN:
			start_shoot()
		WeaponType.GRENADE:
			start_throw()
		WeaponType.SHOVEL:
			start_plant()


func start_shoot() -> void:
	if animation_tree:
		animation_tree.set("parameters/conditions/is_shooting", true)
	if playback:
		playback.travel("Shoot")
		play_sfx_delayed(shoot_out_flower,0.4)
	
	# Spawn projectile after a short delay to match animation
	spawn_projectile_delayed(WeaponType.GUN, 0.2)


func start_throw() -> void:
	if animation_tree:
		animation_tree.set("parameters/conditions/is_throwing", true)
	if playback:
		playback.travel("Throw Grenade")
	play_sfx_delayed(throw_plant_grenade,0.5)
	
	# Spawn projectile after a short delay to match animation
	spawn_projectile_delayed(WeaponType.GRENADE, 0.3)

func start_plant() -> void:
	# Play animation
	if animation_tree:
		animation_tree.set("parameters/conditions/is_planting", true)
	if playback:
		playback.travel("Plant")
	
	# Play shovel sound effect
	if shovel_sfx:
		shovel_sfx.play()
	
	# Actually plant the flower
	plant_flower_at_cursor()
	


func reset_action_state() -> void:
	is_acting = false
	
	# Reset all action parameters
	if animation_tree:
		animation_tree.set("parameters/conditions/is_shooting", false)
		animation_tree.set("parameters/conditions/is_throwing", false)
		animation_tree.set("parameters/conditions/is_planting", false)


# ---------------------------
# First-Person Camera Position Update
# ---------------------------
func _update_camera_position() -> void:
	if not spring_arm:
		return
	
	# Calculate target position and spring length based on current weapon
	if current_weapon == WeaponType.GUN:
		# First-person mode: camera at head/eye level, centered
		target_spring_arm_position = Vector3(
			default_spring_arm_position.x,  # Keep X centered
			default_spring_arm_position.y + first_person_height,  # Raise to head/eye level
			default_spring_arm_position.z  # Keep Z centered
		)
		target_spring_length = 0.0  # Disable spring physics for locked first-person view
		
		# Hide character model in first-person mode for better immersion
		if model:
			model.visible = false
	else:
		# Third-person mode: return to default position and spring length
		target_spring_arm_position = default_spring_arm_position
		target_spring_length = default_spring_length
		
		# Show character model in third-person mode
		if model:
			model.visible = true
	
	# Kill existing tweens if they exist
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
	if spring_length_tween and spring_length_tween.is_valid():
		spring_length_tween.kill()
	
	# Create new tween for smooth position transition
	camera_tween = create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_SINE)
	
	# Calculate transition duration based on distance and speed
	var distance: float = spring_arm.position.distance_to(target_spring_arm_position)
	var duration: float = distance / camera_transition_speed
	duration = clamp(duration, 0.1, 1.0)  # Clamp between 0.1 and 1.0 seconds
	
	# Tween the position
	camera_tween.tween_property(spring_arm, "position", target_spring_arm_position, duration)
	
	# Create new tween for smooth spring length transition
	spring_length_tween = create_tween()
	spring_length_tween.set_ease(Tween.EASE_IN_OUT)
	spring_length_tween.set_trans(Tween.TRANS_SINE)
	
	# Tween the spring length
	spring_length_tween.tween_property(spring_arm, "spring_length", target_spring_length, duration)


func _on_action_animation_finished() -> void:
	reset_action_state()


# ---------------------------
# AnimationTree Expression Helpers
# ---------------------------
func is_shooting() -> bool:
	return is_acting and current_weapon == WeaponType.GUN


func is_throwing() -> bool:
	return is_acting and current_weapon == WeaponType.GRENADE


func is_planting() -> bool:
	return is_acting and current_weapon == WeaponType.SHOVEL


# ---------------------------
# HURT ANIMATION
# ---------------------------
func play_hurt_animation() -> void:
	if not model or is_hurting:
		return
	
	is_hurting = true
	
	# إلغاء أي tween سابق
	if hurt_tween and hurt_tween.is_valid():
		hurt_tween.kill()
	if color_tween and color_tween.is_valid():
		color_tween.kill()
	
	# --- Rotation Tween ---
	hurt_tween = create_tween()
	var hurt_rad: float = deg_to_rad(hurt_angle)
	
	# ميل للأمام (نصف المدة)
	hurt_tween.tween_property(model, "rotation:z", hurt_rad, hurt_duration / 2.0).set_ease(Tween.EASE_OUT)
	# رجوع للوضع الطبيعي (نصف المدة)
	hurt_tween.tween_property(model, "rotation:z", 0.0, hurt_duration / 2.0).set_ease(Tween.EASE_IN)
	
	# لما يخلص
	hurt_tween.tween_callback(func(): is_hurting = false)
	
	# --- Color Flash ---
	flash_color_on_meshes()


func flash_color_on_meshes() -> void:
	var meshes: Array = get_all_mesh_instances(model)
	
	for mesh in meshes:
		if mesh is MeshInstance3D:
			# نحفظ الماتيريال الأصلية ونعمل نسخة
			for i in range(mesh.get_surface_override_material_count()):
				var original_mat = mesh.get_active_material(i)
				if original_mat:
					var mat_copy = original_mat.duplicate()
					if mat_copy is StandardMaterial3D or mat_copy is ORMMaterial3D:
						mesh.set_surface_override_material(i, mat_copy)
						
						# Color tween للماتيريال
						color_tween = create_tween()
						color_tween.tween_property(mat_copy, "albedo_color", hurt_color, 0.05)
						color_tween.tween_property(mat_copy, "albedo_color", Color.WHITE, hurt_duration - 0.05)
						color_tween.tween_callback(func(): 
							mesh.set_surface_override_material(i, null)
						)


func get_all_mesh_instances(node: Node) -> Array:
	var meshes: Array = []
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		meshes.append_array(get_all_mesh_instances(child))
	return meshes


# يمكن استدعاؤها من أي مكان (مثلاً عند التصادم مع عدو)
func take_damage() -> void:
	play_hurt_animation()


# ---------------------------
# EXPLOSION FORCE
# ---------------------------
func apply_explosion_force(direction: Vector3, force: float) -> void:
	# Normalize direction and ensure upward component
	var normalized_dir = direction.normalized()
	
	# Apply upward velocity component (3x jump height)
	# The force already accounts for 3x jump height, so we use it directly
	velocity.y = force
	
	# Apply horizontal velocity component based on direction from explosion
	# Scale horizontal component to be proportional but not too strong
	var horizontal_force = force * 0.6  # 60% of vertical force for horizontal push
	velocity.x += normalized_dir.x * horizontal_force
	velocity.z += normalized_dir.z * horizontal_force


# ---------------------------
# DASH
# ---------------------------
func start_dash(input_dir: Vector2) -> void:
	is_dashing = true
	dash_timer = DASH_DURATION

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if camera:
		direction = direction.rotated(Vector3.UP, camera.global_rotation.y)
	dash_direction = direction

	velocity.x = dash_direction.x * DASH_SPEED
	velocity.z = dash_direction.z * DASH_SPEED
	velocity.y = 0.0



# ---------------------------
# PHYSICS: MOVE / JUMP / DASH / WALL-CLING
# ---------------------------
func _physics_process(delta: float) -> void:
	# نقرأ اتجاه الـ WASD في البداية
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")

	# ----- WALL CLING (E) – الأرنب يمسك في المكعب -----
	if is_clinging:
		# يترك المكعب لو:
		# 1) ترك زر E أو
		# 2) ما عاد فيه جدار قدامه
		if not Input.is_key_pressed(KEY_E) or not is_on_wall():
			is_clinging = false
		else:
			# ماسك في الجدار: نوقف السرعة والجاذبية
			velocity = Vector3.ZERO
			move_and_slide()
			return
	else:
		# يدخل وضع التعلّق لو:
		# في الهواء + لامس جدار + ضاغط E
		if not is_on_floor() and is_on_wall() and Input.is_key_pressed(KEY_E):
			is_clinging = true
			velocity = Vector3.ZERO
			move_and_slide()
			return

	# ----- DASH -----
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			velocity.x = dash_direction.x * DASH_SPEED
			velocity.z = dash_direction.z * DASH_SPEED
			move_and_slide()
			return

	# ----- GRAVITY -----
	if not is_on_floor():
		# سقوط أسرع لما ينزل (fall_multiplier)
		if velocity.y < 0:
			velocity.y -= gravity * fall_multiplier * delta
		else:
			velocity.y -= gravity * delta

	# ----- JUMP (Space / ui_accept) -----
	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor():
			# Regular jump from floor
			velocity.y = jump_velocity
			if jump: jump.play()
		elif has_double_jump:
			# Double jump in air
			velocity.y = double_jump_velocity
			has_double_jump = false
			if jump: jump.play()

	# ----- MOVEMENT (WASD) -----
	var direction: Vector3 = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		# Calculate direction relative to camera
		direction = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		if camera:
			direction = direction.rotated(Vector3.UP, camera.global_rotation.y)

	# Calculate target velocity
	var target_velocity: Vector3 = direction * speed

	# Smoothly accelerate/decelerate towards target velocity
	var current_velocity_xz = Vector2(velocity.x, velocity.z)
	var target_velocity_xz = Vector2(target_velocity.x, target_velocity.z)
	
	# Use move_toward for predictable, smooth movement
	if direction != Vector3.ZERO:
		# Accelerate towards target speed
		current_velocity_xz = current_velocity_xz.move_toward(target_velocity_xz, acceleration * delta)
	else:
		# Decelerate to zero
		current_velocity_xz = current_velocity_xz.move_toward(Vector2.ZERO, friction * delta)

	velocity.x = current_velocity_xz.x
	velocity.z = current_velocity_xz.y

	move_and_slide()
	
	# -------- LANDING SOUND (state-change-based) --------
	var on_floor := is_on_floor()

	if on_floor and not prev_on_floor:
		if drop and not drop.playing:
			drop.play()
		# Reset double jump when landing
		has_double_jump = true

	prev_on_floor = on_floor

	# ----- FOOTSTEP SFX -----
	var on_ground: bool = is_on_floor()
	var is_moving: bool = input_dir != Vector2.ZERO or abs(velocity.x) > 0.1 or abs(velocity.z) > 0.1
	
	if on_ground and is_moving:
		if walking_on_grass_ver_1_ and not walking_on_grass_ver_1_.playing:
			walking_on_grass_ver_1_.play()
	else:
		if walking_on_grass_ver_1_ and walking_on_grass_ver_1_.playing:
			walking_on_grass_ver_1_.stop()


# ---------------------------
# FLOOR INDICATOR (3D square outline snapped to grid)
# ---------------------------
func _create_plant_cursor() -> void:
	if not show_floor_indicator:
		return
	
	# Use call_deferred to ensure scene tree is ready
	call_deferred("_create_floor_indicator_deferred")


func _create_floor_indicator_deferred() -> void:
	# Create material for the outline
	floor_indicator_material = StandardMaterial3D.new()
	floor_indicator_material.albedo_color = indicator_color
	floor_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_indicator_material.no_depth_test = true  # Always render on top
	
	# Create parent node for the outline
	floor_indicator = Node3D.new()
	floor_indicator.name = "FloorIndicator"
	
	# Create 4 box meshes to form a square outline
	var cell_size: float = 1.0  # Default cell size, will be updated based on GridMap
	_create_outline_boxes(cell_size)
	
	# Add to scene root
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(floor_indicator)
		floor_indicator.visible = false
	else:
		push_error("Could not create floor indicator - no scene root")


func _create_outline_boxes(cell_size: float) -> void:
	# Clear existing children
	for child in floor_indicator.get_children():
		child.queue_free()
	
	var line_width: float = indicator_line_width
	var line_height: float = 0.03  # Very thin outline
	# Y = 0 means the center of the box is at floor level
	# So we need to offset by half height so BOTTOM of box is at floor level
	var y_offset: float = line_height * 0.5
	
	# Create 4 sides of the square outline
	var sides: Array = [
		# [position_offset, size] for each side
		{"pos": Vector3(0, y_offset, -cell_size/2 + line_width/2), "size": Vector3(cell_size, line_height, line_width)},  # Front
		{"pos": Vector3(0, y_offset, cell_size/2 - line_width/2), "size": Vector3(cell_size, line_height, line_width)},   # Back
		{"pos": Vector3(-cell_size/2 + line_width/2, y_offset, 0), "size": Vector3(line_width, line_height, cell_size)},  # Left
		{"pos": Vector3(cell_size/2 - line_width/2, y_offset, 0), "size": Vector3(line_width, line_height, cell_size)},   # Right
	]
	
	for side in sides:
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = side.size
		
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = box_mesh
		mesh_instance.material_override = floor_indicator_material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.position = side.pos
		
		floor_indicator.add_child(mesh_instance)


func _update_plant_cursor() -> void:
	if not show_floor_indicator:
		return
	
	# Wait for indicator to be created
	if not floor_indicator or not is_instance_valid(floor_indicator):
		return
	
	# Only show indicator when shovel (planting tool) is equipped
	var show_indicator: bool = current_weapon == WeaponType.SHOVEL
	
	if not show_indicator:
		floor_indicator.visible = false
		return
	
	# Get camera for raycasting
	var cam: Camera3D = raycast_camera if raycast_camera else camera
	if not cam:
		floor_indicator.visible = false
		return
	
	# Get mouse position and viewport info
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Cast ray to find floor position
	var floor_hit: Dictionary = raycast_to_floor(mouse_pos, viewport_size, cam)
	
	if floor_hit.is_empty():
		# No floor found - hide indicator
		floor_indicator.visible = false
		return
	
	# Check if we hit a GridMap - snap to cell
	var collider = floor_hit.collider
	var hit_y: float = floor_hit.position.y  # Use the exact floor Y from raycast
	
	if collider is GridMap:
		var gridmap: GridMap = collider as GridMap
		var cell_size: Vector3 = gridmap.cell_size
		
		# Convert hit position to GridMap local space
		var local_hit: Vector3 = gridmap.to_local(floor_hit.position)
		
		# Get the cell coordinates
		var cell_coords: Vector3i = gridmap.local_to_map(local_hit)
		
		# Only update if cell changed (optimization)
		if cell_coords != current_grid_cell:
			current_grid_cell = cell_coords
			# Rebuild outline with correct cell size
			_create_outline_boxes(cell_size.x)
		
		# Get the cell center position in local space (for X and Z only)
		var cell_center_local: Vector3 = gridmap.map_to_local(cell_coords)
		
		# Convert cell center to global for X and Z
		var cell_center_global: Vector3 = gridmap.to_global(cell_center_local)
		
		# Use raycast hit Y (exact floor surface) with cell center X/Z
		floor_indicator.global_position = Vector3(cell_center_global.x, hit_y, cell_center_global.z)
		floor_indicator.global_rotation = gridmap.global_rotation
		floor_indicator.visible = true
	else:
		# Non-GridMap floor - position exactly at hit point
		floor_indicator.visible = true
		floor_indicator.global_position = floor_hit.position
		floor_indicator.rotation = Vector3.ZERO
	
	# Set color
	floor_indicator_material.albedo_color = indicator_color


# ---------------------------
# FLOWER PLANTING
# ---------------------------
func plant_flower_at_cursor() -> void:
	# Use raycast_camera (SpringArm3D/Camera3D) if available, otherwise use main camera
	var cam: Camera3D = raycast_camera if raycast_camera else camera
	
	if not cam:
		push_error("No camera assigned for planting! Set raycast_camera to SpringArm3D/Camera3D")
		return
	
	if sunflower_scene == null:
		push_error("Sunflower scene not loaded!")
		return
	
	# Get mouse position and viewport info
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Cast ray from camera to find the floor surface
	var floor_hit: Dictionary = raycast_to_floor(mouse_pos, viewport_size, cam)
	
	if floor_hit.is_empty():
		return
	
	# Get the floor surface position and apply offset
	var ground_pos: Vector3 = floor_hit.position
	ground_pos.y += flower_y_offset
	
	# Check distance limit
	var distance_to_plant = global_position.distance_to(ground_pos)
	if distance_to_plant > max_plant_distance:
		# Plant is too far away, don't plant
		return
	
	# Create and place the flower - snaps to the actual floor block
	var flower: Node3D = sunflower_scene.instantiate()
	get_tree().current_scene.add_child(flower)
	flower.global_position = ground_pos
	
	# Check if planted on radiation location and notify GameManager
	if GameManager.instance and GameManager.instance.is_radiation_location(ground_pos, floor_hit.collider):
		GameManager.instance.on_radiation_cleared()


func raycast_to_floor(mouse_pos: Vector2, viewport_size: Vector2, cam: Camera3D) -> Dictionary:
	# Always use manual ray calculation - more reliable with SpringArm3D setup
	# The camera's project_ray functions don't work well when camera isn't "current"
	
	var ray_origin: Vector3 = cam.global_position
	
	# Normalize mouse position to -1 to 1 range (NDC - Normalized Device Coordinates)
	var ndc: Vector2 = (mouse_pos / viewport_size) * 2.0 - Vector2.ONE
	ndc.y = -ndc.y  # Flip Y axis (screen Y is inverted from 3D Y)
	
	# Calculate ray direction based on camera's perspective projection
	var fov_rad: float = deg_to_rad(cam.fov)
	var aspect: float = viewport_size.x / viewport_size.y
	
	# Direction in camera local space (pointing forward into the scene)
	var local_dir: Vector3 = Vector3(
		ndc.x * tan(fov_rad * 0.5) * aspect,
		ndc.y * tan(fov_rad * 0.5),
		-1.0  # Camera looks down -Z axis
	).normalized()
	
	# Transform to world space using camera's rotation
	var ray_dir: Vector3 = cam.global_transform.basis * local_dir
	
	# Perform physics raycast to find the floor
	var ray_end: Vector3 = ray_origin + ray_dir * plant_ray_length
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = ground_collision_mask  # Only hit ground/gridmap layers
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [self.get_rid()]  # Exclude the player from raycast
	
	var result: Dictionary = space_state.intersect_ray(query)
	
	if result.is_empty():
		return {}
	
	return {
		"position": result.position,
		"normal": result.normal,
		"collider": result.collider
	}


# ---------------------------
# PROJECTILE SPAWNING
# ---------------------------
func spawn_projectile_delayed(weapon_type: WeaponType, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	spawn_projectile(weapon_type)


# ---------------------------
# TRAJECTORY CALCULATION
# ---------------------------
func calculate_trajectory_velocity(spawn_pos: Vector3, target_pos: Vector3, arc_height: float = 3.0) -> Vector3:
	"""
	Calculate initial velocity for a parabolic trajectory.
	spawn_pos: Starting position
	target_pos: Target landing position
	arc_height: Maximum height of the arc above the higher of the two points
	Returns: Initial velocity vector for RigidBody3D
	"""
	var horizontal_vec = Vector3(target_pos.x - spawn_pos.x, 0, target_pos.z - spawn_pos.z)
	var horizontal_distance = horizontal_vec.length()
	var vertical_distance = target_pos.y - spawn_pos.y
	
	# Calculate time to reach target (using physics: t = sqrt(2h/g) for upward, then add horizontal time)
	# We want the projectile to reach arc_height, then fall to target
	var max_height = max(spawn_pos.y, target_pos.y) + arc_height
	var height_to_peak = max_height - spawn_pos.y
	var height_from_peak = max_height - target_pos.y
	
	# Time to reach peak: t_up = sqrt(2 * height_to_peak / g)
	var g = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var t_up = sqrt(2.0 * height_to_peak / g) if height_to_peak > 0 else 0.0
	var t_down = sqrt(2.0 * height_from_peak / g) if height_from_peak > 0 else 0.0
	var total_time = t_up + t_down
	
	# If total_time is too small, use a minimum time based on horizontal distance
	if total_time < 0.1:
		total_time = max(0.5, horizontal_distance / 10.0)
	
	# Calculate horizontal velocity: v_x = distance / time
	var horizontal_dir = horizontal_vec.normalized() if horizontal_distance > 0.01 else Vector3(1, 0, 0)
	var horizontal_velocity = horizontal_dir * (horizontal_distance / total_time)
	
	# Calculate vertical velocity: v_y = sqrt(2 * g * height_to_peak)
	var vertical_velocity = sqrt(2.0 * g * height_to_peak) if height_to_peak > 0 else 0.0
	
	# If we need to go down, we still need upward velocity to reach the arc
	# Adjust vertical velocity to account for the target being lower
	if vertical_distance < 0:
		# Need extra upward velocity to compensate for downward target
		var extra_velocity = sqrt(2.0 * g * abs(vertical_distance))
		vertical_velocity += extra_velocity * 0.5
	
	return Vector3(horizontal_velocity.x, vertical_velocity, horizontal_velocity.z)


func spawn_projectile(weapon_type: WeaponType) -> void:
	# Get spawn position (gun/grenade model or hand position)
	var spawn_pos = get_spawn_position(weapon_type)
	
	# Get camera for raycasting
	var cam = raycast_camera if raycast_camera else camera
	if not cam:
		push_error("No camera available for projectile spawning!")
		return
	
	# Use mouse raycast to determine target position
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var floor_hit: Dictionary = raycast_to_floor(mouse_pos, viewport_size, cam)
	
	# Get camera forward direction
	var forward = -cam.global_transform.basis.z
	
	# If no floor hit, use camera forward direction as fallback
	var target_pos: Vector3
	if floor_hit.is_empty():
		# Fallback: aim forward from camera
		var fallback_distance = 15.0 if weapon_type == WeaponType.GUN else 20.0
		target_pos = spawn_pos + forward * fallback_distance
		target_pos.y = spawn_pos.y  # Keep same height
	else:
		target_pos = floor_hit.position
	
	# Add forward offset to land ahead of aim point
	var forward_offset_distance = 1.5 if weapon_type == WeaponType.GUN else 2.0  # Grenades land further ahead
	target_pos = target_pos + forward * forward_offset_distance
	
	# For gun mode, adjust target to be mostly horizontal (slight upward angle)
	if weapon_type == WeaponType.GUN:
		# Keep target at similar height to spawn (slight upward angle)
		var horizontal_to_target = Vector3(target_pos.x - spawn_pos.x, 0, target_pos.z - spawn_pos.z)
		var horizontal_dist = horizontal_to_target.length()
		# Add slight upward offset based on distance (realistic gun trajectory)
		var upward_offset = horizontal_dist * 0.05  # 5% upward angle
		target_pos.y = spawn_pos.y + upward_offset
	
	# For grenades, ensure minimum throw distance from spawn position
	if weapon_type == WeaponType.GRENADE:
		var to_target = target_pos - spawn_pos
		var horizontal_dist = Vector3(to_target.x, 0, to_target.z).length()
		var min_throw_distance = 8.0  # Minimum distance for grenades
		if horizontal_dist < min_throw_distance:
			# Extend the target position to ensure minimum throw distance
			var horizontal_dir = Vector3(to_target.x, 0, to_target.z).normalized()
			target_pos = spawn_pos + horizontal_dir * min_throw_distance
			target_pos.y = target_pos.y  # Keep the Y from original target
	
	# Calculate arc height (very small for gun, higher for grenades)
	var arc_height = 0.3 if weapon_type == WeaponType.GUN else 4.0
	
	# Calculate trajectory velocity
	var initial_velocity = calculate_trajectory_velocity(spawn_pos, target_pos, arc_height)
	
	# For gun mode, prioritize horizontal velocity with minimal vertical component
	if weapon_type == WeaponType.GUN:
		var horizontal_vel = Vector3(initial_velocity.x, 0, initial_velocity.z)
		var horizontal_speed = horizontal_vel.length()
		# Ensure minimum horizontal speed for realistic gun
		if horizontal_speed < 15.0:
			var horizontal_dir = horizontal_vel.normalized() if horizontal_speed > 0.01 else forward
			horizontal_speed = 15.0
			horizontal_vel = horizontal_dir * horizontal_speed
		# Keep vertical velocity small (just slight upward angle)
		var vertical_vel = min(initial_velocity.y, 2.0)  # Cap vertical velocity at 2.0
		initial_velocity = Vector3(horizontal_vel.x, vertical_vel, horizontal_vel.z)
	
	# For grenades, ensure minimum velocity to throw it away from player
	if weapon_type == WeaponType.GRENADE:
		var min_velocity = 8.0  # Minimum horizontal velocity
		var horizontal_vel = Vector3(initial_velocity.x, 0, initial_velocity.z)
		if horizontal_vel.length() < min_velocity:
			# Increase horizontal velocity while maintaining direction
			var horizontal_dir = horizontal_vel.normalized() if horizontal_vel.length() > 0.01 else forward
			initial_velocity = Vector3(horizontal_dir.x * min_velocity, initial_velocity.y, horizontal_dir.z * min_velocity)
	
	# Create projectile node directly using the inner class
	var projectile = create_flower_projectile()
	
	# Configure RigidBody3D properties
	projectile.lock_rotation = true
	projectile.contact_monitor = true
	projectile.max_contacts_reported = 10
	projectile.gravity_scale = 1.0
	
	# Pass the existing sunflower_scene from player (which loads Sunflower1.tscn)
	projectile.flower_scene = sunflower_scene
	# Pass ground collision mask
	projectile.ground_collision_mask = ground_collision_mask
	# Pass weapon type to identify grenades
	projectile.weapon_type = weapon_type
	# Pass player instance reference for explosion effects
	projectile.player_instance = instance
	# Set explosion force for grenades (3x jump height)
	if weapon_type == WeaponType.GRENADE:
		projectile.explosion_force = jump_velocity * 3.0
	
	# Set properties that don't require scene tree
	projectile.initial_velocity = initial_velocity
	
	# Now add to scene tree FIRST (required before accessing global_position)
	if not get_tree() or not get_tree().current_scene:
		push_error("No scene tree or current scene!")
		return
	
	get_tree().current_scene.add_child(projectile)
	
	# NOW set position after it's in the tree
	projectile.global_position = spawn_pos
	
	# Exclude player from collisions to prevent player from being pushed by projectile
	# Must be done after adding to scene tree
	if instance and is_instance_valid(instance):
		projectile.add_collision_exception_with(instance)
	
	# Apply velocity after node is in scene tree (in case _ready() already ran)
	# This ensures velocity is applied even if _ready() was called before initial_velocity was set
	# Use call_deferred to ensure physics is ready
	call_deferred("_apply_projectile_velocity", projectile, initial_velocity)


func _apply_projectile_velocity(projectile: FlowerProjectile, velocity: Vector3) -> void:
	if projectile and is_instance_valid(projectile):
		if velocity != Vector3.ZERO:
			projectile.linear_velocity = velocity


func get_spawn_position(weapon_type: WeaponType) -> Vector3:
	# Try to get spawn position from weapon model
	var weapon_model: Node3D = null
	match weapon_type:
		WeaponType.GUN:
			weapon_model = gun_model
		WeaponType.GRENADE:
			weapon_model = grenade_model
		WeaponType.SHOVEL:
			weapon_model = shovel_model
	
	var cam = raycast_camera if raycast_camera else camera
	var forward = Vector3.ZERO
	if cam:
		forward = -cam.global_transform.basis.z
	
	# If weapon model exists and is visible, use its position
	if weapon_model and weapon_model.visible:
		# Try to find a child node that represents the muzzle/throw point
		# For now, use the model's global position with forward offset
		var forward_offset_distance = 0.3 if weapon_type == WeaponType.GUN else 0.8  # Grenades spawn further forward
		var forward_offset = Vector3(0, 0, -forward_offset_distance)
		var local_offset = weapon_model.global_transform.basis * forward_offset
		return weapon_model.global_position + local_offset
	
	# Fallback: use player position with offset
	if cam:
		# Spawn in front of camera, further for grenades
		var forward_distance = 0.5 if weapon_type == WeaponType.GUN else 1.2
		return global_position + Vector3(0, 1.0, 0) + forward * forward_distance
	
	# Last resort: player position
	return global_position + Vector3(0, 1.0, 0)
