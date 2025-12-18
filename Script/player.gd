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
@onready var walking_on_grass_ver_1_: AudioStreamPlayer = $"../SFX/WalkingOnGrass(ver1)"
@onready var jump: AudioStreamPlayer = $"../SFX/Jump"
@onready var dash: AudioStreamPlayer = $"../SFX/Dash"
@onready var drop: AudioStreamPlayer = $"../SFX/Drop"

var prev_on_floor: bool = false

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

	# تبديل السلاح بالأرقام 1، 2، 3
	if Input.is_action_just_pressed("gun"):
		switch_weapon(WeaponType.GUN)
	elif Input.is_action_just_pressed("grenade"):
		switch_weapon(WeaponType.GRENADE)
	elif Input.is_action_just_pressed("shovel"):
		switch_weapon(WeaponType.SHOVEL)

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

	# Left Click - يعمل الأكشن حسب السلاح المختار
	if Input.is_action_just_pressed("shoot") and can_act:
		perform_weapon_action()
	
	# Hurt Animation (H key)
	if Input.is_action_just_pressed("hurt") and not is_hurting:
		play_hurt_animation()


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


func start_throw() -> void:
	if animation_tree:
		animation_tree.set("parameters/conditions/is_throwing", true)
	if playback:
		playback.travel("Throw Grenade")


func start_plant() -> void:
	# Play animation
	if animation_tree:
		animation_tree.set("parameters/conditions/is_planting", true)
	if playback:
		playback.travel("Plant")
	
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
