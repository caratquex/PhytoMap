extends CharacterBody3D
# ما في class_name عشان ما يصير تعارض

static var instance: CharacterBody3D

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
@export var ground_collision_mask: int = 1  # Set to match your ground/gridmap collision layer
@export var flower_y_offset: float = 0.0  # Fine-tune flower height (0 = exactly at player's floor level)

# ---------------------------
# Floor Indicator (3D square outline snapped to grid)
# ---------------------------
@export var show_floor_indicator: bool = true
@export var indicator_color: Color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow like in the image
@export var indicator_line_width: float = 0.05  # Width of the outline
var floor_indicator: Node3D  # Parent node for the outline
var floor_indicator_material: StandardMaterial3D
var current_grid_cell: Vector3i = Vector3i(-99999, -99999, -99999)  # Track current cell

# ---------------------------
# Shooting Cursor (Crosshair)
# ---------------------------
@export var show_shoot_cursor: bool = true
@export var shoot_cursor_color: Color = Color(1.0, 0.0, 0.0, 1.0)  # Red crosshair
@export var shoot_cursor_size: float = 0.6  # Size of crosshair (larger for visibility)
@export var shoot_cursor_line_width: float = 0.08  # Width of crosshair lines (thicker for visibility)
var shoot_cursor: Node3D  # Parent node for the crosshair
var shoot_cursor_material: StandardMaterial3D
var current_shoot_target: Vector3  # Current target position for shooting

# ---------------------------
# Projectile System
# ---------------------------
@export var projectile_speed: float = 15.0  # Projectile travel speed

# ---------------------------
# Movement
# ---------------------------
@export var gravity: float = 12.0  # جاذبية أسرع قليلاً من الأصل
@export var fall_multiplier: float = 1.2  # تسريع السقوط خفيف جداً
@export var speed: float = 4.0
@export var jump_velocity: float = 8.5      # نطة قريبة من الأصل
@export var rotation_speed: float = 5.0     # سرعة لف الأرنب
@export var acceleration: float = 50.0       # سرعة التسارع عند الحركة (زيادة للاستجابة)
@export var friction: float = 60.0           # سرعة التباطؤ عند التوقف (زيادة للاستجابة)

# ---------------------------
# Nodes (عيّنها من الـ Inspector)
# ---------------------------
@export var camera: Camera3D
@export var raycast_camera: Camera3D  # Camera for raycasting (use SpringArm3D/Camera3D)
@export var model: Node3D
@export var animation_tree: AnimationTree

@export var gun_model: Node3D
@export var grenade_model: Node3D
@export var shovel_model: Node3D

# ---------------------------
# Shoulder Camera Shift
# ---------------------------
@export var spring_arm: SpringArm3D  # Reference to SpringArm3D node (set in Inspector)
@export var shoulder_offset_x: float = 2.5  # Horizontal offset to the right
@export var shoulder_offset_y: float = 0.0  # Vertical offset (if needed)
@export var shoulder_transition_speed: float = 5.0  # Speed of smooth transition
var default_spring_arm_position: Vector3  # Store default SpringArm3D position
var target_spring_arm_position: Vector3  # Target position for smooth transition
var camera_tween: Tween  # Tween for smooth camera movement

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
	
	# Initialize SpringArm3D for shoulder camera shift
	if not spring_arm:
		# Try to find SpringArm3D automatically if not assigned
		spring_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	if spring_arm:
		default_spring_arm_position = spring_arm.position
		target_spring_arm_position = default_spring_arm_position
	else:
		push_warning("SpringArm3D not found! Shoulder camera shift will not work.")
	
	# Create planting cursor UI
	_create_plant_cursor()
	# Create shooting cursor UI
	_create_shoot_cursor()


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
	
	# Update camera position based on weapon
	_update_camera_position()


func _update_camera_position() -> void:
	if not spring_arm:
		return
	
	# Calculate target position based on current weapon
	# SpringArm3D is a child of player, so position is in local space
	if current_weapon == WeaponType.GUN:
		# Shift to right shoulder position (positive X is right in local space)
		target_spring_arm_position = Vector3(
			default_spring_arm_position.x + shoulder_offset_x,
			default_spring_arm_position.y + shoulder_offset_y,
			default_spring_arm_position.z
		)
	else:
		# Return to default position
		target_spring_arm_position = default_spring_arm_position
	
	# Kill existing tween if it exists
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
	
	# Create new tween for smooth transition
	camera_tween = create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_SINE)
	
	# Calculate transition duration based on distance and speed
	var distance: float = spring_arm.position.distance_to(target_spring_arm_position)
	var duration: float = distance / shoulder_transition_speed
	duration = clamp(duration, 0.1, 1.0)  # Clamp between 0.1 and 1.0 seconds
	
	# Tween the position
	camera_tween.tween_property(spring_arm, "position", target_spring_arm_position, duration)


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

	# تبديل السلاح بالأرقام 1، 2، 3
	if Input.is_action_just_pressed("gun"):
		switch_weapon(WeaponType.GUN)
		if hotbar_switching_2: hotbar_switching_2.play()
	elif Input.is_action_just_pressed("grenade"):
		switch_weapon(WeaponType.GRENADE)
		if hotbar_switching_2: hotbar_switching_2.play()
	elif Input.is_action_just_pressed("shovel"):
		switch_weapon(WeaponType.SHOVEL)
		if hotbar_switching_2: hotbar_switching_2.play()

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
	
	# Hurt Animation (H key)
	if Input.is_action_just_pressed("hurt") and not is_hurting:
		play_hurt_animation()
		if got_hurt: got_hurt.play()
	
	# Update planting cursor position
	_update_plant_cursor()
	# Update shooting cursor position
	_update_shoot_cursor()


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
	
	# Launch projectile
	shoot_flower_projectile()


func start_throw() -> void:
	if animation_tree:
		animation_tree.set("parameters/conditions/is_throwing", true)
	if playback:
		playback.travel("Throw Grenade")
		play_sfx_delayed(throw_plant_grenade,0.5)

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
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
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
		print("Floor indicator created successfully")
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
# SHOOTING CURSOR (Crosshair)
# ---------------------------
func _create_shoot_cursor() -> void:
	if not show_shoot_cursor:
		return
	
	call_deferred("_create_shoot_cursor_deferred")


func _create_shoot_cursor_deferred() -> void:
	# Create material for the crosshair
	shoot_cursor_material = StandardMaterial3D.new()
	shoot_cursor_material.albedo_color = shoot_cursor_color
	shoot_cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shoot_cursor_material.no_depth_test = true  # Always render on top
	shoot_cursor_material.emission_enabled = true  # Enable emission for glow
	shoot_cursor_material.emission = shoot_cursor_color
	
	# Create parent node
	shoot_cursor = Node3D.new()
	shoot_cursor.name = "ShootCursor"
	
	# Create 2 intersecting lines (horizontal + vertical) to form crosshair
	var line_length: float = shoot_cursor_size
	var line_width: float = shoot_cursor_line_width
	var line_height: float = 0.1  # Thick crosshair for visibility
	
	# Horizontal line
	var horizontal_box: BoxMesh = BoxMesh.new()
	horizontal_box.size = Vector3(line_length, line_height, line_width)
	var horizontal_mesh: MeshInstance3D = MeshInstance3D.new()
	horizontal_mesh.mesh = horizontal_box
	horizontal_mesh.material_override = shoot_cursor_material
	horizontal_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	horizontal_mesh.position = Vector3(0, line_height * 0.5, 0)
	shoot_cursor.add_child(horizontal_mesh)
	
	# Vertical line
	var vertical_box: BoxMesh = BoxMesh.new()
	vertical_box.size = Vector3(line_width, line_height, line_length)
	var vertical_mesh: MeshInstance3D = MeshInstance3D.new()
	vertical_mesh.mesh = vertical_box
	vertical_mesh.material_override = shoot_cursor_material
	vertical_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vertical_mesh.position = Vector3(0, line_height * 0.5, 0)
	shoot_cursor.add_child(vertical_mesh)
	
	# Add to scene root
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(shoot_cursor)
		shoot_cursor.visible = false
	else:
		push_error("Could not create shooting cursor - no scene root")


func _update_shoot_cursor() -> void:
	if not show_shoot_cursor:
		return
	
	if not shoot_cursor or not is_instance_valid(shoot_cursor):
		return
	
	# Only show cursor when gun is equipped
	var show_cursor: bool = current_weapon == WeaponType.GUN
	
	if not show_cursor:
		shoot_cursor.visible = false
		return
	
	# Get camera for raycasting
	var cam: Camera3D = raycast_camera if raycast_camera else camera
	if not cam:
		shoot_cursor.visible = false
		return
	
	# Get mouse position and viewport info
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Cast ray to find floor position
	var floor_hit: Dictionary = raycast_to_floor(mouse_pos, viewport_size, cam)
	
	if floor_hit.is_empty():
		shoot_cursor.visible = false
		current_shoot_target = Vector3.ZERO
		return
	
	# Store target position
	current_shoot_target = floor_hit.position
	
	# Position crosshair at hit point (slightly above floor for visibility)
	var cursor_pos: Vector3 = floor_hit.position
	cursor_pos.y += 0.1  # Slight offset above floor
	shoot_cursor.global_position = cursor_pos
	
	# Align crosshair to face camera (billboard effect)
	if cam:
		var look_dir: Vector3 = (cam.global_position - shoot_cursor.global_position).normalized()
		shoot_cursor.look_at(shoot_cursor.global_position + look_dir, Vector3.UP)
	
	shoot_cursor.visible = true
	shoot_cursor_material.albedo_color = shoot_cursor_color


func shoot_flower_projectile() -> void:
	if sunflower_scene == null:
		push_error("Sunflower scene not loaded!")
		return
	
	# Check if we have a valid target
	if current_shoot_target == Vector3.ZERO:
		# Try to get current target from cursor
		var cam: Camera3D = raycast_camera if raycast_camera else camera
		if cam:
			var mouse_pos: Vector2 = get_viewport().get_mouse_position()
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			var floor_hit: Dictionary = raycast_to_floor(mouse_pos, viewport_size, cam)
			if not floor_hit.is_empty():
				current_shoot_target = floor_hit.position
			else:
				print("No valid target for shooting")
				return
		else:
			print("No camera for shooting")
			return
	
	# Get spawn position (from gun model or player position)
	var spawn_pos: Vector3 = global_position
	if gun_model:
		spawn_pos = gun_model.global_position
	else:
		# Spawn slightly above player
		spawn_pos.y += 1.0
	
	# Calculate direction to target
	var direction: Vector3 = (current_shoot_target - spawn_pos).normalized()
	
	# Create projectile wrapper (RigidBody3D)
	var projectile: RigidBody3D = RigidBody3D.new()
	projectile.name = "FlowerProjectile"
	projectile.gravity_scale = 1.0
	projectile.linear_damp = 0.0  # No air resistance
	
	# Create collision shape for projectile
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = 0.1  # Small collision sphere
	collision_shape.shape = sphere_shape
	projectile.add_child(collision_shape)
	
	# Instantiate flower and add as child (visible during flight as projectile)
	var flower: Node3D = sunflower_scene.instantiate()
	flower.name = "Flower"
	
	projectile.add_child(flower)
	
	# Add to scene first (must be in tree before setting global_position)
	get_tree().current_scene.add_child(projectile)
	
	# Set initial position and velocity
	projectile.global_position = spawn_pos
	projectile.linear_velocity = direction * projectile_speed
	
	# Check for floor collision using area detection
	var area: Area3D = Area3D.new()
	area.name = "ProjectileArea"
	var area_shape: CollisionShape3D = CollisionShape3D.new()
	var area_sphere: SphereShape3D = SphereShape3D.new()
	area_sphere.radius = 0.15
	area_shape.shape = area_sphere
	area.add_child(area_shape)
	projectile.add_child(area)
	
	# Set collision layers
	area.collision_layer = 0  # Don't collide with anything
	area.collision_mask = ground_collision_mask  # Detect ground
	
	# Connect area signal
	area.body_entered.connect(func(body): _on_projectile_area_collision(projectile, body))
	area.area_entered.connect(func(area_node): _on_projectile_area_collision(projectile, area_node))
	
	# Store reference to check for ground hits
	projectile.set_meta("flower_node", flower)
	projectile.set_meta("has_landed", false)
	
	# Add continuous ground check using timer
	var check_timer: Timer = Timer.new()
	check_timer.wait_time = 0.05  # Check every 0.05 seconds
	check_timer.timeout.connect(func(): _check_projectile_ground_proximity(projectile))
	check_timer.autostart = true
	projectile.add_child(check_timer)


func _on_projectile_area_collision(projectile: RigidBody3D, body: Node) -> void:
	# Check if it's the ground
	if body is StaticBody3D or body is GridMap:
		_handle_projectile_landing(projectile)


func _handle_projectile_landing(projectile: RigidBody3D) -> void:
	# Prevent multiple landings
	if projectile.get_meta("has_landed", false):
		return
	
	projectile.set_meta("has_landed", true)
	
	# Stop projectile physics
	projectile.freeze = true
	projectile.linear_velocity = Vector3.ZERO
	
	# Get the flower node
	var flower: Node3D = projectile.get_meta("flower_node", null)
	if not flower:
		projectile.queue_free()
		return
	
	# Get current position
	var hit_pos: Vector3 = projectile.global_position
	
	# Use raycast to get exact floor position (snap to grid)
	var cam: Camera3D = raycast_camera if raycast_camera else camera
	if cam:
		# Cast ray downward from projectile position
		var ray_origin: Vector3 = hit_pos + Vector3.UP * 2.0  # Start above
		var ray_end: Vector3 = hit_pos - Vector3.UP * 5.0  # Cast downward
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.collision_mask = ground_collision_mask
		query.collide_with_bodies = true
		query.collide_with_areas = false
		
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			hit_pos = result.position
			
			# Snap to grid if it's a GridMap
			var collider = result.collider
			if collider is GridMap:
				var gridmap: GridMap = collider as GridMap
				var local_hit: Vector3 = gridmap.to_local(hit_pos)
				var cell_coords: Vector3i = gridmap.local_to_map(local_hit)
				var cell_center_local: Vector3 = gridmap.map_to_local(cell_coords)
				var cell_center_global: Vector3 = gridmap.to_global(cell_center_local)
				hit_pos = Vector3(cell_center_global.x, result.position.y, cell_center_global.z)
	
	# Apply flower offset
	hit_pos.y += flower_y_offset
	
	# Remove flower from projectile
	projectile.remove_child(flower)
	
	# Remove projectile
	projectile.queue_free()
	
	# Add flower to scene at snapped position
	get_tree().current_scene.add_child(flower)
	flower.global_position = hit_pos
	
	# Play planting sound
	if planting_seed: planting_seed.play()
	
	print("Flower projectile landed and snapped to floor at: ", hit_pos)


func _check_projectile_ground_proximity(projectile: RigidBody3D) -> void:
	if projectile.get_meta("has_landed", false):
		return
	
	# Check if projectile is close to ground
	var pos: Vector3 = projectile.global_position
	var ray_origin: Vector3 = pos + Vector3.UP * 0.2
	var ray_end: Vector3 = pos - Vector3.UP * 2.0
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = ground_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	var result: Dictionary = space_state.intersect_ray(query)
	if not result.is_empty():
		var distance: float = pos.distance_to(result.position)
		# If very close to ground, trigger landing
		if distance < 0.5:
			_handle_projectile_landing(projectile)


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
		print("No floor found at click position")
		return
	
	# Get the floor surface position and apply offset
	var ground_pos: Vector3 = floor_hit.position
	ground_pos.y += flower_y_offset
	
	# Debug: Show what was hit and positions
	var collider_name: String = floor_hit.collider.name if floor_hit.collider else "unknown"
	print("=== FLOWER PLANT DEBUG ===")
	print("  Raycast hit collider: ", collider_name)
	print("  Hit position: ", floor_hit.position)
	print("  Camera position: ", cam.global_position)
	print("  Final flower Y: ", ground_pos.y)
	print("==========================")
	
	# Create and place the flower - snaps to the actual floor block
	var flower: Node3D = sunflower_scene.instantiate()
	get_tree().current_scene.add_child(flower)
	flower.global_position = ground_pos


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
	
	# Debug: print the actual hit position
	print("Raycast hit at Y=", result.position.y, " collider=", result.collider.name if result.collider else "unknown")
	
	return {
		"position": result.position,
		"normal": result.normal,
		"collider": result.collider
	}
