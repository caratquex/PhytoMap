extends Control

func _ready():
	$AnimationPlayer.play("RESET")
	$PanelContainer.visible = false

func resume():
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	$AnimationPlayer.play_backwards("blur")
	$PanelContainer.visible = false
	
func pause():
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$PanelContainer.visible = true
	$AnimationPlayer.play("blur")

func testEsc():
	if Input.is_action_just_pressed("esc") and !get_tree().paused:
		pause()
	elif Input.is_action_just_pressed("esc") and get_tree().paused:
		resume()

func _on_button_pressed() -> void:
	resume()

func _on_button_2_pressed() -> void:
	get_tree().reload_current_scene()

func _on_button_3_pressed() -> void:
	get_tree().quit()

func _process(delta):
	testEsc()
