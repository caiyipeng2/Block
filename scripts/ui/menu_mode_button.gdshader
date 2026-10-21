shader_type canvas_item;

// The approved 1295px artwork has a clear vertical strip at x=1006.
// Reuse its row shading only where the baked Chinese titles live.
varying vec4 face_tint;

void vertex() {
	face_tint = COLOR;
}

void fragment() {
	vec2 source_uv = UV;
	float title_left = 524.0 / 1295.0;
	float title_right = 982.0 / 1295.0;
	float cover = smoothstep(title_left, title_left + 6.0 / 1295.0, UV.x)
		* (1.0 - smoothstep(title_right - 6.0 / 1295.0, title_right, UV.x));
	vec4 original = texture(TEXTURE, source_uv);
	vec4 clear_strip = texture(TEXTURE, vec2(1006.0 / 1295.0, source_uv.y));
	COLOR = mix(original, clear_strip, cover) * face_tint;
}
