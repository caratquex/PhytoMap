shader_type spatial;

// Uniforms (Variables you can edit in the Inspector)
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform float cell_size : hint_range(0.1, 10.0) = 1.0;  // Size of each grid cell
uniform float random_strength : hint_range(0.0, 1.0) = 0.5;
uniform float random_rotation : hint_range(0.0, 1.0) = 0.25;  // Random rotation amount

// Pass world position from vertex to fragment shader
varying vec3 world_vertex_pos;

void vertex() {
	// Calculate world position of each vertex (works for GridMap!)
	world_vertex_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Get the cell ID by flooring world position to grid
	// This makes each GridMap cell have unique randomization
	vec3 tile_id = floor(world_vertex_pos / cell_size + 0.001);
	
	// Create a unique random seed for this cell
	float random_seed = tile_id.x * 127.1 + tile_id.y * 311.7 + tile_id.z * 74.7;
	float noise_offset = fract(sin(random_seed) * 43758.5453) * random_strength;
	
	// Random rotation (0, 90, 180, or 270 degrees)
	float rotation_seed = fract(sin(random_seed * 2.0) * 43758.5453);
	int rotation_step = int(rotation_seed * 4.0);  // 0, 1, 2, or 3
	
	// Apply rotation to UV
	vec2 centered_uv = UV - 0.5;
	vec2 rotated_uv;
	
	if (random_rotation > 0.0) {
		if (rotation_step == 1) {
			rotated_uv = vec2(-centered_uv.y, centered_uv.x);  // 90 degrees
		} else if (rotation_step == 2) {
			rotated_uv = vec2(-centered_uv.x, -centered_uv.y);  // 180 degrees
		} else if (rotation_step == 3) {
			rotated_uv = vec2(centered_uv.y, -centered_uv.x);  // 270 degrees
		} else {
			rotated_uv = centered_uv;  // 0 degrees
		}
	} else {
		rotated_uv = centered_uv;
	}
	
	// Apply Random Offset (UV stays in 0-1 range, offset shifts within texture)
	vec2 final_uv = rotated_uv + 0.5 + noise_offset;
	
	// Output the final color
	ALBEDO = texture(albedo_texture, final_uv).rgb;
}
