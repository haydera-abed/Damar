class_name City
extends Node3D
## يولّد المدينة: أسفلت وأرصفة بخامات Poly Haven الحقيقية، مبانٍ مجمّعة من طقم واجهات حقيقي،
## أفق مبانٍ بعيدة، الإنارة، الحدائق، المتاجر، والمخبأ.

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

const PH_TEX := "res://assets/polyhaven/textures/%s/%s_2k.jpg"
const MODULES := 6                  # وحدات 3 م لكل واجهة = مبنى 18 م

var stores: Array[StoreData] = []
var safe_pos: Vector3
var safe_sx := -1
var safe_ring: MeshInstance3D
var blocks: Array[Dictionary] = []   # {center: Vector2, park: bool} للخريطة المصغّرة
var detail_range := 200.0            # مدى رؤية الواجهات التفصيلية (حسب الجودة)
var buildings: Array[Dictionary] = []  # {center, half, floors, front}
var props: Props

var rng := RandomNumberGenerator.new()
var font: Font = preload("res://assets/fonts/Cairo.ttf")
var kit: FacadeKit
var tree_scenes: Array[PackedScene] = [preload("res://assets/models/tree_oak.glb"), preload("res://assets/models/tree_pine.glb")]
var _box_cache := {}
var _mats := {}


func build() -> void:
	rng.seed = 20261124
	kit = FacadeKit.new()
	kit.detail_range = detail_range
	props = Props.new(self)
	_build_ground()
	_build_blocks()
	_build_markings()
	_build_lamps()
	props.furnish_blocks()
	props.trees_in_parks()
	props.traffic_signals()
	props.billboards(self)


func set_detail_range(r: float) -> void:
	detail_range = r
	for n in get_tree().get_nodes_in_group("facade_detail"):
		(n as GeometryInstance3D).visibility_range_end = r


# ---------------------------------------------------------------- مواد PBR
func pbr(name: String, tile: float, tint := Color.WHITE, wet := 1.0, dirt := 0.25) -> ShaderMaterial:
	var key := "%s_%s_%s_%s" % [name, tile, tint, wet]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pbr_world.gdshader")
	m.set_shader_parameter("albedo_tex", load(PH_TEX % [name, "diff"]))
	m.set_shader_parameter("normal_tex", load(PH_TEX % [name, "nor"]))
	m.set_shader_parameter("arm_tex", load(PH_TEX % [name, "arm"]))
	m.set_shader_parameter("tile_size", tile)
	m.set_shader_parameter("base_tint", tint)
	m.set_shader_parameter("wet_response", wet)
	m.set_shader_parameter("dirt", dirt)
	_mats[key] = m
	return m


# ---------------------------------------------------------------- الأرض والشوارع
func _build_ground() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	m.set_shader_parameter("albedo_tex", load(PH_TEX % ["asphalt_02", "diff"]))
	m.set_shader_parameter("normal_tex", load(PH_TEX % ["asphalt_02", "nor"]))
	m.set_shader_parameter("arm_tex", load(PH_TEX % ["asphalt_02", "arm"]))
	m.set_shader_parameter("cell", Cfg.CELL)
	m.set_shader_parameter("half_city", Cfg.HALF)
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
	for s in [-1, 1]:
		_static_box(Vector3(s * (Cfg.BOUND + 2.2), 5, 0), Vector3(2, 10, Cfg.BOUND * 2 + 6))
		_static_box(Vector3(0, 5, s * (Cfg.BOUND + 2.2)), Vector3(Cfg.BOUND * 2 + 6, 10, 2))


func _static_box(center: Vector3, size: Vector3) -> void:
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
		_static_box(center, size)
	return mi


func _occluder(center: Vector3, size: Vector3) -> void:
	var oi := OccluderInstance3D.new()
	var bo := BoxOccluder3D.new()
	bo.size = size
	oi.occluder = bo
	oi.position = center
	add_child(oi)


## مبنى حقيقي من طقم الواجهات + تصادم + Occluder
func _add_kit_building(lot_pos: Vector3, floors: int, front: Vector3, ground := {}) -> Node3D:
	var b := kit.build(self, Vector3(lot_pos.x, 0.15, lot_pos.z), MODULES, floors, rng, front, ground)
	var w := MODULES * FacadeKit.MOD
	var half := w / 2.0
	buildings.append({"center": Vector3(lot_pos.x, 0.15, lot_pos.z), "half": half, "floors": floors, "front": front})
	props.dress_building(Vector3(lot_pos.x, 0.15, lot_pos.z), half, floors, front)
	var h := floors * FacadeKit.MOD
	_static_box(Vector3(lot_pos.x, h / 2.0 + 0.15, lot_pos.z), Vector3(w + 0.4, h, w + 0.4))
	_occluder(Vector3(lot_pos.x, h / 2.0 + 0.15, lot_pos.z), Vector3(w - 0.6, h - 0.5, w - 0.6))
	return b


## مبنى بعيد خارج حدود اللعب (أفق المدينة)
func _add_far_building(c: Vector3, w: float, d: float, h: float) -> void:
	var mi := _add_box(Vector3(c.x, h / 2.0, c.z), Vector3(w, h, d), kit.far_mats[rng.randi() % kit.far_mats.size()], false)
	var tint: Color = FacadeKit.TINTS[rng.randi() % FacadeKit.TINTS.size()] * rng.randf_range(0.7, 1.0)
	mi.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_occluder(Vector3(c.x, h / 2.0, c.z), Vector3(w - 0.5, h - 0.5, d - 0.5))


# ---------------------------------------------------------------- المربعات السكنية
func _build_blocks() -> void:
	var paving := pbr("rectangular_paving", 2.6, Color(0.82, 0.84, 0.88), 1.0, 0.3)
	var curb := pbr("concrete_pavement", 1.5, Color(0.85, 0.85, 0.85), 1.0, 0.35)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("2a4024")
	grass.roughness = 1.0

	var lots: Array[Dictionary] = []
	for bi in range(-2, Cfg.N + 2):
		for bj in range(-2, Cfg.N + 2):
			var cx := (bi + 0.5) * Cfg.CELL - Cfg.HALF
			var cz := (bj + 0.5) * Cfg.CELL - Cfg.HALF
			var inner := bi >= 0 and bi < Cfg.N and bj >= 0 and bj < Cfg.N
			var ring1 := not inner and bi >= -1 and bi <= Cfg.N and bj >= -1 and bj <= Cfg.N
			var park := inner and not (bi == 0 and bj == 0) and rng.randf() < 0.08
			if not inner and not ring1:
				# الحلقة الثانية: أفق أبراج بعيدة خفيفة (خارج حدود اللعب)
				for sx in [-1, 1]:
					for sz in [-1, 1]:
						_add_far_building(Vector3(cx + sx * 12, 0, cz + sz * 12), rng.randf_range(17, 21), rng.randf_range(17, 21), rng.randf_range(25, 45) + rng.randf_range(0, 50) * rng.randf())
				continue
			blocks.append({"center": Vector2(cx, cz), "park": park})
			if ring1:
				# الحلقة الأولى: مبانٍ حقيقية مطلة على حدود المدينة
				_add_box(Vector3(cx, 0.075, cz), Vector3(Cfg.BLOCK - 0.6, 0.15, Cfg.BLOCK - 0.6), paving, true, false)
				for sx in [-1, 1]:
					for sz in [-1, 1]:
						var lp := Vector3(cx + sx * 12, 0, cz + sz * 12)
						var to_city := (-lp).normalized()
						var front := Vector3(signf(to_city.x), 0, 0) if absf(to_city.x) > absf(to_city.z) else Vector3(0, 0, signf(to_city.z))
						_add_kit_building(lp, rng.randi_range(4, 9), front)
				continue
			# رصيف مبلّط + حافة خرسانية بارزة
			_add_box(Vector3(cx, 0.075, cz), Vector3(Cfg.BLOCK - 0.6, 0.15, Cfg.BLOCK - 0.6), paving, true, false)
			for s in [-1, 1]:
				_add_box(Vector3(cx + s * (Cfg.BLOCK / 2.0 - 0.15), 0.09, cz), Vector3(0.3, 0.18, Cfg.BLOCK), curb, false, false)
				_add_box(Vector3(cx, 0.09, cz + s * (Cfg.BLOCK / 2.0 - 0.15)), Vector3(Cfg.BLOCK - 0.6, 0.18, 0.3), curb, false, false)
			if park:
				_add_box(Vector3(cx, 0.19, cz), Vector3(Cfg.BLOCK - 6, 0.08, Cfg.BLOCK - 6), grass, false, false)
				continue
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					lots.append({"pos": Vector3(cx + sx * 12, 0, cz + sz * 12), "sx": sx, "sz": sz, "block": Vector2i(bi, bj), "center": Vector3(cx, 0, cz)})

	# المخبأ في زاوية المدينة
	var used := {}
	var safe_lot: Dictionary = {}
	for l in lots:
		if l.block == Vector2i(0, 0) and l.sx == -1 and l.sz == 1:
			safe_lot = l
	used[safe_lot.pos] = true
	_make_safehouse(safe_lot)

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
		var floors := rng.randi_range(3, 5) + int(maxf(0.0, 1.0 - dc) * rng.randf_range(0, 8))
		var front := Vector3(l.sx, 0, 0) if rng.randf() < 0.5 else Vector3(0, 0, l.sz)
		_add_kit_building(l.pos, floors, front)


func _add_tree(p: Vector3, k: float) -> void:
	var t: Node3D = tree_scenes[rng.randi() % 2].instantiate()
	t.scale = Vector3.ONE * 3.2 * k
	t.position = p
	t.rotation.y = rng.randf() * TAU
	add_child(t)
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
	_static_box(p + Vector3(0, 2, 0), Vector3(0.6, 4, 0.6))


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
	var p: Vector3 = l.pos
	var floors: int = {"shop": 2, "gas": 2, "jewel": 3, "bank": 5}[type]
	# واجهة المتجر: أبواب زجاجية كبيرة ونوافذ عرض في الطابق الأرضي
	_add_kit_building(p, floors, Vector3(l.sx, 0, 0), {"door": "door_centered_large_01", "window": "window_centered_large_01"})
	var half := MODULES * FacadeKit.MOD / 2.0
	var face: float = p.x + l.sx * half
	var col: Color = def.color
	# مظلة ملوّنة + شريط نيون + لافتة عربية
	var canopy := StandardMaterial3D.new()
	canopy.albedo_color = col.darkened(0.2)
	canopy.roughness = 0.45
	canopy.metallic = 0.3
	_add_box(Vector3(face + l.sx * 0.9, 3.15, p.z), Vector3(1.8, 0.12, 16), canopy, false)
	s.glass_mat = _unshaded(col * 1.4)
	_add_box(Vector3(face + l.sx * 1.79, 3.09, p.z), Vector3(0.05, 0.08, 16), s.glass_mat, false, false)
	s.sign = _sign(def.name, col, Vector3(face + l.sx * 0.35, 3.9, p.z), l.sx, 150)
	s.pos = Vector3(p.x + l.sx * 11.5, 0.15, p.z)
	s.ring = _zone_ring(s.pos, col, 1.7, 2.2)
	s.beacon = _beacon(s.pos, col)
	s.glow = OmniLight3D.new()
	s.glow.light_color = col
	s.glow.light_energy = 2.0
	s.glow.omni_range = 9.0
	s.glow.position = Vector3(face + l.sx * 2.0, 2.6, p.z)
	add_child(s.glow)
	return s


func _make_safehouse(l: Dictionary) -> void:
	var p: Vector3 = l.pos
	var w := 18.0
	var iron := pbr("corrugated_iron", 2.0, Color(0.75, 0.78, 0.8), 0.6, 0.35)
	var brick := pbr("red_brick_03", 2.5, Color.WHITE, 0.5, 0.3)
	_add_box(Vector3(p.x, 3.15, p.z), Vector3(w, 6, w), brick)
	_occluder(Vector3(p.x, 3.15, p.z), Vector3(w - 0.5, 5.5, w - 0.5))
	var face: float = p.x + l.sx * w / 2.0
	_add_box(Vector3(p.x, 6.3, p.z), Vector3(w + 0.4, 0.3, w + 0.4), iron, false)
	# باب المرآب المعدني (Poly Haven)
	var shutter: Node3D = load("res://assets/polyhaven/models/rollershutter_door/rollershutter_door.gltf").instantiate()
	for c in shutter.get_children():
		if String(c.name).contains("graffiti"):
			c.visible = false
	shutter.scale = Vector3(2.4, 1.6, 1.0)
	shutter.rotation.y = PI / 2.0 if l.sx > 0 else -PI / 2.0
	shutter.position = Vector3(face + l.sx * 0.05, 0.15, p.z + 1.3 * l.sx)
	add_child(shutter)
	_sign("المخبأ", Color("3dff7a"), Vector3(face + l.sx * 0.12, 5.0, p.z), l.sx, 140)
	safe_pos = Vector3(p.x + l.sx * 11.5, 0.15, p.z)
	safe_sx = l.sx
	safe_ring = _zone_ring(safe_pos, Color("3dff7a"), 2.2, 2.8)
	_beacon(safe_pos, Color("3dff7a"))
	var g := OmniLight3D.new()
	g.light_color = Color("3dff7a")
	g.light_energy = 2.0
	g.omni_range = 8.0
	g.position = Vector3(face + l.sx * 2.0, 4.0, p.z)
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
				dash_t.append(Transform3D(along_x, Vector3(t, 0.012, c)))
				dash_t.append(Transform3D(Basis.IDENTITY, Vector3(c, 0.012, t)))
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
					cross_t.append(Transform3D(along_x if dx != 0 else Basis.IDENTITY, Vector3(x, 0.012, z)))
					w += 1.3
	var paint := pbr("concrete_pavement", 1.2, Color(1.6, 1.5, 1.1), 1.0, 0.45)
	var white := pbr("concrete_pavement", 1.2, Color(1.7, 1.7, 1.7), 1.0, 0.45)
	_multimesh(Vector3(0.22, 0.01, 3.0), dash_t, paint)
	_multimesh(Vector3(0.6, 0.01, 3.0), cross_t, white)


func _multimesh(size: Vector3, xforms: Array[Transform3D], mat: Material, shadow := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box_mesh(size)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# ---------------------------------------------------------------- الإنارة
func _build_lamps() -> void:
	# عمود إنارة حقيقي في منتصف كل جانب من الرصيف (بعيداً عن إشارات التقاطعات)
	for b in blocks:
		for side in 4:
			var n := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][side] as Vector3
			var t := Vector3(-n.z, 0, n.x)
			var p := Vector3(b.center.x, 0.15, b.center.y) + n * 23.9 + t * (12.0 if side % 2 == 0 else -12.0)
			props.lamp(p, atan2(n.x, n.z))
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.8, 0.55)
			l.light_energy = 7.0
			l.omni_range = 27.0
			l.omni_attenuation = 1.0
			l.light_volumetric_fog_energy = 1.5
			l.light_size = 0.25
			l.distance_fade_enabled = true
			l.distance_fade_begin = 110.0
			l.distance_fade_length = 30.0
			l.position = p + Vector3(0, 4.9, 0)
			l.add_to_group("street_lights")
			add_child(l)
			_static_box(p + Vector3(0, 2.7, 0), Vector3(0.3, 5.4, 0.3))
