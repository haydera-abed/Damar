class_name Extras
extends Node
## محطات تأجير السيارات المجانية، ومنحدرات القفز للهروب من الشرطة.

var game: Node
var terminals: Array[Vector3] = []
var rental: Car
var ramps: Array[Vector3] = []


func _init(g: Node) -> void:
	game = g


func setup() -> void:
	var city: City = game.city
	# محطات تأجير على أرصفة بعض المربعات
	var inner := city.blocks.filter(func(b): return absf(b.center.x) < Cfg.HALF and absf(b.center.y) < Cfg.HALF and not b.park)
	inner.shuffle()
	for k in mini(6, inner.size()):
		var b: Dictionary = inner[k]
		var p := Vector3(b.center.x + 23.0, 0.15, b.center.y - 4.0)
		terminals.append(p)
		_kiosk(p)
	# منحدرات قفز على الطرق المستقيمة
	for spec in [[Vector2i(1, 3), Vector2i(2, 3)], [Vector2i(4, 1), Vector2i(4, 2)], [Vector2i(3, 5), Vector2i(4, 5)], [Vector2i(5, 3), Vector2i(5, 4)]]:
		var a := Cfg.node_pos(spec[0])
		var b2 := Cfg.node_pos(spec[1])
		var mid := (a + b2) / 2.0
		var dir := (b2 - a).normalized()
		_ramp(mid, atan2(dir.x, dir.z))
		ramps.append(mid)


func _kiosk(p: Vector3) -> void:
	var city: City = game.city
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 1.7, 0.9)
	body.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.35, 0.75)
	m.metallic = 0.5
	m.roughness = 0.35
	body.material_override = m
	body.position = p + Vector3(0, 0.85, 0)
	city.add_child(body)
	var screen := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.6, 0.45)
	screen.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.4, 0.9, 1.6)
	screen.material_override = sm
	screen.position = p + Vector3(0.26, 1.25, 0)
	screen.rotation.y = PI / 2.0
	city.add_child(screen)
	var l: Label3D = game.crime._label("🚗 تأجير مجاني", Color("6fd0ff"), p + Vector3(0, 2.3, 0), 64)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.visibility_range_end = 40.0
	city._static_box(p + Vector3(0, 0.85, 0), Vector3(0.5, 1.7, 0.9))


func _ramp(center: Vector3, yaw: float) -> void:
	# منحدر إسفيني: يرتفع 1.1 م على طول 6 م
	var L := 6.0
	var W := 3.4
	var H := 1.1
	var pts := PackedVector3Array([
		Vector3(-W / 2, 0, -L / 2), Vector3(W / 2, 0, -L / 2), Vector3(-W / 2, 0, L / 2), Vector3(W / 2, 0, L / 2),
		Vector3(-W / 2, H, L / 2), Vector3(W / 2, H, L / 2)])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = center + Vector3(-Cfg.LANE * cos(yaw), 0, Cfg.LANE * sin(yaw))
	body.rotation.y = yaw
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [[0, 4, 1], [1, 4, 5], [0, 2, 4], [1, 5, 3], [2, 3, 4], [3, 5, 4], [0, 1, 2], [1, 3, 2]]
	for t in tris:
		for i in t:
			st.add_vertex(pts[i])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.42)
	m.roughness = 0.8
	m.metallic = 0.3
	mi.material_override = m
	body.add_child(mi)
	game.city.add_child(body)


func interact(_dt: float) -> String:
	if game.player.car != null:
		return ""
	var p: Vector3 = game.player_pos()
	for t in terminals:
		if p.distance_to(Vector3(t.x, 0, t.z)) < 1.8:
			if Input.is_action_just_pressed("interact"):
				_rent(t)
			return "اضغط E لاستئجار سيارة مجانية"
	return ""


func _rent(t: Vector3) -> void:
	if rental != null and is_instance_valid(rental) and rental != game.player.car:
		game.remove_car(rental)
	var spot := t + Vector3(4.0, 0.6, 0)
	rental = game._make_car(Cfg.CAR_MODELS[randi() % Cfg.CAR_MODELS.size()], false, Car.AI.PARKED, Transform3D(Basis.IDENTITY, spot))
	rental.engine_power = 6000.0
	rental.max_speed = 36.0
	game.hud.toast("سيارتك المستأجرة جاهزة بجانب المحطة 🔑", Color("6fd0ff"))
