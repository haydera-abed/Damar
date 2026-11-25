class_name Cop
extends Node
## مهنة الشرطي: مكتب الخدمة في مركز الشرطة، المناوبة، الرتب (الشارات)، بلاغات السرقة،
## الاعتقال بالأصفاد ومكافآته. يُدفع الراتب في الحساب البنكي (مال نظيف).

const RANKS := [
	{"name": "شرطي", "price": 0, "health": 100.0, "weapons": ["police_pistol"]},
	{"name": "رقيب", "price": 8000, "health": 125.0, "weapons": ["police_pistol", "smg"]},
	{"name": "ملازم", "price": 40000, "health": 150.0, "weapons": ["police_pistol", "police_rifle"]},
	{"name": "نقيب", "price": 100000, "health": 180.0, "weapons": ["police_pistol", "police_rifle", "shotgun"]},
]
const MAX_ROBBERS := 2

var game: Node
var on_duty := false
var rank := 0
var robbers: Array = []
var shift_pay := 0
var shift_arrests := 0
var total_arrests := 0
var station: City.StoreData
var desk_pos := Vector3.ZERO
var cruiser: Car
var _spawn_t := 12.0
var _saved_weapons := {}


func _init(g: Node) -> void:
	game = g


func setup() -> void:
	for s in game.city.stores:
		if s.type == "police":
			station = s
	if station == null:
		return
	desk_pos = station.pos + Vector3(0, 0, -5.0)
	game.city._zone_ring(desk_pos, Color("3d7bff"), 0.9, 1.15)
	var l: Label3D = game.crime._label("مكتب الخدمة\nمناوبة الشرطة", Color("6fa0ff"), desk_pos + Vector3(0, 2.4, 0), 64)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func rank_name() -> String:
	return RANKS[rank].name


func to_dict() -> Dictionary:
	return {"rank": rank, "arrests": total_arrests}


func from_dict(d: Dictionary) -> void:
	rank = d.get("rank", 0)
	total_arrests = d.get("arrests", 0)


# ---------------------------------------------------------------- مكتب الخدمة
func interact_station(_dt: float) -> String:
	if station == null or game.player.car != null:
		return ""
	if game.player_pos().distance_to(Vector3(desk_pos.x, 0, desk_pos.z)) < 1.8:
		if Input.is_action_just_pressed("interact"):
			open_desk()
		return "اضغط E لمكتب الخدمة (%s)" % ("إنهاء المناوبة" if on_duty else "بدء مناوبة شرطة")
	return ""


func open_desk() -> void:
	var items: Array = []
	if on_duty:
		items.append({"text": "إنهاء المناوبة (كسبت %s · %d اعتقال)" % [Cfg.money(shift_pay), shift_arrests], "enabled": true, "cb": end_duty})
	else:
		var ok: bool = game.wanted == 0 and game.crime.bag.is_empty()
		items.append({"text": "بدء المناوبة — معدات ودورية مجانية" + ("" if ok else "\n(غير متاح وأنت مطلوب أو تحمل غنائم)"), "enabled": ok, "cb": start_duty})
	for i in range(1, RANKS.size()):
		var r: Dictionary = RANKS[i]
		var owned := rank >= i
		var weps := ", ".join(r.weapons.map(func(w): return Weapons.CATALOG[w].name))
		items.append({"text": "شارة %s — %s %s\nصحة %d · أسلحة: %s" % [r.name, Cfg.money(r.price), "(تملكها)" if owned else "", int(r.health), weps],
			"enabled": not owned and rank == i - 1 and game.bank >= r.price, "cb": _buy_rank.bind(i)})
	var sub := "رتبتك: %s · مجموع الاعتقالات: %d · الحساب البنكي: %s\nمكافأة الاعتقال $9,000–$15,000 (+20% إن استسلم اللص) · التحييد $2,000" % [rank_name(), total_arrests, Cfg.money(game.bank)]
	game.hud.open_menu("مركز الشرطة", sub, items)


func _buy_rank(i: int) -> void:
	if game.bank >= RANKS[i].price:
		game.bank -= RANKS[i].price
		rank = i
		game.hud.toast("ترقّيت إلى رتبة %s 🎖" % rank_name(), Color("6fa0ff"))
		if on_duty:
			_equip()
		game.save_game()
	open_desk()


func _equip() -> void:
	var w: Weapons = game.weapons
	w.owned.assign(RANKS[rank].weapons)
	w.current = RANKS[rank].weapons[-1]
	w.ammo = 150
	game.player.max_health = RANKS[rank].health
	game.player.health = game.player.max_health


func start_duty() -> void:
	if game.net.is_online() and game.net.my_role != "cop":
		game.net.request_role("cop")       # الخادم يتحقق من عدد مقاعد الشرطة
		game.close_menu()
		return
	on_duty = true
	shift_pay = 0
	shift_arrests = 0
	_saved_weapons = game.weapons.to_dict()
	_equip()
	game.crime.masked = false
	game.player.human.set_mask(false)
	game.player.human.set_role("cop")
	if cruiser == null or not is_instance_valid(cruiser):
		var p := station.pos + Vector3(station.sx * 6.5, 0.6, 3.0)
		cruiser = game._make_car("police_car", true, Car.AI.PARKED, Transform3D(Basis.IDENTITY, p))
	_spawn_t = 10.0
	game.close_menu()
	game.hud.toast("بدأت المناوبة — انتظر البلاغات على الخريطة (نقاط حمراء)", Color("6fa0ff"))
	game.save_game()


func on_role_result(ok: bool, role: String) -> void:
	if not ok:
		game.hud.toast("لا يمكن: مقاعد الشرطة ممتلئة أو أنت مطلوب", Color("ff9b3b"))
		return
	if role == "cop" and not on_duty:
		start_duty()
	elif role == "criminal" and on_duty:
		end_duty()


func end_duty() -> void:
	if game.net.is_online() and game.net.my_role == "cop":
		game.net.request_role("criminal")
		game.close_menu()
		return
	on_duty = false
	game.weapons.from_dict(_saved_weapons)
	game.player.max_health = 100.0
	game.player.health = 100.0
	game.player.human.set_role("thief")
	for r in robbers.duplicate():
		remove_robber(r)
	game.close_menu()
	game.hud.toast("انتهت المناوبة: %s في حسابك البنكي" % Cfg.money(shift_pay), Color("7dff9e"))
	game.save_game()


# ---------------------------------------------------------------- المناوبة
func tick(dt: float) -> void:
	if not on_duty:
		return
	if game.net.is_online():
		return                     # في اللعب الجماعي اللصوص لاعبون حقيقيون
	_spawn_t -= dt
	if _spawn_t <= 0.0 and robbers.size() < MAX_ROBBERS:
		_spawn_t = randf_range(30.0, 55.0)
		_spawn_robber()
	# التصويب على لص هارب قد يجعله يستسلم
	if game.weapons.aiming:
		var cam: Camera3D = game.cam
		var fwd := -cam.global_basis.z
		for r in robbers:
			var to: Vector3 = (r.global_position + Vector3(0, 1, 0)) - cam.global_position
			if to.normalized().dot(fwd) > 0.985:
				r.threatened()


func _spawn_robber() -> void:
	var options: Array = game.city.stores.filter(func(s): return s.type != "police" and s.pos.distance_to(game.player_pos()) > 50.0)
	if options.is_empty():
		return
	var s: City.StoreData = options[randi() % options.size()]
	var r := Robber.new()
	r.setup(game, s)
	game.add_child(r)
	var side := Vector3(0, 0, 1) * (20.0 if randf() < 0.5 else -20.0)
	r.global_position = s.pos + side + Vector3(0, 0.3, 0)
	robbers.append(r)


func interact(_dt: float) -> String:
	if game.player.car != null:
		return ""
	if game.net.is_online():
		var target: int = game.net.nearest_arrestable(game.player.global_position)
		if target >= 0:
			if Input.is_action_just_pressed("interact"):
				game.net.request_arrest(target)
			return "اضغط E لتقييد %s بالأصفاد" % game.net.peers.get(target, {}).get("name", "")
	for r in robbers:
		if (r.surrendered or r.downed) and not r.arrested and not r.dead and r.global_position.distance_to(game.player.global_position) < 2.2:
			if Input.is_action_just_pressed("interact"):
				_arrest(r)
			return "اضغط E لتقييد اللص بالأصفاد"
	return ""


func _arrest(r: Robber) -> void:
	r.cuff()
	var pay := randi_range(9000, 15000)
	if r.surrendered:
		pay = int(pay * 1.2)
	pay += int(r.loot * 0.25)          # نسبة من الغنائم المصادرة
	game.bank += pay
	if game.net.is_online():
		game.net.req_income("npc_arrest", pay)
	shift_pay += pay
	shift_arrests += 1
	total_arrests += 1
	game.hud.toast("اعتقال ناجح 🚔 +%s في حسابك" % Cfg.money(pay), Color("7dff9e"))
	game.sfx.cash()
	game.check_win()
	game.save_game()


func on_robbery_started(r: Robber) -> void:
	game.hud.toast("🚨 بلاغ: سرقة جارية في %s" % r.store.def.name, Color("ff6b6b"))
	game.sfx.beep(900.0, 0.4)


func on_robber_down(r: Robber, from: Node) -> void:
	if from == game.player:
		game.bank += 2000
		if game.net.is_online():
			game.net.req_income("npc_down", 2000)
		shift_pay += 2000
		game.hud.toast("تم تحييد لص (+$2,000) — الاعتقال يدفع أكثر", Color("ffd36b"))


func on_robber_escaped(r: Robber) -> void:
	game.hud.toast("هرب اللص بالغنائم!", Color("ff9b3b"))
	remove_robber(r)


func remove_robber(r: Robber) -> void:
	robbers.erase(r)
	if is_instance_valid(r):
		r.queue_free()
