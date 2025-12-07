extends CharacterBody3D
# ما في class_name عشان ما يصير تعارض

static var instance: CharacterBody3D

# ---------------------------
# Movement
# ---------------------------
const GRAVITY: float = 9.8
@export var speed: float = 4.0
@export var jump_velocity: float = 8.0      # نطة أقوى (غيّر الرقم لو تبغيه أقوى/أضعف)
@export var rotation_speed: float = 5.0     # سرعة لف الأرنب
@export var gun_visible_time: float = 0.15  # كم ثانية السلاح يبان بعد الإطلاق
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
var is_shooting: bool = false
var is_throwing: bool = false
var is_clinging: bool = false      # الأرنب ماسك في المكعب / الجدار

var playback: AnimationNodeStateMachinePlayback
var target_angle: float = PI

# مؤقّت يظهر السلاح لفترة قصيرة ثم يخفيه
var gun_timer: float = 0.0


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

	# نخفي الأسلحة في البداية
	if gun_model:
		gun_model.visible = false
	if grenade_model:
		grenade_model.visible = false


func _process(delta: float) -> void:
	# مؤقّت إظهار السلاح
	if gun_timer > 0.0:
		gun_timer -= delta
		if gun_timer <= 0.0:
			reset_weapon_state()  # يخفي السلاح ويرجع اليد للوضع الطبيعي

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

	var can_act: bool = (not is_dashing) and (not is_throwing)

	# Dash (ما يندفع لو هو ماسك في الجدار)
	if Input.is_action_just_pressed("dash") and input_dir != Vector2.ZERO and can_act and not is_clinging:
		start_dash(input_dir)

	# Shoot
	if Input.is_action_just_pressed("shoot") and can_act:
		start_shoot()

	# Throw
	if Input.is_action_just_pressed("throw") and can_act:
		start_throw()


# ---------------------------
# SHOOT
# ---------------------------
func start_shoot() -> void:
	is_shooting = true

	# السلاح يطلع وقت الإطلاق
	if gun_model:
		gun_model.visible = true

	# نشغل مؤقّت صغير وبعده يختفي السلاح وترجع اليد
	gun_timer = gun_visible_time

	if animation_tree:
		animation_tree.set("parameters/is_shooting", true)
	if playback:
		playback.travel("Shoot")


func reset_weapon_state() -> void:
	# يرجع السلاح واليد للوضع الطبيعي (Idle / Run)
	is_shooting = false
	gun_timer = 0.0

	if gun_model:
		gun_model.visible = false

	if animation_tree:
		animation_tree.set("parameters/is_shooting", false)

	if playback:
		var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
		if input_dir != Vector2.ZERO:
			playback.travel("Run")
		else:
			playback.travel("Idle")


func _on_shoot_animation_finished() -> void:
	# لو خلصت الأنيميشن قبل التايمر، نرجّع الوضع برضه
	reset_weapon_state()


# ---------------------------
# THROW
# ---------------------------
func start_throw() -> void:
	is_throwing = true

	if grenade_model:
		grenade_model.visible = true

	if animation_tree:
		animation_tree.set("parameters/is_throwing", true)
	if playback:
		playback.travel("Throw")


func _on_throw_animation_finished() -> void:
	is_throwing = false

	if grenade_model:
		grenade_model.visible = false

	if animation_tree:
		animation_tree.set("parameters/is_throwing", false)


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
