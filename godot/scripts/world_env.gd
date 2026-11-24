class_name WorldEnv
extends Node
## نظام البيئة: دورة ليل ونهار، الشمس والقمر، سماء بغيوم حجمية مزيّفة، الطقس (صحو/غائم/مطر/عاصفة)،
## الضباب الحجمي، الإضاءة الشاملة (SDFGI)، تدرّج الألوان، وإعدادات الجودة.
## يكتب قيماً عامة للشيدر: night و wetness و rain و time_of_day تستخدمها مواد المدينة والسيارات.

signal weather_changed(name: String)

enum Weather { CLEAR, CLOUDY, RAIN, STORM }
const WEATHER_NAMES := ["صحو", "غائم", "ماطر", "عاصفة"]
const QUALITY_NAMES := ["منخفض", "متوسط", "عالٍ", "فائق (Ultra)"]

var env: Environment
var cam_attr: CameraAttributesPractical
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial

var hour := 21.5                 # الوقت الحالي (0..24)
var day_minutes := 24.0          # طول اليوم الكامل بالدقائق الحقيقية
var cycle_enabled := true
var weather := Weather.RAIN
var quality := 2                 # 0 منخفض .. 3 فائق
var night := 1.0                 # 0 نهار .. 1 ليل
var wetness := 1.0
var rain := 0.0                  # شدة المطر الحالية 0..1
var cloud := 0.6
var fog_amount := 0.0
var lightning := 0.0

var _weather_timer := 240.0
var _target := {"rain": 0.8, "cloud": 0.8, "fog": 0.35}
var _flash_t := 0.0


func _ready() -> void:
	for p in [["night", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0], ["wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
			["rain", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0], ["time_of_day", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 21.5]]:
		RenderingServer.global_shader_parameter_add(p[0], p[1], p[2])
	_build()
	set_weather(weather, true)


func _build() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.5)
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.8
	env.ssao_power = 1.6
	env.ssil_intensity = 0.8
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_energy = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.35
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_ambient_inject = 0.4
	# تدرّج لوني سينمائي (ظلال مائلة للأزرق، إضاءات دافئة) عبر LUT ثلاثي الأبعاد
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	env.adjustment_color_correction = _make_lut()
	var we := WorldEnvironment.new()
	we.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 320.0
	cam_attr.dof_blur_far_transition = 200.0
	cam_attr.dof_blur_amount = 0.04
	# تعريض تلقائي: العين/الكاميرا تتكيف مع ظلام الليل وسطوع النهار
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.35
	cam_attr.auto_exposure_speed = 0.6
	cam_attr.auto_exposure_min_sensitivity = 80.0
	cam_attr.auto_exposure_max_sensitivity = 900.0
	we.camera_attributes = cam_attr
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.light_angular_distance = 0.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 140.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(moon)


## LUT ألوان: تبريد الظلال وتدفئة الإضاءات قليلاً (مظهر الأفلام)
func _make_lut() -> ImageTexture3D:
	const S := 17
	var imgs: Array[Image] = []
	for b in S:
		var img := Image.create_empty(S, S, false, Image.FORMAT_RGB8)
		for g in S:
			for r in S:
				var c := Color(r / float(S - 1), g / float(S - 1), b / float(S - 1))
				var l := c.get_luminance()
				var shadow := Color(0.94, 0.98, 1.06)
				var high := Color(1.04, 1.0, 0.94)
				var tint := shadow.lerp(high, smoothstep(0.15, 0.75, l))
				c = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b)
				# منحنى S خفيف
				c = Color(_s_curve(c.r), _s_curve(c.g), _s_curve(c.b))
				img.set_pixel(r, g, c.clamp())
		imgs.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, S, S, S, false, imgs)
	return t


func _s_curve(x: float) -> float:
	return lerpf(x, x * x * (3.0 - 2.0 * x), 0.25)


# ---------------------------------------------------------------- الجودة
## يطبّق إعدادات الجودة على البيئة والعارض. يُستدعى من main بعد إنشاء الكاميرا.
func apply_quality(q: int, viewport: Viewport) -> void:
	quality = clampi(q, 0, 3)
	env.ssao_enabled = quality >= 1
	env.ssr_enabled = quality >= 2
	env.ssil_enabled = quality >= 3
	env.sdfgi_enabled = quality >= 2
	env.volumetric_fog_enabled = quality >= 2
	env.glow_enabled = true
	cam_attr.dof_blur_far_enabled = quality >= 2
	cam_attr.auto_exposure_enabled = quality >= 1
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if quality <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = quality >= 2
	viewport.mesh_lod_threshold = [4.0, 2.0, 1.0, 0.5][quality]
	viewport.positional_shadow_atlas_size = [1024, 2048, 4096, 8192][quality]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality])
	RenderingServer.positional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][quality])
	sun.directional_shadow_max_distance = [90.0, 140.0, 220.0, 320.0][quality]
	if quality >= 3:
		RenderingServer.environment_set_volumetric_fog_volume_size(160, 128)
	else:
		RenderingServer.environment_set_volumetric_fog_volume_size(96, 64)


# ---------------------------------------------------------------- الطقس
func set_weather(w: int, instant := false) -> void:
	weather = w
	match w:
		Weather.CLEAR: _target = {"rain": 0.0, "cloud": 0.15, "fog": 0.0}
		Weather.CLOUDY: _target = {"rain": 0.0, "cloud": 0.75, "fog": 0.2}
		Weather.RAIN: _target = {"rain": 0.65, "cloud": 0.85, "fog": 0.4}
		Weather.STORM: _target = {"rain": 1.0, "cloud": 1.0, "fog": 0.65}
	if instant:
		rain = _target.rain
		cloud = _target.cloud
		fog_amount = _target.fog
		wetness = 1.0 if rain > 0.0 else 0.0
	_weather_timer = randf_range(180.0, 420.0)
	weather_changed.emit(WEATHER_NAMES[w])


func _process(dt: float) -> void:
	if cycle_enabled:
		hour = fmod(hour + dt * 24.0 / (day_minutes * 60.0), 24.0)
	_weather_timer -= dt
	if _weather_timer <= 0.0:
		var weights := [0.35, 0.25, 0.28, 0.12]
		var r := randf()
		var acc := 0.0
		for i in 4:
			acc += weights[i]
			if r <= acc:
				set_weather(i)
				break
	# انتقال سلس بين حالات الطقس
	var k := 1.0 - exp(-dt / 20.0)
	rain = lerpf(rain, _target.rain, k)
	cloud = lerpf(cloud, _target.cloud, k)
	fog_amount = lerpf(fog_amount, _target.fog, k)
	# الطرق تتبلّل بسرعة تحت المطر وتجفّ ببطء
	if rain > 0.05:
		wetness = minf(1.0, wetness + dt * rain / 25.0)
	else:
		wetness = maxf(0.0, wetness - dt / 240.0)
	# البرق في العاصفة
	_flash_t -= dt
	if weather == Weather.STORM and _flash_t <= 0.0 and rain > 0.7:
		_flash_t = randf_range(6.0, 18.0)
		lightning = 1.0
	lightning = maxf(0.0, lightning - dt * 3.5)
	_update_lighting()


func _update_lighting() -> void:
	# زاوية الشمس: تشرق 6:00 وتغرب 18:00
	var t := (hour - 6.0) / 12.0 * PI          # 0 شروق .. PI غروب
	var elev := sin(t)                          # ارتفاع الشمس -1..1
	var sun_dir := Vector3(cos(t), sin(t), 0.35).normalized()
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var moon_dir := Vector3(-cos(t) * 0.8, -sin(t) * 0.9 + 0.25, -0.45).normalized()
	moon.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)

	night = 1.0 - smoothstep(-0.08, 0.12, elev)
	var golden := clampf(1.0 - absf(elev) * 3.0, 0.0, 1.0) * (1.0 - night)   # الساعة الذهبية
	var overcast := cloud
	sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.36), golden)
	sun.light_energy = maxf(0.0, smoothstep(-0.05, 0.25, elev)) * lerpf(1.8, 0.35, overcast)
	sun.visible = sun.light_energy > 0.01
	sun.shadow_opacity = lerpf(1.0, 0.45, overcast)
	moon.light_energy = night * lerpf(0.28, 0.08, overcast) + lightning * 6.0
	moon.light_color = Color(0.62, 0.72, 1.0).lerp(Color(0.85, 0.9, 1.0), lightning)
	moon.visible = moon.light_energy > 0.01

	env.ambient_light_energy = lerpf(1.0, 1.6, night) + lightning * 2.0
	env.background_energy_multiplier = lerpf(1.0, 0.6, night) + lightning * 3.0
	env.tonemap_exposure = lerpf(0.95, 1.25, night)
	var fog_col := Color(0.62, 0.68, 0.76).lerp(Color(0.85, 0.6, 0.45), golden * 0.6).lerp(Color(0.05, 0.05, 0.08), night)
	env.fog_light_color = fog_col.lerp(Color(0.5, 0.52, 0.55), overcast * (1.0 - night) * 0.5)
	env.fog_density = lerpf(0.0004, 0.008, fog_amount) + night * 0.001
	env.volumetric_fog_density = lerpf(0.0006, 0.016, fog_amount * fog_amount) + night * 0.002
	env.volumetric_fog_albedo = Color(0.9, 0.9, 0.92)
	env.volumetric_fog_emission = Color(0.02, 0.022, 0.03) * night
	env.glow_hdr_threshold = lerpf(1.4, 0.9, night)
	env.ssr_enabled = env.ssr_enabled

	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("cloud_cover", cloud)
	sky_mat.set_shader_parameter("golden", golden)
	sky_mat.set_shader_parameter("lightning", lightning)

	RenderingServer.global_shader_parameter_set("night", night)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("rain", rain)
	RenderingServer.global_shader_parameter_set("time_of_day", hour)


func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
