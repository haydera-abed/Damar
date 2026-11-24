extends Node
## GameState (Autoload): مصدر الحقيقة للحالة العامة.
## - حفظان منفصلان:
##   1) حفظ الولاية (user://core_state.json): العالم، المخزون، وكل وحدات الولاية — يُمسح في المداهمة الفيدرالية.
##   2) الملف الدائم (user://core_profile.json): سنوات السجن، النفوذ، المكافآت — لا يُمسح أبداً.
## - المديرون الآخرون يسجّلون أنفسهم كـ«وحدات» (register_module) ليُحفظوا ويُستعادوا ويُصفَّروا مع الولاية.
## - الواجهة لا تُستدعى من هنا أبداً: كل التغييرات تُبث كإشارات.

signal state_started(state: StateData)
signal state_loaded(state: StateData)
signal state_wiped(reason: String)
signal inventory_changed(item_id: String, count: int)
signal wanted_changed(level: int)
signal profile_changed(profile: Dictionary)
signal federal_raid_due

const STATE_PATH := "user://core_state.json"
const PROFILE_PATH := "user://core_profile.json"
const DEFAULT_STATE := "sahra"

var player_id := "player"
var state: StateData
var inventory := {}                    # item_id -> عدد (خاص بالولاية)
var wanted := 0
var in_prison := false
var profile := {"jail_years": 0, "sentences": 0, "authority": 0, "rewards": [], "visited_states": []}
var persistence := true                # الاختبارات تعطّل الكتابة على القرص
var state_path := STATE_PATH
var profile_path := PROFILE_PATH

var _modules := {}                     # اسم -> كائن فيه to_state_dict/from_state_dict/reset_state
var _pending := {}                     # بيانات وحدات قُرئت قبل تسجيلها
var _raid_check := 0.0
var _autosave := 30.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--core-test" in args:
		persistence = false
	if "--core-persist-test" in args:       # ملفات منفصلة لاختبار الحفظ الحقيقي
		state_path = "user://test_core_state.json"
		profile_path = "user://test_core_profile.json"
	_load_profile()
	if not _load_state():
		start_state(DEFAULT_STATE)


func _process(dt: float) -> void:
	_autosave -= dt
	if _autosave <= 0.0:
		_autosave = 30.0
		save_state()                    # حفظ دوري (يشمل كل الوحدات المسجّلة)
	_raid_check -= dt
	if _raid_check <= 0.0 and state != null and not in_prison:
		_raid_check = 5.0
		if seconds_until_wipe() <= 0:
			federal_raid_due.emit()


# ---------------------------------------------------------------- الوحدات
func register_module(module_name: String, obj: Object) -> void:
	_modules[module_name] = obj
	if _pending.has(module_name):
		obj.from_state_dict(_pending[module_name])
		_pending.erase(module_name)


# ---------------------------------------------------------------- الولاية
func start_state(state_id: String, seed := 0) -> void:
	state = StateFactory.create(state_id, seed)
	inventory = {}
	wanted = 0
	in_prison = false
	_pending = {}
	for m in _modules.values():
		m.reset_state()
	if not profile.visited_states.has(state_id):
		profile.visited_states.append(state_id)
		save_profile()
	save_state.call_deferred()           # بعد أن تسجّل كل الوحدات نفسها
	state_started.emit(state)


## مسح بيانات الولاية بالكامل (يُستدعى عند السجن) — الملف الدائم لا يُمس
func wipe_state(reason: String) -> void:
	inventory = {}
	wanted = 0
	for m in _modules.values():
		m.reset_state()
	state = null
	if persistence and FileAccess.file_exists(state_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(state_path))
	state_wiped.emit(reason)


func seconds_until_wipe() -> int:
	if state == null:
		return 0
	return state.started_at_unix + Balance.WIPE_PERIOD_SEC - int(Time.get_unix_time_from_system())


func set_wanted(level: int) -> void:
	level = clampi(level, 0, 5)
	if level != wanted:
		wanted = level
		wanted_changed.emit(wanted)


# ---------------------------------------------------------------- المخزون
func item_count(id: String) -> int:
	return int(inventory.get(id, 0))


func add_item(id: String, n := 1) -> void:
	inventory[id] = item_count(id) + n
	inventory_changed.emit(id, inventory[id])


func remove_item(id: String, n := 1) -> bool:
	if item_count(id) < n:
		return false
	inventory[id] = item_count(id) - n
	if inventory[id] == 0:
		inventory.erase(id)
	inventory_changed.emit(id, item_count(id))
	return true


func has_items(req: Dictionary) -> bool:
	for k in req:
		if item_count(k) < int(req[k]):
			return false
	return true


# ---------------------------------------------------------------- الحفظ
func save_state() -> void:
	if not persistence or state == null:
		return
	var mods := {}
	for k in _modules:
		mods[k] = _modules[k].to_state_dict()
	var data := {"v": 1, "state": state.to_dict(), "inventory": inventory, "wanted": wanted, "modules": mods}
	var f := FileAccess.open(state_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _load_state() -> bool:
	if not persistence or not FileAccess.file_exists(state_path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(state_path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("state"):
		return false
	state = StateData.from_dict(data.state)
	inventory = data.get("inventory", {})
	for k in inventory.keys():
		inventory[k] = int(inventory[k])
	wanted = int(data.get("wanted", 0))
	_pending = data.get("modules", {})
	for k in _modules.keys():
		register_module(k, _modules[k])
	state_loaded.emit(state)
	return true


func save_profile() -> void:
	profile_changed.emit(profile)
	if not persistence:
		return
	var f := FileAccess.open(profile_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile))


func _load_profile() -> void:
	if not persistence or not FileAccess.file_exists(profile_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if typeof(data) == TYPE_DICTIONARY:
		for k in data:
			profile[k] = data[k]
		profile.jail_years = int(profile.jail_years)
		profile.authority = int(profile.authority)
		profile.sentences = int(profile.sentences)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and state != null:
		save_state()
