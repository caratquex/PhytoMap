extends RayCast3D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_colliding(): 
		var hit = get_collider()
		print(hit.name)
