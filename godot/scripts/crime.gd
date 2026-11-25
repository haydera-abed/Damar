class_name Crime
extends Node
## نظام الجريمة والاقتصاد:
## القناع، حقيبة الغنائم، أهداف السرقة بأدواتها، العمليات الكبرى التي تنبّه المدينة،
## المشتري (Fence) والسمعة الإجرامية، السوق السوداء والمقايضة، والنقود القذرة وطاولة الغسيل.

const BAG_SLOTS := 16
const NOTORIETY_XP := [0, 20000, 60000, 150000, 400000]      # عتبات المستويات 1..5
const NOTORIETY_BONUS := [0.0, 0.10, 0.20, 0.35, 0.50]       # زيادة سعر المشتري
const LAUNDER_BASE_RATE := 400.0                              # $/ث على الطاولة الأساسية

## أدوات السوق السوداء (price) أو المقايضة (barter: عنصر → عدد)
const TOOLS := {
	"lockpick": {"name": "عُدّة فتح أقفال", "price": 400, "desc": "تفتح صندوق ودائع واحداً"},
	"minidrill": {"name": "مثقاب صغير", "price": 3000, "desc": "لخزائن المتاجر الصغيرة"},
	"drill": {"name": "مثقاب الخزنة الثقيل", "price": 18000, "desc": "لخزنة الذهب في البنك (يُستهلك)"},
	"cutter": {"name": "قاطع زجاج ماسي", "price": 12000, "desc": "لمعروضات المعرض الفني"},
	"jammer": {"name": "جهاز تشويش", "price": 22000, "desc": "يعطّل إنذار سيارة المعرض"},
	"bank_card": {"name": "بطاقة أمن البنك", "barter": {"deposit_key": 8}, "desc": "مطلوبة لخزنة الذهب"},
	"decoder": {"name": "جهاز فك شفرة", "barter": {"deposit_key": 2}, "desc": "لاقتحام القواعد (لا يُباع، يُقايَض)"},
	"armory_card": {"name": "بطاقة مستودع الشرطة", "barter": {"deposit_key": 4, "gold": 1}, "desc": "مطلوبة لمستودع أسلحة الشرطة"},
}


class Target:
	var id := ""
	var label := ""
	var pos := Vector3.ZERO
	var store: City.StoreData
	var tools: Array = []            # أدوات مطلوبة (تُستهلك)
	var time := 4.0                  # ثوانٍ لإتمام السرقة
	var loot_name := ""
	var loot_kind := "cash"          # cash, jewel, gold, art, weapons, box
	var value := Vector2i(500, 1000)
	var count := 1                   # عدد الغنائم في كل مرة
	var heat := 1                    # النجوم عند الإنذار
	var city_alert := false          # عملية كبرى تُبلَّغ بها المدينة كلها
	var cd := 60.0
	var cooldown := 0.0
	var uses_left := -1              # للصناديق: عدد مرات قبل الإغلاق
	var uses_max := -1
	var ring: MeshInstance3D
	var label3d: Label3D


var game: Node
var targets: Array[Target] = []
var bag: Array[Dictionary] = []      # {name, value, kind}
## الأدوات تعيش في مخزون GameState (طبقة المنطق) — نفس القاموس
var tools: Dictionary:
	get:
		return GameState.inventory
	set(v):
		for k in v:
			GameState.inventory[k] = int(v[k])
var masked := false
var notoriety_xp := 0
## المال على طاولة الغسيل يعيش في EconomyManager (يُغسل بالوقت الحقيقي حتى واللعبة مغلقة)
var launder_pool: float:
	get:
		return EconomyManager.desk_pool
	set(v):
		EconomyManager.set_desk_pool(v)
var _was_laundering := false
var launder_level := 1
var fences: Array[Vector3] = []
var dealer_pos := Vector3.ZERO
var exhibit_car: Car
var _active: Target = null
var _prog := 0.0
var _dealer: Human
var _fence_vans: Array[Car] = []


func _init(g: Node) -> void:
	game = g


# ---------------------------------------------------------------- الإعداد
func setup() -> void:
	var city: City = game.city
	for s in city.stores:
		_targets_for_store(s)
	# مواقع المشترين: شاحنات عند أطراف المدينة
	var e := Cfg.HALF + 3.0
	fences = [Vector3(-e, 0, -95), Vector3(e, 0, 75), Vector3(40, 0, e)]
	for f in fences:
		var axis_x := absf(f.x) > absf(f.z)
		var h := 0.0 if axis_x else PI / 2.0
		var van: Car = game._make_car("van", false, Car.AI.PARKED, Transform3D(Basis(Vector3.UP, h), f + Vector3(0, 0.6, 0)))
		van.locked = true
		van.freeze = true
		_fence_vans.append(van)
		var sign := _label("$ المشتري", Color("39e27d"), f + Vector3(0, 4.2, 0), 220)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		city._zone_ring(f + Vector3(0, 0.0, 0), Color("39e27d"), 4.2, 4.8)
	# تاجر السوق السوداء في زقاق بين المباني
	var blk: Dictionary = city.blocks[0]
	for b in city.blocks:
		if absf(b.center.x + 60) < 40 and absf(b.center.y - 20) < 40 and not b.park:
			blk = b
			break
	dealer_pos = Vector3(blk.center.x, 0.15, blk.center.y + 6.0)
	_dealer = Human.new()
	city.add_child(_dealer)
	_dealer.setup("dealer")
	_dealer.position = dealer_pos
	_dealer.rotation.y = PI
	var dl := _label("السوق السوداء", Color("ff9b3b"), dealer_pos + Vector3(0, 2.6, 0), 120)
	dl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.55, 0.25)
	lamp.light_energy = 2.5
	lamp.omni_range = 7.0
	lamp.position = dealer_pos + Vector3(0, 3, 0)
	city.add_child(lamp)
	# سيارة المعرض (مقفلة بإنذار)
	for s in city.stores:
		if s.type == "showroom":
			var p := s.pos - Vector3(s.sx * 2.6, 0, 0) + Vector3(0, 0.6, 0)
			exhibit_car = game._make_car("hero", false, Car.AI.PARKED, Transform3D(Basis(Vector3.UP, PI / 2.0), p))
			exhibit_car.locked = true
			exhibit_car.exhibit = true
			exhibit_car.set_paint(Color(0.85, 0.85, 0.82))


func _label(text: String, col: Color, pos: Vector3, size := 90) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = game.city.font
	l.font_size = size
	l.pixel_size = 0.008
	l.modulate = col * 1.8
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.position = pos
	l.no_depth_test = false
	game.city.add_child(l)
	return l


func _target(s: City.StoreData, offset: float, cfg: Dictionary) -> Target:
	var t := Target.new()
	t.store = s
	t.pos = s.pos + Vector3(0, 0, offset)
	for k in cfg:
		t.set(k, cfg[k])
	t.uses_left = t.uses_max
	t.ring = game.city._zone_ring(t.pos, s.def.color, 0.9, 1.15)
	t.label3d = _label(t.label + ("" if t.tools.is_empty() else "\n🔧 " + ", ".join(t.tools.map(func(x): return TOOLS[x].name))), s.def.color, t.pos + Vector3(0, 2.3, 0), 64)
	t.label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t.label3d.visibility_range_end = 26.0
	targets.append(t)
	return t


func _targets_for_store(s: City.StoreData) -> void:
	match s.type:
		"shop":
			_target(s, 0.0, {"id": "register", "label": "صندوق النقد", "loot_name": "رزم نقود", "value": Vector2i(700, 1600), "time": 4.0, "heat": 1, "cd": 60.0})
		"gas":
			_target(s, 0.0, {"id": "register", "label": "صندوق النقد", "loot_name": "رزم نقود", "value": Vector2i(1100, 2600), "time": 4.0, "heat": 1, "cd": 70.0})
			_target(s, 5.0, {"id": "safe", "label": "خزنة صغيرة", "tools": ["minidrill"], "loot_name": "نقود الخزنة", "value": Vector2i(4000, 8000), "time": 7.0, "heat": 2, "cd": 150.0})
		"jewel":
			_target(s, 0.0, {"id": "cases", "label": "واجهات المجوهرات", "loot_name": "مجوهرات", "loot_kind": "jewel", "value": Vector2i(2500, 5500), "count": 3, "time": 6.0, "heat": 3, "cd": 120.0})
			_target(s, 5.0, {"id": "safe", "label": "خزنة المجوهرات", "tools": ["minidrill"], "loot_name": "ألماس خام", "loot_kind": "jewel", "value": Vector2i(9000, 16000), "time": 8.0, "heat": 3, "cd": 200.0})
		"bank":
			_target(s, 0.0, {"id": "teller", "label": "شبابيك الصرّاف", "loot_name": "رزم نقود", "value": Vector2i(3000, 7000), "count": 2, "time": 5.0, "heat": 3, "cd": 120.0})
			_target(s, -5.0, {"id": "boxes", "label": "صناديق الودائع", "tools": ["lockpick"], "loot_name": "محتويات صندوق", "loot_kind": "box", "value": Vector2i(800, 3200), "time": 3.0, "heat": 2, "cd": 2.0, "uses_max": 20})
			_target(s, 5.0, {"id": "gold", "label": "خزنة الذهب", "tools": ["drill", "bank_card"], "loot_name": "سبيكة ذهب", "loot_kind": "gold", "value": Vector2i(22000, 28000), "count": 6, "time": 20.0, "heat": 5, "city_alert": true, "cd": 900.0})
		"gallery":
			_target(s, 0.0, {"id": "pieces", "label": "تحف صغيرة", "loot_name": "تحفة", "loot_kind": "art", "value": Vector2i(4000, 9000), "count": 2, "time": 5.0, "heat": 2, "cd": 120.0})
			_target(s, 5.0, {"id": "exhibit", "label": "اللوحة الكبرى «ليل دمار»", "tools": ["cutter"], "loot_name": "لوحة «ليل دمار»", "loot_kind": "art", "value": Vector2i(170000, 210000), "time": 12.0, "heat": 5, "city_alert": true, "cd": 900.0})
		"police":
			_target(s, 5.0, {"id": "armory", "label": "مستودع أسلحة الشرطة", "tools": ["armory_card"], "loot_name": "صندوق أسلحة", "loot_kind": "weapons", "value": Vector2i(14000, 18000), "count": 4, "time": 15.0, "heat": 5, "city_alert": true, "cd": 900.0})


# ---------------------------------------------------------------- الحالة
func notoriety_level() -> int:
	var lv := 1
	for i in NOTORIETY_XP.size():
		if notoriety_xp >= NOTORIETY_XP[i]:
			lv = i + 1
	return lv


func fence_bonus() -> float:
	var b: float = NOTORIETY_BONUS[notoriety_level() - 1]
	if game.gangs != null and game.gangs.is_godfather():
		b += 0.10        # الحاكم الخفي
	return b


func bag_value() -> int:
	var v := 0
	for it in bag:
		v += it.value
	return v


func count_loot(kind: String) -> int:
	return bag.filter(func(i): return i.kind == kind).size()


func launder_rate() -> float:
	var bonus: float = game.gangs.launder_bonus() if game.gangs != null else 0.0
	var hm: float = game.land.house.launder_mult() if game.land != null and game.land.house != null and game.land.home.x >= 0 else 1.0
	return LAUNDER_BASE_RATE * launder_level * (1.0 + bonus) * hm


func lose_bag() -> int:
	var v := bag_value()
	bag.clear()
	return v


func to_dict() -> Dictionary:
	return {"tools": tools, "notoriety": notoriety_xp, "pool": launder_pool, "launder_level": launder_level, "bag": bag}


func from_dict(d: Dictionary) -> void:
	if not game.core_owned:                 # ترحيل لمرة واحدة؛ بعدها المصدر هو طبقة المنطق
		tools = d.get("tools", {})
		launder_pool = d.get("pool", 0.0)
	notoriety_xp = d.get("notoriety", 0)
	launder_level = d.get("launder_level", 1)
	bag.assign(d.get("bag", []))


# ---------------------------------------------------------------- التحديث
func toggle_mask() -> void:
	masked = not masked
	game.player.human.set_mask(masked)
	HeistCityManager.set_masked(masked)
	game.hud.toast("القناع: " + ("ملثّم 🥷" if masked else "مكشوف الوجه"), Color("c9c9c9"))


func tick(dt: float) -> void:
	for st in game.city.stores:
		st.cooldown = 1.0
	for t in targets:
		if t.cooldown <= 0.0:
			t.store.cooldown = 0.0
		if t.cooldown > 0.0:
			t.cooldown = maxf(0.0, t.cooldown - dt)
			if t.cooldown == 0.0 and t.uses_max > 0:
				t.uses_left = t.uses_max
		var open := t.cooldown <= 0.0
		t.ring.visible = open
		t.label3d.modulate.a = 1.0 if open else 0.3
	# الغسيل يحسبه EconomyManager بفارق الوقت الحقيقي؛ هنا نزوّده بالمعدّل والضريبة فقط
	EconomyManager.rate_override_per_sec = 0.0 if game.net.is_online() else launder_rate()   # أونلاين يغسل الخادم
	if not EconomyManager.tax_hook.is_valid():
		EconomyManager.tax_hook = func(amount: float) -> float:
			var cut: float = amount * game.land.tenant_tax() if game.land != null else 0.0   # ضريبة مالك المستوطنة
			if cut > 0.0:
				game.land.pay_tax(cut)
			return cut
	if _was_laundering and launder_pool <= 0.5:
		game.hud.toast("اكتمل غسيل الأموال 🧼 — المال في حسابك البنكي", Color("7dff9e"))
		game.check_win()
	_was_laundering = launder_pool > 0.5
	if exhibit_car and is_instance_valid(exhibit_car) and exhibit_car.exhibit and game.player.car == exhibit_car:
		exhibit_car.exhibit = false


## يرجع نص التلميح، ويتعامل مع الضغط على E
## هل يقف اللاعب (راجلاً) على هدف سرقة عادي؟
func on_target(p: Vector3) -> bool:
	if game.player.car != null:
		return false
	for t in targets:
		if p.distance_to(Vector3(t.pos.x, 0, t.pos.z)) < 1.8:
			return true
	return false


func interact(dt: float) -> String:
	var p: Vector3 = game.player_pos()
	var on_foot: bool = game.player.car == null
	# بيع سيارة المعرض للمشتري
	if not on_foot and exhibit_car and game.player.car == exhibit_car:
		for f in fences:
			if p.distance_to(f) < 7.0:
				if Input.is_action_just_pressed("interact"):
					_sell_exhibit_car()
				return "اضغط E لتسليم سيارة المعرض للمشتري (%s)" % Cfg.money(int(150000 * (1.0 + fence_bonus())))
		return ""
	if not on_foot:
		return ""
	# الأهداف
	var near: Target = null
	var nd := INF
	for t in targets:
		var d := p.distance_to(Vector3(t.pos.x, 0, t.pos.z))
		if d < nd:
			nd = d
			near = t
	if near and nd < 1.8:
		return _target_interact(near, dt)
	elif _active:
		game.hud.toast("ابتعدت — فشلت السرقة")
		_active = null
		game.player.robbing = false
	# المشتري
	for f in fences:
		if p.distance_to(f) < 5.0:
			if Input.is_action_just_pressed("interact"):
				_sell_bag()
			if bag.is_empty():
				return "المشتري: «أحضر لي بضاعة»"
			return "اضغط E لبيع الحقيبة (%d غنيمة) بـ %s" % [bag.size(), Cfg.money(int(bag_value() * (1.0 + fence_bonus())))]
	# السوق السوداء
	if p.distance_to(Vector3(dealer_pos.x, 0, dealer_pos.z)) < 2.5:
		if Input.is_action_just_pressed("interact"):
			open_market()
		return "اضغط E للتحدث مع تاجر السوق السوداء"
	# سيارة المعرض
	if exhibit_car and is_instance_valid(exhibit_car) and exhibit_car.locked and p.distance_to(exhibit_car.pos2()) < 3.8:
		if tools.get("jammer", 0) > 0:
			if Input.is_action_just_pressed("interact"):
				tools.jammer -= 1
				if game.net.is_online():
					game.net.req_use("jammer", 1)
				exhibit_car.locked = false
				game.set_wanted(4, "🚨 بلاغ للمدينة كلها: سرقة سيارة المعرض!")
				game.hud.toast("تم تعطيل الإنذار — اركبها (F) وسلّمها للمشتري", Color("ffd36b"))
			return "اضغط E لاستخدام جهاز التشويش على سيارة المعرض"
		return "سيارة المعرض محمية بإنذار — تحتاج: %s" % TOOLS.jammer.name
	return ""


func _target_interact(t: Target, dt: float) -> String:
	if t.cooldown > 0.0:
		_active = null
		return "%s — أُفرغ مؤخراً، عُد بعد %d ثانية" % [t.label, ceili(t.cooldown)]
	var missing: Array = t.tools.filter(func(x): return tools.get(x, 0) <= 0)
	if not missing.is_empty():
		return "%s — تحتاج: %s" % [t.label, ", ".join(missing.map(func(x): return TOOLS[x].name))]
	if bag.size() + t.count > BAG_SLOTS:
		return "الحقيبة ممتلئة (%d/%d) — بِع الغنائم عند المشتري" % [bag.size(), BAG_SLOTS]
	if not Input.is_action_pressed("interact"):
		if _active == t:
			game.hud.toast("توقفت السرقة")
			_active = null
			game.player.robbing = false
		var val := "%s – %s" % [Cfg.money(t.value.x * t.count), Cfg.money(t.value.y * t.count)]
		var extra := "" if t.uses_left < 0 else "  [%d متبقٍ]" % t.uses_left
		return "اضغط مطولاً E: %s  (%s)%s%s" % [t.label, val, extra, "" if masked else "  ⚠ بلا قناع!"]
	if game.net.is_online() and not game.net.target_open(targets.find(t)):
		return "%s — أُفرغ للتو" % t.label
	if _active != t:
		_active = t
		_prog = 0.0
		if game.net.is_online():
			game.net.rob_started(targets.find(t), t.city_alert)
		var heat := t.heat + (0 if masked else 1)
		if t.city_alert:
			game.set_wanted(5, "🚨 بلاغ للمدينة كلها: %s!" % t.label)
		else:
			game.set_wanted(heat, "🚨 انطلق الإنذار!" if masked else "🚨 تم التعرّف على وجهك! (بلا قناع)")
	_prog += dt / t.time
	game.robbing = t.store
	game.rob_prog = _prog
	game.rob_label = t.label
	game.player.robbing = true
	game.player.facing = -t.store.sx * PI / 2.0
	if int(game.time * 2.5) != int((game.time - dt) * 2.5):
		game.sfx.beep()
	if _prog >= 1.0:
		_complete(t)
	return ""


func _complete(t: Target) -> void:
	for tool in t.tools:
		tools[tool] -= 1
	var total := 0
	var online: bool = game.net.is_online()
	if online:
		game.net.req_rob_loot(targets.find(t))   # الخادم يرمي الغنائم ويضعها في الحقيبة بعد التحقق
	else:
		for i in t.count:
			var v := roundi(randf_range(t.value.x, t.value.y) / 10.0) * 10
			bag.append({"name": t.loot_name, "value": v, "kind": t.loot_kind})
			total += v
		if t.loot_kind == "box":
			bag.append({"name": "مفتاح صندوق ودائع", "value": 0, "kind": "deposit_key"})
	if t.uses_max > 0:
		t.uses_left -= 1
		t.cooldown = t.cd if t.uses_left > 0 else 240.0
	else:
		t.cooldown = t.cd
	if game.net.is_online():
		game.net.rob_done(targets.find(t))
	_active = null
	game.robbing = null
	game.player.robbing = false
	game.last_seen = 0.0
	if not online:
		game.hud.toast("+%s %s في الحقيبة  (%d/%d)" % [Cfg.money(total), t.loot_name, bag.size(), BAG_SLOTS], Color("7dff9e"))
	game.sfx.cash()
	game.land.on_robbery(total)
	MotelManager.report(QuestData.Objective.ROB_TARGETS, 1)


func _sell_bag() -> void:
	if bag.is_empty():
		return
	if not masked:
		game.hud.toast("المشتري: «لا أتعامل مع وجوه مكشوفة» — البس القناع (X)", Color("ff9b3b"))
		return
	if game.net.is_online():
		game.net.req_sell()                   # السعر والدفع يحسمهما الخادم
		game.sfx.cash()
		return
	var sellable := bag.filter(func(i): return i.kind != "deposit_key")
	var keys := bag.filter(func(i): return i.kind == "deposit_key")
	var base := 0
	for it in sellable:
		base += it.value
	var paid := int(base * (1.0 + fence_bonus()))
	var lv_before := notoriety_level()
	notoriety_xp += base
	game.cash += paid
	MotelManager.report(QuestData.Objective.SELL_LOOT, paid)
	bag.assign(keys)                  # مفاتيح الودائع تبقى للمقايضة
	game.hud.toast("بعت %d غنيمة بـ %s (نقود قذرة) — اغسلها في المخبأ" % [sellable.size(), Cfg.money(paid)], Color("7dff9e"))
	if notoriety_level() > lv_before:
		game.hud.toast("⭐ ارتفعت سمعتك الإجرامية إلى %d — المشتري يدفع +%d%%" % [notoriety_level(), int(fence_bonus() * 100)], Color("ffd36b"))
	game.sfx.cash()
	game.save_game()


func _sell_exhibit_car() -> void:
	var paid := int(150000 * (1.0 + fence_bonus()))
	notoriety_xp += 150000
	game.cash += paid
	if game.net.is_online():
		game.net.req_income("exhibit", paid)
	game.exit_car_force()
	game.remove_car(exhibit_car)
	exhibit_car = null
	game.hud.toast("سلّمت سيارة المعرض: %s نقود قذرة 🏎" % Cfg.money(paid), Color("7dff9e"))
	game.sfx.cash()
	game.save_game()


# ---------------------------------------------------------------- القوائم
func open_market() -> void:
	var items: Array = []
	for id in TOOLS:
		var t: Dictionary = TOOLS[id]
		var have: int = tools.get(id, 0)
		if t.has("price"):
			var ok: bool = game.cash + game.bank >= t.price
			items.append({"text": "%s — %s  (لديك %d)\n%s" % [t.name, Cfg.money(t.price), have, t.desc], "enabled": ok, "cb": _buy.bind(id)})
		else:
			var parts := []
			var ok2 := true
			for k in t.barter:
				var need: int = t.barter[k]
				var name: String = {"deposit_key": "مفتاح ودائع", "gold": "سبيكة ذهب"}[k]
				parts.append("%d %s" % [need, name])
				if count_loot(k) < need:
					ok2 = false
			items.append({"text": "مقايضة: %s ⇐ %s  (لديك %d)\n%s" % [t.name, " + ".join(parts), have, t.desc], "enabled": ok2, "cb": _barter.bind(id)})
	for w in Weapons.CATALOG:
		var wd: Dictionary = Weapons.CATALOG[w]
		if wd.price > 0:
			var owned: bool = game.weapons.owned.has(w)
			items.append({"text": "%s — %s %s" % [wd.name, Cfg.money(wd.price), "(تملكه)" if owned else ""], "enabled": not owned and game.cash + game.bank >= wd.price, "cb": _buy_weapon.bind(w)})
	items.append({"text": "ذخيرة ×60 — $1,500", "enabled": game.cash + game.bank >= 1500, "cb": _buy_ammo})
	items.append_array(game.land.market_items())
	game.hud.open_menu("السوق السوداء", "يُدفع من النقود القذرة أولاً ثم من الحساب البنكي. لديك: %s نقداً · %s في البنك · 📄 %d مستندات" % [Cfg.money(game.cash), Cfg.money(game.bank), game.land.docs], items)


func _pay(amount: int) -> bool:
	if game.cash + game.bank < amount:
		return false
	var from_cash := mini(game.cash, amount)
	game.cash -= from_cash
	game.bank -= amount - from_cash
	return true


func _buy(id: String) -> void:
	if game.net.is_online():
		game.net.req_buy("tool:" + id)       # الخادم يخصم ويضيف الأداة لمخزونك عنده
		game.after_ledger(open_market)            # تُفتح القائمة من جديد عند وصول رد الخادم
		return
	if _pay(TOOLS[id].price):
		tools[id] = tools.get(id, 0) + 1
		game.sfx.cash()
		game.save_game()
	open_market()


func _buy_weapon(w: String) -> void:
	if game.net.is_online():
		game.net.req_buy("weapon:" + w)
		game.weapons.current = w
		game.after_ledger(open_market)            # تُفتح القائمة من جديد عند وصول رد الخادم
		return
	if _pay(Weapons.CATALOG[w].price):
		game.weapons.give(w)
		game.save_game()
	open_market()


func _buy_ammo() -> void:
	if game.net.is_online():
		game.net.req_buy("ammo")
		game.after_ledger(open_market)            # تُفتح القائمة من جديد عند وصول رد الخادم
		return
	if _pay(1500):
		game.weapons.ammo += 60
		game.save_game()
	open_market()


func _barter(id: String) -> void:
	if game.net.is_online():
		game.net.req_buy("barter:" + id)
		game.after_ledger(open_market)            # تُفتح القائمة من جديد عند وصول رد الخادم
		return
	var t: Dictionary = TOOLS[id]
	for k in t.barter:
		var need: int = t.barter[k]
		for i in need:
			for j in bag.size():
				if bag[j].kind == k:
					bag.remove_at(j)
					break
	tools[id] = tools.get(id, 0) + 1
	game.hud.toast("تمت المقايضة: حصلت على %s" % t.name, Color("ffd36b"))
	game.save_game()
	open_market()


func open_laundering() -> void:
	var items: Array = []
	items.append({"text": "ضع كل النقود القذرة في طاولة الغسيل (%s)" % Cfg.money(game.cash), "enabled": game.cash > 0 and game.wanted == 0, "cb": _deposit_launder})
	var up_cost := 50000 * launder_level
	if launder_level < 4:
		items.append({"text": "تطوير الطاولة إلى المستوى %d (%s/ث) — %s من البنك" % [launder_level + 1, Cfg.money(int(LAUNDER_BASE_RATE * (launder_level + 1))), Cfg.money(up_cost)], "enabled": game.bank >= up_cost, "cb": _upgrade_launder.bind(up_cost)})
	var status := "قيد الغسيل: %s  ·  المعدّل: %s/ث  ·  الحساب البنكي: %s" % [Cfg.money(int(launder_pool)), Cfg.money(int(launder_rate())), Cfg.money(game.bank)]
	if game.wanted > 0:
		status += "\n⚠ الشرطة تلاحقك — لا يمكنك الإيداع الآن"
	game.hud.open_menu("طاولة غسيل الأموال", status, items)


func _deposit_launder() -> void:
	if game.net.is_online():
		game.net.req_deposit()
		EconomyManager.muted(func(): launder_pool += game.cash; game.cash = 0)
		game.hud.toast("أرسلت نقودك القذرة إلى طاولة الغسيل (الخادم يغسلها)", Color("7dff9e"))
		open_laundering()
		return
	launder_pool += game.cash
	game.hud.toast("بدأ غسيل %s — سيظهر في حسابك تدريجياً" % Cfg.money(game.cash), Color("7dff9e"))
	game.cash = 0
	game.save_game()
	open_laundering()


func _upgrade_launder(cost: int) -> void:
	if game.net.is_online():
		game.net.req_upgrade_launder()
		return
	if game.bank >= cost:
		game.bank -= cost
		launder_level += 1
		game.save_game()
	open_laundering()
