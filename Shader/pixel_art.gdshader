shader_type spatial;
render_mode unshaded, fog_disabled;

// Pixelation
uniform vec2 target_resolution = vec2(320.0, 180.0);

// Color quantization (higher = more colors, smoother)
uniform float colors_per_channel : hint_range(2.0, 200.0, 1.0) = 32.0;

// Outline settings
uniform float depth_outline_strength : hint_range(0.0, 1.0) = 0.8;
uniform float color_outline_strength : hint_range(0.0, 1.0) = 0.3;
uniform float outline_threshold : hint_range(0.01, 2.0) = 0.15;
uniform vec3 outline_color : source_color = vec3(0.0, 0.0, 0.0);

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float get_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_texture, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = floor(SCREEN_UV * target_resolution) / target_resolution;
	vec2 t = 1.0 / target_resolution;
	
	// Center sample
	vec3 cc = texture(screen_texture, uv).rgb;
	float cd = get_depth(uv, INV_PROJECTION_MATRIX);
	float cl = luma(cc);
	
	// Neighbor samples (no arrays)
	vec3 cu = texture(screen_texture, uv + vec2(0.0, -t.y)).rgb;
	vec3 cb = texture(screen_texture, uv + vec2(0.0, t.y)).rgb;
	vec3 cr = texture(screen_texture, uv + vec2(t.x, 0.0)).rgb;
	vec3 cleft = texture(screen_texture, uv + vec2(-t.x, 0.0)).rgb;
	
	float du = get_depth(uv + vec2(0.0, -t.y), INV_PROJECTION_MATRIX);
	float db = get_depth(uv + vec2(0.0, t.y), INV_PROJECTION_MATRIX);
	float dr = get_depth(uv + vec2(t.x, 0.0), INV_PROJECTION_MATRIX);
	float dl = get_depth(uv + vec2(-t.x, 0.0), INV_PROJECTION_MATRIX);
	
	// Depth edges
	float depth_edge = 0.0;
	depth_edge = max(depth_edge, step(0.5, abs(cd - du)));
	depth_edge = max(depth_edge, step(0.5, abs(cd - db)));
	depth_edge = max(depth_edge, step(0.5, abs(cd - dr)));
	depth_edge = max(depth_edge, step(0.5, abs(cd - dl)));
	
	// Color edges
	float color_edge = 0.0;
	float diff_u = abs(cl - luma(cu)) + length(cc - cu) * 0.5;
	float diff_b = abs(cl - luma(cb)) + length(cc - cb) * 0.5;
	float diff_r = abs(cl - luma(cr)) + length(cc - cr) * 0.5;
	float diff_l = abs(cl - luma(cleft)) + length(cc - cleft) * 0.5;
	
	color_edge = max(color_edge, step(outline_threshold, diff_u));
	color_edge = max(color_edge, step(outline_threshold, diff_b));
	color_edge = max(color_edge, step(outline_threshold, diff_r));
	color_edge = max(color_edge, step(outline_threshold, diff_l));
	
	// Combine
	float edge = max(depth_edge * depth_outline_strength, color_edge * color_outline_strength);
	edge = step(0.1, edge);
	
	// Quantize colors
	vec3 quantized = floor(cc * colors_per_channel + 0.5) / colors_per_channel;
	
	ALBEDO = mix(quantized, outline_color, edge);
}
