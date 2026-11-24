extends Node3D
## منسّق اللعبة: البيئة، المدينة، المركبات، الشرطة، النجوم، السرقة، الاعتقال، الواجهة، الحفظ.

const SAVE_PATH := "user://damar_save.cfg"
const DETAIL_RANGE := [90.0, 140.0, 200.0, 300.0]   # مدى الواجهات التفصيلية لكل مستوى جودة

var state := "menu"        # menu | play | paused | busted | win
var time := 0.0
var city: City
var player: Player
var cam: GameCamera
var hud: Hud
var sfx: Sfx
var cars: Array[Car] = []
var officers: Array = []

# الحالة
var cash := 0
var bank := 0
var wanted := 0
var last_seen := 0.0
var crime_cd := 0.0
var arrest := 0.0
var robbing: City.StoreData = null
var rob_prog := 0.0
var won_shown := false
var rain_on := true

var _spawn_t := 0.0
var _rain: GPUParticles3D
var world: WorldEnv
var quality := 2
var _hint := ""
var _lamps_on := true
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	_load()
	_build_environment()
	quality = _load_quality()
	city = City.new()
	city.detail_range = DETAIL_RANGE[quality]
	add_child(city)
	city.build()

	cam = GameCamera.new()
	cam.game = self
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_apply_quality()

	player = Player.new()
	player.game = self
	add_child(player)
	player.teleport(city.safe_pos + Vector3(0, 0.2, 0), city.safe_sx * PI / 2.0)
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED

	sfx = Sfx.new()
	add_child(sfx)
	_build_rain()

	for i in 16:
		_spawn_civilian(Car.AI.TRAFFIC)
	for i in 26:
		_spawn_civilian(Car.AI.PARKED)
	var starter := _make_car("sedan_sports", false, Car.AI.PARKED, Transform3D(Basis.IDENTITY, city.safe_pos + Vector3(city.safe_sx * 8.0, 0.6, 4.0)))
	starter.engine_power = 6500.0
	starter.max_speed = 38.0
	for i in 2:
		_spawn_police(false)

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.start_pressed.connect(_on_start)
	hud.continue_pressed.connect(_on_continue)
	set_state("menu")

	if "--autotest" in OS.get_cmdline_user_args():
		_autotest()
	elif "--envshots" in OS.get_cmdline_user_args():
		_envshots()


# ---------------------------------------------------------------- واجهة للسكربتات الأخرى
func world_running() -> bool:
	return state == "play" or state == "menu"


func playing() -> bool:
	return state == "play"


func player_on_foot() -> bool:
	return state == "play" and player.car == null


func player_pos() -> Vector3:
	var p := player.car.global_position if player.car else player.global_position
	return Vector3(p.x, 0, p.z)


func player_vel() -> Vector3:
	return player.car.linear_velocity if player.car else player.velocity


func has_los(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Cfg.LAYER_WORLD)
	return _space.intersect_ray(q).is_empty()


func add_wanted(n: int, msg := "") -> void:
	if crime_cd > 0.0 and msg != "" and n == 1:
		return
	set_wanted(wanted + n, msg)
	crime_cd = 4.0


func set_wanted(level: int, msg := "") -> void:
	level = clampi(level, 0, 5)
	if level <= wanted:
		return
	wanted = level
	last_seen = 0.0
	if msg != "":
		hud.toast(msg, Color("ff6b6b"))
	for c in cars:
		if c.ai == Car.AI.POLICE and not c.chase:
			c.chase = true
			c.tgt_n = Cfg.NONE
			c.prev_n = Cfg.NONE


func on_crash(v: float) -> void:
	cam.shake = minf(1.0, v / 18.0)
	sfx.crash(v)


func spawn_officer(car: Car) -> void:
	if officers.size() >= 6 or car.officer != null:
		return
	var o := Officer.new()
	o.game = self
	o.car = car
	add_child(o)
	var r := Vector3(-car.global_basis.z.z, 0, car.global_basis.z.x)
	o.global_position = car.pos2() - r * 1.9 + Vector3(0, 0.2, 0)
	officers.append(o)
	car.officer = o


# ---------------------------------------------------------------- البيئة
func _build_environment() -> void:
	world = WorldEnv.new()
	add_child(world)
	world.weather_changed.connect(func(n): if hud and state == "play": hud.toast("الطقس: " + n, Color("9fd0ff")))


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 6000
	_rain.lifetime = 1.3
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45, 1, 45)
	pm.direction = Vector3(0.05, -1, 0.02)
	pm.spread = 2.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.75)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.7, 0.85, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	_rain.draw_pass_1 = q
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


# ---------------------------------------------------------------- المركبات
func _make_car(model: String, is_police: bool, ai: int, xf: Transform3D) -> Car:
	var c := Car.new()
	c.setup(model, is_police)
	c.game = self
	c.ai = ai
	add_child(c)
	c.global_transform = xf
	cars.append(c)
	return c


func _space_free(p: Vector3, r: float) -> bool:
	for c in cars:
		if (c.global_position - p).length() < r:
			return false
	return (city.safe_pos - p).length() > 6.0


func _spawn_civilian(ai: int) -> void:
	for tries in 30:
		var a := Vector2i(randi_range(0, Cfg.N), randi_range(0, Cfg.N))
		var nb := Cfg.neighbors(a)
		var b: Vector2i = nb[randi() % nb.size()]
		var pa := Cfg.node_pos(a)
		var pb := Cfg.node_pos(b)
		var dx := b.x - a.x
		var dz := b.y - a.y
		var f := randf_range(0.3, 0.7)
		var off := 6.5 if ai == Car.AI.PARKED else Cfg.LANE
		var p := pa.lerp(pb, f) + Vector3(-dz * off, 0.6, dx * off)
		if not _space_free(p, 9.0):
			continue
		var c := _make_car(Cfg.CAR_MODELS[randi() % Cfg.CAR_MODELS.size()], false, ai, Transform3D(Basis(Vector3.UP, atan2(dx, dz)), p))
		if ai == Car.AI.TRAFFIC:
			c.prev_n = a
			c.tgt_n = b
		return


func _spawn_police(chasing: bool) -> void:
	var p := player_pos() if state == "play" else Vector3.ZERO
	var cand: Array[Vector3] = []
	for i in Cfg.N + 1:
		for j in Cfg.N + 1:
			var n := Cfg.node_pos(Vector2i(i, j))
			var d := (n - p).length()
			if d > 110.0 and d < 190.0 and _space_free(n, 10.0):
				cand.append(n)
	if cand.is_empty():
		return
	var at: Vector3 = cand[randi() % cand.size()]
	var h := atan2(p.x - at.x, p.z - at.z)
	var c := _make_car("police_car", true, Car.AI.POLICE, Transform3D(Basis(Vector3.UP, h), at + Vector3(0, 0.6, 0)))
	c.chase = chasing


func _remove_car(c: Car) -> void:
	if c.officer:
		officers.erase(c.officer)
		c.officer.queue_free()
	cars.erase(c)
	c.queue_free()


func _police() -> Array[Car]:
	var out: Array[Car] = []
	for c in cars:
		if c.ai == Car.AI.POLICE:
			out.append(c)
	return out


# ---------------------------------------------------------------- الحالة والقوائم
func set_state(s: String) -> void:
	state = s
	hud.show_state(s)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if s == "play" else Input.MOUSE_MODE_VISIBLE


func _on_start() -> void:
	_respawn()
	set_state("play")
	hud.toast("اسرق المتاجر ($) واهرب إلى المخبأ (H)", Color("ffd36b"))


func _on_continue() -> void:
	if state == "busted":
		_respawn()
	set_state("play")


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		if state == "play":
			set_state("paused")
		elif state == "paused":
			set_state("play")
	elif state == "play" and e is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _respawn() -> void:
	if player.car:
		_exit_car(true)
	wanted = 0
	last_seen = 0.0
	arrest = 0.0
	robbing = null
	for o in officers.duplicate():
		o.queue_free()
	officers.clear()
	var pol := _police()
	for i in pol.size():
		if i >= 2:
			_remove_car(pol[i])
		else:
			pol[i].chase = false
			pol[i].officer = null
			pol[i].tgt_n = Cfg.NONE
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.teleport(city.safe_pos + Vector3(0, 0.2, 0), city.safe_sx * PI / 2.0)
	cam.yaw = city.safe_sx * PI / 2.0


func _bust() -> void:
	hud.set_bust_text("صادرت الشرطة %s كانت بحوزتك. مالك في المخبأ بأمان." % Cfg.money(cash) if cash > 0 else "لم يكن معك مال هذه المرة. مالك في المخبأ بأمان.")
	cash = 0
	arrest = 0.0
	robbing = null
	sfx.busted()
	set_state("busted")


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		bank = cf.get_value("game", "bank", 0)
	won_shown = bank >= Cfg.GOAL


func _update_lamps() -> void:
	var on := world.night > 0.35 or (world.cloud > 0.9 and world.night > 0.15)
	if on != _lamps_on:
		_lamps_on = on
		for l in get_tree().get_nodes_in_group("street_lights"):
			l.visible = on


func _apply_quality() -> void:
	world.apply_quality(quality, get_viewport())
	city.set_detail_range(DETAIL_RANGE[quality])
	cam.far = [600.0, 800.0, 1000.0, 1200.0][quality]


func _load_quality() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		return cf.get_value("settings", "quality", 2)
	return 2


func _save_quality() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("settings", "quality", quality)
	cf.save(SAVE_PATH)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("game", "bank", bank)
	cf.save(SAVE_PATH)


# ---------------------------------------------------------------- ركوب السيارات
func _nearest_car(max_d: float) -> Car:
	var best: Car = null
	var bd := max_d
	for c in cars:
		var d := (c.pos2() - player_pos()).length()
		if d < bd and c.officer == null:
			bd = d
			best = c
	return best


func _police_sees(range_m := 60.0) -> bool:
	for c in _police():
		if (c.pos2() - player_pos()).length() < range_m and has_los(c.global_position + Vector3.UP * 1.5, player_pos() + Vector3.UP * 1.2):
			return true
	return false


func _enter_car(c: Car) -> void:
	if c.police:
		set_wanted(wanted + 2, "سرقت سيارة شرطة!")
	elif c.ai == Car.AI.TRAFFIC and _police_sees():
		set_wanted(wanted + 1, "الشرطة رأتك تسرق سيارة!")
	c.ai = Car.AI.PLAYER
	c.chase = false
	player.car = c
	robbing = null
	player.robbing = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	cam.last_mouse = -10.0
	var hl := SpotLight3D.new()
	hl.name = "Headlight"
	hl.light_color = Color(1, 0.95, 0.85)
	hl.light_energy = 6.0
	hl.spot_range = 60.0
	hl.spot_angle = 28.0
	hl.position = Vector3(0, 0.8, 2.3)
	hl.rotation.y = PI   # الضوء يتجه نحو -Z افتراضياً
	hl.rotation.x = -0.06
	c.add_child(hl)


func _exit_car(force := false) -> void:
	var c := player.car
	if not force and absf(c.speed) > 7.0:
		hud.toast("خفّف السرعة أولاً")
		return
	var f := c.global_basis.z
	var left := Vector3(f.z, 0, -f.x)
	player.car = null
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.collision_layer = Cfg.LAYER_CHARS
	player.visible = true
	player.teleport(c.pos2() + left * 2.1 + Vector3(0, 0.3, 0), c.heading())
	c.ai = Car.AI.PARKED
	var hl := c.get_node_or_null("Headlight")
	if hl:
		hl.queue_free()


# ---------------------------------------------------------------- منطق اللعب
func _interactions(dt: float) -> void:
	var hint := ""
	var p := player_pos()
	var near: City.StoreData = null
	var nd := INF
	for s in city.stores:
		var d := (s.pos - p).length()
		if d < nd:
			nd = d
			near = s
	var d_safe := (city.safe_pos - p).length()
	if player.car == null:
		if near and nd < 3.2:
			if near.cooldown > 0.0:
				hint = "%s مغلق الآن — عُد بعد %d ثانية" % [near.def.name, ceili(near.cooldown)]
				robbing = null
			elif Input.is_action_pressed("interact"):
				if robbing != near:
					robbing = near
					rob_prog = 0.0
					set_wanted(near.def.heat, "🚨 انطلق جهاز الإنذار! الشرطة في الطريق")
				rob_prog += dt / near.def.time
				player.facing = -near.sx * PI / 2.0
				if int(time * 2.5) != int((time - dt) * 2.5):
					sfx.beep()
				if rob_prog >= 1.0:
					var amt := roundi(randf_range(near.def.value[0], near.def.value[1]) / 10.0) * 10
					cash += amt
					near.cooldown = near.def.cd
					robbing = null
					rob_prog = 0.0
					set_wanted(mini(5, maxi(wanted, near.def.heat) + (1 if near.def.heat >= 3 else 0)))
					last_seen = 0.0
					hud.toast("+%s  اهرب إلى المخبأ!" % Cfg.money(amt), Color("7dff9e"))
					sfx.cash()
			else:
				if robbing:
					hud.toast("توقفت السرقة")
					robbing = null
				hint = "اضغط مطولاً E لسرقة %s  (%s – %s)" % [near.def.name, Cfg.money(near.def.value[0]), Cfg.money(near.def.value[1])]
		elif robbing:
			hud.toast("ابتعدت — فشلت السرقة")
			robbing = null
		player.robbing = robbing != null
		if d_safe < 3.6:
			hint = "اضغط E لإخفاء %s في المخبأ" % Cfg.money(cash) if cash > 0 else "المخبأ — أحضر المال المسروق هنا"
			if Input.is_action_just_pressed("interact") and cash > 0:
				if wanted > 0:
					hud.toast("الشرطة تلاحقك! تخلّص منها أولاً", Color("ff6b6b"))
				else:
					bank += cash
					hud.toast("تم إخفاء %s 💰" % Cfg.money(cash), Color("7dff9e"))
					cash = 0
					_save()
					sfx.cash()
					if bank >= Cfg.GOAL and not won_shown:
						won_shown = true
						get_tree().create_timer(0.9).timeout.connect(func(): set_state("win"))
		var car := _nearest_car(3.8)
		if car and hint == "":
			hint = "اضغط F لسرقة سيارة الشرطة (+2 نجمة)" if car.police else "اضغط F لركوب السيارة"
		if car and Input.is_action_just_pressed("vehicle"):
			_enter_car(car)
	else:
		if near and nd < 7.0 and near.cooldown <= 0.0:
			hint = "انزل من السيارة (F) لسرقة %s" % near.def.name
		if d_safe < 7.0 and cash > 0:
			hint = "انزل من السيارة (F) لإخفاء المال"
		if Input.is_action_just_pressed("vehicle"):
			_exit_car()
	_hint = hint


func _wanted_update(dt: float) -> void:
	crime_cd -= dt
	if wanted <= 0:
		return
	var p := player_pos()
	var seen := false
	for c in _police():
		if not c.chase:
			continue
		var d := (c.pos2() - p).length()
		if d < 18.0 or (d < 65.0 and has_los(c.global_position + Vector3.UP * 1.5, p + Vector3.UP * 1.2)):
			seen = true
			break
	if not seen:
		for o in officers:
			if not o.returning and o.distance_to_player() < 35.0:
				seen = true
				break
	if seen or robbing:
		last_seen = 0.0
	else:
		last_seen += dt
	if last_seen > 5.0 + wanted * 2.5:
		wanted -= 1
		last_seen = 0.0
		if wanted == 0:
			hud.toast("تخلّصت من الشرطة! 😎", Color("8fd3ff"))
			for c in _police():
				c.chase = false
				c.tgt_n = Cfg.NONE
		else:
			hud.toast("خسرت نجمة — استمر بالاختباء", Color("8fd3ff"))


func _police_manager(dt: float) -> void:
	_spawn_t -= dt
	var pol := _police()
	if pol.size() < Cfg.POLICE_TARGET[wanted] and _spawn_t <= 0.0:
		_spawn_police(wanted > 0)
		_spawn_t = 2.2 if wanted > 0 else 8.0
	if wanted == 0 and pol.size() > 2:
		for i in range(2, pol.size()):
			if (pol[i].pos2() - player_pos()).length() > 80.0 or state != "play":
				_remove_car(pol[i])


func _arrest_update(dt: float) -> void:
	var rate := 0.0
	if wanted > 0:
		var p := player_pos()
		if player.car == null:
			for o in officers:
				if not o.returning and o.distance_to_player() < 1.9:
					rate += 0.75
			for c in _police():
				if c.chase and (c.pos2() - p).length() < 7.0 and absf(c.speed) < 3.0:
					rate += 0.25
		elif absf(player.car.speed) < 3.0:
			for c in _police():
				if c.chase and (c.pos2() - p).length() < 7.0:
					rate += 0.35
			for o in officers:
				if o.distance_to_player() < 3.3:
					rate += 0.5
	arrest = minf(1.0, arrest + rate * dt) if rate > 0.0 else maxf(0.0, arrest - dt * 0.6)
	if arrest >= 1.0:
		_bust()


func _physics_process(dt: float) -> void:
	_space = get_world_3d().direct_space_state
	if not world_running():
		return
	time += dt
	for s in city.stores:
		s.cooldown = maxf(0.0, s.cooldown - dt)
	_police_manager(dt)
	if state != "play":
		return
	_interactions(dt)
	_wanted_update(dt)
	_arrest_update(dt)


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("toggle_rain"):
		world.set_weather((world.weather + 1) % 4)
	if Input.is_action_just_pressed("cycle_time"):
		world.hour = fmod(world.hour + 3.0, 24.0)
		hud.toast("الوقت: " + world.clock_text(), Color("ffd36b"))
	if Input.is_action_just_pressed("cycle_quality"):
		quality = (quality + 1) % 4
		_apply_quality()
		_save_quality()
		hud.toast("الجودة: " + WorldEnv.QUALITY_NAMES[quality], Color("9fd0ff"))
	if Input.is_action_just_pressed("toggle_mute"):
		sfx.muted = not sfx.muted
		hud.toast("الصوت: مكتوم" if sfx.muted else "الصوت: تشغيل")
	if Input.is_action_just_pressed("horn") and state == "play":
		sfx.horn()

	if cam.is_processing():
		cam.update_camera(dt)
	_rain.emitting = world.rain > 0.03
	_rain.amount_ratio = clampf(world.rain, 0.05, 1.0)
	_rain.global_position = cam.global_position + Vector3(0, 18, 0)
	# المؤثرات البصرية للمتاجر
	var k := 1.0 + sin(time * 3.0) * 0.08
	for s in city.stores:
		var open := s.cooldown <= 0.0
		s.ring.visible = open
		s.beacon.visible = open
		s.ring.scale = Vector3(k, 0.05, k)
		s.sign.modulate = s.def.color * (2.2 if open else 0.35)
		s.glass_mat.albedo_color = s.def.color * (0.6 if open else 0.08)
		s.glow.visible = open
	city.safe_ring.scale = Vector3(k, 0.05, k)
	_update_lamps()

	var siren := 0.0
	if wanted > 0 and state == "play":
		for c in _police():
			if c.chase:
				siren = maxf(siren, pow(maxf(0.0, 1.0 - (c.pos2() - player_pos()).length() / 140.0), 1.5))
	var car := player.car
	sfx.update(siren, absf(car.speed) if car else 0.0, maxf(0.0, car.throttle) if car else 0.0, car != null and state == "play", world.rain > 0.05 and state != "menu")
	if state != "menu":
		hud.refresh(dt, _hint if state == "play" else "")


# ---------------------------------------------------------------- اختبار آلي (godot -- --autotest)
func _autotest() -> void:
	var out := "user://autotest"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	await _frames(30)
	var early := 0
	for car in cars:
		if car.global_basis.y.y < 0.5:
			early += 1
	print("AUTOTEST early flipped=%d" % early)
	await _shot(out + "/1_menu.png")
	_on_start()
	await _frames(40)
	cam.yaw = city.safe_sx * PI / 2.0
	await _frames(30)
	await _shot(out + "/2_start.png")
	# ركوب السيارة والقيادة
	var c := _nearest_car(30.0)
	player.global_position = c.global_position + Vector3(2, 0, 0)
	await _frames(5)
	_enter_car(c)
	Input.action_press("move_forward")
	for i in 5:
		await _frames(30)
		print("AUTOTEST speed t=%.1fs kmh=%.0f pos=%s" % [(i + 1) * 0.5, absf(c.speed) * 3.6, c.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
	print("AUTOTEST drive: in_car=%s speed_kmh=%.0f" % [player.car != null, absf(c.speed) * 3.6])
	await _shot(out + "/3_drive.png")
	Input.action_release("move_forward")
	await _frames(120)
	_exit_car(true)
	await _frames(10)
	# سرقة متجر مجوهرات
	var st: City.StoreData = null
	for s in city.stores:
		if s.type == "jewel":
			st = s
	player.teleport(st.pos + Vector3(0, 0.3, 0), -st.sx * PI / 2.0)
	cam.yaw = st.sx * PI / 2.0
	await _frames(10)
	Input.action_press("interact")
	await _frames(int(st.def.time * 60.0) + 20)
	Input.action_release("interact")
	print("AUTOTEST rob: cash=%d wanted=%d" % [cash, wanted])
	await _frames(300)
	var pol := _police()
	var nearest := INF
	for p in pol:
		nearest = minf(nearest, (p.pos2() - player_pos()).length())
	print("AUTOTEST chase: police=%d chasing=%d nearest=%.1f officers=%d arrest=%.2f state=%s" % [pol.size(), pol.filter(func(x): return x.chase).size(), nearest, officers.size(), arrest, state])
	if officers.size() > 0:
		var o: Node3D = officers[0]
		cam.yaw = atan2(o.global_position.x - player.global_position.x, o.global_position.z - player.global_position.z) + 0.5
		cam.pitch = 0.15
	await _frames(20)
	await _shot(out + "/4_chase.png")
	await _frames(400)
	print("AUTOTEST end: state=%s cash=%d bank=%d" % [state, cash, bank])
	var flipped := 0
	for car in cars:
		if car.global_basis.y.y < 0.5:
			flipped += 1
	var moving := 0
	for car in cars:
		if car.ai == Car.AI.TRAFFIC and car.linear_velocity.length() > 2.0:
			moving += 1
	print("AUTOTEST cars: total=%d flipped=%d traffic_moving=%d" % [cars.size(), flipped, moving])
	for car in cars:
		if car.global_basis.y.y < 0.5:
			print("  FLIPPED ai=%d police=%s pos=%s up=%s" % [car.ai, car.police, car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), car.global_basis.y.snapped(Vector3(0.01, 0.01, 0.01))])
	get_tree().quit()


## لقطات البيئة: أوقات وطقس مختلفة من زاوية ثابتة في الشارع
func _envshots() -> void:
	var out := "user://envshots"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--only="):
			only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	world.cycle_enabled = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glassdebug="):
			city.kit.glass_mat.set_shader_parameter("debug_mode", int(a.substr(13)))
		if a.begins_with("--quality="):
			quality = int(a.substr(10))
			world.apply_quality(quality, get_viewport())
	_on_start()
	hud.visible = false
	var spots := [
		["street", Vector3(-129.5, 1.7, -180), Vector3(-131.5, 5.0, -110)],
		["avenue", Vector3(-110, 1.6, 3.5), Vector3(-40, 6.0, -2.0)],
		["corner", Vector3(-60, 2.2, -60), Vector3(-80, 8.0, -85)],
		["aerial", Vector3(-150, 70, -150), Vector3(0, 0, 0)],
	]
	var looks := [["noon_clear", 12.5, 0], ["sunset", 17.9, 1], ["night_rain", 22.0, 2], ["night_storm", 1.0, 3]]
	for spot in spots:
		for lk in looks:
			var name: String = "%s_%s" % [spot[0], lk[0]]
			if only != "" and not name.contains(only):
				continue
			world.hour = lk[1]
			world.set_weather(lk[2], true)
			set_process(false)
			cam.set_process(false)
			cam.global_position = spot[1]
			cam.look_at(spot[2])
			await _frames(20)
			_update_lamps()
			await _frames(25)
			await _shot("%s/%s.png" % [out, name])
			if spot[0] == "street" and lk[0] == "noon_clear":
				print("RENDER_INFO objects=%d primitives=%d draw_calls=%d vram_mb=%d" % [
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)
		print("AUTOTEST shot: ", path)
