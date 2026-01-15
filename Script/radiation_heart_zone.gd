extends Area3D

# ---------------------------
# RadiationHeartZone - Final Choice Trigger
# ---------------------------
# A special zone that triggers the Final Choice storyline
# when the player enters. Displays dialog, then shows choice overlay.

# ---------------------------
# Exports - Configurable in Inspector
# ---------------------------
@export var harsh_red_color: Color = Color(0.9, 0.15, 0.1, 1.0)  ## Harsh red glow color
@export var light_energy: float = 3.0  ## Intensity of the red light
@export var light_range: float = 15.0  ## How far the light reaches
@export var zone_size: Vector3 = Vector3(10.0, 5.0, 10.0)  ## Size of the detection zone

@export_group("Dialog")
@export var dialog_lines: Array[String] = [
	"You have reached the heart of the radiation...",
	"Two paths lie before you.",
	"Choose wisely. Your decision will determine the fate of this land."
]  ## Lines shown when player enters
@export var dialogue_ui_scene: PackedScene  ## The dialogue overlay scene

@export_group("Final Choice")
@export var final_choice_overlay_scene: PackedScene  ## The final choice overlay scene

# ---------------------------
# State
# ---------------------------
var has_triggered: bool = false  ## Prevent multiple triggers
var dialogue_ui_instance: Node = null
var final_choice_instance: Node = null

# ---------------------------
# Node References
# ---------------------------
@onready var omni_light: OmniLight3D = $OmniLight3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var zone_visual: MeshInstance3D = $ZoneVisual


func _ready() -> void:
	# Apply initial settings
	_update_light_settings()
	_update_collision_shape()
	_update_zone_visual()
	
	# Connect body entered signal
	body_entered.connect(_on_body_entered)
	
	print("[RadiationHeartZone] Initialized at %s" % global_position)


func _update_light_settings() -> void:
	if omni_light:
		omni_light.light_color = harsh_red_color
		omni_light.light_energy = light_energy
		omni_light.omni_range = light_range


func _update_collision_shape() -> void:
	if collision_shape and collision_shape.shape is BoxShape3D:
		(collision_shape.shape as BoxShape3D).size = zone_size


func _update_zone_visual() -> void:
	if zone_visual and zone_visual.mesh is BoxMesh:
		(zone_visual.mesh as BoxMesh).size = zone_size
	
	# Update visual material color
	if zone_visual:
		var material = zone_visual.get_surface_override_material(0)
		if not material:
			var mesh_material = zone_visual.mesh.surface_get_material(0) if zone_visual.mesh else null
			if mesh_material and mesh_material is StandardMaterial3D:
				material = mesh_material.duplicate() as StandardMaterial3D
				zone_visual.set_surface_override_material(0, material)
		
		if material and material is StandardMaterial3D:
			var visual_color = harsh_red_color
			visual_color.a = 0.25  # Semi-transparent
			(material as StandardMaterial3D).albedo_color = visual_color


func _on_body_entered(body: Node3D) -> void:
	# Prevent multiple triggers
	if has_triggered:
		return
	
	# Check if this is the player
	if not _is_player(body):
		return
	
	has_triggered = true
	print("[RadiationHeartZone] Player entered! Triggering Final Choice storyline...")
	
	# Start the storyline sequence
	_start_dialog_sequence()


func _is_player(body: Node3D) -> bool:
	# Check if body is in player group
	if body.is_in_group("player"):
		return true
	
	# Check by node name
	if body.name == "Player":
		return true
	
	# Check if it's a CharacterBody3D (player is CharacterBody3D)
	if body is CharacterBody3D:
		return true
	
	return false


func _start_dialog_sequence() -> void:
	# Try to use existing dialogue UI from GameManager
	if GameManager.instance and GameManager.instance.dialogue_ui:
		_ensure_dialogue_ui_from_game_manager()
	elif dialogue_ui_scene:
		_create_dialogue_ui()
	else:
		# No dialogue UI available, skip to final choice
		print("[RadiationHeartZone] No dialogue UI configured, skipping to final choice")
		_show_final_choice_overlay()
		return
	
	# Pause the game for dialog
	get_tree().paused = true
	
	# Show dialog
	if dialogue_ui_instance and dialogue_ui_instance.has_method("show_text"):
		dialogue_ui_instance.show_text(dialog_lines, _on_dialog_complete)
	else:
		# Fallback if no dialog method
		_on_dialog_complete()


func _ensure_dialogue_ui_from_game_manager() -> void:
	if GameManager.instance.dialogue_ui:
		if not GameManager.instance.dialogue_ui_instance or not is_instance_valid(GameManager.instance.dialogue_ui_instance):
			dialogue_ui_instance = GameManager.instance.dialogue_ui.instantiate()
			add_child(dialogue_ui_instance)
		else:
			dialogue_ui_instance = GameManager.instance.dialogue_ui_instance


func _create_dialogue_ui() -> void:
	if dialogue_ui_scene:
		dialogue_ui_instance = dialogue_ui_scene.instantiate()
		add_child(dialogue_ui_instance)


func _on_dialog_complete() -> void:
	print("[RadiationHeartZone] Dialog complete, showing final choice...")
	
	# Clean up dialogue UI if we created it
	if dialogue_ui_instance and is_instance_valid(dialogue_ui_instance):
		if dialogue_ui_instance.get_parent() == self:
			dialogue_ui_instance.queue_free()
		dialogue_ui_instance = null
	
	# Show the final choice overlay
	_show_final_choice_overlay()


func _show_final_choice_overlay() -> void:
	if not final_choice_overlay_scene:
		push_error("[RadiationHeartZone] No final_choice_overlay_scene assigned!")
		get_tree().paused = false
		return
	
	# Create and show the final choice overlay
	final_choice_instance = final_choice_overlay_scene.instantiate()
	
	# Add to scene tree (CanvasLayer will handle visibility)
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(final_choice_instance)
		print("[RadiationHeartZone] Final choice overlay shown")
	else:
		push_error("[RadiationHeartZone] No scene root found!")
		get_tree().paused = false


# ---------------------------
# Public API
# ---------------------------

## Reset the zone to allow re-triggering (useful for testing)
func reset_zone() -> void:
	has_triggered = false
	
	if final_choice_instance and is_instance_valid(final_choice_instance):
		final_choice_instance.queue_free()
		final_choice_instance = null
	
	if dialogue_ui_instance and is_instance_valid(dialogue_ui_instance):
		dialogue_ui_instance.queue_free()
		dialogue_ui_instance = null
