extends SpringArm3D

@export var mouse_sensitivity: float = 0.005

func _ready() -> void:
	# 在游戏开始时，锁定光标
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _input(event: InputEvent) -> void:
	# 检测鼠标移动并旋转视角
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_delta = event.relative
		rotation.y -= mouse_delta.x * mouse_sensitivity
		rotation.x -= mouse_delta.y * mouse_sensitivity
		rotation.x = clamp(rotation.x, -PI/2, PI/4)
	
	# 检测Tab键并开启/关闭光标锁定
	if event is InputEventKey:
		if event.keycode == KEY_TAB and event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
