extends Node3D
class_name GameManager

# 游戏管理器单例
static var instance: GameManager

# 字典变量，记录每种拾取物分别捡起了多少个
@export var collected_items: Dictionary[String, int] = {
	'DIAMOND': 0,
	'COIN': 0,
	'CHERRY': 0,
}

@export var item_labels: Dictionary[String, Label]

# 数组变量，用于记录玩家激活了哪些检查点
var activated_checkpoints: Array[Checkpoint]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 如果instance为空，则设置这个GameManager节点为instance
	if instance == null:
		instance = self
	# 如果instance不为空，则删除该GameManager节点
	else:
		queue_free()
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func respawn_player(body: Node3D) -> void:
	if body is CharacterBody3D:
		if len(activated_checkpoints) == 0:
			Player.instance.position = Player.instance.spawn_position
		else:
			var closest_checkpoint = activated_checkpoints[0]
			var closest_distance = closest_checkpoint.position.distance_squared_to(Player.instance.position)
			
			for checkpoint in activated_checkpoints:
				var distance = checkpoint.position.distance_squared_to(Player.instance.position)
				if distance < closest_distance:
					closest_checkpoint = checkpoint
					closest_distance = distance
			
			Player.instance.position = closest_checkpoint.position + Vector3(0, 3, 0)
		

func collect_item(item_type):
	collected_items[item_type] += 1
	item_labels[item_type].text = str(collected_items[item_type])
	
	
