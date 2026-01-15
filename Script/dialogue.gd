extends CanvasLayer

# ---------------------------
# Node References
# ---------------------------
@onready var panel: Panel = $Panel
@onready var label: RichTextLabel = $Panel/MarginContainer/RichTextLabel

# ---------------------------
# State
# ---------------------------
var lines: Array[String] = []
var current_index: int = 0
var on_complete_callback: Callable
var is_active: bool = false


func _ready() -> void:
	# Ensure panel is hidden initially
	if panel:
		panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	
	# Check for left click or space to advance dialogue
	var should_advance = false
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			should_advance = true
	elif event is InputEventKey:
		if event.keycode == KEY_SPACE and event.pressed:
			should_advance = true
	
	if should_advance:
		get_viewport().set_input_as_handled()
		_advance_dialogue()


## Show dialogue text line by line
## lines: Array of strings to display one at a time
## on_complete: Callable to invoke when all lines are shown
func show_text(text_lines: Array[String], on_complete: Callable = Callable()) -> void:
	if text_lines.is_empty():
		# No lines to show, immediately call completion
		if on_complete.is_valid():
			on_complete.call()
		return
	
	lines = text_lines
	current_index = 0
	on_complete_callback = on_complete
	is_active = true
	
	# Show the panel and display first line
	if panel:
		panel.visible = true
	
	_display_current_line()


func _display_current_line() -> void:
	if current_index < lines.size() and label:
		label.text = lines[current_index]


func _advance_dialogue() -> void:
	current_index += 1
	
	if current_index < lines.size():
		# Show next line
		_display_current_line()
	else:
		# All lines finished
		_finish_dialogue()


func _finish_dialogue() -> void:
	is_active = false
	
	# Hide the panel
	if panel:
		panel.visible = false
	
	# Clear state
	lines = []
	current_index = 0
	
	# Call the completion callback
	if on_complete_callback.is_valid():
		on_complete_callback.call()
