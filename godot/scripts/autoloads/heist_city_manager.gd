extends Node
## HeistCityManager (Autoload): مدينة السطو «ميناء سافيرن» — المقابل الأصلي لـ Looty Bay في ROB RUN.
## أربعة أحياء: وسط المدينة (Downtown)، الشاطئ المشمس (Sunny Beach)، حي الحديقة (Parkside)،
## وتلال الأرز (اسم أصلي بدل Loraine Hills). في كل حي مبانٍ قابلة للسطو وسيارات تهريب.
##
## دورة السطو والهروب:
##   1) ادخل المدينة (TravelManager) والبس القناع (set_masked).
##   2) start_heist(): يستهلك الأداة، يرفع الإنذار؛ الأهداف الكبرى تطلق city_alarm_triggered للمدينة كلها.
##   3) الغنائم تدخل bag_inventory (غير مؤمّنة).
##   4) extract_loot(): عند سيارة تهريب (ثبات EXTRACTION_HOLD ثوانٍ) أو عند الخروج من المدينة ← تُنقل إلى المخزون الآمن.
##   5) on_player_busted_or_killed(): إن كنت مقنّعاً داخل المدينة تُمسح الحقيبة كلها؛ بلا قناع لم يتعرّف عليك أحد فتبقى.

signal entered_city
signal left_city
signal mask_changed(is_masked: bool)
signal wanted_state_changed(is_wanted: bool)
signal heist_started(target_id: String, duration: float)
signal heist_progress(target_id: String, ratio: float)
signal heist_completed(target_id: String, loot: Dictionary)
signal heist_failed(target_id: String, reason: String)
signal alarm_raised(level: int, district: String)
signal city_alarm_triggered(target_id: String, district: String)
signal police_arrived(district: String)
signal bag_changed(bag: Dictionary, value: int)
signal extraction_started(point_id: String, seconds: float)
signal extraction_progress(point_id: String, ratio: float)
signal extracted(items: Dictionary, value: int)
signal loot_lost(value: int)

const DISPLAY_NAME: String = "ميناء سافيرن"
const CITY_ALARM_WANTED: int = 4                # مستوى المطلوبية الفوري عند الإنذار العام
const UNMASKED_EXTRA_WANTED: int = 1            # السطو بلا قناع: الكاميرات تتعرّف عليك

var districts: Array[CityDistrictData] = []
var fence_cars: Dictionary = {}                 # car_id -> {name, district}
var is_masked: bool = false
var bag_inventory: Dictionary = {}              # item_id -> عدد (غير مؤمّنة)
var is_wanted: bool:
	get:
		return GameState.wanted > 0
var city_alarm: bool = false
var cooldowns: Dictionary = {}                  # target_id -> unix
var active: Dictionary = {}                     # {id, t, duration}
var extraction: Dictionary = {}                 # {point, t, sell}
var alarm_level: int = 0
var alarm_district: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## اللعب الجماعي: الخادم يحسم. إن ضُبطت هذه الخطافات تُرسل الطلبات للخادم بدل التنفيذ المحلي
var start_hook: Callable = Callable()      # (target_id) -> طلب بدء
var complete_hook: Callable = Callable()   # (target_id) -> الخادم يرمي الغنائم
var extract_hook: Callable = Callable()    # (point_id, sell) -> الخادم يتحقق ويؤمّن
var _alarm_t: float = 0.0
var _was_wanted: bool = false


func _ready() -> void:
	_build_city()
	GameState.register_module("heist", self)
	TravelManager.travel_finished.connect(_on_travel_finished)
	GameState.wanted_changed.connect(func(level: int) -> void:
		if (level > 0) != _was_wanted:
			_was_wanted = level > 0
			wanted_state_changed.emit(_was_wanted))


func _on_travel_finished(hub: int) -> void:
	if hub == TravelManager.Hub.HEIST_CITY:
		entered_city.emit()


# ---------------------------------------------------------------- الاستعلامات
func in_city() -> bool:
	return TravelManager.current_hub == TravelManager.Hub.HEIST_CITY


func has_unextracted() -> bool:
	return not bag_inventory.is_empty()


func bag_value() -> int:
	var v: int = 0
	for k: String in bag_inventory:
		v += ItemDB.value(k) * int(bag_inventory[k])
	return v


func target(id: String) -> HeistTargetData:
	for d: CityDistrictData in districts:
		var b: HeistTargetData = d.find_building(id)
		if b != null:
			return b
	return null


func district_name(id: String) -> String:
	for d: CityDistrictData in districts:
		if d.id == id:
			return d.display_name
	return id


# ---------------------------------------------------------------- القناع
func set_masked(masked: bool) -> void:
	if masked == is_masked:
		return
	is_masked = masked
	mask_changed.emit(is_masked)


# ---------------------------------------------------------------- السطو
## يعيد "" إن أمكن السطو، وإلا السبب
func check_heist(id: String) -> String:
	var t: HeistTargetData = target(id)
	var why: String = ""
	if t == null:
		why = "هدف غير معروف"
	elif not in_city():
		why = "يجب أن تكون في %s" % DISPLAY_NAME
	elif not active.is_empty():
		why = "أنت تنفّذ عملية بالفعل"
	elif int(cooldowns.get(id, 0)) > int(Time.get_unix_time_from_system()):
		why = "الهدف مغلق مؤقتاً"
	elif t.required_tool != "" and GameState.item_count(t.required_tool) <= 0:
		why = "تحتاج %s" % ItemDB.item_name(t.required_tool)
	return why


func start_heist(id: String) -> bool:
	var why := check_heist(id)
	if why != "":
		heist_failed.emit(id, why)
		return false
	if start_hook.is_valid():
		start_hook.call(id)                     # ننتظر موافقة الخادم ثم begin_heist
		return true
	begin_heist(id)
	return true


## بدء السطو فعلياً (محلياً، أو بعد موافقة الخادم في اللعب الجماعي)
func begin_heist(id: String) -> void:
	var t: HeistTargetData = target(id)
	if t.required_tool != "":
		GameState.remove_item(t.required_tool)
	active = {"id": id, "t": 0.0, "duration": t.duration}
	_raise_alarm(t.alarm_level, t.district)
	if not is_masked:
		GameState.set_wanted(GameState.wanted + UNMASKED_EXTRA_WANTED)    # وجهك مكشوف
	if t.is_major and not city_alarm:
		city_alarm = true
		GameState.set_wanted(maxi(GameState.wanted, CITY_ALARM_WANTED))
		city_alarm_triggered.emit(t.id, t.district)
	heist_started.emit(id, t.duration)


func cancel_heist(reason: String = "توقفت") -> void:
	if active.is_empty():
		return
	var id: String = active.id
	active = {}
	heist_failed.emit(id, reason)


func _process(dt: float) -> void:
	step(dt)


## خطوة زمنية (تُستدعى كل إطار، وقابلة للاستدعاء من الاختبارات)
func step(dt: float) -> void:
	if not active.is_empty():
		active.t += dt
		var r: float = minf(1.0, float(active.t) / float(active.duration))
		heist_progress.emit(active.id, r)
		if r >= 1.0:
			_complete()
	if alarm_level > 0:
		_alarm_t += dt
		if _alarm_t >= Balance.HEIST_ALARM_SECONDS / alarm_level:
			_alarm_t = 0.0
			GameState.set_wanted(maxi(GameState.wanted, alarm_level))
			police_arrived.emit(alarm_district)
	if not extraction.is_empty():
		extraction.t += dt
		var er: float = minf(1.0, float(extraction.t) / Balance.EXTRACTION_HOLD)
		extraction_progress.emit(extraction.point, er)
		if er >= 1.0:
			_secure(extraction.point, bool(extraction.sell))


## رمي الغنائم من جدول الهدف (يستخدمه الخادم أيضاً)
func roll_loot(t: HeistTargetData) -> Dictionary:
	var loot: Dictionary = {}
	for k: String in t.loot_table:
		var pair: Array = t.loot_table[k]
		var n: int = rng.randi_range(int(pair[0]), int(pair[1]))
		if n > 0:
			loot[k] = n
	if rng.randf() < 0.35:
		loot["document"] = int(loot.get("document", 0)) + 1
	return loot


func _complete() -> void:
	var t: HeistTargetData = target(active.id)
	active = {}
	cooldowns[t.id] = int(Time.get_unix_time_from_system() + t.cooldown)
	if complete_hook.is_valid():
		complete_hook.call(t.id)                # الخادم يرمي الغنائم ويرسل الحقيبة (set_bag)
		heist_completed.emit(t.id, {})
		return
	var loot: Dictionary = roll_loot(t)
	for k: String in loot:
		bag_inventory[k] = int(bag_inventory.get(k, 0)) + int(loot[k])
	heist_completed.emit(t.id, loot)
	bag_changed.emit(bag_inventory, bag_value())


func _raise_alarm(level: int, district: String) -> void:
	if level > alarm_level:
		alarm_level = level
		alarm_district = district
		_alarm_t = 0.0
		alarm_raised.emit(level, district)


# ---------------------------------------------------------------- تأمين الغنائم (Extraction)
## method: "fence_car" عند سيارة تهريب (تثبت ثوانٍ، ويمكن البيع فوراً بـ sell=true)
##         "city_exit" عند الخروج من المدينة (فوري؛ TravelManager يرفض الخروج وأنت مطلوب)
func extract_loot(method: String = "fence_car", point_id: String = "", sell: bool = false) -> bool:
	if bag_inventory.is_empty():
		return false
	if method == "city_exit":
		_secure("city_exit", false)
		return true
	if not fence_cars.has(point_id) or not in_city():
		return false
	extraction = {"point": point_id, "t": 0.0, "sell": sell}
	extraction_started.emit(point_id, Balance.EXTRACTION_HOLD)
	return true


func abort_extraction() -> void:
	extraction = {}


## حقيبة يحددها الخادم (اللعب الجماعي)
func set_bag(bag: Dictionary) -> void:
	bag_inventory = {}
	for k: String in bag:
		bag_inventory[k] = int(bag[k])
	bag_changed.emit(bag_inventory, bag_value())


func _secure(point: String, sell: bool) -> void:
	if extract_hook.is_valid():
		extraction = {}
		extract_hook.call(point, sell)          # الخادم يتحقق من الموقع ثم secure_items
		return
	secure_items(bag_inventory.duplicate(), sell, point)


## تأمين عناصر محددة (محلياً، أو بعد تأكيد الخادم)
func secure_items(items: Dictionary, sell: bool, point: String) -> void:
	bag_inventory = items.duplicate()
	var value: int = bag_value()
	if sell:
		EconomyManager.add_dirty(value)                       # سيارة التهريب تشتري فوراً
		for k: String in bag_inventory:
			if ItemDB.value(k) <= 0:
				GameState.add_item(k, int(bag_inventory[k]))   # الوثائق ونحوها لا تُباع
	else:
		for k: String in bag_inventory:
			GameState.add_item(k, int(bag_inventory[k]))
	bag_inventory = {}
	extraction = {}
	if point != "city_exit":
		alarm_level = 0
		city_alarm = false
		GameState.set_wanted(0)
	extracted.emit(items, value)
	bag_changed.emit(bag_inventory, 0)


# ---------------------------------------------------------------- المخاطرة: القبض أو الموت
## مقنّع داخل المدينة ← تُمسح الحقيبة كلها. بلا قناع (لم يتعرّف عليك أحد) ← تبقى.
func on_player_busted_or_killed() -> int:
	var lost: int = 0
	if is_masked and in_city():
		lost = bag_value()
		bag_inventory = {}
		if lost > 0:
			loot_lost.emit(lost)
		bag_changed.emit(bag_inventory, 0)
	active = {}
	extraction = {}
	alarm_level = 0
	city_alarm = false
	set_masked(false)
	return lost


## (توافق مع PrisonManager.police_arrest)
func lose_bag() -> int:
	return on_player_busted_or_killed()


func leave_city() -> void:
	if has_unextracted():
		extract_loot("city_exit")
	set_masked(false)
	left_city.emit()


# ---------------------------------------------------------------- بناء المدينة
func _build_city() -> void:
	var mk_t := func(id: String, title: String, district: String, dur: float, tool: String, alarm: int, major: bool, loot: Dictionary, cd: float) -> HeistTargetData:
		var t := HeistTargetData.new()
		t.id = id
		t.title = title
		t.district = district
		t.duration = dur
		t.required_tool = tool
		t.alarm_level = alarm
		t.is_major = major
		t.loot_table = loot
		t.cooldown = cd
		return t
	var mk_d := func(id: String, name: String, buildings: Array, cars: Array) -> CityDistrictData:
		var d := CityDistrictData.new()
		d.id = id
		d.display_name = name
		for b: HeistTargetData in buildings:
			d.buildings.append(b)
		for c: String in cars:
			d.fence_cars.append(c)
		return d
	districts = [
		mk_d.call("downtown", "وسط المدينة", [
			mk_t.call("dt_jewelry", "محل مجوهرات", "downtown", 7.0, "lockpick", 3, false, {"jewelry": [3, 6]}, 180.0),
			mk_t.call("dt_bank", "خزنة البنك المركزي", "downtown", 14.0, "drill", 5, true, {"cash_bundle": [6, 12], "gold_bar": [1, 3], "deposit_key": [0, 2]}, 600.0),
		], ["fc_downtown_alley"]),
		mk_d.call("sunny_beach", "الشاطئ المشمس", [
			mk_t.call("sb_villa", "فيلا على الشاطئ", "sunny_beach", 9.0, "lockpick", 2, false, {"art": [0, 1], "electronics": [2, 5]}, 240.0),
			mk_t.call("sb_kiosk", "أكشاك الشاطئ", "sunny_beach", 4.0, "", 1, false, {"cash_bundle": [1, 2], "electronics": [1, 2]}, 90.0),
		], ["fc_beach_pier"]),
		mk_d.call("parkside", "حي الحديقة", [
			mk_t.call("pk_gallery", "معرض الحديقة", "parkside", 10.0, "drill", 4, false, {"art": [1, 2]}, 400.0),
			mk_t.call("pk_cafe", "مقهى الحديقة", "parkside", 4.0, "", 1, false, {"cash_bundle": [1, 3]}, 90.0),
		], ["fc_park_garage"]),
		mk_d.call("cedar_hills", "تلال الأرز", [
			mk_t.call("ch_mansion", "قصر التلال", "cedar_hills", 12.0, "drill", 4, true, {"gold_bar": [1, 2], "art": [1, 1], "jewelry": [2, 4]}, 600.0),
			mk_t.call("ch_casino", "كازينو خاص", "cedar_hills", 8.0, "lockpick", 3, false, {"cash_bundle": [3, 6], "document": [0, 1]}, 300.0),
		], ["fc_hills_road"]),
	]
	fence_cars = {}
	for d: CityDistrictData in districts:
		for c: String in d.fence_cars:
			fence_cars[c] = {"name": "سيارة تهريب (%s)" % d.display_name, "district": d.id}


# ---------------------------------------------------------------- وحدة الولاية
func reset_state() -> void:
	bag_inventory = {}
	cooldowns = {}
	active = {}
	extraction = {}
	alarm_level = 0
	city_alarm = false
	is_masked = false


func to_state_dict() -> Dictionary:
	return {"bag": bag_inventory, "cooldowns": cooldowns, "masked": is_masked}


func from_state_dict(d: Dictionary) -> void:
	bag_inventory = d.get("bag", {})
	for k: String in bag_inventory.keys():
		bag_inventory[k] = int(bag_inventory[k])
	cooldowns = d.get("cooldowns", {})
	is_masked = bool(d.get("masked", false))
