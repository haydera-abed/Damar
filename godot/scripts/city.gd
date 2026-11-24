class_name City
extends Node3D
## يولّد المدينة الليلية: الشوارع، المباني بنوافذ مضيئة، الأرصفة، الإنارة، الحدائق، المتاجر، والمخبأ.

class StoreData:
	var type: String
	var def: Dictionary
	var pos: Vector3          # نقطة السرقة (أمام الباب)
	var sx: int               # اتجاه الواجهة على محور X
	var cooldown := 0.0
	var sign: Label3D
	var ring: MeshInstance3D
	var beacon: MeshInstance3D
	var glow: OmniLight3D
	var glass_mat: StandardMaterial3D

var stores: Array[StoreData] = []
var safe_pos: Vector3
var safe_sx := -1
var safe_ring: MeshInstance3D
var blocks: Array[Dictionary] = []   # {center: Vector2, park: bool} للخريطة المصغّرة

var rng := RandomNumberGenerator.new()
var font: Font = preload("res://assets/fonts/Cairo.ttf")
var facade_mats: Array[StandardMaterial3D] = []
var mat_parapet := StandardMaterial3D.new()
var mat_dark := StandardMaterial3D.new()
var tree_scenes: Array[PackedScene] = [preload("res://assets/models/tree_oak.glb"), preload("res://assets/models/tree_pine.glb")]
var _box_cache := {}


func build() -> void:
	rng.seed = 20261124
	mat_parapet.albedo_color = Color("1c1e23")
	mat_parapet.roughness = 0.9
	mat_dark.albedo_color = Color("2b2a27")
	mat_dark.roughness = 0.9
	_make_facades()
	_build_ground()
	_build_blocks()
	_build_markings()
	_build_lamps()


# ---------------------------------------------------------------- مواد
func _make_facades() -> void:
	var palettes := [
		[Color("2c2e34"), [Color("ffd89a"), Color("ffe9c0"), Color("bfe0ff")], 0.36],
		[Color("3d3530"), [Color("ffcf88"), Color("ffe2a8")], 0.30],
		[Color("26323d"), [Color("cfe8ff"), Color("ffffff"), Color("9fd0ff")], 0.42],
		[Color("4a4640"), [Color("ffd89a"), Color("ffc070")], 0.28],
	]
	for p in palettes:
		var imgs := _facade_images(p[0], p[1], p[2])
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(imgs[0])
		m.emission_enabled = true
		m.emission_texture = ImageTexture.create_from_image(imgs[1])
		m.emission_energy_multiplier = 1.6
		m.roughness = 0.75
		m.metallic = 0.1
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 8.0
		m.uv1_scale = Vector3(1.0 / 24.0, 1.0 / 28.0, 1.0 / 24.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		facade_mats.append(m)


func _facade_images(wall: Color, lit: Array, lit_p: float) -> Array[Image]:
	const S := 512
	const C := 8
	var cs := S / C
	var a := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var e := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	a.fill(wall)
	e.fill(Color.BLACK)
	for i in 1500:
		var px := rng.randi_range(0, S - 3)
		var py := rng.randi_range(0, S - 3)
		a.fill_rect(Rect2i(px, py, 2, 2), wall.darkened(rng.randf() * 0.15))
	for row in C:
		a.fill_rect(Rect2i(0, row * cs, S, 4), wall.darkened(0.3))
		for col in C:
			var r := Rect2i(col * cs + 11, row * cs + 13, cs - 22, cs - 24)
			a.fill_rect(r.grow(2), Color("1a1d24"))
			if rng.randf() < lit_p:
				var c: Color = lit[rng.randi() % lit.size()]
				a.fill_rect(r, c)
				e.fill_rect(r, c * (0.45 + rng.randf() * 0.55))
				if rng.randf() < 0.5:
					var cw := int(r.size.x * rng.randf_range(0.2, 0.5))
					a.fill_rect(Rect2i(r.position, Vector2i(cw, r.size.y)), Color("281914"))
					e.fill_rect(Rect2i(r.position, Vector2i(cw, r.size.y)), Color.BLACK)
			else:
				a.fill_rect(r, Color("0d1118"))
				a.fill_rect(Rect2i(r.position, Vector2i(r.size.x, r.size.y / 3)), Color("16202e"))
	a.generate_mipmaps()
	e.generate_mipmaps()
	return [a, e]


func _noise_tex(freq: float, seed_v: int, size := 512) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	return t


# ---------------------------------------------------------------- الأرض والشوارع
func _build_ground() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform sampler2D grain : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D puddles : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness = 1.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	float g = texture(grain, p / 9.0).r;
	float pd = smoothstep(0.58, 0.72, texture(puddles, p / 45.0).r) * wetness;
	ALBEDO = vec3(0.075, 0.076, 0.082) * (0.7 + g * 0.6) * mix(1.0, 0.55, pd);
	ROUGHNESS = mix(0.62 - wetness * 0.12, 0.04, pd);
	SPECULAR = 0.5;
	NORMAL_MAP = mix(texture(normal_tex, p / 3.0).rgb, vec3(0.5, 0.5, 1.0), pd);
	NORMAL_MAP_DEPTH = 0.35;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("grain", _noise_tex(0.05, 7))
	m.set_shader_parameter("puddles", _noise_tex(0.012, 99))
	m.set_shader_parameter("normal_tex", load("res://assets/textures/asphalt_normal.webp"))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1400, 1400)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.name = "Ground"
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)
	# جدران حدود المدينة غير المرئية
	for s in [-1, 1]:
		_static_box(Vector3(s * (Cfg.BOUND + 2.2), 5, 0), Vector3(2, 10, Cfg.BOUND * 2 + 6), 99.0)
		_static_box(Vector3(0, 5, s * (Cfg.BOUND + 2.2)), Vector3(Cfg.BOUND * 2 + 6, 10, 2), 99.0)


func _static_box(center: Vector3, size: Vector3, _h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.position = center
	body.add_child(cs)
	add_child(body)


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := size.snapped(Vector3(0.01, 0.01, 0.01))
	if not _box_cache.has(key):
		var b := BoxMesh.new()
		b.size = key
		_box_cache[key] = b
	return _box_cache[key]


func _add_box(center: Vector3, size: Vector3, mat: Material, collide := true, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if collide:
		_static_box(center, size, size.y)
	return mi


func _add_building(c: Vector3, w: float, d: float, h: float, mat: Material, collide := true) -> void:
	_add_box(Vector3(c.x, h / 2.0, c.z), Vector3(w, h, d), mat, collide)
	_add_box(Vector3(c.x, h + 0.25, c.z), Vector3(w + 0.3, 0.7, d + 0.3), mat_parapet, false, false)
	if h > 30.0 and rng.randf() < 0.6:
		var h2 := rng.randf_range(5, 14)
		var w2 := w * rng.randf_range(0.55, 0.75)
		var d2 := d * rng.randf_range(0.55, 0.75)
		_add_box(Vector3(c.x, h + 0.6 + h2 / 2.0, c.z), Vector3(w2, h2, d2), mat, false)
		_add_box(Vector3(c.x, h + 0.6 + h2 + 0.2, c.z), Vector3(w2 + 0.2, 0.5, d2 + 0.2), mat_parapet, false, false)
	elif rng.randf() < 0.6:
		_add_box(Vector3(c.x + rng.randf_range(-w / 4, w / 4), h + 1.2, c.z + rng.randf_range(-d / 4, d / 4)), Vector3(2.4, 1.4, 2.0), mat_parapet, false)
	if h > 42.0:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.1, 0.1)
		l.light_energy = 3.0
		l.omni_range = 6.0
		l.position = Vector3(c.x, h + 1.5, c.z)
		l.add_to_group("blinkers")
		add_child(l)


# ---------------------------------------------------------------- المربعات السكنية
func _build_blocks() -> void:
	var sidewalk := StandardMaterial3D.new()
	sidewalk.albedo_texture = _noise_tex(0.08, 9, 256)
	sidewalk.albedo_color = Color(0.55, 0.55, 0.58)
	sidewalk.normal_enabled = true
	sidewalk.normal_texture = load("res://assets/textures/paving_normal.webp")
	sidewalk.normal_scale = 0.8
	sidewalk.roughness = 0.55
	sidewalk.uv1_triplanar = true
	sidewalk.uv1_world_triplanar = true
	sidewalk.uv1_scale = Vector3(0.22, 0.22, 0.22)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("1f3a1f")
	grass.roughness = 1.0

	var lots: Array[Dictionary] = []
	for bi in range(-1, Cfg.N + 1):
		for bj in range(-1, Cfg.N + 1):
			var cx := (bi + 0.5) * Cfg.CELL - Cfg.HALF
			var cz := (bj + 0.5) * Cfg.CELL - Cfg.HALF
			var inner := bi >= 0 and bi < Cfg.N and bj >= 0 and bj < Cfg.N
			_add_box(Vector3(cx, 0.075, cz), Vector3(Cfg.BLOCK, 0.15, Cfg.BLOCK), sidewalk, true, false)
			var park := inner and not (bi == 0 and bj == 0) and rng.randf() < 0.08
			blocks.append({"center": Vector2(cx, cz), "park": park})
			if park:
				_add_box(Vector3(cx, 0.19, cz), Vector3(Cfg.BLOCK - 6, 0.08, Cfg.BLOCK - 6), grass, false, false)
				for t in 14:
					_add_tree(Vector3(cx + rng.randf_range(-19, 19), 0.23, cz + rng.randf_range(-19, 19)), rng.randf_range(0.8, 1.3))
				continue
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					var lot := {"pos": Vector3(cx + sx * 12, 0, cz + sz * 12), "sx": sx, "sz": sz, "block": Vector2i(bi, bj), "center": Vector3(cx, 0, cz)}
					if inner:
						lots.append(lot)
					else:
						_add_building(lot.pos, rng.randf_range(17, 20), rng.randf_range(17, 20), rng.randf_range(14, 40), facade_mats[rng.randi() % 4], false)

	# المخبأ في زاوية المدينة
	var used := {}
	var safe_lot: Dictionary = {}
	for l in lots:
		if l.block == Vector2i(0, 0) and l.sx == -1 and l.sz == 1:
			safe_lot = l
	used[safe_lot.pos] = true
	_make_safehouse(safe_lot)

	# المتاجر: كل متجر في مربع مختلف، والبنك قرب المركز
	var shuffled := lots.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var used_blocks := {safe_lot.block: true}
	for type in Cfg.STORE_LIST:
		var pool := shuffled.filter(func(l): return not used.has(l.pos) and not used_blocks.has(l.block))
		if type == "bank":
			pool.sort_custom(func(a, b): return a.pos.length() < b.pos.length())
		if pool.is_empty():
			break
		var l: Dictionary = pool[0]
		used[l.pos] = true
		used_blocks[l.block] = true
		stores.append(_make_store(type, l))

	for l in lots:
		if used.has(l.pos):
			continue
		var dc: float = l.pos.length() / Cfg.HALF
		var h := rng.randf_range(9, 22) + maxf(0.0, 1.0 - dc) * rng.randf_range(0, 55)
		_add_building(l.pos, rng.randf_range(16, 19.5), rng.randf_range(16, 19.5), h, facade_mats[rng.randi() % 4])


func _add_tree(p: Vector3, k: float) -> void:
	var t: Node3D = tree_scenes[rng.randi() % 2].instantiate()
	t.scale = Vector3.ONE * 3.2 * k
	t.position = p
	t.rotation.y = rng.randf() * TAU
	add_child(t)
	# مواد الأشجار غير مضاءة في الملف الأصلي؛ نجعلها تتأثر بإضاءة الليل
	for mi in t.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s) as StandardMaterial3D
			if src:
				var nm := src.duplicate() as StandardMaterial3D
				nm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				nm.albedo_color = src.albedo_color.darkened(0.2)
				nm.roughness = 0.95
				m.set_surface_override_material(s, nm)
	_static_box(p + Vector3(0, 2, 0), Vector3(0.6, 4, 0.6), 1.0)


func _sign(text: String, color: Color, pos: Vector3, sx: int, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color * 2.2
	l.outline_size = 14
	l.outline_modulate = Color(0.02, 0.02, 0.03)
	l.position = pos
	l.rotation.y = PI / 2.0 if sx > 0 else -PI / 2.0
	add_child(l)
	return l


func _unshaded(color: Color, additive := false, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	if additive or alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.no_depth_test = false
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _zone_ring(pos: Vector3, color: Color, inner: float, outer: float) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 48
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.scale = Vector3(1, 0.05, 1)
	mi.position = pos + Vector3(0, 0.2, 0)
	mi.material_override = _unshaded(color * 0.9, true, 0.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _beacon(pos: Vector3, color: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = 0.7
	c.bottom_radius = 0.7
	c.height = 70
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.position = pos + Vector3(0, 35, 0)
	mi.material_override = _unshaded(color * 0.6, true, 0.05)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _make_store(type: String, l: Dictionary) -> StoreData:
	var def: Dictionary = Cfg.STORE_TYPES[type]
	var s := StoreData.new()
	s.type = type
	s.def = def
	s.sx = l.sx
	var w := 19.0
	var h: float = def.h
	var body := StandardMaterial3D.new()
	body.albedo_color = Color("d8d2c4") if type == "bank" else Color("3a3d44")
	body.roughness = 0.7
	var p: Vector3 = l.pos
	_add_box(Vector3(p.x, h / 2.0, p.z), Vector3(w, h, w), body)
	_add_box(Vector3(p.x, h + 0.25, p.z), Vector3(w + 0.3, 0.7, w + 0.3), mat_parapet, false, false)
	var face: float = p.x + l.sx * w / 2.0
	var col: Color = def.color
	# واجهة زجاجية مضيئة + مظلة + لافتة
	s.glass_mat = _unshaded(col * 0.6)
	var glass := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(12, 3)
	glass.mesh = qm
	glass.material_override = s.glass_mat
	glass.position = Vector3(face + l.sx * 0.03, 1.7, p.z)
	glass.rotation.y = PI / 2.0 if l.sx > 0 else -PI / 2.0
	add_child(glass)
	var canopy := StandardMaterial3D.new()
	canopy.albedo_color = col
	canopy.emission_enabled = true
	canopy.emission = col
	canopy.emission_energy_multiplier = 0.4
	_add_box(Vector3(face + l.sx * 0.8, 3.6, p.z), Vector3(1.6, 0.15, 13), canopy, false)
	s.sign = _sign(def.name, col, Vector3(face + l.sx * 0.08, minf(h - 1.4, 5.3), p.z), l.sx, 160)
	if type == "bank":
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.5
		cyl.height = 8
		for k in range(-2, 3):
			var c := MeshInstance3D.new()
			c.mesh = cyl
			c.material_override = body
			c.position = Vector3(face + l.sx * 1.4, 4, p.z + k * 3.4)
			add_child(c)
	s.pos = Vector3(p.x + l.sx * 13.6, 0.15, p.z)
	s.ring = _zone_ring(s.pos, col, 1.7, 2.2)
	s.beacon = _beacon(s.pos, col)
	s.glow = OmniLight3D.new()
	s.glow.light_color = col
	s.glow.light_energy = 2.5
	s.glow.omni_range = 9.0
	s.glow.position = Vector3(face + l.sx * 2.5, 3.0, p.z)
	add_child(s.glow)
	return s


func _make_safehouse(l: Dictionary) -> void:
	var w := 19.0
	var p: Vector3 = l.pos
	_add_box(Vector3(p.x, 3, p.z), Vector3(w, 6, w), mat_dark)
	var face: float = p.x + l.sx * w / 2.0
	var door := StandardMaterial3D.new()
	door.albedo_color = Color("6d7076")
	door.metallic = 0.6
	door.roughness = 0.5
	_add_box(Vector3(face + l.sx * 0.05, 2, p.z), Vector3(0.1, 4, 8), door, false)
	_sign("المخبأ", Color("3dff7a"), Vector3(face + l.sx * 0.12, 4.9, p.z), l.sx, 140)
	safe_pos = Vector3(p.x + l.sx * 13.6, 0.15, p.z)
	safe_sx = l.sx
	safe_ring = _zone_ring(safe_pos, Color("3dff7a"), 2.2, 2.8)
	_beacon(safe_pos, Color("3dff7a"))
	var g := OmniLight3D.new()
	g.light_color = Color("3dff7a")
	g.light_energy = 2.0
	g.omni_range = 8.0
	g.position = Vector3(face + l.sx * 2.0, 3.5, p.z)
	add_child(g)


# ---------------------------------------------------------------- علامات الطريق
func _build_markings() -> void:
	var dash_t: Array[Transform3D] = []
	var cross_t: Array[Transform3D] = []
	var along_x := Basis(Vector3.UP, PI / 2.0)
	for k in Cfg.N + 1:
		var c := k * Cfg.CELL - Cfg.HALF
		var t := -Cfg.HALF
		while t <= Cfg.HALF:
			var m := fposmod(t + Cfg.HALF, Cfg.CELL)
			if m > Cfg.ROAD / 2.0 + 3.0 and m < Cfg.CELL - Cfg.ROAD / 2.0 - 3.0:
				dash_t.append(Transform3D(along_x, Vector3(t, 0.02, c)))
				dash_t.append(Transform3D(Basis.IDENTITY, Vector3(c, 0.02, t)))
			t += 7.0
	for i in Cfg.N + 1:
		for j in Cfg.N + 1:
			var n := Vector2i(i, j)
			var np := Cfg.node_pos(n)
			for nb in Cfg.neighbors(n):
				var dx := nb.x - i
				var dz := nb.y - j
				var w := -6.0
				while w <= 6.0:
					var x := np.x + dx * (Cfg.ROAD / 2.0 + 2.0) + (w if dz != 0 else 0.0)
					var z := np.z + dz * (Cfg.ROAD / 2.0 + 2.0) + (w if dx != 0 else 0.0)
					cross_t.append(Transform3D(along_x if dx != 0 else Basis.IDENTITY, Vector3(x, 0.02, z)))
					w += 1.3
	_multimesh(Vector3(0.22, 0.02, 3.0), Color(0.75, 0.68, 0.4), dash_t)
	_multimesh(Vector3(0.6, 0.02, 3.0), Color(0.6, 0.6, 0.62), cross_t)


func _multimesh(size: Vector3, color: Color, xforms: Array[Transform3D], mat: Material = null, shadow := false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box_mesh(size)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.6
		mat = m
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------------------------------------------------------------- الإنارة
func _build_lamps() -> void:
	var poles: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for b in blocks:
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				var x: float = b.center.x + sx * 23.6
				var z: float = b.center.y + sz * 23.6
				poles.append(Transform3D(Basis.IDENTITY, Vector3(x, 3.5, z)))
				heads.append(Transform3D(Basis.IDENTITY, Vector3(x + sx * 0.9, 6.95, z + sz * 0.9)))
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.78, 0.52)
				l.light_energy = 2.2
				l.omni_range = 17.0
				l.omni_attenuation = 1.2
				l.distance_fade_enabled = true
				l.distance_fade_begin = 110.0
				l.distance_fade_length = 30.0
				l.position = Vector3(x + sx * 1.2, 6.6, z + sz * 1.2)
				add_child(l)
				_static_box(Vector3(x, 3.5, z), Vector3(0.3, 7, 0.3), 1.0)
	var pole_m := StandardMaterial3D.new()
	pole_m.albedo_color = Color("2c2f35")
	pole_m.metallic = 0.7
	pole_m.roughness = 0.5
	_multimesh(Vector3(0.2, 7.0, 0.2), Color.BLACK, poles, pole_m, true)
	_multimesh(Vector3(0.7, 0.18, 0.4), Color.BLACK, heads, _unshaded(Color(3.2, 2.4, 1.4)))
