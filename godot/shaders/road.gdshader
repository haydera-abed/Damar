shader_type spatial;
// الأسفلت: خامة Poly Haven (PBR) بلا تكرار، تفاوت كبير المقياس، آثار إطارات في المسارات،
// رقع إصلاح، برك تتكوّن مع البلل، وتموّجات المطر.
#include "res://shaders/notile.gdshaderinc"

global uniform float wetness;
global uniform float rain;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_size = 3.5;
uniform float cell = 66.0;
uniform float half_city = 198.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// المسافة إلى أقرب منتصف شارع (للمسارات وآثار الإطارات)
float lane_offset(vec2 p) {
	vec2 l = mod(p + half_city, cell);
	vec2 d = min(l, cell - l);
	return min(d.x, d.y);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 uv = p / tile_size;
	vec2 oa, ob; float bf;
	notile_params(uv, oa, ob, bf);
	vec3 alb = notile(albedo_tex, uv, oa, ob, bf).rgb;
	vec3 nrm = notile(normal_tex, uv, oa, ob, bf).rgb;
	vec3 arm = notile(arm_tex, uv, oa, ob, bf).rgb;

	// تفاوت كبير المقياس: بقع داكنة/فاتحة ورقع إصلاح
	float macro = fbm3(p * 0.035);
	alb *= mix(0.78, 1.12, macro);
	float patch = step(0.72, vnoise(floor(p / 3.0) * 0.37 + 5.0)) * step(0.5, vnoise(p * 0.08));
	alb = mix(alb, alb * 0.62, patch * 0.8);

	// آثار الإطارات والزيت في وسط المسارات
	float off = lane_offset(p);
	float on_road = step(off, 8.0);
	float tracks = exp(-pow((off - 2.8) / 0.45, 2.0)) + exp(-pow((off - 4.4) / 0.45, 2.0));
	float oil = exp(-pow((off - 3.6) / 0.35, 2.0)) * smoothstep(0.45, 0.8, vnoise(p * 0.25));
	alb *= 1.0 - (tracks * 0.12 + oil * 0.25) * on_road;
	float rough = arm.g * (1.0 - tracks * 0.15 * on_road);

	// البلل والبرك (البرك أعمق قرب الرصيف وفي أخاديد الإطارات)
	float low = smoothstep(6.0, 7.8, off) * on_road * 0.5 + tracks * 0.25;
	float puddle_n = fbm3(p * 0.09) + low * 0.35 + (arm.r - 0.5) * 0.15;
	float puddle = smoothstep(0.95 - wetness * 0.42, 1.0 - wetness * 0.38, puddle_n) * wetness;
	float wet = clamp(wetness * 1.2, 0.0, 1.0);

	alb *= mix(1.0, 0.6, wet);
	alb = mix(alb, alb * 0.45, puddle);
	rough = mix(rough, 0.28, wet);
	rough = mix(rough, 0.02, puddle);

	vec3 n = mix(nrm, vec3(0.5, 0.5, 1.0), puddle * 0.95);
	if (rain > 0.02) {
		vec2 rip = rain_ripples(p * 1.3, TIME) * puddle * rain;
		n.xy += rip * 0.5;
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.55, wet);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = mix(1.0, 0.6, wet);
}
