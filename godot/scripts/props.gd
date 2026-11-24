class_name Props
extends RefCounted
## أثاث الشوارع والتفاصيل الحضرية بمجسمات Poly Haven الحقيقية (CC0):
## أعمدة إنارة، صنابير إطفاء، حاويات قمامة، أكياس، صناديق كهرباء، أحواض نباتات وشجيرات،
## أغطية صرف، حواجز خرسانية، مكيّفات على الجدران والأسطح، أشجار حقيقية، إشارات مرور عاملة، ولوحات إعلانية.

const PH := "res://assets/polyhaven/models/%s/%s.gltf"

var city: City
var rng: RandomNumberGenerator
var _templates := {}
var signals: Array[Dictionary] = []     # إشارات المرور: {red, yellow, green, axis}
var _sig_mats := {}


func _init(c: City) -> void:
	city = c
	rng = c.rng


## قالب مجسم: يُخفي المتغيرات غير المطلوبة (المتآكلة/المرسوم عليها)، يضبط المنشأ أسفل المنتصف، ويحجّم.
func template(name: String, height := 0.0, exclude: Array = ["aged", "rust", "graffiti"], only := "") -> Node3D:
	var key := "%s_%s_%s" % [name, height, only]
	if _templates.has(key):
		return _templates[key]
	var scene: Node3D = load(PH % [name, name]).instantiate()
	var box := AABB()
	var first := true
	for m in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var nm := String(mi.name)
		var hide := false
		for e in exclude:
			if nm.contains(e):
				hide = true
		if only != "" and nm != only:
			hide = true
		if hide:
			mi.visible = false
			continue
		var b: AABB = Car._xf_to(mi, scene) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s := height / box.size.y if height > 0.0 else 1.0
	var wrap := Node3D.new()
	wrap.name = "tpl_" + name
	wrap.visible = false
	city.add_child(wrap)            # القالب داخل الشجرة (مخفي) حتى يُحرَّر مع المشهد
	wrap.add_child(scene)
	scene.scale = Vector3.ONE * s
	scene.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	_templates[key] = wrap
	return wrap


func place(tpl: Node3D, pos: Vector3, yaw: float, range_end := 120.0, shadows := true) -> Node3D:
	var n := tpl.duplicate() as Node3D
	n.visible = true
	n.position = pos
	n.rotation.y = yaw
	city.add_child(n)
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		gi.visibility_range_end = range_end
		gi.visibility_range_end_margin = 10.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


# ---------------------------------------------------------------- الإنارة
func lamp(pos: Vector3, yaw: float) -> void:
	place(template("street_lamp_01", 5.4), pos, yaw, 260.0)


# ---------------------------------------------------------------- أثاث الرصيف
func furnish_blocks() -> void:
	var hydrant := template("fire_hydrant", 0.8)
	var can := template("metal_trash_can", 0.95)
	var bag := template("trashbag", 0.55)
	var ubox := template("utility_box_02", 1.15)
	var ubox2 := template("utility_box_01", 1.15)
	var planter := template("planter_box_01", 0.45)
	var shrub := template("shrub_04", 0.55)
	var barrier := template("concrete_road_barrier_02", 1.05)
	for b in city.blocks:
		var c := Vector3(b.center.x, 0.15, b.center.y)
		if absf(c.x) > Cfg.HALF or absf(c.z) > Cfg.HALF:
			continue
		var edge := Cfg.BLOCK / 2.0 - 1.1          # قرب حافة الرصيف
		for side in 4:
			var n := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][side] as Vector3
			var t := Vector3(-n.z, 0, n.x)
			var yaw := atan2(n.x, n.z)
			# صنبور إطفاء قرب الزاوية
			if rng.randf() < 0.7:
				place(hydrant, c + n * edge + t * rng.randf_range(14, 18) * (1 if rng.randf() < 0.5 else -1), yaw + PI / 2.0, 90.0)
			# حاويات وأكياس
			if rng.randf() < 0.8:
				var p := c + n * (edge - 0.1) + t * rng.randf_range(-12, 12)
				place(can, p, yaw + rng.randf_range(-0.3, 0.3), 90.0)
				for k in rng.randi_range(0, 3):
					place(bag, p + t * rng.randf_range(0.7, 1.6) + n * rng.randf_range(-0.3, 0.3), rng.randf() * TAU, 60.0, false)
			# صندوق كهرباء
			if rng.randf() < 0.35:
				place(ubox if rng.randf() < 0.6 else ubox2, c + n * (edge - 0.2) + t * rng.randf_range(-20, 20), yaw, 90.0)
			# أحواض نباتات بشجيرات
			if b.park == false and rng.randf() < 0.45:
				var base := c + n * (edge + 0.1) + t * rng.randf_range(-9, 9)
				for k in 3:
					var pp := base + t * (k * 1.2)
					place(planter, pp, yaw + PI / 2.0, 80.0)
					place(shrub, pp + Vector3(0, 0.38, 0), rng.randf() * TAU, 70.0, false)
		# أغطية صرف في الشوارع المحيطة
		for k in 2:
			var mh := template("water_manhole_cover", 0.07)
			var on_x := rng.randf() < 0.5
			var off := rng.randf_range(-20, 20)
			var lane := Cfg.LANE * (1 if rng.randf() < 0.5 else -1)
			var road := c + (Vector3(Cfg.CELL / 2.0, 0, off) if on_x else Vector3(off, 0, Cfg.CELL / 2.0))
			road += (Vector3(lane, 0, 0) if on_x else Vector3(0, 0, lane))
			place(mh, Vector3(road.x, 0.005, road.z), rng.randf() * TAU, 80.0, false)
	# حواجز خرسانية عند مداخل الأزقة القريبة من المخبأ
	for k in 3:
		place(barrier, city.safe_pos + Vector3(city.safe_sx * 1.5, 0, 6.0 + k * 1.7), PI / 2.0, 120.0)


# ---------------------------------------------------------------- تفاصيل المباني
func dress_building(center: Vector3, half: float, floors: int, front: Vector3) -> void:
	var ac := template("exterior_aircon_unit", 0.62)
	var h := floors * FacadeKit.MOD
	# مكيّفات على الجدران الجانبية والخلفية (بين النوافذ)
	for face in 4:
		var n := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][face] as Vector3
		if n.dot(front) > 0.7:
			continue
		var t := Vector3.UP.cross(n)
		for k in rng.randi_range(0, 3):
			var f := rng.randi_range(1, maxi(1, floors - 1))
			var slot := rng.randi_range(-2, 3)
			var p := center + n * (half + 0.22) + t * (slot * FacadeKit.MOD - 0.0) + Vector3(0, f * FacadeKit.MOD + 0.3, 0)
			place(ac, p, atan2(n.x, n.z), 110.0, false)
	# معدات السطح
	for k in rng.randi_range(2, 5):
		var p := center + Vector3(rng.randf_range(-half + 2, half - 2), h + 0.05, rng.randf_range(-half + 2, half - 2))
		place(ac, p, rng.randi_range(0, 3) * PI / 2.0, 160.0)


# ---------------------------------------------------------------- الأشجار
func trees_in_parks() -> void:
	var tree := template("jacaranda_tree", 9.5)
	var shrub := template("shrub_03", 0.7)
	for b in city.blocks:
		if not b.park:
			continue
		var c := Vector3(b.center.x, 0.23, b.center.y)
		for k in 4:
			var p := c + Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15))
			var t := place(tree, p, rng.randf() * TAU, 320.0)
			t.scale = Vector3.ONE * rng.randf_range(0.8, 1.15)
			city._static_box(p + Vector3(0, 2, 0), Vector3(0.7, 4, 0.7))
		for k in 30:
			place(shrub, c + Vector3(rng.randf_range(-21, 21), 0, rng.randf_range(-21, 21)), rng.randf() * TAU, 90.0, false)


# ---------------------------------------------------------------- إشارات المرور (تعمل فعلاً)
func traffic_signals() -> void:
	for col in ["r", "y", "g"]:
		for axis in 2:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.05, 0.05, 0.05)
			m.emission_enabled = true
			m.emission = {"r": Color(1, 0.08, 0.05), "y": Color(1, 0.6, 0.05), "g": Color(0.1, 1, 0.45)}[col]
			m.emission_energy_multiplier = 0.0
			_sig_mats["%s%d" % [col, axis]] = m
	var pole_m := StandardMaterial3D.new()
	pole_m.albedo_color = Color(0.12, 0.13, 0.14)
	pole_m.metallic = 0.8
	pole_m.roughness = 0.45
	var house_m := StandardMaterial3D.new()
	house_m.albedo_color = Color(0.08, 0.08, 0.085)
	house_m.roughness = 0.5
	var pole := CylinderMesh.new()
	pole.top_radius = 0.09
	pole.bottom_radius = 0.11
	pole.height = 5.6
	var arm := CylinderMesh.new()
	arm.top_radius = 0.06
	arm.bottom_radius = 0.07
	arm.height = 4.0
	var box := BoxMesh.new()
	box.size = Vector3(0.38, 1.05, 0.3)
	var visor := BoxMesh.new()
	visor.size = Vector3(0.32, 0.03, 0.18)
	var lens := SphereMesh.new()
	lens.radius = 0.11
	lens.height = 0.08
	for i in range(1, Cfg.N):
		for j in range(1, Cfg.N):
			var np := Cfg.node_pos(Vector2i(i, j))
			for q in 4:
				var sx := 1 if q % 2 == 0 else -1
				var sz := 1 if q < 2 else -1
				# كل زاوية تتحكم بحركة اتجاه واحد (المحور يتبدّل بين الزوايا)
				var axis := q % 2
				var root := Node3D.new()
				root.position = np + Vector3(sx * (Cfg.ROAD / 2.0 + 0.6), 0.15, sz * (Cfg.ROAD / 2.0 + 0.6))
				city.add_child(root)
				var face := Vector3(0, 0, -sz) if axis == 0 else Vector3(-sx, 0, 0)
				_mesh(root, pole, pole_m, Vector3(0, 2.8, 0))
				var arm_dir := Vector3(-sx, 0, 0) if axis == 0 else Vector3(0, 0, -sz)
				var a := _mesh(root, arm, pole_m, Vector3(0, 5.4, 0) + arm_dir * 2.0)
				a.rotation = Vector3(0, 0, PI / 2.0) if axis == 0 else Vector3(PI / 2.0, 0, 0)
				var head := Node3D.new()
				head.position = Vector3(0, 4.85, 0) + arm_dir * 3.6
				head.rotation.y = atan2(face.x, face.z)
				root.add_child(head)
				_mesh(head, box, house_m, Vector3.ZERO)
				for k in 3:
					var col: String = ["r", "y", "g"][k]
					var y := 0.32 - k * 0.32
					_mesh(head, lens, _sig_mats["%s%d" % [col, axis]], Vector3(0, y, 0.15)).rotation.x = PI / 2.0
					_mesh(head, visor, house_m, Vector3(0, y + 0.13, 0.22))
				city._static_box(root.position + Vector3(0, 2.8, 0), Vector3(0.25, 5.6, 0.25))


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = 200.0
	parent.add_child(mi)
	return mi


## دورة الإشارات: 20 ث أخضر، 3 ث أصفر لكل محور
func update_signals(t: float) -> void:
	if _sig_mats.is_empty():
		return
	var cyc := fmod(t, 46.0)
	for axis in 2:
		var local := fmod(cyc + axis * 23.0, 46.0)
		var state := "g" if local < 20.0 else ("y" if local < 23.0 else "r")
		for col in ["r", "y", "g"]:
			(_sig_mats["%s%d" % [col, axis]] as StandardMaterial3D).emission_energy_multiplier = 6.0 if col == state else 0.0


# ---------------------------------------------------------------- لوحات إعلانية مضيئة
func billboards(viewport_parent: Node) -> void:
	var ads := [
		["مطعم الأصالة", "أشهى المشاوي في المدينة", Color("e8452c"), Color("1b0d08")],
		["شبكة الريح 5G", "أسرع إنترنت. بلا حدود", Color("26b5ff"), Color("061522")],
		["عطر دمار", "رائحة الليل", Color("d4a640"), Color("140f05")],
		["بنك المدينة", "قرض سيارتك خلال ساعة", Color("39e27d"), Color("06150c")],
	]
	var textures: Array[Texture2D] = []
	for ad in ads:
		var vp := SubViewport.new()
		vp.size = Vector2i(1024, 512)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.transparent_bg = false
		var bg := ColorRect.new()
		bg.color = ad[3]
		bg.size = Vector2(1024, 512)
		vp.add_child(bg)
		var stripe := ColorRect.new()
		stripe.color = ad[2]
		stripe.position = Vector2(0, 430)
		stripe.size = Vector2(1024, 82)
		vp.add_child(stripe)
		for k in 2:
			var l := Label.new()
			l.text = ad[k]
			l.add_theme_font_override("font", city.font)
			l.add_theme_font_size_override("font_size", 150 if k == 0 else 64)
			l.add_theme_color_override("font_color", ad[2] if k == 0 else Color(0.95, 0.95, 0.95))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(1024, 220)
			l.position = Vector2(0, 40 if k == 0 else 270)
			vp.add_child(l)
		viewport_parent.add_child(vp)
		textures.append(vp.get_texture())
	var frame_m := StandardMaterial3D.new()
	frame_m.albedo_color = Color(0.15, 0.16, 0.17)
	frame_m.metallic = 0.85
	frame_m.roughness = 0.4
	var count := 0
	for b in city.buildings:
		if count >= 16 or rng.randf() > 0.25:
			continue
		count += 1
		var tex: Texture2D = textures[rng.randi() % textures.size()]
		var n: Vector3 = b.front
		var t := Vector3.UP.cross(n)
		var y: float = b.floors * FacadeKit.MOD + 3.2
		var root := Node3D.new()
		root.position = b.center + n * (b.half - 2.5) + Vector3(0, y, 0)
		root.rotation.y = atan2(n.x, n.z)
		city.add_child(root)
		var panel := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(9.0, 4.5)
		panel.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.emission_enabled = true
		m.emission_texture = tex
		m.emission_energy_multiplier = 1.6
		m.roughness = 0.35
		panel.material_override = m
		panel.position = Vector3(0, 0, 0.06)
		root.add_child(panel)
		var fr := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(9.4, 4.9, 0.1)
		fr.mesh = fb
		fr.material_override = frame_m
		root.add_child(fr)
		for s in [-1, 1]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.18, 3.6, 0.18)
			leg.mesh = lb
			leg.material_override = frame_m
			leg.position = Vector3(s * 3.4, -3.9, -0.4)
			root.add_child(leg)
