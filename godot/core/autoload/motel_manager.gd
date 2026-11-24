extends Node
## MotelManager (Autoload): موتيل الصحراء — المنطقة الآمنة ونقطة البداية. صاحبه «رفيق».
## (المقابل الأصلي لموتيل ليني في ROB RUN؛ الميكانيكيات نفسها بأسماء أصلية)
## الخدمات (كلها تبث إشارات، والواجهة تستمع فقط):
##  - خزنة الكاش: تخزين الكاش القذر بأمان خارج الحقيبة (لا تصادره الشرطة).
##  - الباب المريب (المقايضة): عناصر نادرة + كاش ← معدات متقدمة (أجهزة فك التشفير، التصاريح…).
##  - المهام اليومية والشحنات: تُفتح تدريجياً حسب مستوى النفوذ (authority).
##  - الروليت: رهان بعملة اللعبة بحد أقصى يرتفع مع النفوذ.

signal stash_changed(amount: int)
signal barter_done(recipe_id: String, item_id: String, count: int)
signal barter_failed(recipe_id: String, reason: String)
signal quests_refreshed(quests: Array)
signal quest_progress(quest_id: String, progress: int, target: int)
signal quest_completed(quest_id: String, reward_cash: int)
signal shipment_ordered(shipment_id: String, eta_unix: int)
signal shipment_delivered(shipment_id: String, contents: Dictionary)
signal roulette_result(number: int, color: String, bet: int, payout: int)
signal motel_error(reason: String)

const OWNER_NAME := "رفيق"
const RED := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
const DAILY_QUESTS := 3

var stash_cash := 0
var recipes: Array[BarterRecipe] = []
var quest_catalog: Array[QuestData] = []
var shipment_catalog: Array[ShipmentData] = []
var active_quests: Array = []          # معرّفات مهام اليوم
var quest_day := -1
var progress := {}                     # quest_id -> تقدم
var done := {}                         # quest_id -> true (اليوم)
var orders: Array = []                 # [{id, eta}]
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_catalogs()
	GameState.register_module("motel", self)
	# المهام تتقدم من أحداث الأنظمة الأخرى (بلا اقتران مباشر بالواجهة)
	EconomyManager.item_sold.connect(func(_id, _n, total): report(QuestData.Objective.SELL_LOOT, total))
	EconomyManager.laundered.connect(func(amount, _off): report(QuestData.Objective.LAUNDER_CASH, amount))
	HeistCityManager.heist_completed.connect(func(_t, _loot): report(QuestData.Objective.ROB_TARGETS, 1))
	HeistCityManager.extracted.connect(func(_items, value): report(QuestData.Objective.EXTRACT_LOOT, value))
	refresh_daily()


func _process(_dt: float) -> void:
	if Engine.get_process_frames() % 60 == 0:
		check_deliveries()
		refresh_daily()


# ---------------------------------------------------------------- خزنة الكاش
func stash_deposit(amount: int) -> bool:
	amount = mini(amount, EconomyManager.dirty_cash)
	if amount <= 0 or TravelManager.current_hub != TravelManager.Hub.MOTEL:
		motel_error.emit("الخزنة في الموتيل فقط، وتحتاج كاشاً معك")
		return false
	EconomyManager.add_dirty(-amount)
	stash_cash += amount
	stash_changed.emit(stash_cash)
	return true


func stash_withdraw(amount: int) -> bool:
	amount = mini(amount, stash_cash)
	if amount <= 0 or TravelManager.current_hub != TravelManager.Hub.MOTEL:
		motel_error.emit("لا يوجد ما تسحبه هنا")
		return false
	stash_cash -= amount
	EconomyManager.add_dirty(amount)
	stash_changed.emit(stash_cash)
	return true


# ---------------------------------------------------------------- الباب المريب (المقايضة)
func available_recipes() -> Array[BarterRecipe]:
	var auth := PrisonManager.authority_level()
	return recipes.filter(func(r): return r.required_authority <= auth)


func barter(recipe_id: String) -> bool:
	var r: BarterRecipe = null
	for x in recipes:
		if x.id == recipe_id:
			r = x
	if r == null:
		barter_failed.emit(recipe_id, "وصفة غير معروفة")
		return false
	if PrisonManager.authority_level() < r.required_authority:
		barter_failed.emit(recipe_id, "نفوذك غير كافٍ (تحتاج المستوى %d)" % r.required_authority)
		return false
	if not GameState.has_items(r.inputs):
		barter_failed.emit(recipe_id, "تنقصك عناصر المقايضة")
		return false
	if not EconomyManager.spend(r.cash_cost):
		barter_failed.emit(recipe_id, "المال غير كافٍ")
		return false
	for k in r.inputs:
		GameState.remove_item(k, int(r.inputs[k]))
	GameState.add_item(r.output_item, r.output_count)
	barter_done.emit(r.id, r.output_item, r.output_count)
	return true


# ---------------------------------------------------------------- المهام اليومية
func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400)


func refresh_daily(force := false) -> void:
	if not force and quest_day == today():
		return
	quest_day = today()
	progress = {}
	done = {}
	var auth := PrisonManager.authority_level()
	var pool := quest_catalog.filter(func(q): return q.required_authority <= auth)
	var r := RandomNumberGenerator.new()
	r.seed = quest_day * 7919 + hash(GameState.player_id)
	active_quests = []
	while active_quests.size() < mini(DAILY_QUESTS, pool.size()):
		var q: QuestData = pool[r.randi() % pool.size()]
		if not active_quests.has(q.id):
			active_quests.append(q.id)
	quests_refreshed.emit(active_quests)


func report(objective: int, amount: int) -> void:
	for qid in active_quests:
		if done.get(qid, false):
			continue
		var q := _quest(qid)
		if q == null or q.objective != objective:
			continue
		progress[qid] = int(progress.get(qid, 0)) + amount
		quest_progress.emit(qid, mini(progress[qid], q.target_amount), q.target_amount)
		if progress[qid] >= q.target_amount:
			done[qid] = true
			EconomyManager.add_dirty(q.reward_cash)
			for k in q.reward_items:
				GameState.add_item(k, int(q.reward_items[k]))
			quest_completed.emit(qid, q.reward_cash)


func _quest(id: String) -> QuestData:
	for q in quest_catalog:
		if q.id == id:
			return q
	return null


# ---------------------------------------------------------------- الشحنات
func available_shipments() -> Array[ShipmentData]:
	var auth := PrisonManager.authority_level()
	var rewards: Array = GameState.profile.rewards
	return shipment_catalog.filter(func(s): return s.required_authority <= auth and (s.exclusive_reward == "" or rewards.has(s.exclusive_reward)))


func order_shipment(id: String) -> bool:
	var sh: ShipmentData = null
	for s in available_shipments():
		if s.id == id:
			sh = s
	if sh == null:
		motel_error.emit("الشحنة غير متاحة لمستوى نفوذك")
		return false
	if not EconomyManager.spend(sh.price):
		return false
	var eta := int(Time.get_unix_time_from_system()) + sh.delivery_seconds
	orders.append({"id": id, "eta": eta})
	shipment_ordered.emit(id, eta)
	return true


## التسليم يعتمد على الوقت الحقيقي (يصل حتى لو كانت اللعبة مغلقة)
func check_deliveries(now := -1) -> void:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	for o in orders.duplicate():
		if now >= int(o.eta):
			orders.erase(o)
			var sh: ShipmentData = null
			for s in shipment_catalog:
				if s.id == o.id:
					sh = s
			if sh:
				for k in sh.contents:
					GameState.add_item(k, int(sh.contents[k]))
				shipment_delivered.emit(sh.id, sh.contents)


# ---------------------------------------------------------------- الروليت
func bet_cap() -> int:
	return Balance.ROULETTE_BET_CAP[clampi(PrisonManager.authority_level(), 0, Balance.ROULETTE_BET_CAP.size() - 1)]


## kind: "red" | "black" | "even" | "odd" | "number" (مع number 0..36)
func spin(amount: int, kind: String, number := -1) -> int:
	if TravelManager.current_hub != TravelManager.Hub.MOTEL:
		motel_error.emit("الروليت في الموتيل فقط")
		return -1
	if amount <= 0 or amount > bet_cap():
		motel_error.emit("الرهان بين 1 و%d" % bet_cap())
		return -1
	if amount > EconomyManager.dirty_cash:
		motel_error.emit("تراهن بالكاش الذي معك فقط")
		return -1
	EconomyManager.add_dirty(-amount)
	var n := rng.randi_range(0, 36)
	var color := "green" if n == 0 else ("red" if RED.has(n) else "black")
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
	if payout > 0:
		EconomyManager.add_dirty(payout)
	roulette_result.emit(n, color, amount, payout)
	return n


# ---------------------------------------------------------------- الكتالوجات
func _build_catalogs() -> void:
	var mk_r := func(id: String, title: String, inputs: Dictionary, cash: int, out: String, n: int, auth: int) -> BarterRecipe:
		var r := BarterRecipe.new()
		r.id = id; r.title = title; r.inputs = inputs; r.cash_cost = cash; r.output_item = out; r.output_count = n; r.required_authority = auth
		return r
	recipes = [
		mk_r.call("decoder", "جهاز فك تشفير", {"deposit_key": 2}, 5000, "decoder", 1, 0),
		mk_r.call("decoder_epic", "جهاز فك تشفير نادر (3 عادية + كاش)", {"decoder": 3}, 10000, "decoder_epic", 1, 1),
		mk_r.call("master_key", "مفتاح رئيسي", {"decoder_epic": 2, "gold_bar": 1}, 20000, "master_key", 1, 2),
		mk_r.call("eviction", "حق طرد", {"decoder_epic": 5}, 50000, "eviction_right", 1, 3),
		mk_r.call("vip_pass", "تصريح خاص", {"art": 1}, 15000, "pass_vip", 1, 1),
	]
	var mk_q := func(id: String, title: String, obj: int, target: int, auth: int, cash: int, items: Dictionary) -> QuestData:
		var q := QuestData.new()
		q.id = id; q.title = title; q.objective = obj; q.target_amount = target; q.required_authority = auth; q.reward_cash = cash; q.reward_items = items
		return q
	quest_catalog = [
		mk_q.call("rob3", "نفّذ 3 عمليات سطو", QuestData.Objective.ROB_TARGETS, 3, 0, 8000, {}),
		mk_q.call("sell20k", "بِع غنائم بقيمة 20,000", QuestData.Objective.SELL_LOOT, 20000, 0, 6000, {"document": 1}),
		mk_q.call("launder50k", "اغسل 50,000", QuestData.Objective.LAUNDER_CASH, 50000, 0, 5000, {}),
		mk_q.call("extract30k", "أخرج غنائم بقيمة 30,000 من مدينة السطو", QuestData.Objective.EXTRACT_LOOT, 30000, 1, 15000, {"document": 2}),
		mk_q.call("rob8", "نفّذ 8 عمليات سطو", QuestData.Objective.ROB_TARGETS, 8, 2, 30000, {"decoder": 1}),
		mk_q.call("launder300k", "اغسل 300,000", QuestData.Objective.LAUNDER_CASH, 300000, 3, 60000, {"decoder_epic": 1}),
	]
	var mk_s := func(id: String, title: String, price: int, secs: int, auth: int, excl: String, contents: Dictionary) -> ShipmentData:
		var s := ShipmentData.new()
		s.id = id; s.title = title; s.price = price; s.delivery_seconds = secs; s.required_authority = auth; s.exclusive_reward = excl; s.contents = contents
		return s
	shipment_catalog = [
		mk_s.call("tools", "صندوق أدوات", 4000, 300, 0, "", {"lockpick": 3, "drill": 1}),
		mk_s.call("docs", "رزمة وثائق", 15000, 900, 1, "", {"document": 2}),
		mk_s.call("contraband", "صندوق ممنوعات (حصري)", 30000, 1800, 2, "shipment_contraband_crate", {"cargo": 3}),
		mk_s.call("gold_run", "رحلة الذهب (حصري)", 60000, 3600, 3, "shipment_gold_run", {"gold_bar": 6}),
	]


# ---------------------------------------------------------------- وحدة الولاية
func reset_state() -> void:
	stash_cash = 0
	orders = []
	progress = {}
	done = {}
	stash_changed.emit(0)


func to_state_dict() -> Dictionary:
	return {"stash": stash_cash, "orders": orders, "day": quest_day, "quests": active_quests, "progress": progress, "done": done}


func from_state_dict(d: Dictionary) -> void:
	stash_cash = int(d.get("stash", 0))
	orders = d.get("orders", [])
	quest_day = int(d.get("day", -1))
	active_quests = d.get("quests", [])
	progress = d.get("progress", {})
	done = d.get("done", {})
