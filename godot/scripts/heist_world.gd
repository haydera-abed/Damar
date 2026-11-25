class_name HeistWorld
extends Node
## مدينة السطو في العالم ثلاثي الأبعاد — واجهة مكانية لـ HeistCityManager (طبقة المنطق).
## - المدينة مقسومة إلى 4 أحياء حسب الربع: وسط المدينة، الشاطئ المشمس، حي الحديقة، تلال الأرز.
## - كل هدف في HeistCityManager يُثبَّت على مبنى حقيقي في حيّه (علامة + حلقة؛ الأهداف الكبرى بمنارة حمراء).
## - سيارة تهريب (شاحنة مقفلة) في كل حي: الثبات عندها يؤمّن الغنائم (أو يبيعها فوراً).
## - داخل المدينة = TravelManager.Hub.HEIST_CITY. الخروج منها مشياً/بالسيارة إلى الموتيل أو المنزل أو المشتري يؤمّن الحقيبة
##   (إن لم تكن مطلوباً)، والقبض عليك وأنت مقنّع يمسحها.

const QUADS := {"downtown": Vector2(-1, -1), "sunny_beach": Vector2(1, -1), "parkside": Vector2(-1, 1), "cedar_hills": Vector2(1, 1)}
const RADIUS := 2.4
const HUB_RADIUS := 40.0

var game: Node
var spots := {}                 # target_id -> {pos, ring, label, beacon}
var cars := {}                  # car_id -> {pos, van}
var _district := ""
var _heist_target := ""
var _extract_car := ""


func _init(g: Node) -> void:
	game = g


func setup() -> void:
	var used := {}
	for d: CityDistrictData in HeistCityManager.districts:
		var q: Vector2 = QUADS.get(d.id, Vector2.ONE)
		var cand: Array = game.city.buildings.filter(func(b): return signf(b.center.x) == q.x and signf(b.center.z) == q.y and absf(b.center.x) < Cfg.HALF - 20 and absf(b.center.z) < Cfg.HALF - 20)
		cand.sort_custom(func(a, b): return a.center.length() < b.center.length())
		var k := 0
		for t: HeistTargetData in d.buildings:
			while k < cand.size() and used.has(cand[k].center):
				k += 1
			if k >= cand.size():
				break
			var b: Dictionary = cand[k]
			used[b.center] = true
			var pos: Vector3 = b.center + b.front * (b.half + 2.0)
			pos.y = 0.15
			_make_spot(t, pos, d.display_name)
			k += 3                                  # تباعد بين الأهداف
		for car_id: String in d.fence_cars:
			var node := Cfg.node_pos(Vector2i(3 + int(q.x) * 2, 3 + int(q.y) * 2))
			var cpos := node + Vector3(Cfg.LANE * 1.8, 0, 9.0)
			var van: Car = game._make_car("delivery_van", false, Car.AI.PARKED, Transform3D(Basis(Vector3.UP, 0.0), cpos + Vector3(0, 0.6, 0)))
			van.locked = true
			van.freeze = true
			van.set_paint(Color(0.12, 0.12, 0.14))
			var lbl: Label3D = game.crime._label("🚚 سيارة تهريب\n%s" % d.display_name, Color("b88cff"), cpos + Vector3(0, 3.6, 0), 90)
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			game.city._zone_ring(cpos + Vector3(2.6, 0, 0), Color("b88cff"), 1.6, 2.0)
			cars[car_id] = {"pos": cpos + Vector3(2.6, 0, 0), "van": van}
	HeistCityManager.heist_completed.connect(_on_completed)
	HeistCityManager.heist_failed.connect(func(_t: String, why: String) -> void: game.hud.toast(why, Color("ff9b6b")))
	HeistCityManager.city_alarm_triggered.connect(_on_city_alarm)
	HeistCityManager.extracted.connect(_on_extracted)
	HeistCityManager.loot_lost.connect(func(v: int) -> void: game.hud.toast("💀 كنت مقنّعاً: ضاعت غنائم السطو (%s)" % Cfg.money(v), Color("ff4b4b")))
	HeistCityManager.police_arrived.connect(func(d: String) -> void: game.hud.toast("🚓 وصلت الشرطة إلى %s" % HeistCityManager.district_name(d), Color("ff6b6b")))


func _make_spot(t: HeistTargetData, pos: Vector3, district: String) -> void:
	var col := Color("ff4b4b") if t.is_major else Color("ffb13b")
	var ring: MeshInstance3D = game.city._zone_ring(pos, col, 1.6, 2.0)
	var tool_txt := (" · " + ItemDB.item_name(t.required_tool)) if t.required_tool != "" else ""
	var lbl: Label3D = game.crime._label("%s%s\n%s%s" % ["⚠ " if t.is_major else "", t.title, district, tool_txt], col, pos + Vector3(0, 3.2, 0), 80)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var beacon: MeshInstance3D = null
	if t.is_major:
		beacon = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 50.0
		beacon.mesh = cm
		beacon.material_override = game.city._unshaded(Color(1, 0.25, 0.2), true, 0.25)
		beacon.position = pos + Vector3(0, 25, 0)
		game.city.add_child(beacon)
	spots[t.id] = {"pos": pos, "ring": ring, "label": lbl, "beacon": beacon}


# ---------------------------------------------------------------- الموقع
func district_at(p: Vector3) -> String:
	for id in QUADS:
		var q: Vector2 = QUADS[id]
		if signf(p.x) == q.x and signf(p.z) == q.y:
			return id
	return "downtown"


## أين اللاعب الآن: قرب الموتيل/المنزل/المشتري = خارج المدينة، غير ذلك = داخل مدينة السطو
func hub_at(p: Vector3) -> int:
	if p.distance_to(game.city.safe_pos) < HUB_RADIUS:
		return TravelManager.Hub.MOTEL
	if game.land.home.x >= 0 and p.distance_to(game.land.base_pos()) < 25.0:
		return TravelManager.Hub.HOME
	for f in game.crime.fences:
		if p.distance_to(f) < 25.0:
			return TravelManager.Hub.SALES_CENTER
	return TravelManager.Hub.HEIST_CITY


## اللعب الجماعي: كل خطوات السطو تمر عبر الخادم (net.gd)
func attach_net() -> void:
	HeistCityManager.start_hook = func(id: String) -> void: game.net.heist_request(id)
	HeistCityManager.complete_hook = func(id: String) -> void: game.net.heist_done(id)
	HeistCityManager.extract_hook = func(point: String, sell: bool) -> void: game.net.heist_extract(point, sell)


func detach_net() -> void:
	HeistCityManager.start_hook = Callable()
	HeistCityManager.complete_hook = Callable()
	HeistCityManager.extract_hook = Callable()


func on_approved(target_id: String) -> void:
	_heist_target = target_id
	game.player.robbing = true


func on_server_loot(loot: Dictionary) -> void:
	var parts := []
	for k in loot:
		parts.append("%d %s" % [int(loot[k]), ItemDB.item_name(k)])
	game.hud.toast("💰 في حقيبة السطو (غير مؤمّنة): %s" % "، ".join(parts), Color("ffd36b"))
	game.sfx.cash()


func tick(_dt: float) -> void:
	if game.net.mode == Net.Mode.SERVER or game.cop.on_duty or TravelManager.traveling:
		return
	var p: Vector3 = game.player_pos()
	var hub := hub_at(p)
	if hub != TravelManager.current_hub:
		var was_city := TravelManager.current_hub == TravelManager.Hub.HEIST_CITY
		TravelManager.current_hub = hub as TravelManager.Hub
		if was_city and HeistCityManager.has_unextracted():
			if GameState.wanted == 0:
				HeistCityManager.leave_city()          # خرجت من المدينة بأمان: تأمين الحقيبة
			else:
				game.hud.toast("⚠ خرجت من المدينة وأنت مطلوب — الغنائم غير مؤمّنة حتى تختفي أو تصل سيارة تهريب", Color("ffb36b"))
		elif hub == TravelManager.Hub.HEIST_CITY:
			HeistCityManager.entered_city.emit()
	if hub == TravelManager.Hub.HEIST_CITY:
		var d := district_at(p)
		if d != _district:
			_district = d
			game.hud.toast("📍 %s — %s" % [HeistCityManager.DISPLAY_NAME, HeistCityManager.district_name(d)], Color("9fd0ff"))
	# مغادرة نقطة السطو أو سيارة التهريب تلغي العملية
	if _heist_target != "" and not HeistCityManager.active.is_empty():
		if p.distance_to(spots[_heist_target].pos) > RADIUS + 1.5 or game.player.car != null:
			HeistCityManager.cancel_heist("ابتعدت — توقف السطو")
			_heist_target = ""
	if _extract_car != "" and not HeistCityManager.extraction.is_empty():
		if p.distance_to(cars[_extract_car].pos) > RADIUS + 1.5:
			HeistCityManager.abort_extraction()
			_extract_car = ""
			game.hud.toast("ابتعدت عن سيارة التهريب", Color("ff9b6b"))
	# إظهار الأهداف المغلقة باهتة
	var now := int(Time.get_unix_time_from_system())
	for id in spots:
		var open: bool = int(HeistCityManager.cooldowns.get(id, 0)) <= now
		spots[id].ring.visible = open
		spots[id].label.modulate.a = 1.0 if open else 0.3


## يعيد التلميح ويتعامل مع E
func interact(_dt: float) -> String:
	if game.player.car != null or game.cop.on_duty:
		return ""
	var p: Vector3 = game.player_pos()
	for id in spots:
		var sp: Dictionary = spots[id]
		if p.distance_to(sp.pos) > RADIUS:
			continue
		var t := HeistCityManager.target(id)
		if HeistCityManager.active.get("id", "") == id:
			game.robbing = game.city.stores[0]
			game.rob_prog = float(HeistCityManager.active.t) / float(HeistCityManager.active.duration)
			game.rob_label = "سطو: %s" % t.title
			return ""
		if int(HeistCityManager.cooldowns.get(id, 0)) > int(Time.get_unix_time_from_system()):
			return "%s — مغلق مؤقتاً" % t.title
		if Input.is_action_just_pressed("interact"):
			if HeistCityManager.start_heist(id):
				_heist_target = id
				game.player.robbing = true
			return ""
		var warn := "" if HeistCityManager.is_masked else "  ⚠ بلا قناع (X): الكاميرات ستتعرّف عليك"
		return "اضغط E للسطو على %s%s%s" % [t.title, (" (يحتاج %s)" % ItemDB.item_name(t.required_tool)) if t.required_tool != "" else "", warn]
	for car_id in cars:
		if p.distance_to(cars[car_id].pos) > RADIUS:
			continue
		if not HeistCityManager.has_unextracted():
			return "سيارة تهريب — أحضر غنائم السطو هنا لتأمينها"
		if not HeistCityManager.extraction.is_empty():
			game.robbing = game.city.stores[0]
			game.rob_prog = float(HeistCityManager.extraction.t) / Balance.EXTRACTION_HOLD
			game.rob_label = "تأمين الغنائم…"
			return ""
		if Input.is_action_just_pressed("interact"):
			HeistCityManager.extract_loot("fence_car", car_id, false)
			_extract_car = car_id
			return ""
		if Input.is_action_just_pressed("sell_fence"):
			HeistCityManager.extract_loot("fence_car", car_id, true)
			_extract_car = car_id
			return ""
		return "E: أمّن الغنائم (%s) · B: بِعها فوراً للسائق" % Cfg.money(HeistCityManager.bag_value())
	return ""


# ---------------------------------------------------------------- الإشارات
func _on_completed(target_id: String, loot: Dictionary) -> void:
	_heist_target = ""
	game.player.robbing = false
	if HeistCityManager.complete_hook.is_valid():
		return                                  # الخادم سيرسل الغنائم (on_server_loot)
	var parts := []
	for k in loot:
		parts.append("%d %s" % [int(loot[k]), ItemDB.item_name(k)])
	game.hud.toast("💰 %s — في حقيبة السطو (غير مؤمّنة): %s" % [HeistCityManager.target(target_id).title, "، ".join(parts)], Color("ffd36b"))
	game.sfx.cash()


func _on_city_alarm(target_id: String, district: String) -> void:
	var pos: Vector3 = spots[target_id].pos if spots.has(target_id) else game.player_pos()
	game.alerts.append([pos, 60.0])
	game.hud.toast("📢 إنذار عام في %s! كل الشرطة متجهة إلى %s" % [HeistCityManager.DISPLAY_NAME, HeistCityManager.district_name(district)], Color("ff3b3b"))
	game.sfx.beep(950.0, 0.6)


## الغنائم المؤمّنة تصل المخزون؛ ما يُباع للمشتري ينتقل إلى حقيبة اللعبة (والمستندات تبقى مستندات)
func _on_extracted(items: Dictionary, value: int) -> void:
	_extract_car = ""
	for k in items:
		if k == "document" or ItemDB.value(k) <= 0 and k != "deposit_key":
			continue
		var n: int = GameState.item_count(k)
		GameState.remove_item(k, n)
		if game.net.is_online():
			continue                               # الخادم أضافها لدفترك وسيرسل الحقيبة
		for i in n:
			var kind: String = {"gold_bar": "gold", "cargo": "cargo", "deposit_key": "deposit_key"}.get(k, "heist")
			game.crime.bag.append({"name": ItemDB.item_name(k), "value": ItemDB.value(k), "kind": kind})
	game.hud.toast("🚚 أُمّنت الغنائم (%s) — صارت في حقيبتك، بعها للمشتري أو خزّنها" % Cfg.money(value), Color("7dff9e"))
	game.save_game()
