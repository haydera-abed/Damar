extends Node
## EconomyManager (Autoload): الكاش القذر المحمول، الرصيد البنكي الآمن، طاولة الغسيل، والبيع عند المشترين.
## طاولة الغسيل تُحسب بفارق الوقت الحقيقي (Time.get_unix_time_from_system) فتعمل وأنت خارج اللعبة:
## عند التحميل نحسب ما غُسل منذ آخر تحديث ونبث laundered(amount, true).

signal dirty_cash_changed(amount: int)
signal bank_changed(amount: int)
signal desk_changed(pool: int, rate_per_hour: float, cap: int)
signal laundered(amount: int, offline: bool)
signal tax_paid(settlement_id: String, amount: int)
signal item_sold(item_id: String, count: int, total: int)
signal economy_error(reason: String)

var dirty_cash := 0          # كاش قذر في جيبك/حقيبتك (يُصادر عند الاعتقال)
var bank_balance := 0        # مال نظيف في البنك (لا يُسرق، يُصادر في السجن الفيدرالي فقط)
var desk_pool := 0.0         # كاش قذر موضوع على طاولة الغسيل
var desk_last_unix := 0
var desk_bonus := 0.0        # عدّادات النقود وغيرها (+0.15…)
var fence_bonus := 0.0
## ربط اللعبة ثلاثية الأبعاد: معدّل غسيل خارجي ($/ث) يحسبه نظام المنزل/الأحياء، ودالة ضريبة خارجية.
## يُحفظ المعدّل ليُستخدم في حساب الغسيل أثناء الإغلاق.
var rate_override_per_sec: float = -1.0
var tax_hook: Callable = Callable()

var _tick := 0.0


func _ready() -> void:
	GameState.register_module("economy", self)
	update_desk.call_deferred()   # اللحاق بما غُسل أثناء الإغلاق (بعد تحميل كل الوحدات)


func _process(dt: float) -> void:
	_tick -= dt
	if _tick <= 0.0:
		_tick = 1.0
		update_desk()


# ---------------------------------------------------------------- الكاش والبنك
func add_dirty(amount: int) -> void:
	dirty_cash = maxi(0, dirty_cash + amount)
	dirty_cash_changed.emit(dirty_cash)


func add_bank(amount: int) -> void:
	bank_balance = maxi(0, bank_balance + amount)
	bank_changed.emit(bank_balance)


## تعيين مباشر لمحتوى الطاولة (للربط): يُحسب ما غُسل حتى الآن أولاً حتى لا يُحتسب وقت قديم
func set_desk_pool(v: float) -> void:
	update_desk()
	desk_pool = maxf(0.0, v)
	desk_last_unix = int(Time.get_unix_time_from_system())
	_emit_desk()


## يدفع من الكاش القذر أولاً ثم من البنك (إن سُمح)
func spend(amount: int, allow_bank := true) -> bool:
	if amount <= 0:
		return true
	var available := dirty_cash + (bank_balance if allow_bank else 0)
	if available < amount:
		economy_error.emit("المال غير كافٍ: تحتاج %d" % amount)
		return false
	var from_cash := mini(dirty_cash, amount)
	add_dirty(-from_cash)
	if amount - from_cash > 0:
		add_bank(-(amount - from_cash))
	return true


# ---------------------------------------------------------------- طاولة الغسيل
func desk_rate() -> float:
	if rate_override_per_sec >= 0.0:
		return rate_override_per_sec * 3600.0
	return Balance.DESK_RATE_PER_HOUR * (1.0 + desk_bonus)


func desk_cap() -> int:
	return Balance.DESK_CAP.get(LandManager.home_level(), 0)


func deposit_to_desk(amount: int) -> bool:
	if not LandManager.has_equipment("laundering_desk"):
		economy_error.emit("تحتاج طاولة غسيل في قاعدتك")
		return false
	if GameState.wanted > 0:
		economy_error.emit("لا يمكنك الإيداع وأنت مطلوب")
		return false
	amount = mini(amount, dirty_cash)
	amount = mini(amount, desk_cap() - int(desk_pool))
	if amount <= 0:
		economy_error.emit("الطاولة ممتلئة أو لا تملك كاشاً")
		return false
	update_desk()
	add_dirty(-amount)
	desk_pool += amount
	desk_last_unix = int(Time.get_unix_time_from_system())
	_emit_desk()
	return true


## يحسب الغسيل بفارق الوقت الحقيقي. now قابل للحقن (للاختبار ولمحاكاة الإغلاق)
func update_desk(now := -1) -> int:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	if desk_pool <= 0.0 or desk_last_unix <= 0:
		desk_last_unix = now
		return 0
	var elapsed := maxi(0, now - desk_last_unix)
	desk_last_unix = now
	if elapsed == 0:
		return 0
	var amount := minf(desk_pool, desk_rate() * elapsed / 3600.0)
	desk_pool -= amount
	var tax: float = float(tax_hook.call(amount)) if tax_hook.is_valid() else LandManager.settlement_tax(amount)
	add_bank(int(round(amount - tax)))
	if tax > 0.0:
		tax_paid.emit(LandManager.home_settlement_id(), int(tax))
	laundered.emit(int(amount), elapsed > 5)
	_emit_desk()
	return int(amount)


func _emit_desk() -> void:
	desk_changed.emit(int(desk_pool), desk_rate(), desk_cap())


# ---------------------------------------------------------------- مركز المبيعات (المشترون)
func sell_item(item_id: String, count := -1) -> int:
	if TravelManager.current_hub != TravelManager.Hub.SALES_CENTER:
		economy_error.emit("البيع يتم في مركز المبيعات فقط")
		return 0
	var have := GameState.item_count(item_id)
	count = have if count < 0 else mini(count, have)
	var unit := ItemDB.value(item_id)
	if count <= 0 or unit <= 0:
		economy_error.emit("لا شيء يُباع")
		return 0
	GameState.remove_item(item_id, count)
	var total := int(unit * count * (1.0 + fence_bonus))
	add_dirty(total)
	item_sold.emit(item_id, count, total)
	return total


func sell_all_loot() -> int:
	var total := 0
	for id in GameState.inventory.keys():
		if ItemDB.value(id) > 0:
			total += sell_item(id)
	return total


## الاعتقال العادي: الشرطة تصادر الحقيبة فقط (الكاش المحمول والمسروقات «الساخنة»)
func confiscate_carried() -> int:
	var lost := dirty_cash
	add_dirty(-dirty_cash)
	for id in GameState.inventory.keys():
		if ItemDB.is_hot(id):
			lost += ItemDB.value(id) * GameState.item_count(id)
			GameState.remove_item(id, GameState.item_count(id))
	return lost


## قيمة كل ما يملكه اللاعب في الولاية (للسجن الفيدرالي)
func total_wealth() -> int:
	var v := dirty_cash + bank_balance + int(desk_pool)
	for id in GameState.inventory:
		v += ItemDB.value(id) * GameState.item_count(id)
	return v


# ---------------------------------------------------------------- وحدة الولاية
func reset_state() -> void:
	dirty_cash = 0
	bank_balance = 0
	desk_pool = 0.0
	desk_last_unix = 0
	desk_bonus = 0.0
	dirty_cash_changed.emit(0)
	bank_changed.emit(0)
	_emit_desk()


func to_state_dict() -> Dictionary:
	return {"dirty": dirty_cash, "bank": bank_balance, "desk": desk_pool, "desk_t": desk_last_unix, "bonus": desk_bonus, "rate": rate_override_per_sec}


func from_state_dict(d: Dictionary) -> void:
	dirty_cash = int(d.get("dirty", 0))
	bank_balance = int(d.get("bank", 0))
	desk_pool = float(d.get("desk", 0.0))
	desk_last_unix = int(d.get("desk_t", 0))
	desk_bonus = float(d.get("bonus", 0.0))
	rate_override_per_sec = float(d.get("rate", -1.0))
