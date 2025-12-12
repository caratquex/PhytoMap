shader_type spatial;
render_mode unshaded;

// MIT License. Made by Leo Peltola
// Modified to work with all renderers (Forward+, Mobile, Compatibility)
// Removed hint_normal_roughness_texture (Forward+ only)

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform bool shadows_enabled = true;
uniform bool highlights_enabled = true;
uniform float shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float highlight_strength : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform vec3 highlight_color : source_color = vec3(1.);
uniform vec3 shadow_color : source_color = vec3(0.0);
uniform float outline_thickness : hint_range(0.0, 5.0, 0.1) = 1.0;

varying mat4 model_view_matrix;

float getDepth(vec2 screen_uv, mat4 inv_projection_matrix){
	float raw_depth = texture(depth_texture, screen_uv)[0];
	vec3 normalized_device_coordinates = vec3(screen_uv * 2.0 - 1.0, raw_depth);
    vec4 view_space = inv_projection_matrix * vec4(normalized_device_coordinates, 1.0);	
	view_space.xyz /= view_space.w;	
	return -view_space.z;
}

void vertex(){
    model_view_matrix = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 e = vec2(outline_thickness / VIEWPORT_SIZE.xy);
	
	// Shadows (depth-based outlines)
	float depth_diff = 0.0;
	float neg_depth_diff = 0.5;
	
	if (shadows_enabled) {
		float depth = getDepth(SCREEN_UV, INV_PROJECTION_MATRIX);
		float du = getDepth(SCREEN_UV + vec2(0., -1.) * e, INV_PROJECTION_MATRIX);
		float dr = getDepth(SCREEN_UV + vec2(1., 0.) * e, INV_PROJECTION_MATRIX);
		float dd = getDepth(SCREEN_UV + vec2(0., 1.) * e, INV_PROJECTION_MATRIX);
		float dl = getDepth(SCREEN_UV + vec2(-1., 0.) * e, INV_PROJECTION_MATRIX);
		
		depth_diff += clamp(du - depth, 0., 1.);
		depth_diff += clamp(dd - depth, 0., 1.);
		depth_diff += clamp(dr - depth, 0., 1.);
		depth_diff += clamp(dl - depth, 0., 1.);
		
		neg_depth_diff += depth - du;
		neg_depth_diff += depth - dd;
		neg_depth_diff += depth - dr;
		neg_depth_diff += depth - dl;
		neg_depth_diff = clamp(neg_depth_diff, 0., 1.);
		neg_depth_diff = clamp(smoothstep(0.5, 0.5, neg_depth_diff) * 10., 0., 1.);
		depth_diff = smoothstep(0.2, 0.3, depth_diff);
	}
	
	// Highlights (depth-based edge detection)
	float edge_diff = 0.0;
	if (highlights_enabled) {
		float depth = getDepth(SCREEN_UV, INV_PROJECTION_MATRIX);
		float du = getDepth(SCREEN_UV + vec2(0., -1.) * e, INV_PROJECTION_MATRIX);
		float dr = getDepth(SCREEN_UV + vec2(1., 0.) * e, INV_PROJECTION_MATRIX);
		float dd = getDepth(SCREEN_UV + vec2(0., 1.) * e, INV_PROJECTION_MATRIX);
		float dl = getDepth(SCREEN_UV + vec2(-1., 0.) * e, INV_PROJECTION_MATRIX);
		
		// Sobel-like edge detection on depth
		float edge_h = abs(dl - dr);
		float edge_v = abs(du - dd);
		edge_diff = sqrt(edge_h * edge_h + edge_v * edge_v);
		edge_diff = smoothstep(0.01, 0.05, edge_diff);
		edge_diff = clamp(edge_diff - neg_depth_diff, 0., 1.);
	}

	vec3 original_color = texture(screen_texture, SCREEN_UV).rgb;
	vec3 final_highlight_color = mix(original_color, highlight_color, highlight_strength);
	vec3 final_shadow_color = mix(original_color, shadow_color, shadow_strength);
	vec3 final = original_color;
	
	if (highlights_enabled) {
		final = mix(final, final_highlight_color, edge_diff);
	}
	if (shadows_enabled) {
		final = mix(final, final_shadow_color, depth_diff);
	}
	
	ALBEDO = final;

	float alpha_mask = depth_diff * float(shadows_enabled) + edge_diff * float(highlights_enabled);
	ALPHA = clamp(alpha_mask * 5., 0., 1.);
}
