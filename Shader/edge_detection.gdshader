shader_type spatial;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

// Edge Settings
uniform float edge_threshold : hint_range(0.01, 2.0) = 0.4;
uniform vec3 outline_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float outline_strength : hint_range(0.0, 1.0) = 1.0;
uniform float pixel_size : hint_range(0.1, 4.0) = 1.0;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texel = pixel_size / VIEWPORT_SIZE;
	
	// Sobel edge detection (color-based)
	vec3 tl = texture(screen_texture, SCREEN_UV + vec2(-texel.x, -texel.y)).rgb;
	vec3 t  = texture(screen_texture, SCREEN_UV + vec2(0.0, -texel.y)).rgb;
	vec3 tr = texture(screen_texture, SCREEN_UV + vec2(texel.x, -texel.y)).rgb;
	vec3 l  = texture(screen_texture, SCREEN_UV + vec2(-texel.x, 0.0)).rgb;
	vec3 c  = texture(screen_texture, SCREEN_UV).rgb;
	vec3 r  = texture(screen_texture, SCREEN_UV + vec2(texel.x, 0.0)).rgb;
	vec3 bl = texture(screen_texture, SCREEN_UV + vec2(-texel.x, texel.y)).rgb;
	vec3 b  = texture(screen_texture, SCREEN_UV + vec2(0.0, texel.y)).rgb;
	vec3 br = texture(screen_texture, SCREEN_UV + vec2(texel.x, texel.y)).rgb;
	
	// Sobel operator
	float gx = luma(tl) + 2.0*luma(l) + luma(bl) - luma(tr) - 2.0*luma(r) - luma(br);
	float gy = luma(tl) + 2.0*luma(t) + luma(tr) - luma(bl) - 2.0*luma(b) - luma(br);
	float edge = sqrt(gx*gx + gy*gy);
	
	// Sharp pixel art edge
	edge = step(edge_threshold, edge);
	
	ALBEDO = mix(c, outline_color, edge * outline_strength);
}
