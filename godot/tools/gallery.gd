extends SceneTree
# معرض اختبار للمجسمات: godot --path . -s res://tools/gallery.gd -- out.png name1,name2,...
func _initialize():
	var args := OS.get_cmdline_user_args()
	var names: PackedStringArray = args[1].split(",")
	var root := Node3D.new(); get_root().add_child(root)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.5, 0.55, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.6, 0.6, 0.65); env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, -30, 0); sun.shadow_enabled = true; root.add_child(sun)
	var floor_mi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); floor_mi.mesh = pm; root.add_child(floor_mi)
	var x := 0.0
	var maxh := 1.0
	for n in names:
		var s: Node3D = load("res://assets/polyhaven/models/%s/%s.gltf" % [n, n]).instantiate()
		var box := AABB(); var first := true
		for m in s.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = Car._xf_to(m, s) * (m as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b); first = false
		s.position = Vector3(x - box.position.x, -box.position.y, -box.get_center().z)
		root.add_child(s)
		var l := Label3D.new(); l.text = n; l.font_size = 48; l.pixel_size = 0.004; l.position = Vector3(x + box.size.x / 2, -0.01, 1.2); l.rotation_degrees.x = -90; l.modulate = Color.BLACK; root.add_child(l)
		x += box.size.x + 0.8
		maxh = maxf(maxh, box.size.y)
	var cam := Camera3D.new(); root.add_child(cam)
	await process_frame
	cam.look_at_from_position(Vector3(x / 2, maxh * 0.9 + 1.0, maxf(x, maxh * 2.0) * 0.75 + 2.0), Vector3(x / 2, maxh * 0.35, 0)); cam.current = true
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	quit()
