class_name Car
extends VehicleBody3D
## سيارة بفيزياء حقيقية (VehicleBody3D). يقودها اللاعب أو الذكاء الاصطناعي (مرور مدني أو شرطة).

enum AI { PARKED, TRAFFIC, POLICE, PLAYER }

const MODELS := {
	"sedan": preload("res://assets/models/sedan.glb"),
	"sedan_sports": preload("res://assets/models/sedan_sports.glb"),
	"suv": preload("res://assets/models/suv.glb"),
	"suv_luxury": preload("res://assets/models/suv_luxury.glb"),
	"taxi": preload("res://assets/models/taxi.glb"),
	"van": preload("res://assets/models/van.glb"),
	"hatchback_sports": preload("res://assets/models/hatchback_sports.glb"),
	"delivery_van": preload("res://assets/models/delivery_van.glb"),
	"police_car": preload("res://assets/models/police_car.glb"),
	"hero": preload("res://assets/models/hero/CarConcept.glb"),
}
const PAINT_SHADER := preload("res://shaders/car_paint.gdshader")
static var _paint_cache := {}
const LENGTH := 4.4

var game: Node          # main.gd
var ai := AI.PARKED
var police := false
var chase := false
var max_speed := 33.0   # م/ث
var engine_power := 5200.0

# مدخلات القيادة
var throttle := 0.0
var steer_in := 0.0
var handbrake := false

var speed := 0.0        # السرعة الأمامية (م/ث)
var prev_n := Cfg.NONE
var tgt_n := Cfg.NONE
var officer: Node = null
var exit_cd := 0.0

var _steer_s := 0.0
var _stuck_t := 0.0
var _reverse_t := 0.0
var _blocked_t := 0.0
var _ignore_t := 0.0
var _flip_t := 0.0
var _wheels: Array[VehicleWheel3D] = []
var _rear: Array[VehicleWheel3D] = []
var _tail_mat: StandardMaterial3D
var _bar_r: StandardMaterial3D
var _bar_b: StandardMaterial3D
var _siren_light: OmniLight3D
var _phase := randf()
var height := 1.5
var is_hero := false
var locked := false          # مقفلة (سيارة المعرض/شاحنة المشتري): لا يمكن قيادتها
var exhibit := false
var _paint_mats: Array[StandardMaterial3D] = []


func setup(model: String, is_police: bool) -> void:
	police = is_police
	mass = 1200.0
	collision_layer = Cfg.LAYER_VEHICLES
	collision_mask = Cfg.LAYER_WORLD | Cfg.LAYER_VEHICLES | Cfg.LAYER_CHARS
	contact_monitor = true
	max_contacts_reported = 4
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	can_sleep = true

	var root: Node3D = MODELS[model].instantiate()
	add_child(root)
	is_hero = model == "hero"
	# السيارة يجب أن تتجه نحو +Z: نقلبها إن كانت العجلات الأمامية خلفها
	for n in root.find_children("*", "Node3D", true, false):
		if String(n.name).to_lower().begins_with("wheelfront") or String(n.name).to_lower().begins_with("wheel-front"):
			if _xf_to(n, root).origin.z < 0.0:
				root.rotation.y = PI
			break
	_apply_materials(root, model)
	# حساب حجم النموذج لتحجيمه إلى 4.4 م طولاً
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := _xf_to(mi, root)
		var b: AABB = xf * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if root.rotation.y != 0.0:
		box = Transform3D(Basis(Vector3.UP, root.rotation.y), Vector3.ZERO) * box
	var s := LENGTH / box.size.z
	root.scale = Vector3.ONE * s
	root.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	height = box.size.y * s
	var width := box.size.x * s

	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# العجلات: ننقل نموذج كل عجلة إلى VehicleWheel3D
	for n in root.find_children("*", "Node3D", true, false):
		var wn := n as Node3D
		var nm := String(wn.name).to_lower()
		if not nm.begins_with("wheel") or String(wn.get_parent().name).to_lower().begins_with("wheel"):
			continue
		if not (nm.contains("front") or nm.contains("back") or nm.contains("rear")):
			continue
		var wxf := _xf_to(wn, self)
		var w_box: AABB = (wn as MeshInstance3D).mesh.get_aabb() if wn is MeshInstance3D else AABB(Vector3(-0.3, -0.3, -0.3), Vector3(0.6, 0.6, 0.6))
		var radius: float = (wxf * w_box).size.y * 0.5
		var wheel := VehicleWheel3D.new()
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = 0.22
		wheel.suspension_travel = 0.22
		wheel.suspension_stiffness = 60.0
		wheel.suspension_max_force = 20000.0
		wheel.damping_compression = 3.0
		wheel.damping_relaxation = 4.0
		wheel.wheel_friction_slip = 1.8
		wheel.wheel_roll_influence = 0.01
		var front := wxf.origin.z > 0.0
		wheel.use_as_steering = front
		wheel.use_as_traction = not front
		wheel.position = wxf.origin + Vector3(0, 0.15, 0)
		add_child(wheel)
		wn.owner = null
		wn.get_parent().remove_child(wn)
		wheel.add_child(wn)
		wn.transform = Transform3D(wxf.basis, Vector3(0, -0.15, 0))
		_wheels.append(wheel)
		if not front:
			_rear.append(wheel)

	var shape := BoxShape3D.new()
	shape.size = Vector3(width * 0.92, height * 0.55, LENGTH * 0.96)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, height * 0.55, 0)
	add_child(cs)
	center_of_mass = Vector3(0, 0.0, 0)  # منخفض جداً: الإطارات تنزلق قبل أن تنقلب السيارة

	# أضواء أمامية وخلفية
	var head := StandardMaterial3D.new()
	head.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head.albedo_color = Color(4, 4, 3.6)
	if _tail_mat == null:
		_tail_mat = StandardMaterial3D.new()
		_tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tail_mat.albedo_color = Color(1.2, 0.05, 0.05)
	var lx := width * 0.3
	var ly := height * 0.36
	if not is_hero:
		for sx in [-1, 1]:
			_light_box(Vector3(sx * lx, ly, LENGTH / 2.0), head)
			_light_box(Vector3(sx * lx, ly + 0.05, -LENGTH / 2.0), _tail_mat)
	if police:
		_bar_r = StandardMaterial3D.new()
		_bar_r.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bar_b = _bar_r.duplicate()
		_light_box(Vector3(-0.28, height - 0.04, -0.15), _bar_r, Vector3(0.5, 0.14, 0.3))
		_light_box(Vector3(0.28, height - 0.04, -0.15), _bar_b, Vector3(0.5, 0.14, 0.3))
		_siren_light = OmniLight3D.new()
		_siren_light.omni_range = 22.0
		_siren_light.light_energy = 0.0
		_siren_light.position = Vector3(0, height + 0.6, 0)
		add_child(_siren_light)
		engine_power = 6500.0
		max_speed = 30.0
	body_entered.connect(_on_body_entered)


## مواد واقعية: طلاء بورنيش لنماذج Kenney، ومواد خاصة لسيارة البطل (Khronos Car Concept)
func _apply_materials(root: Node, model: String) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if src == null:
				continue
			var nm := src.resource_name.to_lower()
			if model == "hero":
				var m: BaseMaterial3D = null
				if nm.begins_with("paint"):
					var p := StandardMaterial3D.new()
					p.albedo_color = Color(0.32, 0.015, 0.02) if nm.contains("1") else Color(0.06, 0.06, 0.065)
					p.metallic = 0.6
					p.roughness = 0.3
					p.clearcoat_enabled = true
					p.clearcoat = 1.0
					p.clearcoat_roughness = 0.03
					if src.normal_texture:
						p.normal_enabled = true
						p.normal_texture = src.normal_texture
						p.normal_scale = 0.25
						p.uv1_scale = src.uv1_scale
					m = p
					_paint_mats.append(p)
				elif nm.contains("glass"):
					var g := StandardMaterial3D.new()
					g.albedo_color = Color(0.02, 0.025, 0.03, 0.55)
					g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					g.roughness = 0.02
					g.metallic_specular = 1.0
					m = g
				elif nm.contains("mirror"):
					var mm := StandardMaterial3D.new()
					mm.albedo_color = Color(0.9, 0.9, 0.9)
					mm.metallic = 1.0
					mm.roughness = 0.0
					m = mm
				elif nm.contains("brakelight"):
					var b := StandardMaterial3D.new()
					b.albedo_color = Color(0.5, 0.02, 0.02)
					b.roughness = 0.15
					b.emission_enabled = true
					b.emission = Color(1, 0.05, 0.03)
					b.emission_energy_multiplier = 1.0
					_tail_mat = b
					m = b
				elif nm.contains("headlight"):
					var h := StandardMaterial3D.new()
					h.albedo_color = Color(0.9, 0.9, 0.9)
					h.roughness = 0.05
					h.emission_enabled = true
					h.emission = Color(1, 0.97, 0.9)
					h.emission_energy_multiplier = 4.0
					m = h
				if m:
					mi.set_surface_override_material(si, m)
			elif src.albedo_texture:
				var key := src.albedo_texture.resource_path + str(src.albedo_texture.get_rid())
				if not _paint_cache.has(key):
					var sm := ShaderMaterial.new()
					sm.shader = PAINT_SHADER
					sm.set_shader_parameter("albedo_tex", src.albedo_texture)
					_paint_cache[key] = sm
				mi.set_surface_override_material(si, _paint_cache[key])


func set_paint(c: Color) -> void:
	for m in _paint_mats:
		m.albedo_color = c


func _light_box(p: Vector3, m: Material, size := Vector3(0.4, 0.13, 0.05)) -> void:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = m
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func _xf_to(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func heading() -> float:
	return Cfg.heading_of(global_basis.z)


func pos2() -> Vector3:
	return Vector3(global_position.x, 0, global_position.z)


# ---------------------------------------------------------------- الفيزياء
func _physics_process(dt: float) -> void:
	if game == null or not game.world_running():
		return
	exit_cd -= dt
	match ai:
		AI.TRAFFIC: _traffic_ai(dt, 11.0)
		AI.POLICE: _police_ai(dt)
		AI.PLAYER: _player_input()
		_:
			throttle = 0.0
			steer_in = 0.0
			handbrake = true

	var v := linear_velocity
	speed = v.dot(global_basis.z)
	var spd := v.length()
	_steer_s = move_toward(_steer_s, steer_in, dt * 4.0)
	steering = _steer_s * 0.55 / (1.0 + spd * 0.11)

	var braking := (throttle < -0.05 and speed > 1.0) or (throttle > 0.05 and speed < -1.0)
	if braking:
		engine_force = 0.0
		brake = 30.0 * absf(throttle)
	else:
		var limit := max_speed if throttle >= 0.0 else max_speed * 0.35
		engine_force = throttle * engine_power * (1.0 if spd < limit else 0.0)
		brake = 1.5 if absf(throttle) < 0.05 else 0.0
	for w in _rear:
		w.brake = 40.0 if handbrake else 0.0
		w.wheel_friction_slip = 1.0 if handbrake else 1.8

	# إعادة السيارة المقلوبة
	if global_basis.y.y < 0.7:
		_flip_t += dt
		if _flip_t > 2.0:
			_flip_t = 0.0
			var h := heading()
			global_transform = Transform3D(Basis(Vector3.UP, h), pos2() + Vector3(0, 0.6, 0))
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_t = 0.0

	# المؤثرات
	var bright := braking or (handbrake and ai != AI.PARKED)
	if is_hero:
		_tail_mat.emission_energy_multiplier = 8.0 if bright else 1.5
	else:
		_tail_mat.albedo_color = Color(6, 0.25, 0.25) if bright else Color(1.2, 0.05, 0.05)
	if police:
		var on := chase
		var red := fmod(game.time * 2.2 + _phase, 1.0) < 0.5
		_bar_r.albedo_color = Color(9, 0.1, 0.1) if on and red else Color(0.4, 0, 0)
		_bar_b.albedo_color = Color(0.1, 1.5, 10) if on and not red else Color(0, 0, 0.4)
		_siren_light.light_energy = 4.0 if on else 0.0
		_siren_light.light_color = Color(1, 0.1, 0.1) if red else Color(0.15, 0.3, 1)


func _player_input() -> void:
	throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	handbrake = Input.is_action_pressed("handbrake")


func _on_body_entered(body: Node) -> void:
	if ai != AI.PLAYER or game == null:
		return
	var impact := linear_velocity.length()
	if body is Car:
		impact = (linear_velocity - (body as Car).linear_velocity).length()
	if impact > 5.0:
		game.on_crash(impact)
		if body is Car and (body as Car).police and impact > 9.0:
			game.add_wanted(1, "اصطدمت بسيارة شرطة!")


# ---------------------------------------------------------------- القيادة الآلية
func drive_towards(target: Vector3, max_v: float, dt: float) -> void:
	var to := target - global_position
	var diff := wrapf(atan2(to.x, to.z) - heading(), -PI, PI)
	if _reverse_t > 0.0:
		_reverse_t -= dt
		throttle = -1.0
		steer_in = -signf(diff) if diff != 0.0 else 1.0
		handbrake = false
		return
	var desired := max_v * (1.0 - minf(absf(diff) / 1.6, 1.0) * 0.7)
	throttle = 1.0 if speed < desired else (-0.7 if speed > desired + 2.0 else 0.0)
	steer_in = clampf(diff * 2.5, -1.0, 1.0)
	handbrake = false
	if throttle > 0.5 and absf(speed) < 1.0:
		_stuck_t += dt
	else:
		_stuck_t = maxf(0.0, _stuck_t - dt)
	if _stuck_t > 1.3:
		_reverse_t = 1.1
		_stuck_t = 0.0


func stop() -> void:
	throttle = -1.0 if speed > 0.5 else 0.0
	steer_in = 0.0
	handbrake = absf(speed) < 0.5


func _pick_next(goal: Vector2i) -> Vector2i:
	var opts := Cfg.neighbors(tgt_n).filter(func(n): return prev_n == Cfg.NONE or n != prev_n)
	if opts.is_empty():
		opts = Cfg.neighbors(tgt_n)
	if goal != Cfg.NONE:
		var best: Vector2i = opts[0]
		var bs := INF
		for n in opts:
			var sc := absi(n.x - goal.x) + absi(n.y - goal.y) + randf() * 0.5
			if sc < bs:
				bs = sc
				best = n
		return best
	return opts[randi() % opts.size()]


func _obstacle_ahead() -> bool:
	var f := global_basis.z
	var r := Vector3(-f.z, 0, f.x)
	for o in game.cars:
		if o == self:
			continue
		var rel: Vector3 = o.global_position - global_position
		var a := rel.dot(f)
		if a > 1.0 and a < 9.5 and absf(rel.dot(r)) < 2.3:
			return true
	if game.player_on_foot():
		var rel2: Vector3 = game.player.global_position - global_position
		var a2 := rel2.dot(f)
		if a2 > 1.0 and a2 < 9.5 and absf(rel2.dot(r)) < 1.8:
			return true
	return false


func _traffic_ai(dt: float, max_v: float) -> void:
	if tgt_n == Cfg.NONE:
		tgt_n = Cfg.nearest_node(global_position)
		prev_n = Cfg.NONE
	var tp := Cfg.lane_point(prev_n, tgt_n)
	if (tp - pos2()).length() < 6.0:
		var nx := _pick_next(Cfg.NONE)
		prev_n = tgt_n
		tgt_n = nx
		tp = Cfg.lane_point(prev_n, tgt_n)
	drive_towards(tp, max_v, dt)
	if _ignore_t > 0.0:
		_ignore_t -= dt
	elif _obstacle_ahead():
		throttle = -1.0 if speed > 0.3 else 0.0
		_stuck_t = 0.0
		_blocked_t += dt
		if _blocked_t > 4.0:
			_ignore_t = 2.5
			_blocked_t = 0.0
	else:
		_blocked_t = 0.0


func _police_ai(dt: float) -> void:
	if officer != null:
		stop()
		return
	if not chase:
		_traffic_ai(dt, 12.0)
		return
	var p: Vector3 = game.player_pos()
	var pv: Vector3 = game.player_vel()
	var d := (p - pos2()).length()
	var max_v := minf(27.0 + game.wanted * 1.8, 36.0)
	var target: Vector3
	if d < 60.0 and game.has_los(global_position + Vector3.UP * 1.5, p + Vector3.UP * 1.2):
		var k := clampf(d / 25.0, 0.0, 1.2)
		target = p + pv * k
		tgt_n = Cfg.NONE
		prev_n = Cfg.NONE
	else:
		if tgt_n == Cfg.NONE:
			tgt_n = Cfg.nearest_node(global_position)
			prev_n = Cfg.NONE
		var tp := Cfg.lane_point(prev_n, tgt_n)
		if (tp - pos2()).length() < 8.0:
			var nx := _pick_next(Cfg.nearest_node(p))
			prev_n = tgt_n
			tgt_n = nx
			tp = Cfg.lane_point(prev_n, tgt_n)
		target = tp
	var on_foot: bool = game.player_on_foot()
	drive_towards(target, clampf((d - 6.0) * 1.1, 0.0, max_v) if on_foot and d < 30.0 else max_v, dt)
	if on_foot and d < 9.0 and _reverse_t <= 0.0:
		stop()
	if on_foot and d < 30.0 and absf(speed) < 3.0 and exit_cd <= 0.0:
		game.spawn_officer(self)
