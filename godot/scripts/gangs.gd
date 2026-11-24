class_name Gangs
extends Node
## العصابات والأحياء والقاعدة:
## - المدينة 9 أحياء بثلاثة مستويات (كما في ROB RUN): الأطراف م1، الأحياء الوسطى م2، وسط المدينة م3.
## - استولِ على حيّ بالقضاء على حراس رايته ثم رفع رايتك. عصابة بلا أحياء تبدأ بحي م1 فقط،
##   وبعدها لا تتمدد إلا إلى الأحياء المجاورة لأحيائك.
## - كل حي تملكه يسرّع غسيل أموالك: +15% لحي م1، +20% لحي م2، +30% لحي م3.
## - من يملك وسط المدينة يصبح «الحاكم الخفي»: يأخذ ضريبة من كل حي تملكه العصابات الأخرى.
## - أحياؤك تدفع ضرائب دورية (مال قذر يدخل طاولة الغسيل).
## - العصابات المنافسة تهاجم أحياءك ومخبأك؛ دافع عنها.
## - القاعدة: نظام أمان (يقاوم أجهزة فك الشفرة)، رفوف تخزين للغنائم، وطاولة الغسيل.
## - المواسم (اختياري): «مداهمة فيدرالية» كل 7 أيام لعب تعيد ضبط كل شيء وتسجّل أفضل نتيجة.

const DISTRICTS := ["الميناء", "السوق القديم", "الحي الصناعي", "الكورنيش", "وسط المدينة", "حي البنوك", "المحطة", "التلال", "الجسر"]
const CENTER := 4
const LEVEL := [1, 2, 1, 2, 3, 2, 1, 2, 1]
const LAUNDER_BONUS := [0.0, 0.15, 0.20, 0.30]
const GANGS := [
	{"name": "عصابتك", "color": Color("ff6a3d")},
	{"name": "الأفاعي", "color": Color("3ddc6a")},
	{"name": "ذئاب الميناء", "color": Color("ffb02e")},
	{"name": "النسور السود", "color": Color("a46bff")},
]
const STASH_CAP := 40
const TAX_PERIOD := 120.0
const SEASON_DAYS := 7

var game: Node
var owner_of: Array[int] = []       # مالك كل حي
var flags: Array[Vector3] = []
var _flag_cloth: Array[StandardMaterial3D] = []
var _flag_labels: Array[Label3D] = []
var members: Array = []             # أفراد عصابات (Robber بحالة GUARD)
var stash: Array = []
var season_mode := true             # المداهمة الفيدرالية الأسبوعية مفعّلة افتراضياً
var day_count := 0
var best_season := 0
var _tax_t := TAX_PERIOD
var _attack_t := 300.0
var _raid_t := 420.0
var _event := {}                    # حدث جارٍ: {kind, district, t, gang}
var _capture := -1
var _cap_prog := 0.0
var _last_hour := 0.0


func _init(g: Node) -> void:
	game = g


func setup() -> void:
	var span := Cfg.HALF * 2.0 / 3.0
	for i in 9:
		var dx := i % 3
		var dz := i / 3
		# الراية على زاوية رصيف قرب تقاطع مركز الحي
		var node := Cfg.node_pos(Vector2i(dx * 2 + 1, dz * 2 + 1))
		flags.append(node + Vector3(11.5, 0.15, 11.5))
		owner_of.append(1 + randi() % 3)
	var sd := district_at(game.city.safe_pos)
	owner_of[sd] = 0
	for i in 9:
		_build_flag(i)


func district_at(p: Vector3) -> int:
	var span := Cfg.HALF * 2.0 / 3.0
	var dx := clampi(int((p.x + Cfg.HALF) / span), 0, 2)
	var dz := clampi(int((p.z + Cfg.HALF) / span), 0, 2)
	return dz * 3 + dx


func _build_flag(i: int) -> void:
	var city: City = game.city
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.07
	cm.height = 6.0
	pole.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.7, 0.7, 0.72)
	pm.metallic = 0.9
	pm.roughness = 0.3
	pole.material_override = pm
	pole.position = flags[i] + Vector3(0, 3.0, 0)
	city.add_child(pole)
	var cloth := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 1.0, 0.03)
	cloth.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = mat
	cloth.position = flags[i] + Vector3(0.85, 5.4, 0)
	city.add_child(cloth)
	_flag_cloth.append(mat)
	var l: Label3D = game.crime._label("", Color.WHITE, flags[i] + Vector3(0, 6.6, 0), 80)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_flag_labels.append(l)
	game.city._zone_ring(flags[i], Color(1, 1, 1), 1.1, 1.35)
	_refresh_flag(i)


func _refresh_flag(i: int) -> void:
	var g: Dictionary = GANGS[owner_of[i]]
	_flag_cloth[i].albedo_color = g.color
	_flag_cloth[i].emission = g.color
	_flag_labels[i].text = "%s (مستوى %d)\n%s" % [DISTRICTS[i], LEVEL[i], g.name]
	_flag_labels[i].modulate = g.color * 1.6


func owned_count() -> int:
	if game.net.is_online():
		return game.net.district_owner.count(game.net.my_name)
	return owner_of.count(0)


## اللعب الجماعي: الأحياء يملكها لاعبون بأسمائهم
func apply_mp_owners(names: Array) -> void:
	for i in 9:
		var n: String = names[i]
		if n == "":
			_refresh_flag(i)
			continue
		var mine: bool = n == game.net.my_name
		var col := Color("ff6a3d") if mine else Color("ff3b6b")
		_flag_cloth[i].albedo_color = col
		_flag_cloth[i].emission = col
		_flag_labels[i].text = "%s (مستوى %d)\n%s" % [DISTRICTS[i], LEVEL[i], n]
		_flag_labels[i].modulate = col * 1.6


func is_mine(i: int) -> bool:
	if game.net.is_online():
		return game.net.district_owner[i] == game.net.my_name
	return owner_of[i] == 0


## قاعدة التمدد: بلا أحياء ← حي م1 فقط، وإلا فحيّ مجاور لأحد أحيائك
func can_challenge(i: int) -> String:
	if owned_count() == 0:
		return "" if LEVEL[i] == 1 else "عصابة بلا أحياء تبدأ بحي من المستوى 1 فقط"
	for j in 9:
		if is_mine(j) and absi(j % 3 - i % 3) + absi(j / 3 - i / 3) == 1:
			return ""
	return "لا يمكنك التمدد إلا إلى حي مجاور لأحيائك"


## زيادة سرعة الغسيل من الأحياء التي تملكها
func launder_bonus() -> float:
	var b := 0.0
	for i in 9:
		if is_mine(i):
			b += LAUNDER_BONUS[LEVEL[i]]
	return b


func is_godfather() -> bool:
	if game.net.is_online():
		return game.net.district_owner[CENTER] == game.net.my_name
	return owner_of[CENTER] == 0


func to_dict() -> Dictionary:
	return {"owners": owner_of, "stash": stash, "season": season_mode, "day": day_count, "best": best_season, "v": 2}


func from_dict(d: Dictionary) -> void:
	if d.has("owners") and d.owners.size() == 9:
		owner_of.assign(d.owners)
		for i in 9:
			_refresh_flag(i)
	if d.has("security") and d.security > 0:        # ترحيل الحفظ القديم: مستويات الأمان ← نظام أمان + صمامات
		game.land.security = true
		game.land.fuses = int(d.security) - 1
	stash.assign(d.get("stash", []))
	season_mode = d.get("season", true) if d.get("v", 1) >= 2 else true
	day_count = d.get("day", 0)
	best_season = d.get("best", 0)


# ---------------------------------------------------------------- أفراد العصابات
func _spawn_guards(at: Vector3, gang: int, n: int) -> void:
	for k in n:
		var r := Robber.new()
		r.setup(game, game.city.stores[0], self)
		r.state = Robber.S.GUARD
		r.armed = true
		r.health = 80.0
		r.gang_color = GANGS[gang].color
		game.add_child(r)
		var ang := TAU * k / n + randf() * 0.5
		r.anchor = at + Vector3(cos(ang), 0, sin(ang)) * randf_range(4.0, 7.0)
		r.global_position = r.anchor + Vector3(0, 0.3, 0)
		r.set_meta("gang", gang)
		members.append(r)


func _alive_near(p: Vector3, radius: float) -> int:
	var n := 0
	for m in members:
		if is_instance_valid(m) and not m.dead and m.anchor.distance_to(p) < radius:
			n += 1
	return n


func on_robber_down(r: Robber, from: Node) -> void:
	if from == game.player:
		game.hud.toast("أسقطت فرداً من عصابة %s" % GANGS[r.get_meta("gang", 1)].name, Color("ffd36b"))


func on_robbery_started(_r: Robber) -> void:
	pass


func on_robber_escaped(r: Robber) -> void:
	remove_robber(r)


func remove_robber(r: Robber) -> void:
	members.erase(r)
	if is_instance_valid(r):
		r.queue_free()


# ---------------------------------------------------------------- التفاعل
func interact(dt: float) -> String:
	if game.player.car != null or game.cop.on_duty:
		return ""
	var p: Vector3 = game.player_pos()
	if game.net.is_online():
		return _interact_mp(p, dt)
	for i in 9:
		if p.distance_to(Vector3(flags[i].x, 0, flags[i].z)) > 2.0:
			continue
		if owner_of[i] == 0:
			return "راية %s — حيّك (ضرائب كل دقيقتين)" % DISTRICTS[i]
		var guards := _alive_near(flags[i], 30.0)
		if _capture != i:
			var why := can_challenge(i)
			if why != "":
				return "حي %s (مستوى %d) — %s" % [DISTRICTS[i], LEVEL[i], why]
			if Input.is_action_just_pressed("interact"):
				_capture = i
				_cap_prog = 0.0
				if guards == 0:
					_spawn_guards(flags[i], owner_of[i], 2 + 2 * LEVEL[i])
				game.set_wanted(maxi(game.wanted, 2), "⚔ اشتباك مع عصابة %s!" % GANGS[owner_of[i]].name)
			return "اضغط E لتحدّي عصابة %s على حي %s (مستوى %d · %d حراس · غسيل +%d%%)" % [GANGS[owner_of[i]].name, DISTRICTS[i], LEVEL[i], 2 + 2 * LEVEL[i], int(LAUNDER_BONUS[LEVEL[i]] * 100)]
		if guards > 0:
			return "اقضِ على حراس العصابة أولاً (%d متبقٍ)" % guards
		if Input.is_action_pressed("interact"):
			_cap_prog += dt / 10.0
			game.robbing = game.city.stores[0]
			game.rob_prog = _cap_prog
			game.rob_label = "رفع رايتك على %s" % DISTRICTS[i]
			if _cap_prog >= 1.0:
				_take(i)
			return ""
		return "اضغط مطولاً E لرفع رايتك"
	return ""


func _interact_mp(p: Vector3, dt: float) -> String:
	for i in 9:
		if p.distance_to(Vector3(flags[i].x, 0, flags[i].z)) > 2.0:
			continue
		var owner: String = game.net.district_owner[i]
		if owner == game.net.my_name:
			return "راية %s — حيّك" % DISTRICTS[i]
		var why := can_challenge(i)
		if why != "":
			return "حي %s (مستوى %d) — %s" % [DISTRICTS[i], LEVEL[i], why]
		if Input.is_action_pressed("interact"):
			_cap_prog += dt / 15.0
			game.robbing = game.city.stores[0]
			game.rob_prog = _cap_prog
			game.rob_label = "رفع رايتك على %s" % DISTRICTS[i]
			if _cap_prog >= 1.0:
				_cap_prog = 0.0
				game.net.capture(i)
				game.set_wanted(2)
			return ""
		_cap_prog = 0.0
		return "اضغط مطولاً E للاستيلاء على %s%s" % [DISTRICTS[i], (" من " + owner) if owner != "" else ""]
	return ""


func _take(i: int) -> void:
	owner_of[i] = 0
	_capture = -1
	_refresh_flag(i)
	game.hud.toast("🚩 استوليت على حي %s!" % DISTRICTS[i], Color("ff6a3d"))
	if i == CENTER:
		game.hud.toast("👑 أصبحت «الحاكم الخفي» — تأخذ ضريبة من كل أحياء العصابات الأخرى", Color("ffd36b"))
	game.sfx.cash()
	game.save_game()


# ---------------------------------------------------------------- الأحداث الدورية
func tick(dt: float) -> void:
	if game.cop.on_duty or game.net.is_online():
		return
	# الضرائب
	_tax_t -= dt
	if _tax_t <= 0.0:
		_tax_t = TAX_PERIOD
		var tax := 0
		for i in 9:
			if owner_of[i] == 0:
				tax += 1500 * LEVEL[i]
			elif is_godfather():
				tax += 1000          # ضريبة الحاكم الخفي على أحياء العصابات الأخرى
		if tax > 0:
			game.crime.launder_pool += tax
			game.hud.toast("💰 ضرائب أحيائك: %s دخلت طاولة الغسيل" % Cfg.money(tax), Color("7dff9e"))
	# هجوم عصابة على أحد أحيائك
	_attack_t -= dt
	if _attack_t <= 0.0 and _event.is_empty() and owned_count() >= 2:
		_attack_t = randf_range(240.0, 420.0)
		var mine: Array = []
		for i in 9:
			if owner_of[i] == 0 and i != district_at(game.city.safe_pos):
				mine.append(i)
		if not mine.is_empty():
			var d: int = mine[randi() % mine.size()]
			var g := 1 + randi() % 3
			_spawn_guards(flags[d], g, 4)
			_event = {"kind": "attack", "district": d, "t": 90.0, "gang": g}
			game.hud.toast("⚔ عصابة %s تهاجم حي %s — دافع عنه خلال 90 ثانية!" % [GANGS[g].name, DISTRICTS[d]], Color("ff6b6b"))
	# مداهمة المخبأ بأجهزة فك الشفرة
	_raid_t -= dt
	var at_risk: float = game.crime.launder_pool + stash_value()
	if _raid_t <= 0.0 and _event.is_empty() and at_risk > 20000:
		start_raid()
	if not _event.is_empty():
		_event.t -= dt
		var where: Vector3 = flags[_event.district] if _event.kind == "attack" else _event.where
		var alive := _alive_near(where, 30.0)
		if alive == 0:
			game.hud.toast("صددت الهجوم! ✊", Color("7dff9e"))
			_event = {}
		elif _event.t <= 0.0:
			_resolve_loss(where)
	# المواسم: عدّ الأيام
	if game.world.hour < _last_hour:
		day_count += 1
		if season_mode and day_count >= SEASON_DAYS:
			federal_raid()
	_last_hour = game.world.hour


func _resolve_loss(where: Vector3) -> void:
	if _event.kind == "attack":
		var d: int = _event.district
		owner_of[d] = _event.gang
		_refresh_flag(d)
		game.hud.toast("خسرت حي %s لصالح %s" % [DISTRICTS[d], GANGS[_event.gang].name], Color("ff6b6b"))
	else:
		game.land.resolve_raid(_event.decoders, GANGS[_event.gang].name)
	for m in members.duplicate():
		if is_instance_valid(m) and m.anchor.distance_to(where) < 30.0:
			remove_robber(m)
	_event = {}
	game.save_game()


## مداهمة عصابة لقاعدتك (منزلك على قطعة الأرض، أو المخبأ إن لم تستأجر قطعة)
func start_raid() -> void:
	_raid_t = randf_range(300.0, 500.0)
	var g2 := 1 + randi() % 3
	var where: Vector3 = game.land.base_pos()
	var decoders := randi_range(1, 2 + owned_count() / 2 + (2 if game.land.home.x >= 0 else 0))
	_spawn_guards(where, g2, 3)
	_event = {"kind": "raid", "t": 60.0, "gang": g2, "where": where, "decoders": decoders}
	if game.land.alarm:
		game.hud.toast("🚨 جهاز الإنذار: عصابة %s تقتحم قاعدتك ومعها %d أجهزة فك شفرة! (60 ثانية)" % [GANGS[g2].name, decoders], Color("ff4b4b"))
		game.sfx.beep(950.0, 0.3)


## المداهمة الفيدرالية تمر عبر PrisonManager (سنوات سجن + نفوذ دائم)، ثم يُمسح العالم عند الحكم
func federal_raid() -> void:
	if GameState.in_prison:
		return
	PrisonManager.imprison("federal_raid")


func wipe_world() -> void:
	best_season = maxi(best_season, game.bank)
	game.hud.toast("🏛 المداهمة الفيدرالية! انتهى الموسم — أفضل نتيجة: %s" % Cfg.money(best_season), Color("ffd36b"))
	day_count = 0
	game.bank = 0
	game.cash = 0
	game.crime.launder_pool = 0.0
	game.crime.bag.clear()
	game.crime.notoriety_xp = 0
	stash.clear()
	game.land.wipe()
	for i in 9:
		owner_of[i] = 1 + randi() % 3
	owner_of[district_at(game.city.safe_pos)] = 0
	for i in 9:
		_refresh_flag(i)
	game.save_game()


func stash_value() -> int:
	var v := 0
	for it in stash:
		v += it.value
	return v


# ---------------------------------------------------------------- قائمة القاعدة
func open_base() -> void:
	var cr: Crime = game.crime
	var items: Array = []
	items.append({"text": "ضع كل النقود القذرة في طاولة الغسيل (%s)" % Cfg.money(game.cash), "enabled": game.cash > 0 and game.wanted == 0, "cb": func(): cr._deposit_launder(); open_base()})
	if cr.launder_level < 4:
		var c: int = 50000 * cr.launder_level
		items.append({"text": "تطوير طاولة الغسيل إلى المستوى %d — %s" % [cr.launder_level + 1, Cfg.money(c)], "enabled": game.bank >= c, "cb": func(): cr._upgrade_launder(c); open_base()})
	items.append_array(game.land.security_items())
	var sellable := cr.bag.filter(func(i): return i.kind != "deposit_key")
	items.append({"text": "خزّن الغنائم على الرفوف (%d غنيمة)" % sellable.size(), "enabled": not sellable.is_empty() and stash.size() < game.land.house.stash_cap(), "cb": _stash_bag})
	items.append({"text": "خذ الغنائم من الرفوف إلى الحقيبة (%d · %s)" % [stash.size(), Cfg.money(stash_value())], "enabled": not stash.is_empty() and cr.bag.size() < Crime.BAG_SLOTS, "cb": _take_stash})
	var sub := "قيد الغسيل: %s (%s/ث، الأحياء +%d%%) · الحساب البنكي: %s\n%s · الرفوف: %d/%d · أحياؤك: %d/9%s" % [
		Cfg.money(int(cr.launder_pool)), Cfg.money(int(cr.launder_rate())), int(launder_bonus() * 100), Cfg.money(game.bank), game.land.security_text(), stash.size(), game.land.house.stash_cap(), owned_count(), " · 👑 الحاكم الخفي" if is_godfather() else ""]
	sub += game.land.base_subtitle()
	if game.wanted > 0:
		sub += "\n⚠ الشرطة تلاحقك — لا يمكنك الإيداع الآن"
	items.append_array(game.land.home_items())
	game.hud.open_menu(game.land.base_title(), sub, items)


func _stash_bag() -> void:
	var cr: Crime = game.crime
	var keep: Array[Dictionary] = []
	for it in cr.bag:
		if it.kind == "deposit_key" or stash.size() >= game.land.house.stash_cap():
			keep.append(it)
		else:
			stash.append(it)
	cr.bag = keep
	game.save_game()
	open_base()


func _take_stash() -> void:
	var cr: Crime = game.crime
	while not stash.is_empty() and cr.bag.size() < Crime.BAG_SLOTS:
		cr.bag.append(stash.pop_back())
	game.save_game()
	open_base()
