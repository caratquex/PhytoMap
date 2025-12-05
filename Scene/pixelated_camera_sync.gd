extends Node3D

# Script to sync the pixelated camera with the SpringArm3D camera
@export var spring_arm_camera_path: NodePath = NodePath("../../../SpringArm3D/Camera3D")
@export var pixelated_camera: Camera3D

var spring_arm_camera: Camera3D

func _ready():
	spring_arm_camera = get_node(spring_arm_camera_path) as Camera3D
	if not pixelated_camera:
		pixelated_camera = get_node("Camera3D") as Camera3D
	
	if not spring_arm_camera or not pixelated_camera:
		push_error("Camera references not found!")
		return

func _process(_delta):
	if spring_arm_camera and pixelated_camera:
		# Sync position and rotation from SpringArm3D camera
		global_transform = spring_arm_camera.global_transform
		# Sync FOV and other camera properties
		pixelated_camera.fov = spring_arm_camera.fov
		pixelated_camera.size = spring_arm_camera.size

