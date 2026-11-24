extends Node
## HeistCityManager (Autoload): مدينة السطو «ميناء سافيرن» (المقابل الأصلي لـ Looty Bay).
## 4 أحياء، لكل منها أهداف سطو ونقطة إخراج. الغنائم تبقى «غير مؤمّنة» في حقيبة السطو حتى تُخرجها
## من نقطة إخراج (تثبت عندها ثوانٍ). الإنذار يتصاعد بمرور الوقت حتى تصل الشرطة؛ إن قُبض عليك تفقد ما لم تُخرجه.
## (أحياء المدينة حسب رسالتك: وسط المدينة، الشاطئ المشمس، الحديقة… والرابع افترضته «الميناء» — أرسل بقية الوصف لأعدّله)

signal entered_city
signal heist_started(target_id: String, duration: float)
signal heist_progress(target_id: String, ratio: float)
signal heist_completed(target_id: String, loot: Dictionary)
signal heist_failed(target_id: String, reason: String)
signal alarm_raised(level: int, district: String)
signal police_arrived(district: String)
signal extraction_started(point_id: String, seconds: float)
signal extraction_progress(point_id: String, ratio: float)
signal extracted(items: Dictionary, value: int)
signal loot_lost(value: int)

const DISTRICTS := {
	"downtown": "وسط المدينة",
	"sunny_beach": "الشاطئ المشمس",
	"park": "الحديقة",
	"harbor": "الميناء",
}
const EXTRACTION_POINTS := {
	"ex_tunnel": {"name": "نفق الصرف", "district": "downtown"},
	"ex_pier": {"name": "رصيف القوارب", "district": "sunny_beach"},
	"ex_bridge": {"name": "جسر المشاة", "district": "park"},
	"ex_cargo": {"name": "سفينة الحاويات", "district": "harbor"},
}

var targets: Array[HeistTargetData] = []
var bag := {}                       # غنائم غير مؤمّنة: item_id -> عدد
var cooldowns := {}                 # target_id -> unix
var active := {}                    # {id, t, duration}
var extraction := {}                # {point, t}
var alarm_level := 0
var alarm_district := ""
var _alarm_t := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_targets()
	GameState.register_module("heist", self)
	TravelManager.travel_finished.connect(func(hub): if hub == TravelManager.Hub.HEIST_CITY: entered_city.emit())


func in_city() -> bool:
	return TravelManager.current_hub == TravelManager.Hub.HEIST_CITY


func has_unextracted() -> bool:
	return not bag.is_empty()


func bag_value() -> int:
	var v := 0
	for k in bag:
		v += ItemDB.value(k) * int(bag[k])
	return v


func target(id: String) -> HeistTargetData:
	for t in targets:
		if t.id == id:
			return t
	return null


# ---------------------------------------------------------------- السطو
func start_heist(id: String) -> bool:
	var t := target(id)
	var why := ""
	if t == null:
		why = "هدف غير معروف"
	elif not in_city():
		why = "يجب أن تكون في مدينة السطو"
	elif not active.is_empty():
		why = "أنت تنفّذ عملية بالفعل"
	elif int(cooldowns.get(id, 0)) > int(Time.get_unix_time_from_system()):
		why = "الهدف مغلق مؤقتاً"
	elif t.required_tool != "" and GameState.item_count(t.required_tool) <= 0:
		why = "تحتاج %s" % ItemDB.item_name(t.required_tool)
	if why != "":
		heist_failed.emit(id, why)
		return false
	if t.required_tool != "":
		GameState.remove_item(t.required_tool)
	active = {"id": id, "t": 0.0, "duration": t.duration}
	_raise_alarm(t.alarm_level, t.district)
	heist_started.emit(id, t.duration)
	return true


func cancel_heist(reason := "توقفت") -> void:
	if active.is_empty():
		return
	var id: String = active.id
	active = {}
	heist_failed.emit(id, reason)


func _process(dt: float) -> void:
	step(dt)


## خطوة زمنية (قابلة للاستدعاء من الاختبارات)
func step(dt: float) -> void:
	if not active.is_empty():
		active.t += dt
		var r: float = minf(1.0, active.t / active.duration)
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
		var er: float = minf(1.0, extraction.t / Balance.EXTRACTION_HOLD)
		extraction_progress.emit(extraction.point, er)
		if er >= 1.0:
			_extract()


func _complete() -> void:
	var t := target(active.id)
	active = {}
	var loot := {}
	for k in t.loot_table:
		var rng_pair: Array = t.loot_table[k]
		var n := rng.randi_range(int(rng_pair[0]), int(rng_pair[1]))
		if n > 0:
			loot[k] = n
			bag[k] = int(bag.get(k, 0)) + n
	if rng.randf() < 0.35:
		bag["document"] = int(bag.get("document", 0)) + 1
		loot["document"] = int(loot.get("document", 0)) + 1
	cooldowns[t.id] = int(Time.get_unix_time_from_system() + t.cooldown)
	heist_completed.emit(t.id, loot)


func _raise_alarm(level: int, district: String) -> void:
	if level > alarm_level:
		alarm_level = level
		alarm_district = district
		_alarm_t = 0.0
		alarm_raised.emit(level, district)


# ---------------------------------------------------------------- الإخراج
func begin_extraction(point_id: String) -> bool:
	if not EXTRACTION_POINTS.has(point_id) or not in_city():
		return false
	if bag.is_empty():
		return false
	extraction = {"point": point_id, "t": 0.0}
	extraction_started.emit(point_id, Balance.EXTRACTION_HOLD)
	return true


func abort_extraction() -> void:
	extraction = {}


func _extract() -> void:
	var items := bag.duplicate()
	var value := bag_value()
	for k in bag:
		GameState.add_item(k, int(bag[k]))
	bag = {}
	extraction = {}
	alarm_level = 0
	GameState.set_wanted(0)
	extracted.emit(items, value)


## القبض عليك في المدينة: تفقد كل ما لم تُخرجه
func lose_bag() -> int:
	var v := bag_value()
	if v > 0:
		loot_lost.emit(v)
	bag = {}
	active = {}
	extraction = {}
	alarm_level = 0
	return v


# ---------------------------------------------------------------- الأهداف
func _build_targets() -> void:
	var mk := func(id: String, title: String, district: String, dur: float, tool: String, alarm: int, loot: Dictionary, cd: float) -> HeistTargetData:
		var t := HeistTargetData.new()
		t.id = id; t.title = title; t.district = district; t.duration = dur; t.required_tool = tool; t.alarm_level = alarm; t.loot_table = loot; t.cooldown = cd
		return t
	targets = [
		mk.call("dt_jewelry", "محل مجوهرات", "downtown", 7.0, "lockpick", 3, {"jewelry": [3, 6]}, 180.0),
		mk.call("dt_bank", "البنك المركزي", "downtown", 14.0, "drill", 5, {"cash_bundle": [6, 12], "gold_bar": [1, 3], "deposit_key": [0, 2]}, 600.0),
		mk.call("sb_villa", "فيلا على الشاطئ", "sunny_beach", 9.0, "lockpick", 2, {"art": [0, 1], "electronics": [2, 5]}, 240.0),
		mk.call("sb_kiosk", "أكشاك الشاطئ", "sunny_beach", 4.0, "", 1, {"cash_bundle": [1, 2], "electronics": [1, 2]}, 90.0),
		mk.call("pk_gallery", "معرض الحديقة", "park", 10.0, "drill", 4, {"art": [1, 2]}, 400.0),
		mk.call("pk_cafe", "مقهى الحديقة", "park", 4.0, "", 1, {"cash_bundle": [1, 3]}, 90.0),
		mk.call("hb_container", "حاوية مهرّبة", "harbor", 8.0, "lockpick", 3, {"cargo": [1, 2], "electronics": [1, 4]}, 300.0),
		mk.call("hb_office", "مكتب الجمارك", "harbor", 11.0, "drill", 4, {"document": [1, 2], "gold_bar": [0, 2]}, 480.0),
	]


# ---------------------------------------------------------------- وحدة الولاية
func reset_state() -> void:
	bag = {}
	cooldowns = {}
	active = {}
	extraction = {}
	alarm_level = 0


func to_state_dict() -> Dictionary:
	return {"bag": bag, "cooldowns": cooldowns}


func from_state_dict(d: Dictionary) -> void:
	bag = d.get("bag", {})
	for k in bag.keys():
		bag[k] = int(bag[k])
	cooldowns = d.get("cooldowns", {})
