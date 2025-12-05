shader_type spatial;
render_mode unshaded, depth_draw_opaque, depth_test_disabled, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;

uniform float edge_threshold : hint_range(0.0, 0.1) = 0.005;
uniform float edge_intensity : hint_range(0.0, 1.0) = 0.15;
uniform vec3 edge_color : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec2 texel_size = 1.0 / VIEWPORT_SIZE;
	
	// Sample raw depth at current and neighboring pixels
	float depth_center = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	float depth_up = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0, -texel_size.y)).r;
	float depth_down = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0, texel_size.y)).r;
	float depth_left = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(-texel_size.x, 0.0)).r;
	float depth_right = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(texel_size.x, 0.0)).r;
	
	// Calculate depth differences (using raw depth values)
	float depth_diff = max(
		max(abs(depth_up - depth_center), abs(depth_down - depth_center)),
		max(abs(depth_left - depth_center), abs(depth_right - depth_center))
	);
	
	// Normalize and threshold - very subtle
	float edge = smoothstep(edge_threshold * 0.5, edge_threshold, depth_diff);
	edge *= edge_intensity;
	
	// Get original screen color
	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	
	// Very subtle blend - only darken edges slightly
	vec3 final_color = mix(color, edge_color, edge);
	
	ALBEDO = final_color;
}
