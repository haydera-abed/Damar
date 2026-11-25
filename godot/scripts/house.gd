class_name House
extends RefCounted
## منزلك على قطعة الأرض (مقتبس من نظام ROB RUN كما تصفه أدلة اللاعبين):
## - المنزل يبدأ شبه فارغ: حاسوب (السوق السوداء)، خزانة إسعافات، طاولة غسيل، ولوحة «مخطط البناء» على الجدار.
## - مخطط البناء: أماكن محدودة لكل نوع أثاث حسب حجم المنزل (كرفان ← منزل صغير ← منزل كبير، والفيلا للمالك).
##   تخزين (خزانة 9 غنائم، خزنة 6 محمية)، رفوف شحنات (6 شحنات)، وطاولات شحنات.
## - طاولة الغسيل: عدّادات نقود (+15/20/30%)، كابل قد يتلف فتنخفض الكفاءة للنصف، وحد للنقود القذرة حسب المنزل.
## - الشحنات: صناديق مغلقة من السرقات أو المختبر، تُفتح على طاولة الشحنات (وحدات: ملزمة، ميزان، عدّة أقفال،
##   منشار، قاطع بلازما) أو تُباع مغلقة للمشتري. إشهار السلاح وأنت تحملها يُسقطها.
## - مبنى ملحق واحد على القطعة: مرآب، مستودع، ورشة، غرفة زراعة (6 طاولات)، أو مختبر كيميائي (دخانه يجذب المداهمين).

const TIER_NAMES := ["", "كرفان", "منزل صغير", "منزل كبير", "فيلا"]
const TIER_SIZE := [Vector3.ZERO, Vector3(5.0, 2.7, 7.0), Vector3(7.5, 3.0, 9.0), Vector3(10.0, 3.0, 9.0), Vector3(8.0, 3.4, 13.0)]   # عمق × ارتفاع × عرض
const TIER_SLOTS := [{}, {"storage": 1, "rack": 1, "bench": 1}, {"storage": 2, "rack": 2, "bench": 2}, {"storage": 3, "rack": 3, "bench": 3}, {"storage": 4, "rack": 4, "bench": 4}]
const TIER_FUSES := [0, 2, 4, 6, 8]
const TIER_DIRTY_CAP := [0, 300000, 1000000, 3000000, 5000000]
const UPGRADE_COST := [0, 0, 80000, 250000]
const FURN := {
	"cabinet": {"name": "خزانة", "slot": "storage", "price": 5000, "desc": "+9 غنائم"},
	"safe": {"name": "خزنة", "slot": "storage", "price": 40000, "desc": "+6 غنائم محمية من المقتحمين"},
	"rack": {"name": "رف شحنات", "slot": "rack", "price": 8000, "desc": "+6 شحنات"},
	"bench": {"name": "طاولة شحنات", "slot": "bench", "price": 25000, "desc": "تفتح الشحنات المغلقة"},
}
const MODULES := {
	"vise": {"name": "ملزمة", "price": 6000, "desc": "+1 شحنة في كل طاولة"},
	"scales": {"name": "ميزان مختبر", "price": 9000, "desc": "+1 شحنة في كل طاولة"},
	"locks": {"name": "عُدّة أقفال", "price": 12000, "desc": "أسرع 20%"},
	"saw": {"name": "منشار شحنات", "price": 18000, "desc": "أسرع 20%"},
	"plasma": {"name": "قاطع بلازما", "price": 35000, "desc": "أسرع 25%"},
}
const COUNTERS := [{}, {"name": "عدّاد نقود Mk1", "bonus": 0.15, "price": 15000}, {"name": "عدّاد نقود Mk2", "bonus": 0.20, "price": 40000}, {"name": "عدّاد نقود Mk3", "bonus": 0.30, "price": 90000}]
const ANNEX := {
	"garage": {"name": "مرآب سيارات", "price": 60000, "desc": "تخزّن فيه سيارة، و+6 غنائم"},
	"warehouse": {"name": "مستودع", "price": 80000, "desc": "+20 غنيمة و+12 شحنة"},
	"workshop": {"name": "ورشة", "price": 70000, "desc": "+2 طاولة شحنات"},
	"grow": {"name": "غرفة زراعة", "price": 100000, "desc": "حتى 6 طاولات زراعة"},
	"lab": {"name": "مختبر كيميائي", "price": 150000, "desc": "يحوّل الكواشف إلى شحنات (دخانه يجذب المداهمين)"},
}
const ANNEX_SIZE := Vector3(7.5, 3.0, 5.0)
const TABLE_PRICE := 8000
const FAN_PRICE := 5000
const GROW_TIME := 480.0
const REACTOR_TIME := 240.0
const REAGENTS_PER_BATCH := 3
const REAGENT_PRICE := 2000
const CRATE_TIME := 180.0
const CRATE_SELL := 6000
const CABLE_REPAIR := 1500
const AID_CD := 90.0

var land: Node
var game: Node
var tier := 1
var annex := ""
var slots: Array = []                 # أنواع الأثاث الموضوعة بالترتيب
var modules := {}
var counter := 0
var cable_broken := false
var cargo: Array = []                 # شحنات مغلقة على الرفوف (قيمة البيع)
var bench_jobs: Array = []            # الثواني المتبقية لكل شحنة قيد الفتح
var tables: Array = []                # لكل طاولة زراعة: -1 فارغة، >0 ثوانٍ للنضج، 0 جاهزة
var fan := false
var reactor_t := -1.0
var garage_car := ""
var bushes := 0                       # شتلات جمعتها من الحدائق
var reagents := 0                     # كواشف كيميائية
var aid_cd := 0.0
var _vis := {}                        # مراجع المشاهد لتحديث الشكل


func _init(l: Node) -> void:
	land = l
	game = l.game


# ---------------------------------------------------------------- الاستعلامات
func tier_eff() -> int:
	return 4 if land.home.x >= 0 and land.home.y == 0 else tier


func count(kind: String) -> int:
	return slots.count(kind)


func slot_cap(slot: String) -> int:
	var c: int = TIER_SLOTS[tier_eff()].get(slot, 0)
	if slot == "bench" and annex == "workshop":
		c += 2
	return c


func slot_used(slot: String) -> int:
	var n := 0
	for k in slots:
		if FURN[k].slot == slot:
			n += 1
	return n


func stash_cap() -> int:
	return 4 + 9 * count("cabinet") + 6 * count("safe") + (20 if annex == "warehouse" else 0) + (6 if annex == "garage" else 0)


func protected_cap() -> int:
	return 6 * count("safe")


func cargo_cap() -> int:
	return 6 * count("rack") + (12 if annex == "warehouse" else 0)


func bench_capacity() -> int:
	return count("bench") * (1 + (1 if modules.get("vise", false) else 0) + (1 if modules.get("scales", false) else 0))


func crate_time() -> float:
	var t := CRATE_TIME
	if modules.get("locks", false):
		t *= 0.8
	if modules.get("saw", false):
		t *= 0.8
	if modules.get("plasma", false):
		t *= 0.75
	return t


func max_fuses() -> int:
	return TIER_FUSES[tier_eff()]


func dirty_cap() -> int:
	return TIER_DIRTY_CAP[tier_eff()]


func launder_mult() -> float:
	var m: float = 1.0 + (COUNTERS[counter].bonus if counter > 0 else 0.0)
	return m * (0.5 if cable_broken else 1.0)


func house_size() -> Vector3:
	return TIER_SIZE[tier_eff()]


# ---------------------------------------------------------------- الدورة الزمنية
func tick(dt: float) -> void:
	aid_cd = maxf(0.0, aid_cd - dt)
	if land.home.x < 0:
		return
	var cr: Crime = game.crime
	# كابل الغسيل قد يتلف أثناء العمل (مرة كل ~15 دقيقة في المتوسط)
	if cr.launder_pool > 0.0 and not cable_broken and randf() < dt / 900.0:
		cable_broken = true
		game.hud.toast("⚡ تلف كابل طاولة الغسيل — الكفاءة انخفضت للنصف، أصلحه عند الطاولة", Color("ffb36b"))
	# طاولات الشحنات: تأخذ الشحنات من الرفوف تلقائياً
	while bench_jobs.size() < bench_capacity() and not cargo.is_empty():
		cargo.pop_back()
		bench_jobs.append(crate_time())
	for i in range(bench_jobs.size() - 1, -1, -1):
		bench_jobs[i] -= dt
		if bench_jobs[i] <= 0.0:
			bench_jobs.remove_at(i)
			_crate_opened()
	# الزراعة
	var grow_k := 1.0 / (0.75 if fan else 1.0)
	for i in tables.size():
		if tables[i] > 0.0:
			tables[i] = maxf(0.0, tables[i] - dt * grow_k)
			if tables[i] == 0.0:
				game.hud.toast("🌿 نضج نبات على طاولة الزراعة %d — احصده" % (i + 1), Color("9dffb0"))
	# المختبر
	if reactor_t > 0.0:
		reactor_t -= dt
		if reactor_t <= 0.0:
			reactor_t = -1.0
			if cargo.size() < cargo_cap():
				cargo.append(CRATE_SELL)
			else:
				cr.bag.append(_crate_item())
			game.hud.toast("⚗ أنتج المختبر شحنة جديدة", Color("d9c7ff"))


func _crate_item() -> Dictionary:
	return {"name": "شحنة مغلقة", "value": CRATE_SELL, "kind": "cargo"}


func _crate_opened() -> void:
	var v := randi_range(9000, 26000)
	var item := {"name": ["أسلحة مهرّبة", "إلكترونيات", "ساعات فاخرة", "أدوية"][randi() % 4], "value": v, "kind": "goods"}
	if game.gangs.stash.size() < stash_cap():
		game.gangs.stash.append(item)
	else:
		game.crime.bag.append(item)
	game.hud.toast("📦 فُتحت شحنة: %s بقيمة %s" % [item.name, Cfg.money(v)], Color("ffd36b"))


# ---------------------------------------------------------------- القوائم
func open_plan() -> void:
	var items: Array = []
	var te := tier_eff()
	if te < 3:
		var nt := te + 1
		items.append({"text": "⬆ ترقية إلى %s — %s (أماكن أثاث وصمامات أكثر)" % [TIER_NAMES[nt], Cfg.money(UPGRADE_COST[nt])], "enabled": game.bank >= UPGRADE_COST[nt], "cb": _upgrade})
	for k in FURN:
		var f: Dictionary = FURN[k]
		var free: bool = slot_used(f.slot) < slot_cap(f.slot)
		items.append({"text": "ضع %s — %s (%s) · %s %d/%d" % [f.name, Cfg.money(f.price), f.desc, {"storage": "تخزين", "rack": "رفوف", "bench": "طاولات"}[f.slot], slot_used(f.slot), slot_cap(f.slot)], "enabled": free and game.bank >= f.price, "cb": _place.bind(k)})
	if annex == "" and land.home.y > 0:
		for a in ANNEX:
			items.append({"text": "🏗 ابنِ %s — %s (%s)" % [ANNEX[a].name, Cfg.money(ANNEX[a].price), ANNEX[a].desc], "enabled": game.bank >= ANNEX[a].price, "cb": _build_annex.bind(a)})
	elif annex != "":
		items.append({"text": "🔨 اهدم %s (لتبني ملحقاً آخر)" % ANNEX[annex].name, "enabled": true, "cb": _demolish})
	var sub := "%s · تخزين %d/%d · رفوف %d/%d · طاولات %d/%d · صمامات حتى %d · حد النقود القذرة %s%s" % [
		TIER_NAMES[te], slot_used("storage"), slot_cap("storage"), slot_used("rack"), slot_cap("rack"), slot_used("bench"), slot_cap("bench"),
		max_fuses(), Cfg.money(dirty_cap()), ("\nالملحق: " + ANNEX[annex].name) if annex != "" else ""]
	game.hud.open_menu("مخطط البناء", sub, items)


func _upgrade() -> void:
	var nt := tier_eff() + 1
	if game.bank < UPGRADE_COST[nt]:
		return
	game.bank -= UPGRADE_COST[nt]
	tier = nt
	game.hud.toast("🏠 رقّيت منزلك إلى %s" % TIER_NAMES[nt], Color("7dff9e"))
	_rebuild()
	open_plan()


func _place(k: String) -> void:
	var f: Dictionary = FURN[k]
	if game.bank < f.price or slot_used(f.slot) >= slot_cap(f.slot):
		return
	game.bank -= f.price
	slots.append(k)
	game.sfx.cash()
	_rebuild()
	open_plan()


func _build_annex(a: String) -> void:
	if game.bank < ANNEX[a].price:
		return
	game.bank -= ANNEX[a].price
	annex = a
	if a == "grow":
		tables = [-1.0]
	game.hud.toast("🏗 بُني %s بجوار منزلك" % ANNEX[a].name, Color("7dff9e"))
	_rebuild()
	open_plan()


func _demolish() -> void:
	annex = ""
	tables = []
	reactor_t = -1.0
	_rebuild()
	open_plan()


func _rebuild() -> void:
	game.save_game()
	var hp: Dictionary = land._home_plot()
	if not hp.is_empty():
		land._build_house(hp, true, land.home.y == 0)


func open_desk() -> void:
	var cr: Crime = game.crime
	var room := maxi(0, dirty_cap() - int(cr.launder_pool))
	var amt := mini(game.cash, room)
	var items: Array = [
		{"text": "ضع %s نقوداً قذرة على الطاولة (الحد %s)" % [Cfg.money(amt), Cfg.money(dirty_cap())], "enabled": amt > 0 and game.wanted == 0, "cb": _deposit.bind(amt)},
	]
	if cable_broken:
		items.append({"text": "⚡ أصلح كابل الطاولة — %s" % Cfg.money(CABLE_REPAIR), "enabled": game.cash + game.bank >= CABLE_REPAIR, "cb": _repair})
	if counter < 3:
		var c: Dictionary = COUNTERS[counter + 1]
		items.append({"text": "ركّب %s (+%d%% سرعة) — %s" % [c.name, int(c.bonus * 100), Cfg.money(c.price)], "enabled": game.bank >= c.price, "cb": _counter})
	if cr.launder_level < 4:
		var up: int = 50000 * cr.launder_level
		items.append({"text": "طاولة أكبر (المستوى %d) — %s" % [cr.launder_level + 1, Cfg.money(up)], "enabled": game.bank >= up, "cb": func(): cr._upgrade_launder(up); open_desk()})
	var sub := "قيد الغسيل: %s · المعدّل: %s/ث%s%s\nالمال في البنك لا يمكن سرقته؛ المال على الطاولة يأخذه المقتحمون." % [
		Cfg.money(int(cr.launder_pool)), Cfg.money(int(cr.launder_rate())), (" · " + COUNTERS[counter].name) if counter > 0 else "", " · ⚡ الكابل تالف" if cable_broken else ""]
	game.hud.open_menu("طاولة الغسيل", sub, items)


func _deposit(amt: int) -> void:
	if game.net.is_online():
		game.net.req_deposit(amt)
	EconomyManager.mute += 1
	game.crime.launder_pool += amt
	game.cash -= amt
	EconomyManager.mute -= 1
	game.save_game()
	open_desk()


func _repair() -> void:
	if game.crime._pay(CABLE_REPAIR):
		cable_broken = false
		game.save_game()
	open_desk()


func _counter() -> void:
	var c: Dictionary = COUNTERS[counter + 1]
	if game.bank < c.price:
		return
	game.bank -= c.price
	counter += 1
	game.save_game()
	open_desk()


func first_aid() -> void:
	if aid_cd > 0.0:
		game.hud.toast("خزانة الإسعافات فارغة مؤقتاً (%d ث)" % int(aid_cd))
		return
	game.player.health = game.player.max_health
	aid_cd = AID_CD
	game.hud.toast("🩹 عالجت جراحك — صحتك كاملة", Color("7dff9e"))


func open_storage() -> void:
	var gg: Gangs = game.gangs
	var cr: Crime = game.crime
	var sellable := cr.bag.filter(func(i): return i.kind != "deposit_key" and i.kind != "cargo")
	var items: Array = [
		{"text": "خزّن الغنائم (%d غنيمة)" % sellable.size(), "enabled": not sellable.is_empty() and gg.stash.size() < stash_cap(), "cb": func(): _store_loot(); open_storage()},
		{"text": "خذ الغنائم إلى الحقيبة (%d · %s)" % [gg.stash.size(), Cfg.money(gg.stash_value())], "enabled": not gg.stash.is_empty() and cr.bag.size() < Crime.BAG_SLOTS, "cb": func(): gg._take_stash(); open_storage()},
	]
	game.hud.open_menu("التخزين", "%d/%d غنيمة (منها %d محمية بالخزائن) · قيمتها %s" % [gg.stash.size(), stash_cap(), mini(gg.stash.size(), protected_cap()), Cfg.money(gg.stash_value())], items)


func _store_loot() -> void:
	var gg: Gangs = game.gangs
	var cr: Crime = game.crime
	var keep: Array[Dictionary] = []
	for it in cr.bag:
		if it.kind == "deposit_key" or it.kind == "cargo" or gg.stash.size() >= stash_cap():
			keep.append(it)
		else:
			gg.stash.append(it)
	cr.bag = keep
	game.save_game()


func open_racks() -> void:
	var cr: Crime = game.crime
	var in_bag := cr.count_loot("cargo")
	var items: Array = [
		{"text": "ضع الشحنات على الرفوف (%d في حقيبتك)" % in_bag, "enabled": in_bag > 0 and cargo.size() < cargo_cap(), "cb": func(): _store_cargo(); open_racks()},
		{"text": "خذ شحنة إلى الحقيبة (لبيعها مغلقة للمشتري)", "enabled": not cargo.is_empty() and cr.bag.size() < Crime.BAG_SLOTS, "cb": func(): cargo.pop_back(); cr.bag.append(_crate_item()); open_racks()},
	]
	game.hud.open_menu("رفوف الشحنات", "%d/%d شحنة مغلقة · طاولات الشحنات تأخذ منها تلقائياً" % [cargo.size(), cargo_cap()], items)


func _store_cargo() -> void:
	var cr: Crime = game.crime
	var keep: Array[Dictionary] = []
	for it in cr.bag:
		if it.kind == "cargo" and cargo.size() < cargo_cap():
			cargo.append(it.value)
		else:
			keep.append(it)
	cr.bag = keep
	game.save_game()


func open_bench() -> void:
	var items: Array = []
	for m in MODULES:
		if not modules.get(m, false):
			items.append({"text": "ركّب %s — %s (%s)" % [MODULES[m].name, Cfg.money(MODULES[m].price), MODULES[m].desc], "enabled": game.bank >= MODULES[m].price, "cb": _module.bind(m)})
	var jobs := []
	for j in bench_jobs:
		jobs.append("%d ث" % int(j))
	var sub := "%d طاولة · تتسع لـ %d شحنة معاً · وقت الفتح %d ث\nقيد الفتح: %s · على الرفوف: %d" % [count("bench"), bench_capacity(), int(crate_time()), "، ".join(jobs) if not jobs.is_empty() else "لا شيء", cargo.size()]
	game.hud.open_menu("طاولة الشحنات", sub, items)


func _module(m: String) -> void:
	if game.bank < MODULES[m].price:
		return
	game.bank -= MODULES[m].price
	modules[m] = true
	game.save_game()
	open_bench()


func open_grow() -> void:
	var items: Array = []
	for i in tables.size():
		var t: float = tables[i]
		if t < 0.0:
			items.append({"text": "الطاولة %d: فارغة — ازرع شتلة (معك %d)" % [i + 1, bushes], "enabled": bushes > 0, "cb": _plant.bind(i)})
		elif t > 0.0:
			items.append({"text": "الطاولة %d: ينمو… %d ث" % [i + 1, int(t * (0.75 if fan else 1.0))], "enabled": false, "cb": func(): pass})
		else:
			items.append({"text": "الطاولة %d: ناضج 🌿 — احصد" % (i + 1), "enabled": true, "cb": _harvest.bind(i)})
	if tables.size() < 6:
		items.append({"text": "أضف طاولة زراعة — %s" % Cfg.money(TABLE_PRICE), "enabled": game.bank >= TABLE_PRICE, "cb": _add_table})
	if not fan:
		items.append({"text": "ركّب مروحة (نمو أسرع 25%%) — %s" % Cfg.money(FAN_PRICE), "enabled": game.bank >= FAN_PRICE, "cb": _buy_fan})
	game.hud.open_menu("غرفة الزراعة", "شتلات معك: %d — تجدها في حدائق المدينة (علامات خضراء)\nكل نبتة ناضجة تعطي 2–4 أكياس تبيعها للمشتري." % bushes, items)


func _plant(i: int) -> void:
	if bushes <= 0:
		return
	bushes -= 1
	tables[i] = GROW_TIME
	game.save_game()
	open_grow()


func _harvest(i: int) -> void:
	var n := randi_range(2, 4)
	for k in n:
		game.crime.bag.append({"name": "كيس أعشاب", "value": 3000, "kind": "weed"})
	tables[i] = -1.0
	game.hud.toast("🌿 حصدت %d أكياس — بعها للمشتري" % n, Color("9dffb0"))
	game.save_game()
	open_grow()


func _add_table() -> void:
	if game.bank < TABLE_PRICE:
		return
	game.bank -= TABLE_PRICE
	tables.append(-1.0)
	_rebuild()
	open_grow()


func _buy_fan() -> void:
	if game.bank < FAN_PRICE:
		return
	game.bank -= FAN_PRICE
	fan = true
	_rebuild()
	open_grow()


func open_lab() -> void:
	var items: Array = [
		{"text": "ابدأ دفعة: %d كواشف → شحنة (%d ث)" % [REAGENTS_PER_BATCH, int(REACTOR_TIME)], "enabled": reactor_t < 0.0 and reagents >= REAGENTS_PER_BATCH, "cb": _start_batch},
		{"text": "اشترِ كاشفاً — %s" % Cfg.money(REAGENT_PRICE), "enabled": game.cash + game.bank >= REAGENT_PRICE, "cb": _buy_reagent},
	]
	var st := "يعمل… %d ث (الدخان يتصاعد!)" % int(reactor_t) if reactor_t > 0.0 else "متوقف"
	game.hud.open_menu("المختبر الكيميائي", "الكواشف: %d · المفاعل: %s\nالكواشف تجدها في سرقات محطات الوقود والمتاجر. الدخان يجذب العصابات إلى قاعدتك." % [reagents, st], items)


func _buy_reagent() -> void:
	if game.crime._pay(REAGENT_PRICE):
		reagents += 1
	open_lab()


func _start_batch() -> void:
	if reagents < REAGENTS_PER_BATCH or reactor_t > 0.0:
		return
	reagents -= REAGENTS_PER_BATCH
	reactor_t = REACTOR_TIME
	game.gangs._raid_t = minf(game.gangs._raid_t, randf_range(60.0, 180.0))   # الدخان يلفت الأنظار
	game.save_game()
	open_lab()


func open_garage() -> void:
	var near := _nearest_car()
	var items: Array = [
		{"text": "خزّن السيارة القريبة%s" % ((" (%s)" % near.model_name) if near else ""), "enabled": near != null and garage_car == "", "cb": _store_car},
		{"text": "أخرج سيارتك (%s)" % garage_car if garage_car != "" else "لا توجد سيارة مخزّنة", "enabled": garage_car != "", "cb": _take_car},
	]
	game.hud.open_menu("المرآب", "قد سيارة إلى جوار المرآب ثم خزّنها هنا. السيارة المخزّنة لا تضيع.", items)


func _nearest_car() -> Car:
	var g: Vector3 = _vis.get("garage_pos", Vector3.INF)
	if g == Vector3.INF:
		return null
	var best: Car = null
	var bd := 14.0
	for c in game.cars:
		if c.police or c.locked or c == game.player.car:
			continue
		var d: float = (c.global_position - g).length()
		if d < bd:
			bd = d
			best = c
	return best


func _store_car() -> void:
	var c := _nearest_car()
	if c == null:
		return
	garage_car = c.model_name
	game.remove_car(c)
	game.save_game()
	open_garage()


func _take_car() -> void:
	var g: Vector3 = _vis.get("garage_out", Vector3.INF)
	if garage_car == "" or g == Vector3.INF:
		return
	var c: Car = game._make_car(garage_car, false, Car.AI.PARKED, Transform3D(Basis(Vector3.UP, _vis.get("garage_yaw", 0.0)), g + Vector3(0, 0.6, 0)))
	c.engine_power = maxf(c.engine_power, 6000.0)
	garage_car = ""
	game.save_game()
	game.close_menu()


# ---------------------------------------------------------------- المداهمة والمصادرة
## خسائر اختراق القاعدة: المال على الطاولة، الغنائم غير المحمية، الشحنات، ودفعة المختبر
func raid_losses(master_key: bool) -> String:
	var gg: Gangs = game.gangs
	var prot := 0 if master_key else protected_cap()
	var open_items := maxi(0, gg.stash.size() - prot)
	var taken := open_items / 2
	for k in taken:
		gg.stash.pop_back()
	var lost_cargo := cargo.size() / 2
	for k in lost_cargo:
		cargo.pop_back()
	var lab := reactor_t > 0.0
	reactor_t = -1.0
	var parts := []
	if taken > 0:
		parts.append("%d غنيمة" % taken)
	if lost_cargo > 0:
		parts.append("%d شحنة" % lost_cargo)
	if lab:
		parts.append("دفعة المختبر")
	if prot > 0 and gg.stash.size() > 0:
		parts.append("(الخزائن حمت %d)" % mini(prot, gg.stash.size()))
	elif master_key and count("safe") > 0:
		parts.append("(معهم مفتاح رئيسي فتح الخزائن)")
	return "، ".join(parts)


func wipe() -> void:
	tier = 1
	annex = ""
	slots = []
	modules = {}
	counter = 0
	cable_broken = false
	cargo = []
	bench_jobs = []
	tables = []
	fan = false
	reactor_t = -1.0
	garage_car = ""
	bushes = 0
	reagents = 0


func to_dict() -> Dictionary:
	return {"tier": tier, "annex": annex, "slots": slots, "modules": modules, "counter": counter, "cable": cable_broken, "cargo": cargo,
		"jobs": bench_jobs, "tables": tables, "fan": fan, "reactor": reactor_t, "garage": garage_car, "bushes": bushes, "reagents": reagents}


func from_dict(d: Dictionary) -> void:
	tier = d.get("tier", 1)
	annex = d.get("annex", "")
	slots = d.get("slots", [])
	modules = d.get("modules", {})
	counter = d.get("counter", 0)
	cable_broken = d.get("cable", false)
	cargo = d.get("cargo", [])
	bench_jobs = d.get("jobs", [])
	tables = d.get("tables", [])
	fan = d.get("fan", false)
	reactor_t = d.get("reactor", -1.0)
	garage_car = d.get("garage", "")
	bushes = d.get("bushes", 0)
	reagents = d.get("reagents", 0)


# ---------------------------------------------------------------- الشكل الداخلي
## نقاط على الجدران الداخلية (للأثاث الثابت ثم أماكن مخطط البناء)
func _anchors(size: Vector3) -> Array:
	var d := size.x
	var w := size.z
	var out: Array = []
	var z := -w / 2.0 + 0.9
	while z <= w / 2.0 - 0.9 + 0.01:
		out.append({"p": Vector3(-d / 2.0 + 0.45, 0, z), "n": Vector3(1, 0, 0)})
		z += 1.5
	for zs in [-1, 1]:
		var x := -d / 2.0 + 1.6
		while x <= d / 2.0 - 1.4 + 0.01:
			out.append({"p": Vector3(x, 0, zs * (w / 2.0 - 0.45)), "n": Vector3(0, 0, -zs)})
			x += 1.5
	for zs in [-1, 1]:
		var zz := 1.6
		while zz <= w / 2.0 - 0.9 + 0.01:
			out.append({"p": Vector3(d / 2.0 - 0.45, 0, zs * zz), "n": Vector3(-1, 0, 0)})
			zz += 1.5
	return out


func furnish(plot: Dictionary, h: Node3D, size: Vector3) -> void:
	var L: Node = land
	var hh := size.y
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 1.8
	lamp.omni_range = maxf(size.x, size.z)
	lamp.position = Vector3(0, hh - 0.4, 0)
	h.add_child(lamp)
	L._hbox(h, Vector3(0, hh - 0.05, 0), Vector3(0.6, 0.08, 0.6), L._glow(Color(1.0, 0.9, 0.7)), false)
	L._hbox(h, Vector3(0, 0.15, 0), Vector3(minf(3.6, size.x - 2.0), 0.02, minf(2.6, size.z - 3.0)), L._mat(Color("7a2630"), 1.0), false)
	var metal: StandardMaterial3D = L._mat(Color("2b2e33"), 0.35)
	metal.metallic = 0.8
	var wood: StandardMaterial3D = L._mat(Color("4b3a2a"), 0.6)
	var anchors := _anchors(size)
	var used := {}
	plot.stations = []
	# الثابت: طاولة الغسيل (نقطتان في الجدار الخلفي)، الحاسوب، الإسعافات، مخطط البناء، لوحة الأمان
	var back := anchors.filter(func(a): return a.n.x > 0.5)
	var front := anchors.filter(func(a): return a.n.x < -0.5)
	var sides := anchors.filter(func(a): return absf(a.n.z) > 0.5)
	var desk_a: Dictionary = back[0]
	used[desk_a] = true
	var dp: Vector3 = desk_a.p + Vector3(0.15, 0, 0.6)
	L._hbox(h, dp + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 2.2), wood)
	L._hbox(h, dp + Vector3(0.1, 0.98, -0.6), Vector3(0.5, 0.16, 0.4), L._glow(Color(0.3, 1.0, 0.5), 0.6), false)
	var money: Array = []
	for k in 6:
		money.append(L._hbox(h, dp + Vector3((k % 2) * 0.3 - 0.15, 0.98 + (k / 2) * 0.11, 0.3), Vector3(0.26, 0.1, 0.5), L._mat(Color("4f8a4a"), 0.8), false))
	if back.size() > 1:
		used[back[1]] = true
	_vis.money = money
	plot.stations.append({"kind": "desk", "pos": h.transform * (dp + Vector3(1.2, 0, 0))})
	var lap_a: Dictionary = back[back.size() - 1]
	used[lap_a] = true
	L._hbox(h, lap_a.p + Vector3(0, 0.4, 0), Vector3(0.7, 0.8, 1.1), wood)
	L._hbox(h, lap_a.p + Vector3(0.05, 0.92, 0), Vector3(0.35, 0.03, 0.5), metal, false)
	L._hbox(h, lap_a.p + Vector3(-0.12, 1.08, 0), Vector3(0.03, 0.3, 0.5), L._glow(Color(0.35, 0.6, 1.0), 1.2), false)
	plot.stations.append({"kind": "laptop", "pos": h.transform * (lap_a.p + Vector3(0.9, 0, 0))})
	var fr0: Dictionary = front[0]
	var fr1: Dictionary = front[front.size() - 1]
	used[fr0] = true
	used[fr1] = true
	# مخطط البناء + لوحة الأمان (يسار الباب)
	L._hbox(h, fr0.p + Vector3(0.12, 1.5, 0), Vector3(0.05, 0.9, 1.2), L._mat(Color("e9e3d2"), 0.8), false)
	L._hbox(h, fr0.p + Vector3(0.1, 1.5, 0), Vector3(0.04, 0.7, 1.0), L._glow(Color(0.25, 0.45, 0.9), 0.4), false)
	plot.stations.append({"kind": "plan", "pos": h.transform * (fr0.p + Vector3(-0.9, 0, 0.0))})
	var led: StandardMaterial3D = L._glow(Color.RED)
	L._hbox(h, fr0.p + Vector3(0.12, 1.4, 0.85 * signf(fr0.p.z)), Vector3(0.06, 0.5, 0.35), metal, false)
	L._hbox(h, fr0.p + Vector3(0.08, 1.55, 0.85 * signf(fr0.p.z)), Vector3(0.04, 0.08, 0.18), led, false)
	_vis.led = led
	plot.stations.append({"kind": "panel", "pos": h.transform * (fr0.p + Vector3(-0.9, 0, 0.85 * signf(fr0.p.z)))})
	# خزانة الإسعافات (يمين الباب)
	L._hbox(h, fr1.p + Vector3(0.12, 1.5, 0), Vector3(0.25, 0.6, 0.6), L._mat(Color("e8e8e8"), 0.5), false)
	L._hbox(h, fr1.p + Vector3(-0.02, 1.5, 0), Vector3(0.02, 0.3, 0.08), L._glow(Color(1, 0.1, 0.1), 1.0), false)
	L._hbox(h, fr1.p + Vector3(-0.02, 1.5, 0), Vector3(0.02, 0.08, 0.3), L._glow(Color(1, 0.1, 0.1), 1.0), false)
	plot.stations.append({"kind": "aid", "pos": h.transform * (fr1.p + Vector3(-0.9, 0, 0))})
	# أماكن مخطط البناء
	var free_a: Array = []
	for a in sides + back + front:
		if not used.has(a):
			free_a.append(a)
	var crates: Array = []
	var loot: Array = []
	for i in mini(slots.size(), free_a.size()):
		var a: Dictionary = free_a[i]
		var kind: String = slots[i]
		var p: Vector3 = a.p
		var n: Vector3 = a.n
		var along := Vector3(absf(n.z), 0, absf(n.x))      # موازٍ للجدار
		match kind:
			"cabinet":
				L._hbox(h, p + Vector3(0, 0.95, 0), along * 1.0 + Vector3(absf(n.x), 0, absf(n.z)) * 0.55 + Vector3(0, 1.9, 0), L._mat(Color("6b5640"), 0.7))
				for k in 3:
					var b: MeshInstance3D = L._hbox(h, p + n * 0.3 + Vector3(0, 0.4 + k * 0.6, 0) + along * 0.0, along * 0.7 + Vector3(absf(n.x), 0, absf(n.z)) * 0.05 + Vector3(0, 0.3, 0), L._mat(Color("c9a46a"), 0.9), false)
					loot.append(b)
			"safe":
				L._hbox(h, p + Vector3(0, 0.55, 0), Vector3(0.9, 1.1, 0.9), metal)
				L._hbox(h, p + n * 0.46 + Vector3(0, 0.7, 0), along * 0.25 + Vector3(absf(n.x), 0, absf(n.z)) * 0.03 + Vector3(0, 0.25, 0), L._glow(Color(0.9, 0.8, 0.3), 0.5), false)
			"rack":
				L._hbox(h, p + Vector3(0, 1.0, 0), along * 1.3 + Vector3(absf(n.x), 0, absf(n.z)) * 0.5 + Vector3(0, 2.0, 0), metal)
				for k in 6:
					var c: MeshInstance3D = L._hbox(h, p + n * 0.32 + Vector3(0, 0.45 + (k / 2) * 0.62, 0) + along * ((k % 2) * 0.6 - 0.3), Vector3(0.5, 0.4, 0.5), L._mat(Color("7c5a2c"), 0.9), false)
					crates.append(c)
			"bench":
				L._hbox(h, p + n * 0.1 + Vector3(0, 0.45, 0), along * 1.3 + Vector3(absf(n.x), 0, absf(n.z)) * 0.7 + Vector3(0, 0.9, 0), L._mat(Color("3d4a3a"), 0.6))
				L._hbox(h, p + n * 0.1 + Vector3(0, 1.0, 0) + along * 0.35, Vector3(0.25, 0.2, 0.25), metal, false)
		plot.stations.append({"kind": kind, "pos": h.transform * (p + n * 1.0)})
	_vis.crates = crates
	_vis.loot = loot
	update_visuals()


## الملحق: مبنى ثانٍ على القطعة بجوار المنزل
func build_annex(plot: Dictionary, a: Node3D) -> void:
	var L: Node = land
	var size := ANNEX_SIZE
	var d := size.x
	var hh := size.y
	var w := size.z
	var t: float = L.WALL_T
	var wall: StandardMaterial3D = L._mat(Color("8f8676"), 0.9)
	L._hbox(a, Vector3(0, 0.08, 0), Vector3(d, 0.12, w), L._mat(Color("5e5a55"), 0.9), false)
	L._hbox(a, Vector3(0, hh + 0.1, 0), Vector3(d, 0.2, w), wall)
	L._hbox(a, Vector3(-d / 2.0 + t / 2.0, hh / 2.0, 0), Vector3(t, hh, w), wall)
	for zs in [-1, 1]:
		L._hbox(a, Vector3(0, hh / 2.0, zs * (w / 2.0 - t / 2.0)), Vector3(d, hh, t), wall)
	var gap := 3.6 if annex == "garage" else 1.6
	var seg := (w - gap) / 2.0
	for zs in [-1, 1]:
		L._hbox(a, Vector3(d / 2.0 - t / 2.0, hh / 2.0, zs * (gap / 2.0 + seg / 2.0)), Vector3(t, hh, seg), wall)
	L._hbox(a, Vector3(d / 2.0 - t / 2.0, (2.6 + hh) / 2.0, 0), Vector3(t, hh - 2.6, gap), wall)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.85, 0.95, 1.0) if annex != "grow" else Color(1.0, 0.5, 0.9)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, hh - 0.4, 0)
	a.add_child(lamp)
	var sign: Label3D = game.crime._label(ANNEX[annex].name, Color("ffd36b"), Vector3(d / 2.0 + 0.1, hh + 0.5, 0), 48)
	sign.reparent(a, false)
	sign.position = Vector3(d / 2.0 + 0.1, hh + 0.5, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var metal: StandardMaterial3D = L._mat(Color("2b2e33"), 0.35)
	metal.metallic = 0.8
	var st_kind := ""
	match annex:
		"grow":
			var plants: Array = []
			for i in tables.size():
				var p := Vector3(-d / 2.0 + 1.3 + (i / 2) * 2.0, 0, (i % 2) * 2.4 - 1.2)
				L._hbox(a, p + Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 1.0), L._mat(Color("4a3d2c"), 0.8))
				var plant: MeshInstance3D = L._hbox(a, p + Vector3(0, 1.3, 0), Vector3(0.8, 0.8, 0.6), L._mat(Color("3f8f3a"), 0.9), false)
				plants.append(plant)
			if fan:
				L._hbox(a, Vector3(-d / 2.0 + 0.3, 2.2, 0), Vector3(0.2, 0.7, 0.7), metal, false)
			_vis.plants = plants
			st_kind = "grow"
		"lab":
			var cyl := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.6
			cm.bottom_radius = 0.7
			cm.height = 1.8
			cyl.mesh = cm
			cyl.material_override = metal
			cyl.position = Vector3(-d / 2.0 + 1.4, 0.9, 0)
			a.add_child(cyl)
			L._hbox(a, Vector3(-d / 2.0 + 1.4, 2.4, 0), Vector3(0.25, 1.4, 0.25), metal, false)
			var smoke := GPUParticles3D.new()
			smoke.amount = 60
			smoke.lifetime = 4.0
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 12.0
			pm.initial_velocity_min = 1.5
			pm.initial_velocity_max = 2.5
			pm.gravity = Vector3(0.3, 0.2, 0)
			pm.scale_min = 1.5
			pm.scale_max = 3.0
			pm.color = Color(0.75, 0.78, 0.72, 0.5)
			smoke.process_material = pm
			var qm := QuadMesh.new()
			qm.size = Vector2(1.2, 1.2)
			var sm := StandardMaterial3D.new()
			sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.vertex_color_use_as_albedo = true
			sm.albedo_color = Color(0.8, 0.8, 0.78, 0.35)
			qm.material = sm
			smoke.draw_pass_1 = qm
			smoke.position = Vector3(-d / 2.0 + 1.4, hh + 0.6, 0)
			smoke.emitting = false
			a.add_child(smoke)
			_vis.smoke = smoke
			st_kind = "lab"
		"garage":
			L._hbox(a, Vector3(0, 0.15, 0), Vector3(d - 1.0, 0.02, 2.6), L._mat(Color("c9b23a"), 0.6), false)
			st_kind = "garage"
		"warehouse":
			for i in 2:
				L._hbox(a, Vector3(-d / 2.0 + 1.0 + i * 2.4, 1.1, w / 2.0 - 0.6), Vector3(2.0, 2.2, 0.6), metal)
				L._hbox(a, Vector3(-d / 2.0 + 1.0 + i * 2.4, 1.1, -w / 2.0 + 0.6), Vector3(2.0, 2.2, 0.6), metal)
			st_kind = "storage"
		"workshop":
			for zs in [-1, 1]:
				L._hbox(a, Vector3(-0.5, 0.45, zs * (w / 2.0 - 0.6)), Vector3(2.6, 0.9, 0.8), L._mat(Color("3d4a3a"), 0.6))
			st_kind = "bench"
	plot.stations.append({"kind": st_kind, "pos": a.transform * Vector3(0.6, 0, 0)})
	_vis.garage_pos = a.transform * Vector3(d / 2.0 + 3.0, 0, 0)
	_vis.garage_out = a.transform * Vector3(d / 2.0 + 3.5, 0, 0)
	_vis.garage_yaw = a.rotation.y + PI / 2.0
	plot.annex_node = a
	update_visuals()


func update_visuals() -> void:
	var pool: float = game.crime.launder_pool
	var n_money := 0 if pool <= 0.0 else clampi(int(ceil(pool / 20000.0)), 1, 6)
	for i in _vis.get("money", []).size():
		if is_instance_valid(_vis.money[i]):
			_vis.money[i].visible = i < n_money
	var crates: Array = _vis.get("crates", [])
	for i in crates.size():
		if is_instance_valid(crates[i]):
			crates[i].visible = i < cargo.size()
	var loot: Array = _vis.get("loot", [])
	var per := float(game.gangs.stash.size()) / maxf(1.0, float(stash_cap()))
	for i in loot.size():
		if is_instance_valid(loot[i]):
			loot[i].visible = float(i) / loot.size() < per
	if _vis.has("led") and _vis.led:
		var c := Color(0.2, 1.0, 0.35) if land.security else Color(1.0, 0.15, 0.1)
		_vis.led.albedo_color = c
		_vis.led.emission = c
	var plants: Array = _vis.get("plants", [])
	for i in plants.size():
		if i < tables.size() and is_instance_valid(plants[i]):
			var t: float = tables[i]
			plants[i].visible = t >= 0.0
			var k := 1.0 if t == 0.0 else clampf(1.0 - t / GROW_TIME, 0.15, 1.0)
			plants[i].scale = Vector3(k, k, k)
	if _vis.has("smoke") and is_instance_valid(_vis.smoke):
		_vis.smoke.emitting = reactor_t > 0.0


## تلميح ومحطة تفاعل داخل المنزل أو الملحق
func station_hint(kind: String, e: bool) -> String:
	match kind:
		"desk":
			if e:
				open_desk()
			return "طاولة الغسيل — اضغط E (قيد الغسيل: %s%s)" % [Cfg.money(int(game.crime.launder_pool)), " · ⚡ الكابل تالف" if cable_broken else ""]
		"laptop":
			if e:
				game.crime.open_market()
			return "الحاسوب — اضغط E للسوق السوداء"
		"aid":
			if e:
				first_aid()
			return "خزانة الإسعافات — اضغط E للعلاج" + (" (%d ث)" % int(aid_cd) if aid_cd > 0.0 else "")
		"plan":
			if e:
				open_plan()
			return "مخطط البناء — اضغط E (ترقية المنزل، الأثاث، الملحق)"
		"panel":
			if e:
				land.open_panel()
			return "لوحة نظام الأمان — اضغط E (%s)" % ("محمي" if land.security else "بلا حماية")
		"cabinet", "safe", "storage":
			if e:
				open_storage()
			return "التخزين — اضغط E (%d/%d غنيمة)" % [game.gangs.stash.size(), stash_cap()]
		"rack":
			if e:
				open_racks()
			return "رف الشحنات — اضغط E (%d/%d)" % [cargo.size(), cargo_cap()]
		"bench":
			if e:
				open_bench()
			return "طاولة الشحنات — اضغط E (%d قيد الفتح)" % bench_jobs.size()
		"grow":
			if e:
				open_grow()
			return "غرفة الزراعة — اضغط E (%d طاولات)" % tables.size()
		"lab":
			if e:
				open_lab()
			return "المختبر — اضغط E (كواشف: %d)" % reagents
		"garage":
			if e:
				open_garage()
			return "المرآب — اضغط E" + (" (فيه %s)" % garage_car if garage_car != "" else "")
	return ""
