extends Node2D

const LEVEL_1_PATH: String = "res://Map/Level 1.tscn"

@export var allow_skip: bool = true  ## Allow player to skip the cutscene

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var skip_label: Label = $UILayer/SkipLabel


func _ready() -> void:
	# Connect to animation finished signal
	animation_player.animation_finished.connect(_on_animation_finished)
	
	# Show/hide skip label
	if skip_label:
		skip_label.visible = allow_skip


func _unhandled_input(event: InputEvent) -> void:
	# Skip cutscene on key press or mouse click (if allowed)
	if allow_skip:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_skip_cutscene()
				var viewport = get_viewport()
				if viewport:
					viewport.set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_skip_cutscene()
				var viewport = get_viewport()
				if viewport:
					viewport.set_input_as_handled()


func _skip_cutscene() -> void:
	print("[ComicCutscene] Cutscene skipped by player")
	
	# Stop animation and audio
	if animation_player:
		animation_player.stop()
	
	# Stop any playing audio
	var narration1 = get_node_or_null("Narration1")
	var narration2 = get_node_or_null("Narration2")
	if narration1:
		narration1.stop()
	if narration2:
		narration2.stop()
	
	# Go to level
	get_tree().change_scene_to_file(LEVEL_1_PATH)


func _on_animation_finished(anim_name: StringName) -> void:
	# When the cutscene animation finishes, transition to Level 1
	if anim_name == "cutscene":
		get_tree().change_scene_to_file(LEVEL_1_PATH)
