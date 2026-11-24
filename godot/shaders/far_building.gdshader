shader_type spatial;
// نسخة بعيدة خفيفة للمباني (LOD): جص بخامة حقيقية + شبكة نوافذ 3 م مطابقة للوحدات القريبة،
// تُضاء ليلاً حسب ساعة اليوم. تظهر عندما تختفي الواجهات التفصيلية بسبب المسافة.
#include "res://shaders/notile.gdshaderinc"

global uniform float night;
global uniform float time_of_day;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
instance uniform vec3 tint : source_color = vec3(1.0);
uniform float tile_scale = 3.0;
instance uniform float has_windows = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wnrm);
	vec2 uv = an.x > an.z ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
	bool roof = an.y > 0.5;
	if (roof) uv = wpos.xz;
	vec3 alb = texture(albedo_tex, uv / tile_scale).rgb * tint;
	vec3 nrm = texture(normal_tex, uv / tile_scale).rgb;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	if (!roof && has_windows > 0.5) {
		vec2 cell = floor(uv / 3.0);
		vec2 f = fract(uv / 3.0);
		float win = step(0.22, f.x) * step(f.x, 0.78) * step(0.2, f.y) * step(f.y, 0.88) * step(0.5, wpos.y);
		float r = h21(cell + floor(wpos.xz * 0.01) * 17.0);
		float hr = time_of_day;
		float occ = hr > 17.0 ? 0.65 * (1.0 - smoothstep(22.5, 24.0, hr) * 0.45) : (hr < 6.5 ? 0.2 : 0.3);
		float lit = step(r, occ);
		vec3 lc = mix(vec3(1.0, 0.75, 0.45), vec3(0.85, 0.9, 1.0), step(0.7, fract(r * 13.0)));
		alb = mix(alb, vec3(0.03, 0.035, 0.04), win);
		rough = mix(rough, 0.08, win);
		emit = lc * lit * win * night * 2.4;
		nrm = mix(nrm, vec3(0.5, 0.5, 1.0), win);
	}
	if (roof) alb *= 0.55;
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	EMISSION = emit;
	NORMAL_MAP = nrm;
}
