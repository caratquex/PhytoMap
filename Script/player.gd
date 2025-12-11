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
const GRAVITY: float = 9.8
@export var speed: float = 4.0
@export var jump_velocity: float = 8.0      # نطة أقوى (غيّر الرقم لو تبغيه أقوى/أضعف)
@export var rotation_speed: float = 5.0     # سرعة لف الأرنب
@export var action_visible_time: float = 0.3  # كم ثانية السلاح يبان بعد الإطلاق
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

var playback: AnimationNodeStateMachinePlayback
var target_angle: float = PI

# مؤقّت يظهر السلاح لفترة قصيرة ثم يخفيه
var action_timer: float = 0.0


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
	# مؤقّت الأكشن
	if action_timer > 0.0:
		action_timer -= delta
		if action_timer <= 0.0:
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


# ---------------------------
# WEAPON ACTION (Left Click)
# ---------------------------
func perform_weapon_action() -> void:
	is_acting = true
	action_timer = action_visible_time
	
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
	action_timer = 0.0
	
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
		velocity.y -= GRAVITY * delta

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
