class_name FacadeKit
extends RefCounted
## يجمّع مباني حقيقية من طقم واجهات Poly Haven (Modular Urban Apartments Facade, CC0):
## وحدات 3×3 م (جدار + نافذة/باب بإطار وزجاج)، أفاريز بين الطوابق، وتاج في الأعلى.
## كل نوع قطعة في كل مبنى = MultiMesh واحد (رسم واحد للبطاقة الرسومية) مع LOD تلقائي ومدى رؤية.

const KIT := "res://assets/polyhaven/models/modular_urban_apartments_facade/modular_urban_apartments_facade.gltf"
const PREFIX := "modular_urban_apartments_facade_"
const MOD := 3.0          # عرض وارتفاع الوحدة
const WINDOW_TYPES := ["window_centered_large_01", "window_centered_double_01", "window_centered_small_01", "window_offset_small_01"]
const GROUND_TYPES := ["window_centered_large_01", "window_centered_double_01"]
const DOOR_TYPES := ["door_centered_large_01", "door_centered_small_01", "door_centered_small_02"]
# خامات الواجهات الحقيقية (Poly Haven): الاسم، حجم البلاطة، لون أساسي
const WALLS := [["painted_plaster_wall", 3.0], ["concrete_wall_008", 3.5], ["red_brick_03", 2.4],
	["concrete_tile_facade", 4.0], ["rectangular_facade_tiles", 3.0]]
const TINTS := [Color(1, 1, 1), Color(0.93, 0.86, 0.74), Color(0.78, 0.78, 0.78), Color(0.86, 0.68, 0.56),
	Color(0.72, 0.78, 0.82), Color(0.98, 0.93, 0.82), Color(0.6, 0.58, 0.55), Color(0.85, 0.8, 0.7)]

var pieces := {}       # الاسم المختصر -> {"mesh": Mesh, "basis": Basis}
var glass_mat: ShaderMaterial
var plaster_core: StandardMaterial3D
var far_mat: ShaderMaterial
var column_mat: ShaderMaterial
var detail_range := 200.0
var wall_mats: Array[ShaderMaterial] = []
var column_mats: Array[ShaderMaterial] = []
var far_mats: Array[ShaderMaterial] = []
const TEX := "res://assets/polyhaven/models/modular_urban_apartments_facade/textures/modular_urban_apartments_facade_plaster_%s_1k.jpg"


func _init() -> void:
	var root: Node3D = load(KIT).instantiate()
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = load("res://shaders/window_glass.gdshader")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var short := String(mi.name).replace(PREFIX, "")
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m == null:
				continue
			if m.resource_name.ends_with("glass"):
				mesh.surface_set_material(s, glass_mat)
			elif m.resource_name.ends_with("plaster") and m is StandardMaterial3D:
				var pm := (m as StandardMaterial3D)
				pm.vertex_color_use_as_albedo = true      # لون مختلف لكل مبنى عبر MultiMesh
				if plaster_core == null:
					plaster_core = pm.duplicate()
					plaster_core.vertex_color_use_as_albedo = false
		pieces[short] = {"mesh": mesh, "basis": Car._xf_to(mi, root).basis}
	root.free()
	far_mat = ShaderMaterial.new()
	far_mat.shader = load("res://shaders/far_building.gdshader")
	far_mat.set_shader_parameter("albedo_tex", load(TEX % "diff"))
	far_mat.set_shader_parameter("normal_tex", load(TEX % "nor_gl"))
	column_mat = ShaderMaterial.new()
	column_mat.shader = load("res://shaders/pbr_world.gdshader")
	column_mat.set_shader_parameter("albedo_tex", load(TEX % "diff"))
	column_mat.set_shader_parameter("normal_tex", load(TEX % "nor_gl"))
	column_mat.set_shader_parameter("arm_tex", load(TEX % "arm"))
	column_mat.set_shader_parameter("tile_size", 3.0)
	column_mat.set_shader_parameter("wet_response", 0.3)
	for w in WALLS:
		var path := "res://assets/polyhaven/textures/%s/%%s_2k.jpg" % w[0]
		for kind in 3:
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/far_building.gdshader" if kind == 2 else "res://shaders/pbr_world.gdshader")
			m.set_shader_parameter("albedo_tex", load(path % "diff"))
			m.set_shader_parameter("normal_tex", load(path % "nor"))
			if kind != 2:
				m.set_shader_parameter("arm_tex", load(path % "arm"))
				m.set_shader_parameter("tile_size", w[1])
				m.set_shader_parameter("wet_response", 0.35)
				m.set_shader_parameter("dirt", 0.3)
				m.set_shader_parameter("use_instance_color", kind == 0)
			else:
				m.set_shader_parameter("tile_scale", w[1])
			[wall_mats, column_mats, far_mats][kind].append(m)


func has(piece: String) -> bool:
	return pieces.has(piece)


## يبني مبنى كاملاً. center على الأرض، size عرض المبنى (مضاعف 3 م)، floors عدد الطوابق.
## front_dir: الواجهة التي تحمل الباب (Vector3 أفقي)، plain_faces: واجهات خلفية تُبنى بنوافذ صغيرة.
func build(parent: Node3D, center: Vector3, modules: int, floors: int, rng: RandomNumberGenerator, front_dir: Vector3, ground_override := {}) -> Node3D:
	var b := Node3D.new()
	b.position = center
	parent.add_child(b)
	var half := modules * MOD / 2.0
	var wall_i := rng.randi() % WALLS.size()
	var tint: Color = TINTS[rng.randi() % TINTS.size()]
	if WALLS[wall_i][0] == "red_brick_03":
		tint = Color(1, 1, 1).lerp(tint, 0.3)
	var win: String = WINDOW_TYPES[rng.randi() % WINDOW_TYPES.size()]
	var ground_win: String = GROUND_TYPES[rng.randi() % GROUND_TYPES.size()]
	var door: String = DOOR_TYPES[rng.randi() % DOOR_TYPES.size()]
	var plain_pattern := rng.randf() < 0.35          # وحدات صمّاء في الأطراف لتنويع الإيقاع
	var cornice_every := 1 if rng.randf() < 0.5 else floors
	var batches := {}      # piece -> [Array[Transform3D], Array[Color] tint, Array[Color] custom]

	for face in 4:
		var n := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][face] as Vector3
		var t := Vector3.UP.cross(n)                  # محور الوحدة المحلي x
		var basis := Basis(t, Vector3.UP, n)
		var is_front := n.dot(front_dir) > 0.7
		for f in floors:
			for i in modules:
				var right_edge := -half + MOD * (i + 1)
				var origin := n * half + t * right_edge + Vector3(0, f * MOD, 0)
				var xf := Transform3D(basis, origin)
				var piece: String
				if f == 0:
					var door_slot := modules / 2
					if is_front and i == door_slot:
						piece = ground_override.get("door", door)
					elif is_front:
						piece = ground_override.get("window", ground_win)
					else:
						piece = "window_centered_small_01" if (i % 2 == 0) else ""
				else:
					var edge := i == 0 or i == modules - 1
					piece = "" if (plain_pattern and edge) else win
				var wall := ("wall_" + piece) if piece != "" else "wall_standard_standard_01"
				if not pieces.has(wall):
					wall = "wall_standard_standard_01"
					piece = ""
				_add(batches, wall, xf, tint)
				if piece != "" and pieces.has(piece):
					_add(batches, piece, xf, Color.WHITE, true, rng)
				if f > 0 and (f % cornice_every == 0) and pieces.has("cornice_standard_standard_01"):
					_add(batches, "cornice_standard_standard_01", Transform3D(basis, origin - Vector3(0, 0.1, 0)), tint * 0.92)
			# التاج أعلى المبنى
		for i in modules:
			var origin2 := n * half + t * (-half + MOD * (i + 1)) + Vector3(0, floors * MOD, 0)
			_add(batches, "crown_standard_standard_01", Transform3D(basis, origin2), tint * 0.95)

	for piece in batches:
		var mmi := _emit(b, piece, batches[piece])
		if piece.begins_with("wall_"):
			mmi.material_override = wall_mats[wall_i]

	# أعمدة الزوايا، القلب الداخلي، والسقف
	var h := floors * MOD
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(b, Vector3(sx * half, h / 2.0 + 0.2, sz * half), Vector3(0.55, h + 0.4, 0.55), column_mats[wall_i], tint)
	# القلب: يظهر كنسخة بعيدة (نوافذ مرسومة) عندما تختفي الواجهات التفصيلية
	var core := _box(b, Vector3(0, h / 2.0, 0), Vector3(half * 2 - 0.4, h - 0.05, half * 2 - 0.4), far_mats[wall_i], tint)
	core.set_instance_shader_parameter("has_windows", 1.0)
	return b


func _add(batches: Dictionary, piece: String, xf: Transform3D, tint: Color, windowed := false, rng: RandomNumberGenerator = null) -> void:
	if not pieces.has(piece):
		return
	if not batches.has(piece):
		batches[piece] = [[], [], []]
	batches[piece][0].append(xf * Transform3D(pieces[piece].basis, Vector3.ZERO))
	batches[piece][1].append(tint)
	var cust := Color(randf(), randf(), randf(), 0) if windowed else Color(0, 0, 0, 0)
	batches[piece][2].append(cust)


func _emit(parent: Node3D, piece: String, data: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = pieces[piece].mesh
	mm.instance_count = data[0].size()
	for i in data[0].size():
		mm.set_instance_transform(i, data[0][i])
		mm.set_instance_color(i, data[1][i])
		mm.set_instance_custom_data(i, data[2][i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = detail_range
	mmi.visibility_range_end_margin = 20.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mmi.add_to_group("facade_detail")
	parent.add_child(mmi)
	return mmi


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, tint: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mi.position = pos
	parent.add_child(mi)
	return mi
