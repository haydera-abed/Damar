shader_type spatial;
// مادة PBR عامة بإحداثيات العالم (Triplanar) مع منع التكرار وتفاعل مع المطر:
// للأرصفة، حواف الأرصفة، الأسطح، والمباني الخلفية.
#include "res://shaders/notile.gdshaderinc"

global uniform float wetness;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_tint : source_color = vec3(1.0);
instance uniform vec3 tint : source_color = vec3(1.0);
uniform float tile_size = 2.0;
uniform float wet_response = 1.0;
uniform float dirt = 0.25;
uniform bool use_instance_color = false;   // لون كل مبنى من MultiMesh

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 vtint;

void vertex() {
	vtint = use_instance_color ? COLOR.rgb : vec3(1.0);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wnrm);
	vec2 uv;
	if (an.y > an.x && an.y > an.z) uv = wpos.xz;
	else if (an.x > an.z) uv = vec2(wpos.z * sign(wnrm.x), wpos.y);
	else uv = vec2(-wpos.x * sign(wnrm.z), wpos.y);
	uv /= tile_size;
	vec2 oa, ob; float bf;
	notile_params(uv, oa, ob, bf);
	vec3 alb = notile(albedo_tex, uv, oa, ob, bf).rgb * tint * base_tint * vtint;
	vec3 nrm = notile(normal_tex, uv, oa, ob, bf).rgb;
	vec3 arm = notile(arm_tex, uv, oa, ob, bf).rgb;

	alb *= mix(1.0 - dirt, 1.0 + dirt * 0.3, fbm3(wpos.xz * 0.15 + wpos.y * 0.2));
	// أوساخ تتجمع أسفل الجدران
	alb *= mix(0.7, 1.0, smoothstep(0.0, 1.2, wpos.y));

	float up = smoothstep(0.6, 0.9, wnrm.y);
	float wet = clamp(wetness * wet_response * mix(0.35, 1.0, up), 0.0, 1.0);
	alb *= mix(1.0, 0.65, wet);
	float rough = mix(arm.g, 0.3, wet);

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = arm.b;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = nrm;
}
