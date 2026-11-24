shader_type spatial;
// زجاج النوافذ مع "Interior Mapping": غرفة مزيّفة ثلاثية الأبعاد خلف كل نافذة (أرضية، سقف، جدران، ستارة)
// تتحرك مع منظور الكاميرا بلا أي هندسة إضافية. الإنارة تعتمد على الليل وساعة اليوم وبيانات كل نافذة.
// INSTANCE_CUSTOM: r = عشوائي للإضاءة، g = عشوائي لنوع الغرفة، b = عشوائي للستارة.
render_mode cull_back;

global uniform float night;
global uniform float time_of_day;
global uniform float wetness;

uniform float room_depth = 4.0;
uniform int debug_mode = 0;
uniform vec2 module_min = vec2(-3.0, 0.0);
uniform vec2 module_max = vec2(0.0, 3.0);

varying vec3 lpos;
varying vec3 lcam;
varying vec4 icust;

float h11(float x) { return fract(sin(x * 91.345) * 47453.5453); }

void vertex() {
	lpos = VERTEX;
	lcam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	icust = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 d = normalize(lpos - lcam);
	// تقاطع الشعاع مع صندوق الغرفة خلف الواجهة (الداخل باتجاه -z)
	vec3 bmin = vec3(module_min.x + 0.15, module_min.y + 0.05, -room_depth);
	vec3 bmax = vec3(module_max.x - 0.15, module_max.y - 0.1, 0.0);
	vec3 t1 = (bmin - lpos) / d;
	vec3 t2 = (bmax - lpos) / d;
	vec3 tf = max(t1, t2);
	float t = min(min(tf.x, tf.y), tf.z);
	vec3 hit = lpos + d * t;

	float kind = icust.g;
	vec3 wall_col = mix(vec3(0.75, 0.7, 0.62), vec3(0.55, 0.62, 0.66), step(0.5, kind));
	wall_col = mix(wall_col, vec3(0.8, 0.55, 0.45), step(0.85, kind));
	vec3 floor_col = mix(vec3(0.32, 0.22, 0.14), vec3(0.45, 0.43, 0.4), step(0.6, h11(kind * 13.0)));
	vec3 ceil_col = vec3(0.9, 0.88, 0.85);

	vec3 room;
	float shade;
	if (t == tf.z) {           // الجدار الخلفي
		room = wall_col;
		shade = 0.85;
		// إطار صورة / رف على الجدار الخلفي
		vec2 q = hit.xy - vec2((bmin.x + bmax.x) * 0.5, 1.6);
		float frame = step(abs(q.x), 0.45) * step(abs(q.y), 0.3);
		room = mix(room, vec3(0.15 + kind * 0.3, 0.2, 0.25), frame * step(0.4, kind));
	} else if (t == tf.y) {    // سقف أو أرضية
		bool is_ceil = d.y > 0.0;
		room = is_ceil ? ceil_col : floor_col;
		shade = is_ceil ? 1.0 : 0.6;
	} else {                   // الجدران الجانبية
		room = wall_col * 0.9;
		shade = 0.7;
	}
	// إضاءة الغرفة: مصباح سقفي في المنتصف يخفت نحو العمق والأطراف
	float depth = clamp(-hit.z / room_depth, 0.0, 1.0);
	vec2 c = vec2((bmin.x + bmax.x) * 0.5, 2.9);
	float falloff = 1.0 / (1.0 + dot(hit.xy - c, hit.xy - c) * 0.35 + depth * 1.5);

	// أي النوافذ مضاءة: يعتمد على ساعة اليوم (الذروة مساءً، قليلة بعد منتصف الليل)
	float hr = time_of_day;
	float occupancy = hr > 17.0 ? mix(0.55, 0.75, smoothstep(17.0, 21.0, hr)) * (1.0 - smoothstep(22.5, 24.0, hr) * 0.45)
		: (hr < 6.5 ? 0.18 + smoothstep(5.0, 6.5, hr) * 0.3 : 0.35);
	float lit = step(icust.r, occupancy);
	vec3 light_col = mix(vec3(1.0, 0.78, 0.5), vec3(0.85, 0.92, 1.0), step(0.7, h11(icust.r * 7.0)));
	float tv = step(0.93, icust.g) * (0.6 + 0.4 * sin(TIME * 7.0 + icust.r * 40.0) * sin(TIME * 2.3));
	light_col = mix(light_col, vec3(0.4, 0.55, 1.0) * tv, step(0.93, icust.g));

	vec3 interior_day = room * shade * 0.22;
	vec3 interior_night = room * shade * falloff * light_col * 3.2 * lit;
	vec3 interior = mix(interior_day, interior_night + room * 0.01, night);

	// ستارة تغطي جزءاً من النافذة
	vec2 sx = (lpos.xy - module_min) / (module_max - module_min);
	float curtain_w = icust.b * 0.45;
	float curtain = step(sx.x, curtain_w) + step(1.0 - curtain_w * 0.6, sx.x);
	vec3 curtain_col = mix(vec3(0.75, 0.68, 0.55), vec3(0.35, 0.4, 0.5), step(0.5, icust.b));
	interior = mix(interior, curtain_col * mix(0.15, 1.2 * lit * light_col.r, night), clamp(curtain, 0.0, 1.0) * step(0.25, icust.b));

	// زجاج: فرينل قوي = انعكاس السماء والمدينة على الزوايا المائلة
	float fres = pow(1.0 - clamp(dot(-d, vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 4.0);
	ALBEDO = vec3(0.02, 0.025, 0.03);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ROUGHNESS = 0.04;
	EMISSION = interior * (1.0 - fres * 0.85);
	if (debug_mode == 1) EMISSION = vec3(2.0, 0.0, 0.0);
	if (debug_mode == 2) EMISSION = abs(d) * 2.0;
	if (debug_mode == 3) EMISSION = vec3(fract(lpos.x), fract(lpos.y), -lpos.z) ;
	if (debug_mode == 4) EMISSION = vec3(float(t > 0.0), float(t == tf.z), float(t == tf.y));
}
