class_name Net
extends Node
## اللعب الجماعي عبر الإنترنت (ENet):
## - خادم مخصّص بلا رسوم (godot --headless -- --server) أو «استضافة واللعب» من جهازك.
## - الخادم هو المرجع في: من سرق ماذا ومتى، المطلوبية، إصابات الرصاص بين اللاعبين،
##   الاعتقال والسجن، السيطرة على الأحياء، وحفظ تقدّم كل لاعب باسمه.
## - كل لاعب يتحكم بحركته ويرسل حالته 15 مرة/ث، والخادم يبثّ لقطة جماعية للجميع.

const PORT := 7777
const MAX_PLAYERS := 32
const MAX_COPS := 4
const RATE := 15.0
const F_MASK := 1
const F_SURRENDER := 2
const F_DOWNED := 4
const F_ROBBING := 8
const F_AIM := 16
const PROFILE_PATH := "user://damar_server.cfg"

enum Mode { SOLO, HOST, CLIENT, SERVER }

signal joined(ok: bool, msg: String)

var game: Node
var mode := Mode.SOLO
var my_name := "لاعب"
var my_role := "criminal"
var peers := {}              # id -> {name, role}
var remotes := {}            # id -> RemotePlayer (عند العملاء والمضيف)
var states := {}             # الخادم: id -> [pos, yaw, speed, flags, model, car_xf, hp, bag]
var wanted := {}             # الخادم: id -> {level, unseen}
var district_owner: Array = ["", "", "", "", "", "", "", "", ""]
var settle_owner: Array = ["", "", "", "", "", "", "", "", ""]   # مالك كل مستوطنة (اسم لاعب)
var plot_tenant := {}                                           # "مستوطنة:قطعة" -> اسم الساكن
var _send_t := 0.0
var _snap_t := 0.0
var _tax_t := 120.0
var _profiles := ConfigFile.new()
var log_events := false      # يطبع أحداث الشبكة (للخادم المخصّص والاختبار)


func _init(g: Node) -> void:
	game = g


func is_online() -> bool:
	return mode != Mode.SOLO


func is_server() -> bool:
	return mode == Mode.HOST or mode == Mode.SERVER


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func _log(msg: String) -> void:
	if log_events or mode == Mode.SERVER:
		print("[NET %s] %s" % [["solo", "host", "client", "server"][mode], msg])


# ---------------------------------------------------------------- الاتصال
func host(port := PORT, dedicated := false) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "تعذّر فتح المنفذ %d (ربما مستخدم)" % port
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER if dedicated else Mode.HOST
	_signals()
	_profiles.load(PROFILE_PATH)
	if not dedicated:
		peers[1] = {"name": my_name, "role": my_role}
		wanted[1] = {"level": 0, "unseen": 0.0}
	_log("listening on port %d" % port)
	return ""


func join(ip: String, port := PORT) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return "عنوان غير صالح"
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_signals()
	_log("connecting to %s:%d" % [ip, port])
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.SOLO
	for id in remotes:
		remotes[id].cleanup()
	remotes.clear()
	peers.clear()


func _signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_failed)
		multiplayer.server_disconnected.connect(_on_server_gone)


func _on_peer_connected(id: int) -> void:
	_log("peer %d connected" % id)


func _on_connected() -> void:
	_log("connected, registering as %s (%s)" % [my_name, my_role])
	register.rpc_id(1, my_name, my_role)


func _on_failed() -> void:
	mode = Mode.SOLO
	multiplayer.multiplayer_peer = null
	joined.emit(false, "تعذّر الاتصال بالخادم")


func _on_server_gone() -> void:
	leave()
	game.on_net_lost("انقطع الاتصال بالخادم")


func _on_peer_disconnected(id: int) -> void:
	_log("peer %d left" % id)
	if is_server() and peers.has(id):
		chat.rpc(0, "%s غادر المدينة" % peers[id].name)
		_chat_local(0, "%s غادر المدينة" % peers[id].name)
		peers.erase(id)
		states.erase(id)
		wanted.erase(id)
		peer_left.rpc(id)
		_remove_remote(id)


# ---------------------------------------------------------------- التسجيل
func _cop_count() -> int:
	var n := 0
	for id in peers:
		if peers[id].role == "cop":
			n += 1
	return n


func _unique_name(n: String) -> String:
	n = n.strip_edges().substr(0, 16)
	if n == "":
		n = "لاعب"
	var base := n
	var k := 2
	var taken := peers.values().map(func(p): return p.name)
	while n in taken:
		n = "%s%d" % [base, k]
		k += 1
	return n


@rpc("any_peer", "reliable")
func register(pname: String, role: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = _unique_name(pname)
	var note := ""
	if role == "cop" and _cop_count() >= MAX_COPS:
		role = "criminal"
		note = "كل مقاعد الشرطة (%d) مشغولة — دخلت كمجرم" % MAX_COPS
	peers[id] = {"name": pname, "role": role}
	wanted[id] = {"level": 0, "unseen": 0.0}
	var profile: Dictionary = _profiles.get_value("players", pname, {})
	welcome.rpc_id(id, id, pname, role, peers, profile, _shared_state(), note)
	peer_joined.rpc(id, pname, role)
	if mode == Mode.HOST:
		_spawn_remote(id)
	_log("registered %d as %s (%s)" % [id, pname, role])
	chat.rpc(0, "%s دخل المدينة (%s)" % [pname, "شرطي" if role == "cop" else "مجرم"])
	_chat_local(0, "%s دخل المدينة (%s)" % [pname, "شرطي" if role == "cop" else "مجرم"])


func _shared_state() -> Dictionary:
	var cds := []
	for t in game.crime.targets:
		cds.append([t.cooldown, t.uses_left])
	return {"targets": cds, "districts": district_owner, "settle": settle_owner, "plots": plot_tenant}


@rpc("authority", "reliable")
func welcome(id: int, pname: String, role: String, peer_dict: Dictionary, profile: Dictionary, shared: Dictionary, note: String) -> void:
	my_name = pname
	my_role = role
	peers = peer_dict
	for pid in peers:
		if pid != id:
			_spawn_remote(pid)
	var cds: Array = shared.targets
	for i in mini(cds.size(), game.crime.targets.size()):
		game.crime.targets[i].cooldown = cds[i][0]
		game.crime.targets[i].uses_left = cds[i][1]
	district_owner = shared.districts
	game.gangs.apply_mp_owners(district_owner)
	game.on_net_joined(profile, note)
	settle_owner = shared.get("settle", settle_owner)
	plot_tenant = shared.get("plots", {})
	game.land.mp_apply(settle_owner, plot_tenant)
	joined.emit(true, note)
	_log("welcome as %s (%s), %d peers" % [pname, role, peers.size()])


@rpc("authority", "reliable")
func peer_joined(id: int, pname: String, role: String) -> void:
	if id == my_id():
		return
	peers[id] = {"name": pname, "role": role}
	_spawn_remote(id)


@rpc("authority", "reliable")
func peer_left(id: int) -> void:
	peers.erase(id)
	_remove_remote(id)


func _spawn_remote(id: int) -> void:
	if remotes.has(id) or id == my_id() or not peers.has(id) or mode == Mode.SERVER:
		return
	var r := RemotePlayer.new()
	game.add_child(r)
	r.setup(game, id, peers[id].name, peers[id].role)
	remotes[id] = r


func _remove_remote(id: int) -> void:
	if remotes.has(id):
		remotes[id].cleanup()
		remotes.erase(id)


# ---------------------------------------------------------------- الحالة واللقطات
func _physics_process(dt: float) -> void:
	if not is_online():
		return
	_send_t -= dt
	if _send_t <= 0.0 and mode != Mode.SERVER and peers.has(my_id()):
		_send_t = 1.0 / RATE
		var st: Array = game.local_net_state()
		if is_server():
			states[1] = st
		else:
			push_state.rpc_id(1, st)
	if is_server():
		_snap_t -= dt
		if _snap_t <= 0.0:
			_snap_t = 1.0 / RATE
			_server_tick(1.0 / RATE)
			var data := {}
			for id in states:
				var s: Array = states[id]
				data[id] = [s[0], s[1], s[2], s[3], s[4], s[5], s[6], wanted.get(id, {"level": 0}).level]
			snapshot.rpc(data)
			if mode == Mode.HOST:
				_apply_snapshot(data)


@rpc("any_peer", "unreliable_ordered")
func push_state(st: Array) -> void:
	if is_server():
		var id := multiplayer.get_remote_sender_id()
		if peers.has(id):
			states[id] = st


@rpc("authority", "unreliable_ordered")
func snapshot(data: Dictionary) -> void:
	_apply_snapshot(data)


func _apply_snapshot(data: Dictionary) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id in data:
		var s: Array = data[id]
		if id == my_id():
			game.net_set_wanted(s[7])
			continue
		if not remotes.has(id):
			_spawn_remote(id)
		if remotes.has(id):
			if peers.has(id):
				remotes[id].set_role(peers[id].role)
			remotes[id].push(t, s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7])


## الخادم: تناقص المطلوبية عندما لا يرى أي شرطي (لاعب) المجرمَ، والضرائب
func _server_tick(dt: float) -> void:
	for id in wanted:
		var w: Dictionary = wanted[id]
		if w.level <= 0 or not states.has(id):
			continue
		var p: Vector3 = states[id][0]
		var seen := false
		for cid in peers:
			if peers[cid].role != "cop" or not states.has(cid):
				continue
			var cp: Vector3 = states[cid][0]
			var d := cp.distance_to(p)
			if d < 15.0 or (d < 70.0 and game.has_los(cp + Vector3(0, 1.5, 0), p + Vector3(0, 1.2, 0))):
				seen = true
				break
		w.unseen = 0.0 if seen else w.unseen + dt
		if w.unseen > 6.0 + w.level * 3.0:
			w.level -= 1
			w.unseen = 0.0
	_tax_t -= dt
	if _tax_t <= 0.0:
		_tax_t = 120.0
		for id in peers:
			var n := 0
			for i in 9:
				if district_owner[i] == peers[id].name:
					n += 3 if i == Gangs.CENTER else 1
			if n > 0:
				_send_tax(id, 1500 * n)


func _send_tax(id: int, amount: int) -> void:
	if id == my_id():
		tax(amount)
	else:
		tax.rpc_id(id, amount)


@rpc("authority", "reliable")
func tax(amount: int) -> void:
	game.crime.launder_pool += amount
	game.hud.toast("💰 ضرائب أحيائك: %s دخلت طاولة الغسيل" % Cfg.money(amount), Color("7dff9e"))


# ---------------------------------------------------------------- الجرائم والمطلوبية
func report_crime(level: int) -> void:
	if is_server():
		_raise(my_id(), level)
	else:
		_report.rpc_id(1, level)


@rpc("any_peer", "reliable")
func _report(level: int) -> void:
	if is_server():
		_raise(multiplayer.get_remote_sender_id(), level)


func _raise(id: int, level: int) -> void:
	if not wanted.has(id) or peers.get(id, {}).get("role", "") == "cop":
		return
	wanted[id].level = clampi(maxi(wanted[id].level, level), 0, 5)
	wanted[id].unseen = 0.0


func rob_started(idx: int, city_alert: bool) -> void:
	if is_server():
		_rob_start(my_id(), idx, city_alert)
	else:
		_req_rob.rpc_id(1, idx, city_alert)


@rpc("any_peer", "reliable")
func _req_rob(idx: int, city_alert: bool) -> void:
	if is_server():
		_rob_start(multiplayer.get_remote_sender_id(), idx, city_alert)


func _rob_start(id: int, idx: int, city_alert: bool) -> void:
	var t: Crime.Target = game.crime.targets[idx]
	_log("%s started robbing %s" % [peers.get(id, {}).get("name", "?"), t.label])
	var where: Vector3 = t.pos
	alarm.rpc(idx, peers.get(id, {}).get("name", "?"), city_alert, where)
	alarm(idx, peers.get(id, {}).get("name", "?"), city_alert, where)


@rpc("authority", "reliable")
func alarm(idx: int, who: String, city_alert: bool, where: Vector3) -> void:
	if mode == Mode.SERVER:
		return
	var t: Crime.Target = game.crime.targets[idx]
	if my_role == "cop":
		game.hud.toast("🚨 بلاغ: %s في %s%s" % [t.label, t.store.def.name, " — عملية كبرى!" if city_alert else ""], Color("ff6b6b"))
		game.add_alert(where)
	elif who != my_name and city_alert:
		game.hud.toast("📢 %s يسرق %s!" % [who, t.label], Color("ffd36b"))


func rob_done(idx: int) -> void:
	var t: Crime.Target = game.crime.targets[idx]
	if is_server():
		target_state.rpc(idx, t.cooldown, t.uses_left)
	else:
		_rob_done.rpc_id(1, idx, t.cooldown, t.uses_left)


@rpc("any_peer", "reliable")
func _rob_done(idx: int, cd: float, uses: int) -> void:
	if is_server():
		var t: Crime.Target = game.crime.targets[idx]
		t.cooldown = cd
		t.uses_left = uses
		target_state.rpc(idx, cd, uses)


@rpc("authority", "reliable")
func target_state(idx: int, cd: float, uses: int) -> void:
	var t: Crime.Target = game.crime.targets[idx]
	t.cooldown = cd
	t.uses_left = uses


## هل الهدف متاح؟ (الخادم يرسل حالة الأهداف للجميع)
func target_open(idx: int) -> bool:
	return game.crime.targets[idx].cooldown <= 0.0


# ---------------------------------------------------------------- الرصاص بين اللاعبين
func shot(origin: Vector3, dir: Vector3, rng: float, dmg: float) -> void:
	if is_server():
		_server_shot(my_id(), origin, dir, rng, dmg)
	else:
		_shot.rpc_id(1, origin, dir, rng, dmg)


@rpc("any_peer", "unreliable")
func _shot(origin: Vector3, dir: Vector3, rng: float, dmg: float) -> void:
	if is_server():
		_server_shot(multiplayer.get_remote_sender_id(), origin, dir, rng, dmg)


func _server_shot(shooter: int, origin: Vector3, dir: Vector3, rng: float, dmg: float) -> void:
	dir = dir.normalized()
	rng = minf(rng, 100.0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng, Cfg.LAYER_WORLD | Cfg.LAYER_VEHICLES)
	var ray: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	var max_t: float = origin.distance_to(ray.position) if ray else rng
	var best := -1
	var best_t := max_t
	for id in states:
		if id == shooter:
			continue
		var s: Array = states[id]
		if s[4] != "":          # داخل سيارة
			continue
		var base: Vector3 = s[0]
		var t := (base + Vector3(0, 0.9, 0) - origin).dot(dir)
		if t < 0.0 or t > best_t:
			continue
		var c := origin + dir * t
		if Vector2(c.x - base.x, c.z - base.z).length() < 0.45 and c.y > base.y and c.y < base.y + 1.85:
			best = id
			best_t = t
	var end := origin + dir * best_t
	_log("shot by %s: hit=%s dist=%.1f" % [peers.get(shooter, {}).get("name", "?"), peers.get(best, {}).get("name", "-"), best_t])
	shot_fx.rpc(origin, end, shooter)
	if mode == Mode.HOST and shooter != 1:
		shot_fx(origin, end, shooter)
	if best >= 0:
		var shooter_role: String = peers.get(shooter, {}).get("role", "criminal")
		if shooter_role == "criminal":
			_raise(shooter, 2 if peers.get(best, {}).get("role", "") != "cop" else 4)
		if best == my_id():
			hit(dmg, shooter)
		else:
			hit.rpc_id(best, dmg, shooter)


@rpc("authority", "unreliable")
func shot_fx(a: Vector3, b: Vector3, shooter: int) -> void:
	if shooter == my_id() or mode == Mode.SERVER:
		return
	game.weapons._tracer(a, b)
	game.on_gunshot(a, false)


@rpc("authority", "reliable")
func hit(dmg: float, shooter: int) -> void:
	_log("hit by %s for %.0f" % [peers.get(shooter, {}).get("name", "?"), dmg])
	game.player.take_damage(dmg, null)
	game.hud.toast("أصابك %s" % peers.get(shooter, {}).get("name", "?"), Color("ff6b6b"))


# ---------------------------------------------------------------- الاعتقال بين اللاعبين
func nearest_arrestable(p: Vector3) -> int:
	for id in remotes:
		var r: RemotePlayer = remotes[id]
		if r.role == "cop":
			continue
		if r.flags & (F_SURRENDER | F_DOWNED) != 0 and r.global_position.distance_to(p) < 2.4:
			return id
	return -1


func request_arrest(target: int) -> void:
	if is_server():
		_do_arrest(my_id(), target)
	else:
		_req_arrest.rpc_id(1, target)


@rpc("any_peer", "reliable")
func _req_arrest(target: int) -> void:
	if is_server():
		_do_arrest(multiplayer.get_remote_sender_id(), target)


func _do_arrest(cop: int, target: int) -> void:
	if peers.get(cop, {}).get("role", "") != "cop" or not states.has(target) or not states.has(cop):
		return
	var ts: Array = states[target]
	if (ts[0] as Vector3).distance_to(states[cop][0]) > 3.5 or ts[3] & (F_SURRENDER | F_DOWNED) == 0:
		return
	if wanted.get(target, {"level": 0}).level <= 0:
		return                       # لا اعتقال بلا مطلوبية (ويمنع تكرار اعتقال نفس الشخص)
	var surrendered: bool = ts[3] & F_SURRENDER != 0
	var reward := randi_range(9000, 15000)
	if surrendered:
		reward = int(reward * 1.2)
	reward += int(ts[7] * 0.25)
	var cop_name: String = peers[cop].name
	wanted[target].level = 0
	_log("%s arrested %s, reward %d" % [cop_name, peers[target].name, reward])
	if target == my_id():
		arrested(cop_name)
	else:
		arrested.rpc_id(target, cop_name)
	if cop == my_id():
		reward_paid(reward, peers[target].name)
	else:
		reward_paid.rpc_id(cop, reward, peers[target].name)
	chat.rpc(0, "🚔 %s اعتقل %s" % [cop_name, peers[target].name])
	_chat_local(0, "🚔 %s اعتقل %s" % [cop_name, peers[target].name])


@rpc("authority", "reliable")
func arrested(cop_name: String) -> void:
	_log("arrested by %s" % cop_name)
	game.hud.toast("اعتقلك الشرطي %s" % cop_name, Color("ff4b4b"))
	game._bust()


@rpc("authority", "reliable")
func reward_paid(amount: int, who: String) -> void:
	game.bank += amount
	game.cop.shift_pay += amount
	game.cop.shift_arrests += 1
	game.cop.total_arrests += 1
	game.hud.toast("اعتقلت %s 🚔 +%s في حسابك" % [who, Cfg.money(amount)], Color("7dff9e"))
	game.save_game()


# ---------------------------------------------------------------- الأحياء
func capture(i: int) -> void:
	if is_server():
		_set_district(i, my_name)
	else:
		_req_capture.rpc_id(1, i)


@rpc("any_peer", "reliable")
func _req_capture(i: int) -> void:
	if is_server():
		_set_district(i, peers.get(multiplayer.get_remote_sender_id(), {}).get("name", ""))


func _set_district(i: int, owner: String) -> void:
	district_owner[i] = owner
	district.rpc(i, owner)
	if mode == Mode.HOST:
		district(i, owner)
	_log("district %d -> %s" % [i, owner])


@rpc("authority", "reliable")
func district(i: int, owner: String) -> void:
	district_owner[i] = owner
	game.gangs.apply_mp_owners(district_owner)
	game.hud.toast("🚩 %s استولى على %s" % [owner, Gangs.DISTRICTS[i]], Color("ff6a3d"))


# ---------------------------------------------------------------- الأراضي والمستوطنات (الخادم يحسم الملكية)
func land_request(kind: String, s: int, p: int) -> void:
	if is_server():
		_land_do(my_id(), kind, s, p)
	else:
		_req_land.rpc_id(1, kind, s, p)


@rpc("any_peer", "reliable")
func _req_land(kind: String, s: int, p: int) -> void:
	if is_server():
		_land_do(multiplayer.get_remote_sender_id(), kind, s, p)


func _land_do(id: int, kind: String, s: int, p: int) -> void:
	var who: String = peers.get(id, {}).get("name", "")
	if who == "" or s < 0 or s >= settle_owner.size():
		return
	var key := "%d:%d" % [s, p]
	var reason := ""
	match kind:
		"rent":
			if settle_owner[s] == "":
				reason = "المستوطنة بلا مالك"
			elif plot_tenant.get(key, "") != "":
				reason = "سبقك %s إلى هذه القطعة" % plot_tenant[key]
			elif plot_tenant.values().has(who) or settle_owner.has(who):
				reason = "لديك قاعدة بالفعل"
			else:
				plot_tenant[key] = who
		"leave":
			if plot_tenant.get(key, "") == who:
				plot_tenant.erase(key)
		"buy":
			if settle_owner[s] != "":
				reason = "يملكها %s بالفعل" % settle_owner[s]
			else:
				settle_owner[s] = who
				for k in plot_tenant.keys():          # المالك يسكن قصره ويترك قطعته المستأجرة
					if plot_tenant[k] == who:
						plot_tenant.erase(k)
	if reason != "":
		if id == my_id():
			land_denied(kind, s, reason)
		else:
			land_denied.rpc_id(id, kind, s, reason)
		return
	_log("land %s %s by %s" % [kind, key, who])
	land_state.rpc(settle_owner, plot_tenant)
	if mode == Mode.HOST or mode == Mode.SERVER:
		land_state(settle_owner, plot_tenant)


@rpc("authority", "reliable")
func land_state(so: Array, pt: Dictionary) -> void:
	settle_owner = so
	plot_tenant = pt
	var before: Vector2i = game.land.home
	game.land.mp_apply(so, pt)
	if game.land.home != before and game.land.home.x >= 0:
		game.hud.toast("🏠 قاعدتك الآن في %s" % game.land.settlements[game.land.home.x].name, Color("7dff9e"))
		game.save_game()


@rpc("authority", "reliable")
func land_denied(kind: String, s: int, reason: String) -> void:
	var lvl: int = game.land.settlements[s].level
	if kind == "rent":
		game.land.plot_titles[lvl] += 1             # إرجاع الوثيقة
	elif kind == "buy":
		game.land.settle_titles[lvl] += 1
	game.hud.toast("تعذّر: " + reason + " (أُعيدت إليك الوثيقة)", Color("ff6b6b"))


## ضريبة الساكن تذهب إلى مالك المستوطنة (إن كان متصلاً)
func land_tax(owner_name: String, amount: int) -> void:
	if amount <= 0:
		return
	if is_server():
		_route_land_tax(owner_name, amount, my_name)
	else:
		_req_land_tax.rpc_id(1, owner_name, amount)


@rpc("any_peer", "reliable", "call_remote", 2)
func _req_land_tax(owner_name: String, amount: int) -> void:
	if is_server():
		_route_land_tax(owner_name, amount, peers.get(multiplayer.get_remote_sender_id(), {}).get("name", ""))


func _route_land_tax(owner_name: String, amount: int, from: String) -> void:
	for pid in peers:
		if peers[pid].name == owner_name:
			if pid == my_id():
				land_rent(amount, from)
			else:
				land_rent.rpc_id(pid, amount, from)
			return


var _rent_acc := 0
var rent_total := 0            # مجموع ضرائب السكان المستلمة (للإحصاء والاختبار)
@rpc("authority", "reliable", "call_remote", 2)
func land_rent(amount: int, _from: String) -> void:
	game.bank += amount
	_rent_acc += amount
	rent_total += amount
	if _rent_acc >= 1000:
		game.hud.toast("🏛 ضرائب سكان مستوطنتك: +%s" % Cfg.money(_rent_acc), Color("7dff9e"))
		_rent_acc = 0


# ---------------------------------------------------------------- تغيير الدور
func request_role(role: String) -> void:
	if is_server():
		_change_role(my_id(), role)
	else:
		_req_role.rpc_id(1, role)


@rpc("any_peer", "reliable")
func _req_role(role: String) -> void:
	if is_server():
		_change_role(multiplayer.get_remote_sender_id(), role)


func _change_role(id: int, role: String) -> void:
	if role == "cop" and (_cop_count() >= MAX_COPS or wanted.get(id, {"level": 0}).level > 0):
		if id == my_id():
			role_result(false, role)
		else:
			role_result.rpc_id(id, false, role)
		return
	peers[id].role = role
	role_update.rpc(id, role)
	if mode == Mode.HOST:
		role_update(id, role)
	if id == my_id():
		role_result(true, role)
	else:
		role_result.rpc_id(id, true, role)


@rpc("authority", "reliable")
func role_update(id: int, role: String) -> void:
	if peers.has(id):
		peers[id].role = role
	if id == my_id():
		my_role = role


@rpc("authority", "reliable")
func role_result(ok: bool, role: String) -> void:
	game.cop.on_role_result(ok, role)


# ---------------------------------------------------------------- الدردشة والحفظ
func send_chat(text: String) -> void:
	text = text.strip_edges().substr(0, 140)
	if text == "":
		return
	if is_server():
		chat.rpc(my_id(), text)
		_chat_local(my_id(), text)
	else:
		_chat_in.rpc_id(1, text)


@rpc("any_peer", "reliable")
func _chat_in(text: String) -> void:
	if is_server():
		var id := multiplayer.get_remote_sender_id()
		chat.rpc(id, text.substr(0, 140))
		_chat_local(id, text.substr(0, 140))


@rpc("authority", "reliable")
func chat(from: int, text: String) -> void:
	_chat_local(from, text)


func _chat_local(from: int, text: String) -> void:
	var who: String = "📢" if from == 0 else peers.get(from, {}).get("name", "?")
	_log("chat %s: %s" % [who, text])
	if mode != Mode.SERVER and game.hud:
		game.hud.add_chat(who, text, from != 0 and peers.get(from, {}).get("role", "") == "cop")


func save_profile(d: Dictionary) -> void:
	if not is_online():
		return
	if is_server():
		_store_profile(my_name, d)
	else:
		_save_profile.rpc_id(1, d)


@rpc("any_peer", "reliable")
func _save_profile(d: Dictionary) -> void:
	if is_server():
		var id := multiplayer.get_remote_sender_id()
		if peers.has(id):
			_store_profile(peers[id].name, d)


func _store_profile(pname: String, d: Dictionary) -> void:
	_profiles.set_value("players", pname, d)
	_profiles.save(PROFILE_PATH)
