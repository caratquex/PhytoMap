extends Area3D

# 三种拾取物的enum
enum CollectibleType {DIAMOND, COIN, CHERRY}
@export var type: CollectibleType

# 三种拾取物对应的模型
@export var diamond_model: PackedScene
@export var coin_model: PackedScene
@export var cherry_model: PackedScene

# 拾取物模型的自转速度和浮动动画
@export var rotation_speed: float = 0.5
@export var floating_speed: float = 0.01
@export var floating_magnitude: float = 0.05
var original_y: float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	original_y = position.y    # 获得节点的初始Y轴位置
	
	type = randi_range(0, 2)    # 随机设置拾取物的类型
	var model: PackedScene
	# 基于拾取物类型，设置正确的模型文件
	match type:
		CollectibleType.DIAMOND:
			model = diamond_model
		CollectibleType.COIN:
			model = coin_model
		CollectibleType.CHERRY:
			model = cherry_model
		_:
			printerr('Invalid type!')
	
	# 生成模型节点
	var node = model.instantiate()
	add_child(node)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	rotation.y += rotation_speed * delta    # 控制节点旋转
	position.y = original_y + sin(Time.get_ticks_msec() * floating_speed) * floating_magnitude    # 控制模型上下浮动
	


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		queue_free()
		GameManager.instance.collect_item(CollectibleType.find_key(type))
		
		
