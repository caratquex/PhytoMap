extends CanvasLayer

# ---------------------------
# Ending Video Player
# ---------------------------
# Full-screen video player for ending cutscenes.
# Plays the selected ending video and returns to menu when finished.

# ---------------------------
# Exports
# ---------------------------
@export var video_path: String = ""  ## Path to the video file to play
@export var menu_scene_path: String = "res://Scene/menu.tscn"  ## Path to return to after video
@export var allow_skip: bool = true  ## Allow player to skip the video

# ---------------------------
# State
# ---------------------------
var _video_started: bool = false

# ---------------------------
# Node References
# ---------------------------
@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var skip_label: Label = $SkipLabel
@onready var background: ColorRect = $Background


func _ready() -> void:
	# Ensure this runs even when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	print("[EndingVideoPlayer] _ready() called, video_path = '%s'" % video_path)
	
	# Make sure we're visible
	visible = true
	show()
	
	# Ensure video player is set up correctly
	if video_player:
		video_player.visible = true
		video_player.finished.connect(_on_video_finished)
		# Disable autoplay - we control playback
		video_player.autoplay = false
		video_player.stop()
	
	# Show/hide skip label
	if skip_label:
		skip_label.visible = allow_skip
	
	# If video_path was set before adding to tree, load it now
	if video_path != "":
		call_deferred("_load_and_play_video")


func set_video_path(path: String) -> void:
	video_path = path
	print("[EndingVideoPlayer] set_video_path() called with: %s" % path)
	
	# If already in tree and not started, load and play
	if is_inside_tree() and not _video_started:
		_load_and_play_video()


func _load_and_play_video() -> void:
	if _video_started:
		print("[EndingVideoPlayer] Video already started, skipping")
		return
	
	if video_path == "":
		push_error("[EndingVideoPlayer] No video_path set!")
		return
	
	# Find video player
	if not video_player:
		video_player = get_node_or_null("VideoStreamPlayer")
	
	if not video_player:
		push_error("[EndingVideoPlayer] VideoStreamPlayer not found!")
		_return_to_menu()
		return
	
	# Load the video stream
	print("[EndingVideoPlayer] Loading video: %s" % video_path)
	
	var video_stream = load(video_path)
	if video_stream:
		print("[EndingVideoPlayer] Video stream loaded: %s" % video_stream)
		_video_started = true
		
		# Configure and play
		video_player.stream = video_stream
		video_player.visible = true
		video_player.expand = true
		video_player.play()
		
		print("[EndingVideoPlayer] Called play(), is_playing: %s" % video_player.is_playing())
		print("[EndingVideoPlayer] VideoStreamPlayer visible: %s, size: %s" % [video_player.visible, video_player.size])
	else:
		push_error("[EndingVideoPlayer] Failed to load video: %s" % video_path)
		_return_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	# Skip video on key press or mouse click (if allowed)
	if allow_skip and _video_started:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_skip_video()
				var viewport = get_viewport()
				if viewport:
					viewport.set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_skip_video()
				var viewport = get_viewport()
				if viewport:
					viewport.set_input_as_handled()


func _skip_video() -> void:
	print("[EndingVideoPlayer] Video skipped by player")
	
	if video_player:
		video_player.stop()
	
	_return_to_menu()


func _on_video_finished() -> void:
	print("[EndingVideoPlayer] Video finished signal received")
	_return_to_menu()


func _return_to_menu() -> void:
	print("[EndingVideoPlayer] Returning to menu: %s" % menu_scene_path)
	
	# Unpause the game
	get_tree().paused = false
	
	# Return to main menu
	if menu_scene_path != "":
		get_tree().change_scene_to_file(menu_scene_path)
	else:
		get_tree().quit()
	
	# Clean up
	queue_free()
