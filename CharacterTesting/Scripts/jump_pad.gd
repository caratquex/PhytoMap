extends Area3D

@export var jump_velocity: float = 10
@export var particle_system: GPUParticles3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.velocity.y = jump_velocity
		particle_system.restart()
