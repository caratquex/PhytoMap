shader_type spatial;
render_mode depth_draw_opaque, depth_test_disabled, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;

uniform float light_intensity : hint_range(0.0, 5.0) = 1.0;
uniform float line_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float edge_threshold : hint_range(0.0, 0.01) = 0.001;
uniform vec3 edge_color : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec2 texel_size = 1.0 / VIEWPORT_SIZE;
	
	// Sample depth at center and 4 neighbors for clean 1px outline
	float depth_center = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	float depth_up = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0, -texel_size.y)).r;
	float depth_down = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0, texel_size.y)).r;
	float depth_left = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(-texel_size.x, 0.0)).r;
	float depth_right = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(texel_size.x, 0.0)).r;
	
	// Calculate depth differences - detect any significant change
	float depth_diff_h = max(abs(depth_right - depth_center), abs(depth_left - depth_center));
	float depth_diff_v = max(abs(depth_down - depth_center), abs(depth_up - depth_center));
	float depth_diff = max(depth_diff_h, depth_diff_v);
	
	// Clean 1px outline - use step for sharp, binary edges
	float edge = step(edge_threshold, depth_diff);
	edge *= line_alpha;
	
	// Get original screen color
	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	
	// Apply light intensity to base color
	color *= light_intensity;
	
	// Apply clean 1px outline - only on edges
	vec3 final_color = mix(color, edge_color, edge);
	
	ALBEDO = final_color;
}
