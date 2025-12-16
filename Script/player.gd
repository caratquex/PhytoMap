extends CharacterBody3D
# ما في class_name عشان ما يصير تعارض

static var instance: CharacterBody3D

# ---------------------------
# Weapon System
# ---------------------------
enum WeaponType { GUN = 1, GRENADE = 2, SHOVEL = 3 }
var current_weapon: WeaponType = WeaponType.SHOVEL  # Default is Shovel (Plant)

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
@onready var dash: AudioStreamPlayer = $"../SFX/dash"
@onready var drop: AudioStreamPlayer = $"../SFX/drop"


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
	if animation_tree:
		animation_tree.set("parameters/conditions/is_planting", true)
	if playback:
		playback.travel("Plant")


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
	
	
