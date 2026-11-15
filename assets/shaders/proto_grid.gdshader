// Prototyp-Grid im Weltraum (triplanar). Gibt bei hohem Tempo klares
// Geschwindigkeits-Feedback. Nutzt die MultiMesh-Instanzfarbe (COLOR).
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.42, 0.44, 0.48);
uniform vec3 line_color : source_color = vec3(0.16, 0.17, 0.2);
uniform float cell_size = 2.0;
uniform float line_width = 0.035;
uniform bool use_instance_tint = false;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 instance_tint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	instance_tint = use_instance_tint ? COLOR.rgb : vec3(1.0);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.5 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	vec2 g = abs(fract(uv / cell_size - 0.5) - 0.5) * cell_size;
	float d = min(g.x, g.y);
	float aa = fwidth(d);
	float line = 1.0 - smoothstep(line_width - aa, line_width + aa, d);
	ALBEDO = mix(base_color * instance_tint, line_color, line);
	ROUGHNESS = 0.85;
}
