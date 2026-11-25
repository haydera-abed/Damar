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
# مدينة السطو (الخادم يحسم): إغلاق الأهداف، السطو الجاري، وحقيبة كل لاعب
var heist_cd := {}                                              # target_id -> unix حتى يُفتح
var heist_active := {}                                          # peer -> {target, t0}
var heist_bags := {}                                            # peer -> {item: n}
# السجن الفيدرالي والنفوذ (الخادم يحسم): الملف الدائم لكل لاعب في قسم "permanent" ولا يُمسح أبداً
var season_start := 0                                           # بداية الموسم (المداهمة بعد 7 أيام حقيقية)
var _sentence_lock := {}                                        # اسم -> وقت؛ نتجاهل حفظاً قديماً يصل بعد الحكم
var _raid_check := 0.0
# دفتر الاقتصاد (الخادم مصدر الحقيقة للمال في اللعب الجماعي)
const START_CASH := 2000
const CLAIM_CAP_PER_HOUR := 60000           # سقف ما يُقبل من «إنتاج المنزل» (حصاد، شحنات) غير القابل للتحقق
const CLAIMABLE := ["weed", "cargo", "goods", "gold", "heist"]
var ledger := {}                            # الاسم -> {bank, cash, pool, motel, bag, stash, xp, lvl, claims, t}
var rob_active := {}                        # peer -> {idx, t0}
var _ledger_dirty := {}
var _ledger_t := 0.0
var _ledger_full := 0
var server_bag: Array = []                  # (عند العميل) آخر حقيبة أرسلها الخادم — للمقارنة
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
	season_start = int(_profiles.get_value("server", "season_start", 0))
	if season_start == 0:
		season_start = int(Time.get_unix_time_from_system())
		_profiles.set_value("server", "season_start", season_start)
		_profiles.save(PROFILE_PATH)
	if not dedicated:
		var perm := _perm(my_name)
		peers[1] = {"name": my_name, "role": my_role, "auth": PrisonManager.level_for_years(perm.jail_years), "years": perm.jail_years}
		_apply_perm(perm)
		_ledger_of(my_name)
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
	EconomyManager.outflow_hook = Callable()
	MotelManager.net_spin = Callable()
	MotelManager.net_barter = Callable()
	MotelManager.quest_cash_enabled = true
	game.ledger_synced = 0
	if game.heist:
		game.heist.detach_net()
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
	register.rpc_id(1, my_name, my_role, my_info())


func _on_failed() -> void:
	mode = Mode.SOLO
	multiplayer.multiplayer_peer = null
	joined.emit(false, "تعذّر الاتصال بالخادم")


func _on_server_gone() -> void:
	leave()
	game.on_net_lost("انقطع الاتصال بالخادم")


func _on_peer_disconnected(id: int) -> void:
	heist_bags.erase(id)
	heist_active.erase(id)
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


## معلومات تُعلن عند الدخول: النفوذ وسنوات السجن (من الملف الدائم لطبقة المنطق)
func my_info() -> Dictionary:
	return {"auth": PrisonManager.authority_level(), "years": int(GameState.profile.jail_years)}


@rpc("any_peer", "reliable")
func register(pname: String, role: String, info: Dictionary = {}) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = _unique_name(pname)
	var note := ""
	if role == "cop" and _cop_count() >= MAX_COPS:
		role = "criminal"
		note = "كل مقاعد الشرطة (%d) مشغولة — دخلت كمجرم" % MAX_COPS
	var perm := _perm(pname)                 # الخادم مصدر الحقيقة للنفوذ (ما يعلنه العميل للعرض فقط في السجل)
	peers[id] = {"name": pname, "role": role, "auth": PrisonManager.level_for_years(perm.jail_years), "years": perm.jail_years}
	if int(info.get("years", 0)) != perm.jail_years:
		_log("ignored client-claimed years %d for %s (server: %d)" % [int(info.get("years", 0)), pname, perm.jail_years])
	wanted[id] = {"level": 0, "unseen": 0.0}
	var profile: Dictionary = _profiles.get_value("players", pname, {})
	var shared := _shared_state()
	shared["perm"] = perm
	welcome.rpc_id(id, id, pname, role, peers, profile, shared, note)
	_ledger_of(pname)
	_sync_ledger(id)
	peer_joined.rpc(id, pname, role, peers[id].auth)
	if mode == Mode.HOST:
		_spawn_remote(id)
	_log("registered %d as %s (%s, authority %d)" % [id, pname, role, peers[id].auth])
	chat.rpc(0, "%s دخل المدينة (%s)" % [pname, "شرطي" if role == "cop" else "مجرم"])
	_chat_local(0, "%s دخل المدينة (%s)" % [pname, "شرطي" if role == "cop" else "مجرم"])


func _shared_state() -> Dictionary:
	var cds := []
	for t in game.crime.targets:
		cds.append([t.cooldown, t.uses_left])
	return {"targets": cds, "districts": district_owner, "settle": settle_owner, "plots": plot_tenant, "heist_cd": heist_cd, "season_start": season_start}


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
	heist_cd = shared.get("heist_cd", {})
	season_start = int(shared.get("season_start", 0))
	_apply_perm(shared.get("perm", {}))
	for k in heist_cd:
		HeistCityManager.cooldowns[k] = int(heist_cd[k])
	joined.emit(true, note)
	_log("welcome as %s (%s), %d peers" % [pname, role, peers.size()])


@rpc("authority", "reliable")
func peer_joined(id: int, pname: String, role: String, auth: int = 0) -> void:
	if id == my_id():
		return
	peers[id] = {"name": pname, "role": role, "auth": auth}
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
	_ledger_t -= dt
	if _ledger_t <= 0.0:
		_ledger_t = 1.0
		_ledger_full -= 1
		if _ledger_full <= 0:                  # مزامنة كاملة دورية: تمحو أي دخل محلي لم يعتمده الخادم
			_ledger_full = 5
			for pid in peers:
				_ledger_dirty[peers[pid].name] = true
		_launder_ledgers()
		for n in _ledger_dirty:
			var pid := _peer_by_name(n)
			if pid != 0:
				_sync_ledger(pid)
		if not _ledger_dirty.is_empty():
			_save_ledgers()
		_ledger_dirty = {}
	_raid_check -= dt
	if _raid_check <= 0.0:
		_raid_check = 2.0
		if int(Time.get_unix_time_from_system()) >= season_start + Balance.WIPE_PERIOD_SEC:
			federal_raid_all()
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
				var lt := _ledger_of(peers[id].name)
				lt.pool = float(lt.pool) + 1500 * n
				_ledger_dirty[peers[id].name] = true
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
	rob_active[id] = {"idx": idx, "t0": Time.get_ticks_msec()}
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
	if not _spend_ammo(shooter, origin):
		return
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
	var lv := _ledger_of(peers[target].name)          # الشرطة تصادر الكاش والحقيبة
	lv.cash = 0
	lv.bag = []
	_ledger_dirty[peers[target].name] = true
	var lc := _ledger_of(cop_name)
	lc.bank = int(lc.bank) + reward
	_ledger_dirty[cop_name] = true
	heist_active.erase(target)
	if ts[3] & F_MASK != 0 and heist_bags.has(target):
		_log("heist bag of %s lost on arrest" % peers[target].name)
		heist_bags.erase(target)
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
		"evict":
			if plot_tenant.get(key, "") == "":
				reason = "القطعة فارغة"
			else:
				_log("evicted %s" % plot_tenant[key])
				var victim := _ledger_of(plot_tenant[key])
				victim.inv.house = _fresh_inv().house       # المنزل يضيع مع القطعة
				_ledger_dirty[plot_tenant[key]] = true
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


## بلاغ للجميع (مثلاً: لاعب يجمع ضرائب مستوطنته)
func land_alert(pos: Vector3, msg: String) -> void:
	if is_server():
		land_alert_all.rpc(pos, msg)
		land_alert_all(pos, msg)
	else:
		_req_land_alert.rpc_id(1, pos, msg)


@rpc("any_peer", "reliable")
func _req_land_alert(pos: Vector3, msg: String) -> void:
	if is_server():
		land_alert_all.rpc(pos, msg)
		if mode == Mode.HOST:
			land_alert_all(pos, msg)


@rpc("authority", "reliable")
func land_alert_all(pos: Vector3, msg: String) -> void:
	if mode == Mode.SERVER:
		_log(msg)
		return
	game.alerts.append([pos, 40.0])
	game.hud.toast(msg, Color("ffb36b"))


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


func _route_land_tax(_owner_name: String, _amount: int, _from: String) -> void:
	return                                     # صار الخادم يحسب ضريبة الساكن من غسيله في الدفتر (_launder_ledgers)


func _route_land_tax_old(owner_name: String, amount: int, from: String) -> void:
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


# ---------------------------------------------------------------- دفتر الاقتصاد (الخادم يحسم المال)
func _fresh_ledger() -> Dictionary:
	return {"bank": 0, "cash": START_CASH, "pool": 0.0, "motel": 0, "bag": [], "stash": [], "xp": 0, "lvl": 1, "claims": [], "t": int(Time.get_unix_time_from_system()), "inv": _fresh_inv()}


func _ledger_of(pname: String) -> Dictionary:
	if ledger.has(pname):
		return ledger[pname]
	var l: Dictionary = _profiles.get_value("ledger", pname, {})
	if l.is_empty():
		# ترحيل لمرة واحدة من ملف اللاعب القديم على الخادم، أو بداية جديدة
		var prof: Dictionary = _profiles.get_value("players", pname, {})
		l = _fresh_ledger()
		if not prof.is_empty():
			var cr: Dictionary = prof.get("crime", {})
			l.bank = int(prof.get("bank", 0))
			l.cash = int(prof.get("cash", 0))
			l.pool = float(cr.get("pool", 0.0))
			l.bag = cr.get("bag", [])
			l.xp = int(cr.get("notoriety", 0))
			l.lvl = int(cr.get("launder_level", 1))
			l.motel = int(prof.get("land", {}).get("motel", 0))
	if not l.has("inv"):
		l["inv"] = _inv_from_profile(_profiles.get_value("players", pname, {}))
	var fresh := _fresh_ledger()
	for k in fresh:
		if not l.has(k):
			l[k] = fresh[k]
	ledger[pname] = l
	return l


func _peer_by_name(pname: String) -> int:
	for id in peers:
		if peers[id].name == pname:
			return id
	return 0


func _sync_ledger(id: int) -> void:
	if not peers.has(id):
		return
	var l := _ledger_of(peers[id].name)
	var view := {"bank": int(l.bank), "cash": int(l.cash), "pool": float(l.pool), "motel": int(l.motel), "bag": l.bag, "xp": int(l.xp), "lvl": int(l.lvl), "inv": l.inv}
	_send(id, "ledger_sync", [view])


func _save_ledgers() -> void:
	for n in ledger:
		_profiles.set_value("ledger", n, ledger[n])
	_profiles.save(PROFILE_PATH)


## الغسيل على الخادم بالوقت الحقيقي (للاعب غير المتصل يُحسب ما فاته عند تحميل دفتره)
func _launder_ledgers() -> void:
	var now := int(Time.get_unix_time_from_system())
	for n in ledger.keys():
		var l: Dictionary = ledger[n]
		var elapsed := maxi(0, now - int(l.t))
		l.t = now
		if float(l.pool) <= 0.0 or elapsed == 0:
			continue
		var amount := minf(float(l.pool), _launder_rate(n, l) * elapsed)
		l.pool = float(l.pool) - amount
		var tax := 0.0
		var landlord := _landlord_of(n)
		if landlord != "":
			tax = amount * _tenant_tax_rate(n)
			var lo := _ledger_of(landlord)
			lo.bank = int(lo.bank) + int(tax)
			_ledger_dirty[landlord] = true
			if landlord == my_name:
				rent_total += int(tax)
			else:
				var lid := _peer_by_name(landlord)
				if lid != 0:
					_send(lid, "rent_received", [int(tax)])
		l.bank = int(l.bank) + int(round(amount - tax))
		_ledger_dirty[n] = true


@rpc("authority", "reliable")
func rent_received(amount: int) -> void:
	rent_total += amount
	_rent_acc += amount
	if _rent_acc >= 1000:
		game.hud.toast("🏛 ضرائب سكان مستوطنتك: +%s" % Cfg.money(_rent_acc), Color("7dff9e"))
		_rent_acc = 0


func _launder_rate(pname: String, l: Dictionary) -> float:
	var bonus := 0.0
	for i in 9:
		if district_owner[i] == pname:
			bonus += Gangs.LAUNDER_BONUS[Gangs.LEVEL[i]]
	return Crime.LAUNDER_BASE_RATE * clampi(int(l.lvl), 1, 4) * (1.0 + bonus)


## مالك المستوطنة التي يسكنها اللاعب (إن كان لاعباً آخر)
func _landlord_of(pname: String) -> String:
	for key in plot_tenant:
		if plot_tenant[key] == pname:
			var si := int((key as String).split(":")[0])
			var owner: String = settle_owner[si]
			return owner if owner != pname else ""
	return ""


func _tenant_tax_rate(pname: String) -> float:
	for key in plot_tenant:
		if plot_tenant[key] == pname:
			var si := int((key as String).split(":")[0])
			return Land.TENANT_TAX[game.land.settlements[si].level]
	return 0.0


## الدفع: يُخصم من الكاش ثم البنك؛ يُرفض إن لم يكفِ
func req_spend(amount: int) -> void:
	if amount <= 0:
		return
	if is_server():
		_spend(my_id(), amount)
	else:
		_req_spend.rpc_id(1, amount)


@rpc("any_peer", "reliable")
func _req_spend(amount: int) -> void:
	if is_server():
		_spend(multiplayer.get_remote_sender_id(), amount)


func _spend(id: int, amount: int) -> void:
	if not peers.has(id):
		return
	var l := _ledger_of(peers[id].name)
	if int(l.cash) + int(l.bank) < amount:
		_log("rejected spend %d by %s (has %d)" % [amount, peers[id].name, int(l.cash) + int(l.bank)])
		_send(id, "ledger_note", ["الخادم رفض الدفع: رصيدك لا يكفي"])
	else:
		var from_cash := mini(int(l.cash), amount)
		l.cash = int(l.cash) - from_cash
		l.bank = int(l.bank) - (amount - from_cash)
	_ledger_dirty[peers[id].name] = true


func req_deposit(amount := -1) -> void:
	if is_server():
		_deposit(my_id(), amount)
	else:
		_req_deposit.rpc_id(1, amount)


@rpc("any_peer", "reliable")
func _req_deposit(amount: int) -> void:
	if is_server():
		_deposit(multiplayer.get_remote_sender_id(), amount)


func _deposit(id: int, amount: int) -> void:
	if not peers.has(id) or wanted.get(id, {"level": 0}).level > 0:
		return
	var l := _ledger_of(peers[id].name)
	var a := int(l.cash) if amount < 0 else mini(amount, int(l.cash))
	l.cash = int(l.cash) - a
	l.pool = float(l.pool) + a
	l.t = int(Time.get_unix_time_from_system())
	_ledger_dirty[peers[id].name] = true


## خزنة الموتيل: amount موجب = إيداع، سالب = سحب. half_launder = غسيل رفيق بنصف القيمة
func req_motel(amount: int, half_launder := false) -> void:
	if is_server():
		_motel(my_id(), amount, half_launder)
	else:
		_req_motel.rpc_id(1, amount, half_launder)


@rpc("any_peer", "reliable")
func _req_motel(amount: int, half_launder: bool) -> void:
	if is_server():
		_motel(multiplayer.get_remote_sender_id(), amount, half_launder)


func _motel(id: int, amount: int, half_launder: bool) -> void:
	if not peers.has(id) or (states.has(id) and (states[id][0] as Vector3).distance_to(game.city.safe_pos) > 12.0):
		return
	var l := _ledger_of(peers[id].name)
	if half_launder:
		var a := mini(int(l.cash), 100000)
		l.cash = int(l.cash) - a
		l.bank = int(l.bank) + a / 2
	elif amount > 0:
		var a2 := mini(amount, int(l.cash))
		l.cash = int(l.cash) - a2
		l.motel = int(l.motel) + a2
	else:
		var a3 := mini(-amount, int(l.motel))
		l.motel = int(l.motel) - a3
		l.cash = int(l.cash) + a3
	_ledger_dirty[peers[id].name] = true


## غنائم السرقات العادية: الخادم يرميها بعد التحقق من الهدف والوقت والموقع
func req_rob_loot(idx: int) -> void:
	if is_server():
		_rob_loot(my_id(), idx)
	else:
		_req_rob_loot.rpc_id(1, idx)


@rpc("any_peer", "reliable")
func _req_rob_loot(idx: int) -> void:
	if is_server():
		_rob_loot(multiplayer.get_remote_sender_id(), idx)


func _rob_loot(id: int, idx: int) -> void:
	var a: Dictionary = rob_active.get(id, {})
	if a.is_empty() or int(a.idx) != idx or not states.has(id) or idx < 0 or idx >= game.crime.targets.size():
		_log("rejected rob loot by %s (no active robbery of %d)" % [peers.get(id, {}).get("name", "?"), idx])
		return
	var t: Crime.Target = game.crime.targets[idx]
	if (Time.get_ticks_msec() - int(a.t0)) / 1000.0 < t.time * 0.8 or (states[id][0] as Vector3).distance_to(t.pos) > 5.0:
		_log("rejected rob loot by %s" % peers[id].name)
		return
	rob_active.erase(id)
	var l := _ledger_of(peers[id].name)
	var items: Dictionary = l.inv.items
	for tool in t.tools:
		if int(items.get(tool, 0)) <= 0:
			_log("rejected rob loot by %s (missing %s on server)" % [peers[id].name, tool])
			_send(id, "ledger_note", ["الخادم رفض السرقة: لا تملك %s" % Crime.TOOLS[tool].name])
			_ledger_dirty[peers[id].name] = true
			return
	for tool in t.tools:
		items[tool] = int(items[tool]) - 1
	var total := 0
	for i in t.count:
		var v := roundi(randf_range(t.value.x, t.value.y) / 10.0) * 10
		l.bag.append({"name": t.loot_name, "value": v, "kind": t.loot_kind})
		total += v
	if t.loot_kind == "box":
		l.bag.append({"name": "مفتاح صندوق ودائع", "value": 0, "kind": "deposit_key"})
	_ledger_dirty[peers[id].name] = true
	_log("%s robbed %s for %d" % [peers[id].name, t.label, total])
	_send(id, "ledger_note", ["+%s %s في الحقيبة" % [Cfg.money(total), t.loot_name]])


## البيع للمشتري: عند شاحنة المشتري وأنت مقنّع؛ السعر يحسبه الخادم من سمعتك
func req_sell() -> void:
	if is_server():
		_sell(my_id())
	else:
		_req_sell.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_sell() -> void:
	if is_server():
		_sell(multiplayer.get_remote_sender_id())


func _sell(id: int) -> void:
	if not states.has(id):
		return
	var p: Vector3 = states[id][0]
	var near := false
	for f in game.crime.fences:
		if p.distance_to(f) < 9.0:
			near = true
	if not near or states[id][3] & F_MASK == 0:
		_send(id, "ledger_note", ["المشتري لا يتعامل معك هنا (اقترب من شاحنته والبس القناع)"])
		return
	var l := _ledger_of(peers[id].name)
	var base := 0
	var keep := []
	for it in l.bag:
		if it.get("kind", "") == "deposit_key":
			keep.append(it)
		else:
			base += int(it.get("value", 0))
	if base <= 0:
		return
	var lvl := 1
	for i in Crime.NOTORIETY_XP.size():
		if int(l.xp) >= Crime.NOTORIETY_XP[i]:
			lvl = i + 1
	var bonus: float = Crime.NOTORIETY_BONUS[lvl - 1] + (0.10 if district_owner[Gangs.CENTER] == peers[id].name else 0.0)
	var paid := int(base * (1.0 + bonus))
	l.cash = int(l.cash) + paid
	l.xp = int(l.xp) + base
	l.bag = keep
	_ledger_dirty[peers[id].name] = true
	_log("%s sold loot for %d" % [peers[id].name, paid])
	_send(id, "ledger_note", ["بعت الغنائم بـ %s نقوداً قذرة" % Cfg.money(paid)])


## فروقات الحقيبة: ما أُزيل (تخزين، مقايضة) يُنقل لمخزن الخادم؛ ما أُضيف يُقبل من المخزن، أو كإنتاج ضمن سقف ساعي
func req_bag_diff(removed: Array, added: Array) -> void:
	if is_server():
		_bag_diff(my_id(), removed, added)
	else:
		_req_bag_diff.rpc_id(1, removed, added)


@rpc("any_peer", "reliable")
func _req_bag_diff(removed: Array, added: Array) -> void:
	if is_server():
		_bag_diff(multiplayer.get_remote_sender_id(), removed, added)


func _bag_diff(id: int, removed: Array, added: Array) -> void:
	if not peers.has(id):
		return
	var l := _ledger_of(peers[id].name)
	for it in removed:
		var j := _find_item(l.bag, it)
		if j >= 0:
			l.stash.append(l.bag[j])
			l.bag.remove_at(j)
	var now := int(Time.get_unix_time_from_system())
	var claims: Array = l.claims.filter(func(c): return now - int(c[0]) < 3600)
	var used := 0
	for c in claims:
		used += int(c[1])
	var rejected := 0
	for it in added:
		var j := _find_item(l.stash, it)
		var val := int(it.get("value", 0))
		if j >= 0:
			l.bag.append(l.stash[j])
			l.stash.remove_at(j)
		elif CLAIMABLE.has(it.get("kind", "")) and val <= 30000 and used + val <= CLAIM_CAP_PER_HOUR:
			l.bag.append({"name": it.get("name", ""), "value": val, "kind": it.get("kind", "")})
			used += val
			claims.append([now, val])
		else:
			rejected += 1
	l.claims = claims
	_ledger_dirty[peers[id].name] = true
	if rejected > 0:
		_log("rejected %d bag claims from %s" % [rejected, peers[id].name])
		_send(id, "ledger_note", ["الخادم رفض %d عناصر غير قابلة للتحقق" % rejected])


func _find_item(arr: Array, it: Dictionary) -> int:
	for j in arr.size():
		if arr[j].get("kind", "") == it.get("kind", "") and int(arr[j].get("value", 0)) == int(it.get("value", 0)) and arr[j].get("name", "") == it.get("name", ""):
			return j
	return -1


## تطوير طاولة الغسيل: يخصم الخادم من البنك ويرفع المستوى في الدفتر
func req_upgrade_launder() -> void:
	if is_server():
		_upgrade_launder(my_id())
	else:
		_req_upgrade_launder.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_upgrade_launder() -> void:
	if is_server():
		_upgrade_launder(multiplayer.get_remote_sender_id())


func _upgrade_launder(id: int) -> void:
	if not peers.has(id):
		return
	var l := _ledger_of(peers[id].name)
	var cost := 50000 * int(l.lvl)
	if int(l.lvl) >= 4 or int(l.bank) < cost:
		_send(id, "ledger_note", ["الخادم رفض التطوير (تحتاج %s في البنك)" % Cfg.money(cost)])
		return
	l.bank = int(l.bank) - cost
	l.lvl = int(l.lvl) + 1
	_ledger_dirty[peers[id].name] = true
	_send(id, "ledger_note", ["طوّرت طاولة الغسيل إلى المستوى %d" % int(l.lvl)])


## دخل من أحداث يحاكيها العميل (اعتقال لص آلي، ضرائب سكان آليين، طرد، سيارة المعرض):
## لا يمكن التحقق منه كاملاً، فيُقبل ضمن حد لكل نوع وسقف ساعي مشترك
const INCOME_MAX := {"npc_arrest": 25000, "npc_down": 2000, "evict": 60000, "settle_tax": 150000, "exhibit": 240000}
const INCOME_CAP_PER_HOUR := 300000


func req_income(kind: String, amount: int) -> void:
	if is_server():
		_income(my_id(), kind, amount)
	else:
		_req_income.rpc_id(1, kind, amount)


@rpc("any_peer", "reliable")
func _req_income(kind: String, amount: int) -> void:
	if is_server():
		_income(multiplayer.get_remote_sender_id(), kind, amount)


func _income(id: int, kind: String, amount: int) -> void:
	if not peers.has(id) or not INCOME_MAX.has(kind) or amount <= 0:
		return
	var l := _ledger_of(peers[id].name)
	if not l.has("income"):
		l["income"] = []
	var now := int(Time.get_unix_time_from_system())
	var inc: Array = l.income.filter(func(c): return now - int(c[0]) < 3600)
	var used := 0
	for c in inc:
		used += int(c[1])
	var a := mini(amount, int(INCOME_MAX[kind]))
	if used + a > INCOME_CAP_PER_HOUR:
		_log("rejected income %s %d from %s (hourly cap)" % [kind, amount, peers[id].name])
		_send(id, "ledger_note", ["الخادم لم يعتمد هذا الدخل (تجاوزت السقف الساعي)"])
		l.income = inc
		return
	inc.append([now, a])
	l.income = inc
	if kind in ["npc_arrest", "npc_down", "settle_tax"]:
		l.bank = int(l.bank) + a
	else:
		l.cash = int(l.cash) + a
	_ledger_dirty[peers[id].name] = true


# ---------------------------------------------------------------- مخزون الخادم (الأدوات، الأسلحة، الذخيرة، بناء المنزل)
const TRACKED_ITEMS := ["lockpick", "minidrill", "drill", "cutter", "jammer", "bank_card", "decoder", "armory_card", "decoder_epic", "master_key", "eviction_right", "pass_vip"]
const BAG_KIND_OF := {"deposit_key": "deposit_key", "gold_bar": "gold", "gold": "gold", "art": "art"}
var _last_volley := {}                      # peer -> origin آخر طلقة (لعدّ الخرطوش طلقة واحدة)


func _fresh_inv() -> Dictionary:
	return {"items": {"lockpick": 3}, "weapons": ["pistol"], "ammo": 36,
		"house": {"tier": 1, "annex": "", "slots": [], "modules": {}, "counter": 0, "tables": 0, "fan": false}}


## ترحيل لمرة واحدة: ما كان محفوظاً على الخادم من ملف اللاعب القديم
func _inv_from_profile(prof: Dictionary) -> Dictionary:
	var inv := _fresh_inv()
	if prof.is_empty():
		return inv
	var tools: Dictionary = prof.get("crime", {}).get("tools", {})
	inv.items = {}
	for k in tools:
		if TRACKED_ITEMS.has(k) and int(tools[k]) > 0:
			inv.items[k] = int(tools[k])
	var w: Dictionary = prof.get("weapons", {})
	inv.weapons = (w.get("owned", []) as Array).filter(func(x): return Weapons.CATALOG.has(x) and int(Weapons.CATALOG[x].price) > 0)
	inv.ammo = int(w.get("ammo", 0))
	var h: Dictionary = prof.get("land", {}).get("house", {})
	if not h.is_empty():
		inv.house = {"tier": int(h.get("tier", 1)), "annex": h.get("annex", ""), "slots": h.get("slots", []), "modules": h.get("modules", {}),
			"counter": int(h.get("counter", 0)), "tables": (h.get("tables", []) as Array).size(), "fan": bool(h.get("fan", false))}
	return inv


func _pay_ledger(l: Dictionary, amount: int, bank_only := false) -> bool:
	if amount <= 0:
		return true
	if bank_only:
		if int(l.bank) < amount:
			return false
		l.bank = int(l.bank) - amount
		return true
	if int(l.cash) + int(l.bank) < amount:
		return false
	var from_cash := mini(int(l.cash), amount)
	l.cash = int(l.cash) - from_cash
	l.bank = int(l.bank) - (amount - from_cash)
	return true


func _take_from_bag(l: Dictionary, kind: String, n: int) -> bool:
	var idx := []
	for j in l.bag.size():
		if l.bag[j].get("kind", "") == kind and idx.size() < n:
			idx.append(j)
	if idx.size() < n:
		return false
	idx.reverse()
	for j in idx:
		l.bag.remove_at(j)
	return true


## الشراء: what = "tool:x" | "barter:x" | "weapon:x" | "ammo" | "house:upgrade|place:k|annex:a|demolish|counter|module:m|table|fan" | "motel:recipe"
func req_buy(what: String) -> void:
	if is_server():
		_buy(my_id(), what)
	else:
		_req_buy.rpc_id(1, what)


@rpc("any_peer", "reliable")
func _req_buy(what: String) -> void:
	if is_server():
		_buy(multiplayer.get_remote_sender_id(), what)


func _buy(id: int, what: String) -> void:
	if not peers.has(id):
		return
	var pname: String = peers[id].name
	var l := _ledger_of(pname)
	var inv: Dictionary = l.inv
	var items: Dictionary = inv.items
	var h: Dictionary = inv.house
	var p := what.split(":")
	var arg: String = p[1] if p.size() > 1 else ""
	var why := ""
	match p[0]:
		"tool":
			if not Crime.TOOLS.has(arg) or not Crime.TOOLS[arg].has("price"):
				why = "أداة غير معروفة"
			elif not _pay_ledger(l, int(Crime.TOOLS[arg].price)):
				why = "رصيدك لا يكفي"
			else:
				items[arg] = int(items.get(arg, 0)) + 1
		"barter":
			if not Crime.TOOLS.has(arg) or not Crime.TOOLS[arg].has("barter"):
				why = "مقايضة غير معروفة"
			else:
				var need: Dictionary = Crime.TOOLS[arg].barter
				for k in need:
					if l.bag.filter(func(it): return it.get("kind", "") == k).size() < int(need[k]):
						why = "تنقصك عناصر المقايضة في حقيبتك"
				if why == "":
					for k in need:
						_take_from_bag(l, k, int(need[k]))
					items[arg] = int(items.get(arg, 0)) + 1
		"motel":
			why = _motel_barter(id, l, arg)
		"weapon":
			if not Weapons.CATALOG.has(arg) or int(Weapons.CATALOG[arg].price) <= 0 or inv.weapons.has(arg):
				why = "سلاح غير متاح"
			elif not _pay_ledger(l, int(Weapons.CATALOG[arg].price)):
				why = "رصيدك لا يكفي"
			else:
				inv.weapons.append(arg)
				if int(inv.ammo) < 30:
					inv.ammo = int(inv.ammo) + 30
		"ammo":
			if not _pay_ledger(l, 1500):
				why = "رصيدك لا يكفي"
			else:
				inv.ammo = int(inv.ammo) + 60
		"house":
			why = _house_buy(pname, l, h, arg, p[2] if p.size() > 2 else "")
		_:
			why = "طلب غير معروف"
	if why != "":
		_log("rejected buy %s by %s: %s" % [what, pname, why])
		_send(id, "ledger_note", ["الخادم رفض الشراء: " + why])
	else:
		_log("%s bought %s" % [pname, what])
	_ledger_dirty[pname] = true
	_sync_ledger(id)                          # فوراً لتظهر النتيجة في القائمة


func _house_buy(pname: String, l: Dictionary, h: Dictionary, sub: String, arg: String) -> String:
	var te: int = 4 if settle_owner.has(pname) else int(h.tier)
	match sub:
		"upgrade":
			var nt := te + 1
			if te >= 3:
				return "لا ترقية بعد هذا المستوى"
			if not _pay_ledger(l, House.UPGRADE_COST[nt], true):
				return "تحتاج %s في البنك" % Cfg.money(House.UPGRADE_COST[nt])
			h.tier = nt
		"place":
			if not House.FURN.has(arg):
				return "أثاث غير معروف"
			var slot: String = House.FURN[arg].slot
			var cap: int = House.TIER_SLOTS[te].get(slot, 0) + (2 if slot == "bench" and h.annex == "workshop" else 0)
			var used := 0
			for k in h.slots:
				if House.FURN.has(k) and House.FURN[k].slot == slot:
					used += 1
			if used >= cap:
				return "لا مكان فارغ"
			if not _pay_ledger(l, int(House.FURN[arg].price), true):
				return "رصيدك في البنك لا يكفي"
			h.slots.append(arg)
		"annex":
			if not House.ANNEX.has(arg) or h.annex != "" or settle_owner.has(pname):
				return "لا يمكن بناء الملحق"
			if not _pay_ledger(l, int(House.ANNEX[arg].price), true):
				return "رصيدك في البنك لا يكفي"
			h.annex = arg
			h.tables = 1 if arg == "grow" else 0
		"demolish":
			h.annex = ""
			h.tables = 0
		"counter":
			if int(h.counter) >= House.COUNTERS.size() - 1:
				return "أعلى عدّاد"
			if not _pay_ledger(l, int(House.COUNTERS[int(h.counter) + 1].price), true):
				return "رصيدك في البنك لا يكفي"
			h.counter = int(h.counter) + 1
		"module":
			if not House.MODULES.has(arg) or h.modules.has(arg):
				return "وحدة غير متاحة"
			if not _pay_ledger(l, int(House.MODULES[arg].price), true):
				return "رصيدك في البنك لا يكفي"
			h.modules[arg] = true
		"table":
			if h.annex != "grow" or int(h.tables) >= 6:
				return "لا مكان لطاولة"
			if not _pay_ledger(l, House.TABLE_PRICE, true):
				return "رصيدك في البنك لا يكفي"
			h.tables = int(h.tables) + 1
		"fan":
			if h.annex != "grow" or h.fan:
				return "غير متاح"
			if not _pay_ledger(l, House.FAN_PRICE, true):
				return "رصيدك في البنك لا يكفي"
			h.fan = true
		_:
			return "طلب غير معروف"
	return ""


## مقايضة الباب المريب في الموتيل (وصفات MotelManager)
func _motel_barter(id: int, l: Dictionary, recipe_id: String) -> String:
	var r: BarterRecipe = null
	for x in MotelManager.recipes:
		if x.id == recipe_id:
			r = x
	if r == null:
		return "وصفة غير معروفة"
	if int(peers[id].get("auth", 0)) < r.required_authority:
		return "نفوذك غير كافٍ"
	if not TRACKED_ITEMS.has(r.output_item):
		return "مخرجات غير مدعومة"
	var items: Dictionary = l.inv.items
	for k in r.inputs:
		var n := int(r.inputs[k])
		if TRACKED_ITEMS.has(k):
			if int(items.get(k, 0)) < n:
				return "تنقصك عناصر المقايضة"
		elif BAG_KIND_OF.has(k):
			if l.bag.filter(func(it): return it.get("kind", "") == BAG_KIND_OF[k]).size() < n:
				return "تنقصك عناصر المقايضة في حقيبتك"
		else:
			return "عنصر غير مدعوم"
	if int(l.cash) + int(l.bank) < r.cash_cost:
		return "رصيدك لا يكفي"
	_pay_ledger(l, r.cash_cost)
	for k in r.inputs:
		if TRACKED_ITEMS.has(k):
			items[k] = int(items[k]) - int(r.inputs[k])
		else:
			_take_from_bag(l, BAG_KIND_OF[k], int(r.inputs[k]))
	items[r.output_item] = int(items.get(r.output_item, 0)) + r.output_count
	return ""


## استهلاك أداة خارج السرقات (جهاز التشويش، أجهزة فك الشفرة للطرد والاقتحام)
func req_use(item: String, n: int) -> void:
	if is_server():
		_use(my_id(), item, n)
	else:
		_req_use.rpc_id(1, item, n)


@rpc("any_peer", "reliable")
func _req_use(item: String, n: int) -> void:
	if is_server():
		_use(multiplayer.get_remote_sender_id(), item, n)


func _use(id: int, item: String, n: int) -> void:
	if not peers.has(id) or not TRACKED_ITEMS.has(item) or n <= 0:
		return
	var items: Dictionary = _ledger_of(peers[id].name).inv.items
	items[item] = maxi(0, int(items.get(item, 0)) - n)
	_ledger_dirty[peers[id].name] = true


## الرصاص: كل رشقة تستهلك طلقة من مخزون الخادم؛ بلا ذخيرة لا تصيب أحداً (الشرطة مستثناة: سلاح الخدمة)
func _spend_ammo(shooter: int, origin: Vector3) -> bool:
	if not peers.has(shooter) or peers[shooter].role == "cop":
		return true
	if _last_volley.get(shooter, Vector3.INF) == origin:
		return true                            # بقية حبيبات الخرطوش من الرشقة نفسها
	_last_volley[shooter] = origin
	var inv: Dictionary = _ledger_of(peers[shooter].name).inv
	if int(inv.ammo) <= 0:
		_log("rejected shot by %s (no server ammo)" % peers[shooter].name)
		return false
	inv.ammo = int(inv.ammo) - 1
	_ledger_dirty[peers[shooter].name] = true
	return true


## منح اختباري (لا يعمل إلا إن شُغّل الخادم بـ --allow-test-grants)
var allow_test_grants := false


func req_test_grant(field: String, amount: int) -> void:
	if is_server():
		_test_grant(my_id(), field, amount)
	else:
		_req_test_grant.rpc_id(1, field, amount)


@rpc("any_peer", "reliable")
func _req_test_grant(field: String, amount: int) -> void:
	if is_server():
		_test_grant(multiplayer.get_remote_sender_id(), field, amount)


func _test_grant(id: int, field: String, amount: int) -> void:
	if not allow_test_grants or not peers.has(id) or not field in ["bank", "cash", "pool"]:
		_log("rejected test grant from %s" % peers.get(id, {}).get("name", "?"))
		return
	var l := _ledger_of(peers[id].name)
	l[field] = (float(l[field]) + amount) if field == "pool" else (int(l[field]) + amount)
	l.t = int(Time.get_unix_time_from_system())
	_ledger_dirty[peers[id].name] = true
	_log("test grant %s +%d to %s" % [field, amount, peers[id].name])


## الروليت على الخادم
func req_roulette(amount: int, kind: String, number: int) -> void:
	if is_server():
		_roulette(my_id(), amount, kind, number)
	else:
		_req_roulette.rpc_id(1, amount, kind, number)


@rpc("any_peer", "reliable")
func _req_roulette(amount: int, kind: String, number: int) -> void:
	if is_server():
		_roulette(multiplayer.get_remote_sender_id(), amount, kind, number)


func _roulette(id: int, amount: int, kind: String, number: int) -> void:
	if not peers.has(id) or not states.has(id) or (states[id][0] as Vector3).distance_to(game.city.safe_pos) > 12.0:
		return
	var l := _ledger_of(peers[id].name)
	var cap: int = Balance.ROULETTE_BET_CAP[clampi(int(peers[id].get("auth", 0)), 0, Balance.ROULETTE_BET_CAP.size() - 1)]
	if amount <= 0 or amount > cap or amount > int(l.cash):
		_send(id, "ledger_note", ["رهان غير مقبول (الحد %s، ومن الكاش الذي معك)" % Cfg.money(cap)])
		return
	var n := randi_range(0, 36)
	var color := "green" if n == 0 else ("red" if MotelManager.RED.has(n) else "black")
	var win := false
	var mult := 2
	match kind:
		"red", "black":
			win = color == kind
		"even":
			win = n != 0 and n % 2 == 0
		"odd":
			win = n % 2 == 1
		"number":
			win = n == number
			mult = 36
	var payout := amount * mult if win else 0
	l.cash = int(l.cash) - amount + payout
	_ledger_dirty[peers[id].name] = true
	_send(id, "roulette_server", [n, color, amount, payout])


@rpc("authority", "reliable")
func roulette_server(n: int, color: String, bet: int, payout: int) -> void:
	MotelManager.roulette_result.emit(n, color, bet, payout)


@rpc("authority", "reliable")
func ledger_note(text: String) -> void:
	game.hud.toast(text, Color("ffd36b"))


## يطبّق دفتر الخادم على اللاعب المحلي (بلا إرسال «دفع»)
@rpc("authority", "reliable")
func ledger_sync(view: Dictionary) -> void:
	server_bag = view.get("bag", []).duplicate(true)
	game.apply_ledger(view)


# ---------------------------------------------------------------- مدينة السطو (الخادم يحسم)
func heist_request(target_id: String) -> void:
	if is_server():
		_heist_start(my_id(), target_id)
	else:
		_req_heist.rpc_id(1, target_id)


@rpc("any_peer", "reliable")
func _req_heist(target_id: String) -> void:
	if is_server():
		_heist_start(multiplayer.get_remote_sender_id(), target_id)


func _heist_start(id: int, target_id: String) -> void:
	var t: HeistTargetData = HeistCityManager.target(target_id)
	var now := int(Time.get_unix_time_from_system())
	var why := ""
	if t == null or not states.has(id) or peers.get(id, {}).get("role", "") == "cop":
		why = "غير مسموح"
	elif int(heist_cd.get(target_id, 0)) > now:
		why = "سبقك أحدهم — الهدف مغلق مؤقتاً"
	elif (states[id][0] as Vector3).distance_to(game.heist.spots[target_id].pos) > 4.5:
		why = "ابتعدت عن الهدف"
	if why != "":
		_send(id, "heist_denied", [target_id, why])
		return
	heist_active[id] = {"target": target_id, "t0": Time.get_ticks_msec()}
	heist_cd[target_id] = now + int(t.cooldown)
	heist_cooldown.rpc(target_id, heist_cd[target_id])
	var masked: bool = states[id][3] & F_MASK != 0
	_raise(id, t.alarm_level + (0 if masked else 1))
	var who: String = peers[id].name
	_log("%s started heist %s%s" % [who, target_id, "" if masked else " (unmasked)"])
	if t.is_major:
		_raise(id, HeistCityManager.CITY_ALARM_WANTED)
		heist_city_alarm.rpc(target_id, t.district, game.heist.spots[target_id].pos, who)
		if mode != Mode.SERVER:
			heist_city_alarm(target_id, t.district, game.heist.spots[target_id].pos, who)
	_send(id, "heist_approved", [target_id])


func heist_done(target_id: String) -> void:
	if is_server():
		_heist_finish(my_id(), target_id)
	else:
		_req_heist_done.rpc_id(1, target_id)


@rpc("any_peer", "reliable")
func _req_heist_done(target_id: String) -> void:
	if is_server():
		_heist_finish(multiplayer.get_remote_sender_id(), target_id)


func _heist_finish(id: int, target_id: String) -> void:
	var a: Dictionary = heist_active.get(id, {})
	var t: HeistTargetData = HeistCityManager.target(target_id)
	if a.is_empty() or a.target != target_id or t == null:
		return
	if (Time.get_ticks_msec() - int(a.t0)) / 1000.0 < t.duration * 0.85:
		_log("rejected early heist finish by %s" % peers.get(id, {}).get("name", "?"))
		return
	heist_active.erase(id)
	var bag: Dictionary = heist_bags.get(id, {})
	var loot: Dictionary = HeistCityManager.roll_loot(t)
	for k in loot:
		bag[k] = int(bag.get(k, 0)) + int(loot[k])
	heist_bags[id] = bag
	_log("%s finished %s, bag value %d" % [peers[id].name, target_id, _bag_value(bag)])
	_send(id, "heist_bag", [bag, loot])


func heist_extract(point: String, sell: bool) -> void:
	if is_server():
		_heist_extract(my_id(), point, sell)
	else:
		_req_heist_extract.rpc_id(1, point, sell)


@rpc("any_peer", "reliable")
func _req_heist_extract(point: String, sell: bool) -> void:
	if is_server():
		_heist_extract(multiplayer.get_remote_sender_id(), point, sell)


func _heist_extract(id: int, point: String, sell: bool) -> void:
	var bag: Dictionary = heist_bags.get(id, {})
	if bag.is_empty() or not states.has(id):
		return
	var p: Vector3 = states[id][0]
	var ok := false
	if point == "city_exit":
		ok = game.heist.hub_at(p) != TravelManager.Hub.HEIST_CITY and wanted.get(id, {"level": 0}).level == 0
	elif game.heist.cars.has(point):
		ok = p.distance_to(game.heist.cars[point].pos) < 5.0
	if not ok:
		_send(id, "heist_denied", [point, "الخادم رفض التأمين (لست عند سيارة التهريب أو ما زلت مطلوباً)"])
		return
	heist_bags.erase(id)
	if point != "city_exit" and wanted.has(id):
		wanted[id].level = 0
	var lh := _ledger_of(peers[id].name)
	if sell:
		lh.cash = int(lh.cash) + _bag_value(bag)
	else:
		for k in bag:
			if k == "document":
				continue
			for i in int(bag[k]):
				var kind: String = {"gold_bar": "gold", "cargo": "cargo", "deposit_key": "deposit_key"}.get(k, "heist")
				lh.bag.append({"name": ItemDB.item_name(k), "value": ItemDB.value(k), "kind": kind})
	_ledger_dirty[peers[id].name] = true
	_log("%s secured heist loot (%d) at %s" % [peers[id].name, _bag_value(bag), point])
	_send(id, "heist_secured", [bag, sell, point])


func _bag_value(bag: Dictionary) -> int:
	var v := 0
	for k in bag:
		v += ItemDB.value(k) * int(bag[k])
	return v


## إرسال إلى لاعب واحد (أو تنفيذ محلي إن كان المضيف نفسه)
func _send(id: int, method: String, args: Array) -> void:
	if id == my_id():
		callv(method, args)
	else:
		rpc_id.callv([id, method] + args)


@rpc("authority", "reliable")
func heist_denied(_what: String, why: String) -> void:
	game.hud.toast(why, Color("ff9b6b"))
	HeistCityManager.abort_extraction()


@rpc("authority", "reliable")
func heist_approved(target_id: String) -> void:
	HeistCityManager.begin_heist(target_id)
	game.heist.on_approved(target_id)


@rpc("authority", "reliable")
func heist_cooldown(target_id: String, until: int) -> void:
	heist_cd[target_id] = until
	HeistCityManager.cooldowns[target_id] = until


@rpc("authority", "reliable")
func heist_city_alarm(target_id: String, district: String, pos: Vector3, who: String) -> void:
	if mode == Mode.SERVER:
		return
	game.add_alert(pos)
	var t := HeistCityManager.target(target_id)
	_log("city alarm: %s at %s" % [who, target_id])
	if my_role == "cop":
		game.hud.toast("🚨 إنذار عام: %s يسطو على %s في %s!" % [who, t.title, HeistCityManager.district_name(district)], Color("ff3b3b"))
	elif who != my_name:
		game.hud.toast("📢 %s يسطو على %s — الشرطة كلها في الطريق" % [who, t.title], Color("ffd36b"))


@rpc("authority", "reliable")
func heist_bag(bag: Dictionary, loot: Dictionary) -> void:
	HeistCityManager.set_bag(bag)
	game.heist.on_server_loot(loot)


@rpc("authority", "reliable")
func heist_secured(bag: Dictionary, sell: bool, point: String) -> void:
	HeistCityManager.secure_items(bag, sell, point)


# ---------------------------------------------------------------- السجن الفيدرالي والنفوذ (الخادم يحسم)
func _perm(pname: String) -> Dictionary:
	var p: Dictionary = _profiles.get_value("permanent", pname, {})
	return {"jail_years": int(p.get("jail_years", 0)), "sentences": int(p.get("sentences", 0)), "rewards": p.get("rewards", [])}


## يطبّق ملف الخادم الدائم على اللاعب المحلي (للعرض ولمكافآت الشحنات)
func _apply_perm(perm: Dictionary) -> void:
	if perm.is_empty():
		return
	GameState.profile.jail_years = int(perm.get("jail_years", 0))
	GameState.profile.sentences = int(perm.get("sentences", 0))
	GameState.profile.rewards = perm.get("rewards", [])
	GameState.profile.authority = PrisonManager.level_for_years(GameState.profile.jail_years)
	GameState.profile_changed.emit(GameState.profile)


## الثروة كما يعرفها الخادم من آخر ملف حفظه للاعب
func _wealth_of(prof: Dictionary, pname := "") -> int:
	if pname != "" and (ledger.has(pname) or _profiles.has_section_key("ledger", pname)):
		var lw := _ledger_of(pname)
		var w := int(lw.bank) + int(lw.cash) + int(lw.pool) + int(lw.motel)
		for it in lw.bag + lw.stash:
			w += int(it.get("value", 0))
		return w
	var v := int(prof.get("bank", 0)) + int(prof.get("cash", 0))
	var cr: Dictionary = prof.get("crime", {})
	v += int(cr.get("pool", 0.0))
	for it in cr.get("bag", []):
		v += int(it.get("value", 0))
	var ld: Dictionary = prof.get("land", {})
	v += int(ld.get("motel", 0))
	return v


func surrender_feds() -> void:
	if is_server():
		_sentence_player(my_id(), "surrender")
	else:
		_req_surrender.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_surrender() -> void:
	if is_server():
		_sentence_player(multiplayer.get_remote_sender_id(), "surrender")


func _sentence_player(id: int, reason: String) -> void:
	if not peers.has(id):
		return
	_sentence(peers[id].name, reason, id)


## الحكم على لاعب (متصل أو غير متصل): الثروة ← سنوات، تحديث الملف الدائم، مسح ملفه وأراضيه
func _sentence(pname: String, reason: String, id := 0) -> void:
	var prof: Dictionary = _profiles.get_value("players", pname, {})
	var value := _wealth_of(prof, pname) + _bag_value(heist_bags.get(id, {}))
	var years := PrisonManager.years_for(value)
	var perm := _perm(pname)
	var before := PrisonManager.level_for_years(perm.jail_years)
	perm.jail_years += years
	perm.sentences += 1
	var after := PrisonManager.level_for_years(perm.jail_years)
	var new_rewards := []
	for r in PrisonManager.rewards_between(before, after):
		if not perm.rewards.has(r):
			perm.rewards.append(r)
			new_rewards.append(r)
	_profiles.set_value("permanent", pname, perm)
	_profiles.set_value("players", pname, {})          # يبدأ من الصفر
	ledger[pname] = _fresh_ledger()
	_profiles.set_value("ledger", pname, ledger[pname])
	_ledger_dirty[pname] = true
	_sentence_lock[pname] = Time.get_ticks_msec()
	_profiles.save(PROFILE_PATH)
	# الأراضي والأحياء تعود بلا مالك
	var land_changed := false
	for i in settle_owner.size():
		if settle_owner[i] == pname:
			settle_owner[i] = ""
			land_changed = true
	for k in plot_tenant.keys():
		if plot_tenant[k] == pname:
			plot_tenant.erase(k)
			land_changed = true
	for i in district_owner.size():
		if district_owner[i] == pname:
			_set_district(i, "")
	if land_changed:
		land_state.rpc(settle_owner, plot_tenant)
		if mode == Mode.HOST:
			land_state(settle_owner, plot_tenant)
	_log("%s sentenced (%s): wealth %d -> %d years, total %d, authority %d" % [pname, reason, value, years, perm.jail_years, after])
	if id != 0:
		heist_bags.erase(id)
		heist_active.erase(id)
		if wanted.has(id):
			wanted[id].level = 0
		peers[id].auth = after
		peers[id].years = perm.jail_years
		_send(id, "fed_sentenced", [years, value, perm, reason, new_rewards])
		peer_authority.rpc(id, after)
	var msg := "⛓ %s %s — %d سنة سجن" % [pname, "استسلم للفيدراليين" if reason == "surrender" else "أُخذ في المداهمة الفيدرالية", years]
	chat.rpc(0, msg)
	_chat_local(0, msg)


## المداهمة الأسبوعية: كل لاعبي الخادم (المتصلون وغير المتصلين) يُحكم عليهم ويبدأ موسم جديد
func federal_raid_all() -> void:
	var names := {}
	if _profiles.has_section("players"):
		for n in _profiles.get_section_keys("players"):
			names[n] = 0
	for id in peers:
		names[peers[id].name] = id
	_log("FEDERAL RAID: %d players" % names.size())
	chat.rpc(0, "🏛 المداهمة الفيدرالية! انتهى الموسم")
	_chat_local(0, "🏛 المداهمة الفيدرالية! انتهى الموسم")
	for n in names:
		var id: int = names[n]
		if id == 0 and _wealth_of(_profiles.get_value("players", n, {}), n) <= 0 and _profiles.get_value("players", n, {}).is_empty():
			continue
		_sentence(n, "federal_raid", id)
	heist_cd = {}
	season_start = int(Time.get_unix_time_from_system())
	_profiles.set_value("server", "season_start", season_start)
	_profiles.save(PROFILE_PATH)


@rpc("authority", "reliable")
func fed_sentenced(years: int, value: int, perm: Dictionary, reason: String, new_rewards: Array) -> void:
	_log("sentenced %d years (total %d)" % [years, int(perm.jail_years)])
	_apply_perm(perm)
	game.on_net_sentenced(years, value, int(perm.jail_years), reason, new_rewards)


@rpc("authority", "reliable")
func peer_authority(id: int, auth: int) -> void:
	if peers.has(id):
		peers[id].auth = auth
	if remotes.has(id):
		remotes[id]._update_tag()


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
	if Time.get_ticks_msec() - int(_sentence_lock.get(pname, -100000)) < 4000:
		return                                   # حفظ قديم أُرسل قبل أن يصل الحكم إلى العميل
	if ledger.has(pname):                     # المال لا يأتي من العميل: نكتبه من دفتر الخادم
		var l: Dictionary = ledger[pname]
		d["bank"] = l.bank
		d["cash"] = l.cash
		var cr: Dictionary = d.get("crime", {})
		cr["pool"] = l.pool
		cr["bag"] = l.bag
		cr["notoriety"] = l.xp
		var tools: Dictionary = (cr.get("tools", {}) as Dictionary).duplicate()
		for k in TRACKED_ITEMS:
			tools[k] = int(l.inv.items.get(k, 0))
		cr["tools"] = tools
		d["crime"] = cr
		var wd: Dictionary = d.get("weapons", {})
		if peers.get(_peer_by_name(pname), {}).get("role", "") != "cop":
			wd["owned"] = l.inv.weapons
			wd["ammo"] = l.inv.ammo
			d["weapons"] = wd
	_profiles.set_value("players", pname, d)
	_profiles.save(PROFILE_PATH)
