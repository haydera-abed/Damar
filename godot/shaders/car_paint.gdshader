shader_type spatial;
// طلاء سيارات واقعي لنماذج الأطلس اللوني: يميّز تلقائياً بين الطلاء والزجاج والإطارات/الكروم،
// ويضيف طبقة ورنيش (Clearcoat) ولمعان معدني دقيق (Flakes) وقطرات مطر على الهيكل عند البلل.
#include "res://shaders/notile.gdshaderinc"

global uniform float wetness;
global uniform float rain;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float paint_metallic = 0.45;
uniform float paint_roughness = 0.28;

varying vec3 lpos;

void vertex() { lpos = VERTEX; }

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	bool glass = c.b > c.r + 0.08 && lum > 0.35 && c.b > 0.5;
	bool rubber = lum < 0.09;
	bool chrome = !glass && abs(c.r - c.g) < 0.03 && abs(c.g - c.b) < 0.03 && lum > 0.55;

	float flake = h21(floor(lpos.xy * 400.0) + floor(lpos.z * 400.0)) ;
	float drops = 0.0;
	if (wetness > 0.05) {
		vec2 q = lpos.xz * 22.0 + lpos.y * 9.0;
		drops = smoothstep(0.86, 0.9, vnoise(q)) * wetness;
	}

	if (glass) {
		ALBEDO = vec3(0.015, 0.02, 0.025);
		METALLIC = 0.0;
		ROUGHNESS = 0.02;
		SPECULAR = 1.0;
	} else if (rubber) {
		ALBEDO = vec3(0.025);
		METALLIC = 0.0;
		ROUGHNESS = mix(0.8, 0.45, wetness);
	} else if (chrome) {
		ALBEDO = vec3(0.85);
		METALLIC = 1.0;
		ROUGHNESS = 0.12;
	} else {
		ALBEDO = c * 0.85;
		METALLIC = paint_metallic;
		ROUGHNESS = paint_roughness + (flake - 0.5) * 0.08;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = mix(0.06, 0.02, wetness);
		NORMAL_MAP = vec3(0.5 + (flake - 0.5) * 0.04, 0.5 + (h21(lpos.zy * 300.0) - 0.5) * 0.04, 1.0);
		NORMAL_MAP = mix(NORMAL_MAP, vec3(0.5 + drops * 0.3, 0.5, 1.0), drops);
	}
}
