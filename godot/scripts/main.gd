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
var crime: Crime
var cop: Cop
var gangs: Gangs
var extras: Extras
var land: Land
var no_save := false
var net: Net
var alerts: Array = []          # بلاغات للشرطة على الخريطة [موقع، وقت]
var _bot := ""
var _bot_t := 0.0
var weapons: Weapons
var civilians: Array[Civilian] = []
var rob_label := ""
var jail_t := 0.0
var most_wanted_t := 0.0
var _down_t := 0.0
var _arrested_by_surrender := false
var _wanted_at_bust := 0
var _new_save := true

var _spawn_t := 0.0
var _rain: GPUParticles3D
var world: WorldEnv
var quality := 2
var _hint := ""
var _lamps_on := true
var _head_pool: Array[SpotLight3D] = []
var _head_t := 0.0
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	net = Net.new(self)
	net.name = "Net"
	add_child(net)
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
	for i in 6:
		var hl := SpotLight3D.new()
		hl.light_color = Color(1.0, 0.95, 0.85)
		hl.light_energy = 6.0
		hl.spot_range = 42.0
		hl.spot_angle = 30.0
		hl.spot_angle_attenuation = 1.5
		hl.light_volumetric_fog_energy = 1.2
		hl.visible = false
		add_child(hl)
		_head_pool.append(hl)
	_build_rain()

	for i in 16:
		_spawn_civilian(Car.AI.TRAFFIC)
	for i in 26:
		_spawn_civilian(Car.AI.PARKED)
	var starter := _make_car("hero", false, Car.AI.PARKED, Transform3D(Basis.IDENTITY, city.safe_pos + Vector3(city.safe_sx * 8.0, 0.6, 4.0)))
	starter.engine_power = 6500.0
	starter.max_speed = 38.0
	for i in 2:
		_spawn_police(false)

	weapons = Weapons.new(self)
	add_child(weapons)
	crime = Crime.new(self)
	add_child(crime)
	crime.setup()
	cop = Cop.new(self)
	add_child(cop)
	cop.setup()
	land = Land.new(self)
	add_child(land)
	gangs = Gangs.new(self)
	add_child(gangs)
	gangs.setup()
	land.setup()
	extras = Extras.new(self)
	add_child(extras)
	extras.setup()
	_spawn_civilians(40)
	_load_extra()

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.start_pressed.connect(_on_start)
	hud.continue_pressed.connect(_on_continue)
	set_state("menu")

	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		_start_dedicated(args)
	elif _arg(args, "--join") != "":
		net.my_name = _arg(args, "--name", "لاعب")
		net.my_role = _arg(args, "--role", "criminal")
		_bot = _arg(args, "--bot")
		net.log_events = true
		start_join(_arg(args, "--join"), int(_arg(args, "--port", str(Net.PORT))))
	elif "--autotest" in args:
		no_save = true
		_autotest()
	elif "--envshots" in OS.get_cmdline_user_args():
		no_save = true
		_envshots()
	elif "--landshots" in OS.get_cmdline_user_args():
		no_save = true
		_landshots()


# ---------------------------------------------------------------- واجهة للسكربتات الأخرى
# ---------------------------------------------------------------- اللعب الجماعي
func _arg(args: PackedStringArray, key: String, def := "") -> String:
	for a in args:
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


func _start_dedicated(args: PackedStringArray) -> void:
	var port := int(_arg(args, "--port", str(Net.PORT)))
	var err := net.host(port, true)
	if err != "":
		print("SERVER ERROR: ", err)
		get_tree().quit(1)
		return
	_go_online()
	state = "server"
	hud.visible = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(0, -50, 0)
	print("SERVER READY port=%d" % port)


func start_host(pname: String, role: String, port := Net.PORT) -> void:
	net.my_name = pname
	net.my_role = role
	var err := net.host(port, false)
	if err != "":
		hud.toast(err, Color("ff6b6b"))
		return
	_go_online()
	_on_start()
	if role == "cop":
		cop.start_duty()
	hud.toast("تستضيف لعبة على المنفذ %d — أعطِ أصدقاءك عنوان IP جهازك" % port, Color("9fd0ff"))


func start_join(ip: String, port := Net.PORT) -> void:
	var err := net.join(ip, port)
	if err != "":
		hud.toast(err, Color("ff6b6b"))
		return
	hud.set_menu_status("جارٍ الاتصال بـ %s…" % ip)


## إيقاف ما لا يناسب اللعب الجماعي: الشرطة الآلية (الشرطة لاعبون حقيقيون)
func _go_online() -> void:
	land.mp_apply(net.settle_owner, net.plot_tenant)
	for c in _police():
		_remove_car(c)
	for o in officers.duplicate():
		o.queue_free()
	officers.clear()


func on_net_joined(profile: Dictionary, note: String) -> void:
	_go_online()
	if not profile.is_empty():
		_apply_profile(profile)
		_new_save = false
	_on_start()
	if net.my_role == "cop":
		cop.start_duty()
	if note != "":
		hud.toast(note, Color("ff9b3b"))
	hud.toast("دخلت المدينة كـ %s — %d لاعب متصل" % [net.my_name, net.peers.size()], Color("9fd0ff"))


func on_net_lost(msg: String) -> void:
	if state == "server":
		return
	cop.on_duty = false
	set_state("menu")
	hud.toast(msg, Color("ff6b6b"))


func _profile() -> Dictionary:
	return {"bank": bank, "cash": cash, "crime": crime.to_dict(), "weapons": weapons.to_dict() if not cop.on_duty else cop._saved_weapons, "cop": cop.to_dict(), "land": land.to_dict()}


func _apply_profile(d: Dictionary) -> void:
	bank = d.get("bank", 0)
	won_shown = bank >= Cfg.GOAL
	cash = d.get("cash", 0)
	crime.from_dict(d.get("crime", {}))
	weapons.from_dict(d.get("weapons", {}))
	cop.from_dict(d.get("cop", {}))
	land.from_dict(d.get("land", {}))


func local_net_state() -> Array:
	var f := 0
	if crime.masked:
		f |= Net.F_MASK
	if player.surrendered:
		f |= Net.F_SURRENDER
	if player.downed:
		f |= Net.F_DOWNED
	if player.robbing:
		f |= Net.F_ROBBING
	if weapons.aiming:
		f |= Net.F_AIM
	var c := player.car
	var p: Vector3 = c.global_position if c else player.global_position
	var spd: float = absf(c.speed) if c else Vector2(player.velocity.x, player.velocity.z).length()
	return [p, c.heading() if c else player.facing, spd, f, c.model_name if c else "", c.global_transform if c else Transform3D.IDENTITY, player.health, crime.bag_value()]


func net_set_wanted(level: int) -> void:
	if level > wanted:
		last_seen = 0.0
	wanted = level


func add_alert(p: Vector3) -> void:
	alerts.append([p, 45.0])


func remote_cops_near(p: Vector3, r: float) -> bool:
	for id in net.remotes:
		var rp: RemotePlayer = net.remotes[id]
		if rp.role == "cop" and rp.global_position.distance_to(p) < r:
			return true
	return false


## روبوتات اختبار اللعب الجماعي (--bot=criminal أو --bot=cop)
func _bot_tick(dt: float) -> void:
	if _bot == "" or state != "play":
		return
	_bot_t += dt
	if _bot == "criminal":
		var shop: Crime.Target = crime.targets[0]
		if _bot_t > 3.0 and _bot_t < 3.2 and not crime.masked:
			crime.toggle_mask()
			player.teleport(shop.pos + Vector3(0, 0.3, 0), 0.0)
			print("BOT criminal: at %s" % shop.label)
		if _bot_t > 3.5 and _bot_t < 12.0:
			Input.action_press("interact")
		if _bot_t >= 12.0 and _bot_t < 12.1:
			Input.action_release("interact")
			print("BOT criminal: bag=%d value=%d wanted=%d" % [crime.bag.size(), crime.bag_value(), wanted])
		if _bot_t > 14.0 and not player.surrendered and state == "play":
			player.set_surrender(true)
			print("BOT criminal: surrendered, wanted=%d" % wanted)
	elif _bot == "landlord":
		if _bot_t > 3.0 and _bot_t - dt <= 3.0:
			land.settle_titles[1] = 1
			land._buy_settlement(0)
			print("BOT landlord: requested settlement 0")
		if _bot_t > 6.0 and _bot_t - dt <= 6.0:
			print("BOT landlord: home=%s owner=%s bank=%d" % [land.home, land.owner_text(land.settlements[0]), bank])
		if _bot_t > 22.0 and _bot_t - dt <= 22.0:
			print("BOT landlord: tenants=%s bank=%d rent_received=%d" % [[land.settlements[0].plots[1].tenant], bank, net.rent_total])
			land.settlements[0].tax_box = 500
			land._collect(0)                         # يُبلَّغ الجميع
			land.eviction_rights = 1
			crime.tools["decoder"] = 5
			land._do_evict(0, 1, 2)                  # طرد الساكن (لاعب حقيقي)
	elif _bot == "tenant":
		if _bot_t > 5.0 and _bot_t - dt <= 5.0:
			land.settle_titles[1] = 1
			land._buy_settlement(0)                 # يجب أن يُرفض: للمستوطنة مالك
		if _bot_t > 7.0 and _bot_t - dt <= 7.0:
			print("BOT tenant: settle_titles=%s (refunded?)" % [land.settle_titles])
			land.plot_titles[1] = 1
			land._rent(0, 1)
		if _bot_t > 10.0 and _bot_t - dt <= 10.0:
			print("BOT tenant: home=%s tax=%.2f" % [land.home, land.tenant_tax()])
			crime.launder_pool = 40000.0
		if _bot_t > 20.0 and _bot_t - dt <= 20.0:
			print("BOT tenant: pool=%.0f bank=%d" % [crime.launder_pool, bank])
		if _bot_t > 27.0 and _bot_t - dt <= 27.0:
			print("BOT tenant: after eviction home=%s alerts=%d" % [land.home, alerts.size()])
	elif _bot == "cop":
		if int(_bot_t / 5.0) != int((_bot_t - dt) / 5.0) and _bot_t > 0.0:
			var fl := []
			for id in net.remotes:
				fl.append("%s:%d" % [net.remotes[id].pname, net.remotes[id].flags])
			print("BOT cop: t=%.0f state=%s remotes=%s" % [_bot_t, state, fl])
		for id in net.remotes:
			var rp: RemotePlayer = net.remotes[id]
			if rp.role != "cop" and rp.flags & Net.F_SURRENDER != 0:
				if player.global_position.distance_to(rp.global_position) > 2.0:
					player.teleport(rp.global_position + Vector3(0, 0.3, 1.3), PI)
					print("BOT cop: moved next to %s" % rp.pname)
					_bot_t = 0.0
					# طلقة اختبار بين اللاعبين (من الشرطي نحو اللص)
					var o: Vector3 = player.global_position + Vector3(0, 1.4, 0)
					net.shot(o, (rp.global_position + Vector3(0, 1.0, 0) - o).normalized(), 30.0, 10.0)
				elif _bot_t >= 1.0:
					net.request_arrest(id)
					print("BOT cop: arrest requested on %s, bank=%d" % [rp.pname, bank])
					_bot_t = -1000.0


# ---------------------------------------------------------------- أنظمة الجريمة والقتال
func _spawn_civilians(n: int) -> void:
	var inner := city.blocks.filter(func(b): return absf(b.center.x) < Cfg.HALF and absf(b.center.y) < Cfg.HALF)
	for i in n:
		var b: Dictionary = inner[randi() % inner.size()]
		var c := Civilian.new()
		add_child(c)
		c.setup(self, Vector3(b.center.x, 0, b.center.y))
		civilians.append(c)


func shootables() -> Array:
	var out: Array = []
	out.append_array(officers)
	out.append_array(civilians)
	if state == "play" and player.car == null:
		out.append(player)
	out.append_array(cop.robbers)
	out.append_array(gangs.members)
	return out


func on_gunshot(origin: Vector3, by_player: bool) -> void:
	for c in civilians:
		if c.global_position.distance_to(origin) < 45.0:
			c.scare()
	if by_player:
		var near_cop := _police_sees(70.0)
		for o in officers:
			if o.global_position.distance_to(origin) < 45.0:
				near_cop = true
		if near_cop:
			set_wanted(maxi(wanted, 2), "أطلقت النار! الشرطة سترد بالرصاص")
		elif wanted == 0:
			set_wanted(1, "بلاغ عن إطلاق نار")


func on_civilian_killed(_c: Civilian, from: Node) -> void:
	if from != player:
		return
	add_wanted(1, "قتلت مدنياً!")
	crime_cd = 0.0
	if wanted >= 5:
		most_wanted_t = 30.0
		hud.toast("⚠ أنت المطلوب الأول — موقعك مكشوف لكل دوريات المدينة", Color("ff4b4b"))


func on_officer_down(o: Officer, from: Node) -> void:
	if from == player:
		crime_cd = 0.0
		set_wanted(wanted + 2, "أسقطت شرطياً!")
	if is_instance_valid(o.car):
		o.car.exit_cd = 999.0


func on_player_hit(_dmg: float) -> void:
	cam.shake = maxf(cam.shake, 0.25)
	hud.flash_damage()


func on_player_downed() -> void:
	_down_t = 0.0
	hud.toast("سقطت مصاباً!", Color("ff4b4b"))


func check_win() -> void:
	if bank >= Cfg.GOAL and not won_shown:
		won_shown = true
		get_tree().create_timer(0.9).timeout.connect(func(): set_state("win"))


func exit_car_force() -> void:
	if player.car:
		_exit_car(true)


func remove_car(c: Car) -> void:
	_remove_car(c)


func save_game() -> void:
	if no_save:
		return                       # أوضاع الاختبار والتصوير لا تلمس حفظ اللاعب
	_save()


func close_menu() -> void:
	set_state("play")


func world_running() -> bool:
	return state == "play" or state == "menu" or state == "server" or (net != null and net.is_online() and state != "busted")


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
	if cop != null and cop.on_duty:
		return
	level = clampi(level, 0, 5)
	if net != null and net.is_online():
		net.report_crime(level)
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
	if s != "ui":
		hud.close_menu()
	hud.show_state(s)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if s == "play" else Input.MOUSE_MODE_VISIBLE


func _on_start() -> void:
	_respawn()
	set_state("play")
	if _new_save:
		_new_save = false
		weapons.give("pistol")
		weapons.ammo = 36
		crime.tools["lockpick"] = 3
		cash = 2000
		hud.toast("البس القناع (X)، اسرق، بِع للمشتري ($)، واغسل المال في المخبأ (H)", Color("ffd36b"))
	else:
		hud.toast("مرحباً بعودتك — السمعة %d" % crime.notoriety_level(), Color("ffd36b"))


func _on_continue() -> void:
	if state == "busted":
		if jail_t > 0.0:
			return
		_respawn(true)
	set_state("play")


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and state == "ui":
		set_state("play")
		return
	if state == "play" and e.is_action_pressed("chat") and not hud.chat_edit.visible:
		hud.open_chat()
		get_viewport().set_input_as_handled()
		return
	if hud.chat_edit.visible:
		return
	if state == "play":
		if e.is_action_pressed("mask"):
			if cop.on_duty:
				hud.toast("أنت شرطي في المناوبة")
			else:
				crime.toggle_mask()
		elif e.is_action_pressed("weapon"):
			weapons.cycle()
		elif e.is_action_pressed("surrender") and player.car == null and not player.downed:
			if player.surrendered:
				player.set_surrender(false)
				hud.toast("أنزلت يديك")
			elif wanted > 0:
				player.set_surrender(true)
				hud.toast("استسلمت ✋ — ستحتفظ بأسلحتك لكن تخسر الحقيبة", Color("ffd36b"))
	if e.is_action_pressed("pause"):
		if state == "play":
			set_state("paused")
		elif state == "paused":
			set_state("play")
	elif state == "play" and e is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _respawn(from_jail := false) -> void:
	if player.car:
		_exit_car(true)
	player.revive()
	most_wanted_t = 0.0
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
	var spawn := city.safe_pos
	var yaw := city.safe_sx * PI / 2.0
	if from_jail:
		for s in city.stores:
			if s.type == "police":
				spawn = s.pos
				yaw = s.sx * PI / 2.0
	player.teleport(spawn + Vector3(0, 0.2, 0), yaw)
	cam.yaw = yaw


func _bust() -> void:
	var surrendered := player.surrendered
	var lost_bag := crime.lose_bag()
	var lost_cash := cash
	var lines := []
	if lost_bag > 0:
		lines.append("صودرت حقيبة الغنائم (%s)" % Cfg.money(lost_bag))
	if lost_cash > 0:
		lines.append("صودرت النقود القذرة (%s)" % Cfg.money(lost_cash))
	if not surrendered and weapons.current != "":
		lines.append("صودر سلاحك: " + Weapons.CATALOG[weapons.current].name)
		weapons.drop_current()
	lines.append("الحساب البنكي وطاولة الغسيل بأمان.")
	cash = 0
	_wanted_at_bust = maxi(wanted, 1)
	jail_t = 15.0 * _wanted_at_bust * (0.5 if surrendered else 1.0)
	_arrested_by_surrender = surrendered
	arrest = 0.0
	robbing = null
	player.revive()
	crime.masked = false
	player.human.set_mask(false)
	sfx.busted()
	hud.set_bust_text("\n".join(lines))
	set_state("busted")
	hud.update_jail(jail_t, bank)
	save_game()


## رشوة الضابط: تُدفع من الحساب البنكي، وقد يرفضها
func try_bribe(amount: int) -> void:
	if bank < amount or jail_t <= 0.0:
		return
	var chance := clampf(0.2 + float(amount) / 200000.0 * 0.75 - _wanted_at_bust * 0.04, 0.05, 0.95)
	if randf() < chance:
		bank -= amount
		jail_t = 0.0
		hud.toast("قبل الضابط الرشوة 🤝 (%s)" % Cfg.money(amount), Color("7dff9e"))
	else:
		jail_t += 10.0
		hud.toast("رفض الضابط الرشوة! +10 ثوانٍ", Color("ff6b6b"))
	hud.update_jail(jail_t, bank)
	save_game()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		bank = cf.get_value("game", "bank", 0)
	won_shown = bank >= Cfg.GOAL


func _load_extra() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK and cf.has_section_key("game", "crime"):
		_new_save = false
		cash = cf.get_value("game", "cash", 0)
		crime.from_dict(cf.get_value("game", "crime", {}))
		weapons.from_dict(cf.get_value("game", "weapons", {}))
		cop.from_dict(cf.get_value("game", "cop", {}))
		land.from_dict(cf.get_value("game", "land", {}))
		gangs.from_dict(cf.get_value("game", "gangs", {}))


## مصابيح أمامية حقيقية ليلاً لأقرب السيارات إلى الكاميرا (مجموعة ثابتة من الأضواء لأداء ثابت)
# ---------------------------------------------------------------- إعدادات (من المفاتيح أو قائمة الإيقاف)
func cycle_weather() -> void:
	world.set_weather((world.weather + 1) % 4)
	hud.refresh_settings()


func advance_time() -> void:
	world.hour = fmod(world.hour + 3.0, 24.0)
	hud.toast("الوقت: " + world.clock_text(), Color("ffd36b"))
	hud.refresh_settings()


func cycle_quality() -> void:
	quality = (quality + 1) % 4
	_apply_quality()
	_save_quality()
	hud.toast("الجودة: " + WorldEnv.QUALITY_NAMES[quality], Color("9fd0ff"))
	hud.refresh_settings()


func toggle_season() -> void:
	gangs.season_mode = not gangs.season_mode
	hud.refresh_settings()
	save_game()


func toggle_day_cycle() -> void:
	world.cycle_enabled = not world.cycle_enabled
	hud.refresh_settings()


func _update_headlights() -> void:
	var on := world.night > 0.3 or world.cloud > 0.95
	var cand: Array = []
	if on:
		for c in cars:
			if c == player.car or c.ai == Car.AI.PARKED:
				continue
			var d := c.global_position.distance_squared_to(cam.global_position)
			if d < 140.0 * 140.0:
				cand.append([d, c])
		cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in _head_pool.size():
		var l := _head_pool[i]
		l.visible = i < cand.size()
		if l.visible:
			var c: Car = cand[i][1]
			l.global_transform = c.global_transform * Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.07), Vector3(0, 0.8, 2.4))


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
	if net != null and net.is_online():
		net.save_profile(_profile())
		return
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("game", "bank", bank)
	cf.set_value("game", "cash", cash)
	cf.set_value("game", "crime", crime.to_dict())
	cf.set_value("game", "weapons", weapons.to_dict() if not cop.on_duty else cop._saved_weapons)
	cf.set_value("game", "cop", cop.to_dict())
	cf.set_value("game", "gangs", gangs.to_dict())
	cf.set_value("game", "land", land.to_dict())
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
	if c.locked:
		hud.toast("مقفلة" + (" بإنذار — تحتاج جهاز تشويش" if c.exhibit else ""), Color("ff9b3b"))
		return
	if player.surrendered or player.downed:
		return
	if c.police and not cop.on_duty:
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
	robbing = null
	var hint := ""
	if player.downed or player.surrendered:
		_hint = "✋ مستسلم — اضغط Z لإنزال يديك" if player.surrendered else "مُصاب…"
		return
	var p := player_pos()
	hint = cop.interact_station(dt)
	if hint == "":
		hint = gangs.interact(dt)
	if hint == "":
		hint = land.interact(dt)
	if hint == "":
		hint = extras.interact(dt)
	if hint == "":
		hint = cop.interact(dt) if cop.on_duty else crime.interact(dt)
	var d_safe := (city.safe_pos - p).length()
	if player.car == null:
		if hint == "" and d_safe < 3.6:
			hint = "موتيل Lenny — اضغط E (يحفظ نقودك فقط)" + ("  (عند Lenny: %s)" % Cfg.money(land.motel_cash) if land.motel_cash > 0 else "")
			if Input.is_action_just_pressed("interact"):
				land.open_motel()
		var car := _nearest_car(3.8)
		if car and hint == "":
			if car.locked:
				hint = "سيارة مقفلة"
			else:
				hint = "اضغط F لسرقة سيارة الشرطة (+2 نجمة)" if car.police else "اضغط F لركوب السيارة"
		if car and Input.is_action_just_pressed("vehicle"):
			_enter_car(car)
	else:
		if hint == "" and d_safe < 7.0 and cash > 0:
			hint = "انزل من السيارة (F) لغسيل المال في المخبأ"
		if Input.is_action_just_pressed("vehicle"):
			_exit_car()
	_hint = hint


func _wanted_update(dt: float) -> void:
	crime_cd -= dt
	if net.is_online():
		return                   # الخادم يحسب المطلوبية في اللعب الجماعي
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
	if most_wanted_t > 0.0:
		most_wanted_t -= dt
		seen = true
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
	if net.is_online():
		return
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
	var p := player_pos()
	var helpless := player.surrendered or player.downed
	if player.downed:
		_down_t += dt
		var cops_near := false
		for o in officers:
			if not o.dead and o.distance_to_player() < 60.0:
				cops_near = true
		for c in _police():
			if c.chase and (c.pos2() - p).length() < 60.0:
				cops_near = true
		if net.is_online():
			cops_near = remote_cops_near(p, 60.0)
		if not cops_near and _down_t > 8.0:
			player.revive()
			player.health = 35.0
			hud.toast("نهضت مصاباً — اهرب!", Color("ffd36b"))
	if wanted > 0:
		if player.car == null:
			for o in officers:
				if o.dead or o.returning:
					continue
				var d: float = o.distance_to_player()
				if helpless and d < 2.2:
					rate += 1.4                     # تقييد بالأصفاد
				elif not helpless and wanted <= 1 and d < 1.9:
					rate += 0.75
			for c in _police():
				var cd: float = (c.pos2() - p).length()
				if c.chase and absf(c.speed) < 3.0 and ((helpless and cd < 11.0) or (wanted <= 1 and cd < 7.0)):
					rate += 0.3
		elif absf(player.car.speed) < 3.0:
			for c in _police():
				if c.chase and (c.pos2() - p).length() < 7.0:
					rate += 0.35
			for o in officers:
				if not o.dead and o.distance_to_player() < 3.3:
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
	crime.tick(dt)
	if state != "play":
		return
	cop.tick(dt)
	gangs.tick(dt)
	land.tick(dt)
	_bot_tick(dt)
	for a in alerts.duplicate():
		a[1] -= dt
		if a[1] <= 0.0:
			alerts.erase(a)
	weapons.tick(dt)
	_interactions(dt)
	_wanted_update(dt)
	_arrest_update(dt)


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("toggle_rain"):
		cycle_weather()
	if Input.is_action_just_pressed("cycle_time"):
		advance_time()
	if Input.is_action_just_pressed("cycle_quality"):
		cycle_quality()
	if Input.is_action_just_pressed("toggle_mute"):
		sfx.muted = not sfx.muted
		hud.toast("الصوت: مكتوم" if sfx.muted else "الصوت: تشغيل")
	if Input.is_action_just_pressed("settle_map") and state == "play" and not hud.chat_edit.visible:
		land.open_map()
	if Input.is_action_just_pressed("horn") and state == "play":
		sfx.horn()

	if state == "busted" and jail_t > 0.0:
		jail_t = maxf(0.0, jail_t - dt)
		hud.update_jail(jail_t, bank)
	if cam.is_processing():
		cam.update_camera(dt)
	_rain.emitting = world.rain > 0.03 and not land.inside_home
	_rain.amount_ratio = clampf(world.rain, 0.05, 1.0)
	_rain.global_position = cam.global_position + Vector3(0, 18, 0)
	# المؤثرات البصرية للمتاجر
	var k := 1.0 + sin(time * 3.0) * 0.08
	for s in city.stores:
		var open := s.cooldown <= 0.0
		s.ring.visible = false
		s.beacon.visible = open
		s.ring.scale = Vector3(k, 0.05, k)
		s.sign.modulate = s.def.color * (2.2 if open else 0.35)
		s.glass_mat.albedo_color = s.def.color * (0.6 if open else 0.08)
		s.glow.visible = open
	city.safe_ring.scale = Vector3(k, 0.05, k)
	city.props.update_signals(time)
	_update_headlights()
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_new_save = true
	await _frames(20)
	_on_start()
	await _frames(20)
	print("AUTOTEST start: weapon=%s ammo=%d cash=%d tools=%s" % [weapons.current, weapons.ammo, cash, crime.tools])
	# 1) القيادة
	var c := _nearest_car(40.0)
	_enter_car(c)
	Input.action_press("move_forward")
	await _frames(150)
	print("AUTOTEST drive: in_car=%s speed_kmh=%.0f" % [player.car != null, absf(c.speed) * 3.6])
	Input.action_release("move_forward")
	await _frames(90)
	_exit_car(true)
	await _frames(5)
	# 2) سرقة المجوهرات بلا قناع ثم بقناع
	var st: City.StoreData = null
	for s in city.stores:
		if s.type == "jewel":
			st = s
	crime.toggle_mask()
	player.teleport(st.pos + Vector3(0, 0.3, 0), -st.sx * PI / 2.0)
	cam.yaw = st.sx * PI / 2.0
	await _frames(5)
	Input.action_press("interact")
	await _frames(int(6.0 * 60) + 15)
	Input.action_release("interact")
	print("AUTOTEST rob: bag=%d value=%d wanted=%d masked=%s" % [crime.bag.size(), crime.bag_value(), wanted, crime.masked])
	await _shot(out + "/1_rob.png")
	# 3) البيع للمشتري
	wanted = 0
	var f: Vector3 = crime.fences[0]
	player.teleport(f + Vector3(0, 0.3, 0) + (Vector3(-f.x, 0, -f.z).normalized() * 3.0), 0.0)
	await _frames(5)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(2)
	print("AUTOTEST fence: cash=%d bag=%d notoriety=%d xp=%d" % [cash, crime.bag.size(), crime.notoriety_level(), crime.notoriety_xp])
	await _shot(out + "/2_fence.png")
	# 4) السوق السوداء
	player.teleport(crime.dealer_pos + Vector3(0, 0.3, -1.5), 0.0)
	await _frames(5)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(3)
	await _shot(out + "/3_market.png")
	crime._buy("minidrill")
	print("AUTOTEST market: state=%s minidrill=%d cash=%d" % [state, crime.tools.get("minidrill", 0), cash])
	close_menu()
	# 5) إطلاق النار على مدني
	var victim: Civilian = civilians[0]
	player.teleport(victim.global_position + Vector3(4, 0.3, 0), 0.0)
	await _frames(3)
	weapons.shoot(player.global_position + Vector3(0, 1.4, 0), (victim.global_position + Vector3(0, 1.0, 0) - player.global_position - Vector3(0, 1.4, 0)).normalized(), 30.0, 60.0, player)
	await _frames(3)
	print("AUTOTEST shoot: civilian_dead=%s wanted=%d" % [victim.dead, wanted])
	# 6) مطاردة بمطلوبية عالية: الشرطة تطلق النار
	set_wanted(3, "test")
	var hp0 := player.health
	await _frames(600)
	var pol := _police()
	print("AUTOTEST chase: police=%d officers=%d health=%.0f->%.0f downed=%s state=%s arrest=%.2f" % [pol.size(), officers.size(), hp0, player.health, player.downed, state, arrest])
	if officers.size() > 0:
		var o: Node3D = officers[0]
		cam.yaw = atan2(o.global_position.x - player.global_position.x, o.global_position.z - player.global_position.z) + 0.4
	await _shot(out + "/4_chase.png")
	# 7) الاستسلام والسجن
	if state == "play":
		player.set_surrender(true)
		for i in 2400:
			await get_tree().physics_frame
			if state != "play":
				break
	print("AUTOTEST jail: state=%s jail_t=%.0f bag=%d cash=%d weapon=%s" % [state, jail_t, crime.bag.size(), cash, weapons.current])
	await _shot(out + "/5_jail.png")
	if state == "play":
		player.revive()          # لم تصل الشرطة في الوقت المحدد: نكمل بقية الاختبار
	bank = 300000
	try_bribe(200000)
	print("AUTOTEST bribe: jail_t=%.0f bank=%d" % [jail_t, bank])
	jail_t = 0.0
	_on_continue()
	await _frames(5)
	# 8) الغسيل
	cash = 50000
	wanted = 0
	player.teleport(city.safe_pos + Vector3(0, 0.3, 0), 0.0)
	var bank0 := bank
	crime.open_laundering()
	crime._deposit_launder()
	await _shot(out + "/6_launder.png")
	close_menu()
	await _frames(120)
	print("AUTOTEST launder: pool=%.0f bank %d -> %d" % [crime.launder_pool, bank0, bank])
	# 9) مهنة الشرطي
	wanted = 0
	crime.bag.clear()
	player.teleport(cop.desk_pos + Vector3(0, 0.3, 0), 0.0)
	await _frames(3)
	cop.start_duty()
	await _frames(5)
	cop._spawn_robber()
	var rb: Robber = cop.robbers[-1]
	rb.state = Robber.S.FLEEING
	rb._surrender()
	player.teleport(rb.global_position + Vector3(1.2, 0.3, 0), 0.0)
	await _frames(3)
	var bank_c := bank
	print("AUTOTEST cop-pre: robber state=%d surr=%s dist=%.2f hint=%s downed=%s" % [rb.state, rb.surrendered, rb.global_position.distance_to(player.global_position), _hint, player.downed])
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(2)
	print("AUTOTEST cop: on_duty=%s weapons=%s arrests=%d bank %d -> %d" % [cop.on_duty, weapons.owned, cop.shift_arrests, bank_c, bank])
	await _shot(out + "/7_cop.png")
	cop.end_duty()
	# 10) الاستيلاء على حي
	var di := -1
	for i in 9:
		if gangs.owner_of[i] != 0 and gangs.can_challenge(i) == "":
			di = i
			break
	player.teleport(gangs.flags[di] + Vector3(0, 0.3, 0.8), 0.0)
	await _frames(3)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(20)
	var guards := gangs._alive_near(gangs.flags[di], 30.0)
	cam.yaw = PI
	await _shot(out + "/8_gang.png")
	for m in gangs.members.duplicate():
		m.take_damage(999.0, player)
	Input.action_press("interact")
	await _frames(int(10.5 * 60))
	Input.action_release("interact")
	print("AUTOTEST gang: guards=%d owner=%d owned=%d" % [guards, gangs.owner_of[di], gangs.owned_count()])
	# 11) القاعدة والتأجير
	player.teleport(city.safe_pos + Vector3(0, 0.3, 0), 0.0)
	crime.bag.append({"name": "تحفة", "value": 5000, "kind": "art"})
	gangs.open_base()
	gangs._stash_bag()
	await _shot(out + "/9_base.png")
	print("AUTOTEST base: stash=%d bag=%d security=%d" % [gangs.stash.size(), crime.bag.size(), land.decoders_needed()])
	close_menu()
	player.teleport(extras.terminals[0] + Vector3(0, 0.3, 0.6), 0.0)
	await _frames(3)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(30)
	print("AUTOTEST rental: rental=%s" % [extras.rental != null])
	await _land_test(out)
	var flipped := 0
	for car in cars:
		if car.global_basis.y.y < 0.5:
			flipped += 1
	print("AUTOTEST end: cars=%d flipped=%d civilians=%d" % [cars.size(), flipped, civilians.size()])
	get_tree().quit()


## اختبار الأراضي والمستوطنات والأحياء (على طريقة ROB RUN)
func _land_test(out: String) -> void:
	if extras.rental != null and player.car == extras.rental:
		_exit_car(true)
	await _frames(5)
	wanted = 0
	land.wipe()                      # بداية نظيفة لاختبار الأراضي
	var lv := []
	for i in 9:
		lv.append("%s:%s" % [Gangs.LEVEL[i], "me" if gangs.is_mine(i) else str(gangs.owner_of[i])])
	print("AUTOTEST districts: %s bonus=%.2f rate=%.0f governor=%s" % [lv, gangs.launder_bonus(), crime.launder_rate(), gangs.is_godfather()])
	# الوثائق من السوق السوداء: المستوى 1 بالمستندات
	land.docs = 20
	bank += 2000000
	crime.open_market()
	land._buy_title("plot", 1)            # يجب أن يُرفض: لم تبحث عنها بعد
	var before_research: int = land.plot_titles[1]
	land._research("plot", 1)
	land._research("settle", 1)
	land._research("plot", 3)
	land._buy_title("plot", 1)
	land._buy_title("settle", 1)
	land._buy_title("plot", 3)            # يجب أن يُرفض: لا تسكن مستوطنة م2
	close_menu()
	print("AUTOTEST titles: before_research=%d researched=%s docs=%d plot=%s settle=%s" % [before_research, land.researched.keys(), land.docs, land.plot_titles, land.settle_titles])
	# الموتيل يحفظ النقود فقط
	cash = 7000
	land.open_motel()
	land._motel_deposit()
	close_menu()
	print("AUTOTEST motel: cash=%d motel=%d" % [cash, land.motel_cash])
	# خريطة المستوطنة واختيار قطعة
	land.open_map(0)
	await _frames(2)
	var mv_ok: bool = hud.menu_list.get_child(0) is Land.MapView
	land._pick(0, 3)
	print("AUTOTEST map: view=%s waypoint_set=%s beacon=%s" % [mv_ok, land.waypoint != Vector3.INF, land._beacon.visible])
	# استئجار قطعة في مستوطنة م1 تملكها عصابة
	var si := -1
	var pk := -1
	for i in land.settlements.size():
		var st: Dictionary = land.settlements[i]
		if st.level == 1 and st.district != gangs.district_at(city.safe_pos):
			if st.owner <= 0:
				st.owner = 1
				land._refresh(st)
			for k in range(1, Land.PLOTS):
				if st.plots[k].tenant == "":
					si = i
					pk = k
					break
			if si >= 0:
				break
	var sp: Dictionary = land.settlements[si].plots[pk]
	player.teleport(sp.sign + Vector3(0, 0.3, 0), 0.0)
	await _frames(3)
	print("AUTOTEST plot-hint: %s" % _hint)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(5)
	print("AUTOTEST rent: home=%s house=%s tax=%.2f base=%s" % [land.home, sp.house != null, land.tenant_tax(), land.base_title()])
	# الدخول إلى المنزل مشياً عبر الباب
	var door_w: Vector3 = sp.house.transform * Vector3(sp.size.x / 2.0 + 2.5, 0.3, 0)
	var in_yaw := atan2(-sp.face.x, -sp.face.z)
	player.teleport(door_w, in_yaw)
	cam.yaw = in_yaw
	await _frames(20)
	var door_open: float = absf(sp.door.rotation.y)
	Input.action_press("move_forward")
	await _frames(int(1.4 * 60))
	Input.action_release("move_forward")
	await _frames(10)
	print("AUTOTEST enter: door_open=%.2f inside=%s cam_indoor=%s hint=%s" % [door_open, land.inside_home, cam.indoor, _hint])
	# محطات الداخل
	var seen := []
	for st in sp.stations:
		player.teleport(st.pos + Vector3(0, 0.3, 0), 0.0)
		await _frames(3)
		seen.append("%s:%s" % [st.kind, _hint.substr(0, 14)])
	print("AUTOTEST stations: %s" % [seen])
	await _house_test(sp)
	# بيت ساكن آخر: الباب مغلق
	var npc_plot: Dictionary = {}
	for st2 in land.settlements:
		for k in range(1, Land.PLOTS):
			if st2.plots[k].tenant != "" and st2.plots[k] != sp:
				npc_plot = st2.plots[k]
	if not npc_plot.is_empty():
		var ny := atan2(-npc_plot.face.x, -npc_plot.face.z)
		player.teleport(npc_plot.house.transform * Vector3(npc_plot.size.x / 2.0 + 2.5, 0.3, 0), ny)
		cam.yaw = ny
		await _frames(10)
		Input.action_press("move_forward")
		await _frames(int(1.4 * 60))
		Input.action_release("move_forward")
		print("AUTOTEST npc-door: inside=%s dist_from_center=%.1f" % [land._is_inside(npc_plot, player_pos()), Vector2(player_pos().x - npc_plot.pos.x, player_pos().z - npc_plot.pos.z).length()])
		# الطرد: حق طرد + أجهزة فك شفرة
		var ev_si := -1
		var ev_k := -1
		for i in land.settlements.size():
			for k in range(1, Land.PLOTS):
				if land.settlements[i].plots[k] == npc_plot:
					ev_si = i
					ev_k = k
		crime.tools["decoder"] = 10
		bank += 100000
		land._buy_eviction()
		close_menu()
		var who: String = npc_plot.tenant
		player.teleport(npc_plot.sign + Vector3(0, 0.3, 0), 0.0)
		wanted = 0
		await _frames(2)
		print("AUTOTEST evict-hint: %s" % _hint)
		player.max_health = 100000.0          # المدافعون مسلحون؛ نختبر الاقتحام لا القتال
		player.health = 100000.0
		Input.action_press("interact")
		await _frames(int(8.4 * 60))
		Input.action_release("interact")
		await _frames(3)
		print("AUTOTEST evict: who=%s now=\"%s\" rights=%d decoders=%d cash=%d downed=%s" % [who, land.settlements[ev_si].plots[ev_k].tenant, land.eviction_rights, crime.tools.get("decoder", 0), cash, player.downed])
		player.max_health = 100.0
		for m in gangs.members.duplicate():
			gangs.remove_robber(m)
		wanted = 0
		player.revive()                   # المدافعون ربما أصابوه أثناء الاقتحام
	# الأمان: نظام + صمامات + إنذار + خزنة
	land._buy("security", Land.SECURITY_COST)
	land._buy("fuse", Land.FUSE_COST)
	land._buy("fuse", Land.FUSE_COST)
	land._buy("alarm", Land.ALARM_COST)
	land._buy("safe", Land.SAFE_COST)
	close_menu()
	crime.launder_pool = 60000.0
	gangs.stash.append({"name": "تحفة", "value": 5000, "kind": "art"})
	gangs.stash.append({"name": "تحفة", "value": 5000, "kind": "art"})
	gangs.start_raid()
	var ev_where: Vector3 = gangs._event.where
	land.resolve_raid(2, "الأفاعي")
	var pool_a := crime.launder_pool
	land.resolve_raid(5, "الأفاعي")
	print("AUTOTEST raid: at_home=%s need=%d pool %.0f -> %.0f stash=%d" % [ev_where.distance_to(land.base_pos()) < 1.0, land.decoders_needed(), pool_a, crime.launder_pool, gangs.stash.size()])
	for m in gangs.members.duplicate():
		gangs.remove_robber(m)
	gangs._event = {}
	# شراء مستوطنة: مستوطنة حي المخبأ (حيّك) بلا مالك
	var hs := -1
	for i in land.settlements.size():
		if land.settlements[i].district == gangs.district_at(city.safe_pos):
			hs = i
	var hst: Dictionary = land.settlements[hs]
	player.teleport(hst.plots[0].sign + Vector3(0, 0.3, 0), 0.0)
	await _frames(3)
	print("AUTOTEST settle-hint: %s" % _hint)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await _frames(3)
	land._set_tenant(hst, 1, "سامر")
	land._set_tenant(hst, 2, "ليلى")
	land._tax_t = 0.0
	await _frames(3)
	var box: int = hst.tax_box
	land._tax_t = 0.0
	await _frames(3)
	var box2: int = hst.tax_box                # يجب ألا يزيد قبل الجمع
	var b0 := bank
	var g0 := gangs.members.size()
	land._collect(hs)
	close_menu()
	print("AUTOTEST tax-hold: %d -> %d  hitmen=%d" % [box, box2, gangs.members.size() - g0])
	print("AUTOTEST settlement: owner=%s home=%s old_plot_free=%s tax_box=%d collected=%d" % [land.owner_text(hst), land.home, sp.tenant == "", box, bank - b0])
	player.teleport(hst.plots[0].sign + Vector3(0, 0.3, 0), 0.0)
	await _frames(30)
	await _shot(out + "/11_settlement.png")
	# الحفظ والتحميل
	var d := land.to_dict()
	land.home = Vector2i(-1, -1)
	land.from_dict(d)
	print("AUTOTEST land-save: home=%s docs=%d fuses=%d" % [land.home, land.docs, land.fuses])
	# المداهمة الفيدرالية تصادر كل شيء
	gangs.federal_raid()
	await _frames(3)
	print("AUTOTEST federal: home=%s docs=%d titles=%s research=%d motel=%d security=%s owner=%s bank=%d season=%s" % [land.home, land.docs, land.plot_titles, land.researched.size(), land.motel_cash, land.security, land.owner_text(hst), bank, gangs.season_mode])


## اختبار المنزل: مخطط البناء، الترقية، الأثاث، الغسيل، الشحنات، الزراعة، المختبر، المرآب
func _house_test(sp: Dictionary) -> void:
	var H: House = land.house
	bank += 3000000
	print("AUTOTEST house-start: tier=%s stations=%d fuses_max=%d dirty_cap=%d stash_cap=%d" % [House.TIER_NAMES[H.tier_eff()], sp.stations.size(), H.max_fuses(), H.dirty_cap(), H.stash_cap()])
	H._upgrade()
	for k in ["cabinet", "safe", "rack", "bench", "bench", "cabinet"]:
		H._place(k)
	H._build_annex("grow")
	close_menu()
	sp = land._home_plot()
	var kinds := {}
	for st in sp.stations:
		kinds[st.kind] = kinds.get(st.kind, 0) + 1
	print("AUTOTEST house-plan: tier=%s slots=%s annex=%s stations=%s stash_cap=%d cargo_cap=%d benches=%d" % [House.TIER_NAMES[H.tier_eff()], H.slots, H.annex, kinds, H.stash_cap(), H.cargo_cap(), H.count("bench")])
	# المحطات الثابتة تعمل
	var hints := []
	for st in sp.stations:
		if st.kind in ["laptop", "aid", "plan", "grow"]:
			player.teleport(st.pos + Vector3(0, 0.3, 0), 0.0)
			await _frames(3)
			hints.append(_hint.substr(0, 16))
	print("AUTOTEST house-hints: %s" % [hints])
	player.health = 20.0
	H.first_aid()
	print("AUTOTEST aid: health=%.0f" % player.health)
	# طاولة الغسيل: العدّاد والكابل والحد
	crime.launder_pool = 10000.0
	var r0 := crime.launder_rate()
	H._counter()
	var r1 := crime.launder_rate()
	H.cable_broken = true
	var r2 := crime.launder_rate()
	H._repair()
	close_menu()
	print("AUTOTEST desk: rate %.0f -> counter %.0f -> broken %.0f -> repaired=%s cap=%d" % [r0, r1, r2, not H.cable_broken, H.dirty_cap()])
	# الشحنات: من الحقيبة إلى الرف ثم الطاولة تفتحها
	crime.bag.clear()
	crime.bag.append(H._crate_item())
	crime.bag.append(H._crate_item())
	H._store_cargo()
	var st0 := gangs.stash.size()
	H.tick(1.0)
	var jobs := H.bench_jobs.size()
	H.tick(H.crate_time() + 1.0)
	print("AUTOTEST cargo: racks=%d jobs=%d stash %d -> %d" % [H.cargo.size(), jobs, st0, gangs.stash.size()])
	H._module("plasma")
	print("AUTOTEST bench: crate_time=%.0f capacity=%d" % [H.crate_time(), H.bench_capacity()])
	# إشهار السلاح يُسقط الشحنة
	crime.bag.append(H._crate_item())
	weapons.aiming = true
	land._tick_pickups(0.1)
	weapons.aiming = false
	var dropped := land.pickups.filter(func(pk): return pk.kind == "cargo").size()
	print("AUTOTEST drop: dropped=%d bag_cargo=%d" % [dropped, crime.count_loot("cargo")])
	# الزراعة
	var bush_n := land.pickups.filter(func(pk): return pk.kind == "bush").size()
	H.bushes = 2
	H._add_table()
	H._plant(0)
	H._plant(1)
	H._buy_fan()
	H.tick(House.GROW_TIME)
	var ready := H.tables.count(0.0)
	H._harvest(0)
	close_menu()
	print("AUTOTEST grow: park_bushes=%d tables=%d ready=%d weed_bags=%d" % [bush_n, H.tables.size(), ready, crime.count_loot("weed")])
	# المختبر
	H._demolish()
	H._build_annex("lab")
	H.reagents = 3
	var c0 := H.cargo.size()
	H._start_batch()
	var smoke: bool = H._vis.smoke.emitting if H._vis.has("smoke") else false
	H.update_visuals()
	smoke = H._vis.smoke.emitting
	H.tick(House.REACTOR_TIME + 1.0)
	close_menu()
	print("AUTOTEST lab: smoke=%s cargo %d -> %d (or bag)" % [smoke, c0, H.cargo.size()])
	# المرآب
	H._demolish()
	H._build_annex("garage")
	H.garage_car = "sedan_sports"
	var n_cars := cars.size()
	H._take_car()
	print("AUTOTEST garage: cars %d -> %d stored=%s" % [n_cars, cars.size(), H.garage_car])
	# الموتيل: غسيل بنصف القيمة
	cash = 40000
	var b1 := bank
	land._motel_launder()
	close_menu()
	print("AUTOTEST motel-launder: cash=%d bank+%d" % [cash, bank - b1])
	# المداهمة: الخزائن تحمي جزءاً
	gangs.stash.clear()
	for i in 10:
		gangs.stash.append({"name": "تحفة", "value": 5000, "kind": "art"})
	H.cargo = [6000, 6000]
	print("AUTOTEST raid-house: %s · left stash=%d cargo=%d" % [H.raid_losses(false), gangs.stash.size(), H.cargo.size()])


## لقطات البيئة: أوقات وطقس مختلفة من زاوية ثابتة في الشارع
## لقطات المستوطنات والقطع والمنازل (كاميرا ثابتة موجّهة)
func _landshots() -> void:
	var out := "user://landshots"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--only="):
			only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	world.cycle_enabled = false
	gangs.season_mode = false          # تغيير الوقت بين اللقطات يعدّ أياماً؛ لا نريد مداهمة فيدرالية هنا
	_on_start()
	# مستوطنة تملكها أنت فيها سكان، ومستوطنة عصابة فيها قطع للإيجار
	var mine: Dictionary = land.settlements[0]
	land._take_settlement(0, "")
	land._set_tenant(mine, 1, "سامر")
	land._set_tenant(mine, 2, "ليلى")
	var other: Dictionary = land.settlements[4]
	other.owner = 2
	land._set_tenant(other, 1, "")
	land._set_tenant(other, 2, "أنت")
	land.home = Vector2i(4, 2)
	land._refresh(other)
	crime.launder_pool = 90000.0
	for i in 9:
		gangs.stash.append({"name": "تحفة", "value": 5000, "kind": "art"})
	land.security = true
	bank += 5000000
	land.house._upgrade()
	for k in ["cabinet", "safe", "rack", "bench", "rack", "bench"]:
		land.house._place(k)
	land.house.cargo = [6000, 6000, 6000, 6000, 6000]
	land.house._build_annex("grow")
	land.house.tables = [0.0, 200.0, -1.0, 0.0]
	land.house.fan = true
	land._build_house(other.plots[2], true, false)
	land.house.update_visuals()
	close_menu()
	land._set_tenant(other, 3, "")
	hud.visible = false
	var spots := []
	for st in [mine, other]:
		var c: Vector3 = st.center
		var gd: Vector3 = st.gate_dir
		var sd := Vector3(-gd.z, 0, gd.x)
		spots.append(["%s_aerial" % st.district, c + gd * 40.0 + sd * 22.0 + Vector3(0, 34.0, 0), c])
		spots.append(["%s_gate" % st.district, c + gd * 34.0 + sd * 4.0 + Vector3(0, 1.8, 0), c + gd * 20.0])
		spots.append(["%s_courtyard" % st.district, c + gd * 10.0 + Vector3(0, 2.0, 0), c - gd * 18.0])
	var hp: Dictionary = other.plots[2]
	var ht: Transform3D = hp.house.transform
	spots.append(["interior_back", ht * Vector3(3.2, 1.75, 3.8), ht * Vector3(-3.6, 0.9, -2.5)])
	spots.append(["interior_side", ht * Vector3(3.2, 1.75, -3.8), ht * Vector3(-2.0, 1.0, 3.5)])
	var at: Transform3D = hp.annex_node.transform
	spots.append(["annex_grow", at * Vector3(3.2, 1.9, 1.8), at * Vector3(-3.0, 0.8, -0.8)])
	spots.append(["plot_yard", hp.pos + hp.face * 13.0 + Vector3(0, 3.5, 0) + hp.lat * 3.0, hp.pos + Vector3(0, 1.5, 0)])
	for spot in spots:
		if only != "" and not (spot[0] as String).contains(only):
			continue
		for lk in [["noon", 13.0, 0], ["night", 22.0, 0]]:
			world.hour = lk[1]
			world.set_weather(lk[2], true)
			set_process(false)
			cam.set_process(false)
			cam.global_position = spot[1]
			cam.look_at(spot[2])
			await _frames(20)
			_update_lamps()
			await _frames(25)
			await _shot("%s/%s_%s.png" % [out, spot[0], lk[0]])
	# لقطة مع الواجهة عند لافتة قطعة للإيجار
	hud.visible = true
	set_process(true)
	cam.set_process(true)
	world.hour = 20.0
	var pl: Dictionary = other.plots[3]
	var fy := atan2(-pl.face.x, -pl.face.z)
	player.teleport(pl.sign + pl.face * 1.5 + Vector3(0, 0.3, 0), fy)
	cam.yaw = fy + 0.5
	land.plot_titles[other.level] = 1
	land.home = Vector2i(-1, -1)
	for i in 120:
		_update_camera_for_shot()
		await get_tree().process_frame
	await _shot("%s/hud_sign.png" % out)
	land.open_map(4)
	for i in 30:
		await get_tree().process_frame
	await _shot("%s/settle_map.png" % out)
	get_tree().quit()


func _update_camera_for_shot() -> void:
	cam.update_camera(1.0 / 60.0)
	_interactions(0.0)
	hud.refresh(1.0 / 60.0, _hint)


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
		["sidewalk", Vector3(-76.3, 1.7, -186), Vector3(-75.0, 2.2, -150)],
	]
	for c in cars:
		if c.is_hero:
			var hp := c.global_position
			spots.append(["hero", hp + Vector3(-5.5 * city.safe_sx, 1.4, 6.0), hp + Vector3(0, 0.5, 0)])
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
			city.props.update_signals(5.0)
			_update_headlights()
			await _frames(25)
			await _shot("%s/%s.png" % [out, name])
			if spot[0] == "street" and lk[0] == "noon_clear":
				print("RENDER_INFO objects=%d primitives=%d draw_calls=%d vram_mb=%d" % [
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576])
	# قائمة الإيقاف مع الإعدادات
	hud.visible = true
	set_state("paused")
	await _frames(10)
	await _shot("%s/zz_pause_menu.png" % out)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)
		print("AUTOTEST shot: ", path)
