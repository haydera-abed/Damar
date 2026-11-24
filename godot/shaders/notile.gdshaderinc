// أدوات مشتركة: ضوضاء، ومنع تكرار الخامات (تقنية Inigo Quilez لتغيير إزاحة البلاطات عشوائياً)

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm3(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.37 + 3.3) * 0.15;
}

// يرجع إزاحتين ونسبة المزج لعيّنتين بلا تكرار ملحوظ
void notile_params(vec2 uv, out vec2 off_a, out vec2 off_b, out float blend_f) {
	float k = vnoise(uv * 0.11);
	float l = k * 8.0;
	float ia = floor(l);
	blend_f = fract(l);
	off_a = sin(vec2(3.0, 7.0) * ia);
	off_b = sin(vec2(3.0, 7.0) * (ia + 1.0));
}

vec4 notile(sampler2D s, vec2 uv, vec2 oa, vec2 ob, float f) {
	vec2 dx = dFdx(uv), dy = dFdy(uv);
	vec4 a = textureGrad(s, uv + oa, dx, dy);
	vec4 b = textureGrad(s, uv + ob, dx, dy);
	return mix(a, b, smoothstep(0.2, 0.8, f - 0.1 * dot(a - b, vec4(1.0))));
}

// تموّجات قطرات المطر على البرك (حلقات متوسّعة في خلايا عشوائية)
vec2 rain_ripples(vec2 p, float t) {
	vec2 n = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = p * (layer == 0 ? 1.7 : 2.9) + float(layer) * 3.1;
		vec2 cid = floor(q);
		vec2 f = fract(q) - 0.5;
		float rnd = h21(cid);
		vec2 c = (vec2(h21(cid + 1.3), h21(cid + 2.7)) - 0.5) * 0.6;
		float phase = fract(t * (0.8 + rnd * 0.6) + rnd);
		vec2 d = f - c;
		float r = length(d);
		float ring = sin((r - phase * 0.55) * 60.0) * smoothstep(0.08, 0.0, abs(r - phase * 0.55)) * (1.0 - phase);
		n += normalize(d + 1e-4) * ring;
	}
	return n * 0.5;
}
