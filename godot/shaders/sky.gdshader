shader_type sky;
// سماء إجرائية: تدرّج جوي حسب ارتفاع الشمس، قرص الشمس والقمر، نجوم، وغيوم متحركة بطبقتين.

uniform vec3 sun_dir = vec3(0.0, 0.5, 0.5);
uniform vec3 moon_dir = vec3(0.0, 0.5, -0.5);
uniform float night : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform float golden : hint_range(0.0, 1.0) = 0.0;
uniform float lightning = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 6; i++) { v += a * noise(p); p = r * p * 2.03 + 11.7; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float se = sun_dir.y;

	// --- الغلاف الجوي
	vec3 day_zenith = vec3(0.16, 0.34, 0.72);
	vec3 day_horizon = vec3(0.62, 0.74, 0.88);
	vec3 gold_horizon = vec3(1.05, 0.52, 0.24);
	vec3 night_zenith = vec3(0.004, 0.007, 0.02);
	vec3 night_horizon = vec3(0.035, 0.03, 0.05);
	float t = pow(clamp(h, 0.0, 1.0), 0.45);
	vec3 day = mix(day_horizon, day_zenith, t);
	float toward_sun = pow(max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z))), 0.0), 3.0);
	day = mix(day, mix(day, gold_horizon, (1.0 - t) * (0.5 + 0.5 * toward_sun)), golden);
	vec3 nightc = mix(night_horizon, night_zenith, t);
	nightc += vec3(0.06, 0.045, 0.04) * pow(1.0 - clamp(h, 0.0, 1.0), 6.0);   // توهج المدينة في الأفق
	vec3 col = mix(day, nightc, night);
	if (h < 0.0) col = mix(col, col * 0.35, clamp(-h * 4.0, 0.0, 1.0));

	// --- الشمس
	float sd = dot(d, normalize(sun_dir));
	col += vec3(1.0, 0.85, 0.65) * pow(max(sd, 0.0), 350.0) * 25.0 * (1.0 - night) * (1.0 - cloud_cover * 0.85);
	col += vec3(1.0, 0.7, 0.45) * pow(max(sd, 0.0), 8.0) * 0.35 * (1.0 - night);

	// --- النجوم والقمر
	if (night > 0.01 && h > 0.0) {
		vec3 sp = d * 300.0;
		float s = hash3(floor(sp));
		float star = step(0.9975, s) * (0.5 + 0.5 * sin(TIME * 2.0 + s * 100.0));
		col += vec3(star) * night * (1.0 - cloud_cover) * 0.9;
		float md = dot(d, normalize(moon_dir));
		col += vec3(0.85, 0.9, 1.0) * smoothstep(0.99955, 0.9997, md) * 3.0 * night;
		col += vec3(0.25, 0.3, 0.4) * pow(max(md, 0.0), 60.0) * 0.4 * night;
	}

	// --- الغيوم (إسقاط على قبة)
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 1.6;
		vec2 wind = vec2(TIME * 0.006, TIME * 0.002);
		float n = fbm(uv * 1.4 + wind) * 0.65 + fbm(uv * 3.7 - wind * 1.7) * 0.35;
		float cov = mix(0.72, 0.28, cloud_cover);
		float dens = smoothstep(cov, cov + 0.22, n);
		float shade = fbm(uv * 1.4 + wind + normalize(sun_dir.xz + 1e-4) * 0.06);
		vec3 lit_day = mix(vec3(1.0), vec3(1.0, 0.72, 0.5), golden) * (1.05 - shade * 0.5);
		vec3 storm = vec3(0.32, 0.34, 0.38);
		vec3 cloud_day = mix(lit_day, storm, cloud_cover * cloud_cover);
		vec3 cloud_night = vec3(0.03, 0.03, 0.045) + vec3(0.08, 0.06, 0.05) * (1.0 - shade);  // تضيئها أنوار المدينة
		vec3 cc = mix(cloud_day, cloud_night, night) + vec3(lightning * 1.5);
		col = mix(col, cc, dens * smoothstep(0.0, 0.08, h) * 0.97);
		// غطاء رمادي كامل في الطقس السيء
		col = mix(col, mix(vec3(0.55, 0.57, 0.6), vec3(0.025, 0.025, 0.035), night), smoothstep(0.75, 1.0, cloud_cover) * 0.6);
	}
	COLOR = col;
}
