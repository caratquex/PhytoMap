extends CanvasLayer

# ---------------------------
# Final Choice Overlay
# ---------------------------
# UI overlay that presents the player with two ending choices.
# Pauses the game and waits for player selection.

# ---------------------------
# Exports
# ---------------------------
@export var ending_a_video_path: String = "res://Cut Scene/Ending 1.ogv"
@export var ending_b_video_path: String = "res://Cut Scene/Ending 2.ogv"
@export var ending_video_player_scene: PackedScene  ## The video player scene

# ---------------------------
# Node References
# ---------------------------
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var ending_a_button: Button = $Panel/VBoxContainer/EndingAButton
@onready var ending_b_button: Button = $Panel/VBoxContainer/EndingBButton
@onready var background: ColorRect = $Background


func _ready() -> void:
	# Ensure this runs even when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect button signals
	if ending_a_button:
		ending_a_button.pressed.connect(_on_ending_a_pressed)
	if ending_b_button:
		ending_b_button.pressed.connect(_on_ending_b_pressed)
	
	# Ensure game is paused
	get_tree().paused = true
	
	# Capture mouse for UI interaction
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	print("[FinalChoiceOverlay] Displayed, waiting for player choice...")


func _on_ending_a_pressed() -> void:
	print("[FinalChoiceOverlay] Player chose Ending A")
	_play_ending_video(ending_a_video_path)


func _on_ending_b_pressed() -> void:
	print("[FinalChoiceOverlay] Player chose Ending B")
	_play_ending_video(ending_b_video_path)


func _play_ending_video(video_path: String) -> void:
	# Hide this overlay - CanvasLayer doesn't have visible property, hide children instead
	if panel:
		panel.hide()
	if background:
		background.hide()
	
	# Move this layer behind everything
	layer = -100
	
	if ending_video_player_scene:
		# Instantiate the video player scene
		var video_player_node = ending_video_player_scene.instantiate()
		
		# Set the video path BEFORE adding to tree (directly set the property)
		video_player_node.video_path = video_path
		print("[FinalChoiceOverlay] Set video_path to: %s" % video_path)
		
		# Add to scene tree - this triggers _ready() which will now see the video_path
		var scene_root = get_tree().current_scene
		if scene_root:
			scene_root.add_child(video_player_node)
			print("[FinalChoiceOverlay] Added EndingVideoPlayer to scene")
		
		# Clean up this overlay immediately (not deferred)
		get_parent().remove_child(self)
		queue_free()
	else:
		# No video player scene configured, fallback to menu
		push_warning("[FinalChoiceOverlay] No ending_video_player_scene assigned! Returning to menu.")
		_return_to_menu()


func _return_to_menu() -> void:
	# Unpause before scene change
	get_tree().paused = false
	
	# Return to main menu
	get_tree().change_scene_to_file("res://Scene/menu.tscn")
	
	# Clean up
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Consume all input to prevent game actions while overlay is shown
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
