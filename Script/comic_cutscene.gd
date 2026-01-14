extends Node2D

const LEVEL_1_PATH: String = "res://Map/Level 1.tscn"

@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	# Connect to animation finished signal
	animation_player.animation_finished.connect(_on_animation_finished)


func _on_animation_finished(anim_name: StringName) -> void:
	# When the cutscene animation finishes, transition to Level 1
	if anim_name == "cutscene":
		get_tree().change_scene_to_file(LEVEL_1_PATH)
