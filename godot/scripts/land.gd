class_name Land
extends Node
## الأراضي والمستوطنات (مقتبسة من نظام ROB RUN كما تصفه أدلة اللاعبين):
## - في كل حي مستوطنة من 4 قطع: قطعة المالك (قصر) و3 قطع للإيجار عليها لافتة.
## - وثيقة قطعة أرض (Land Plot Title) تسمح باستئجار قطعة واحدة في مستوطنة لها مالك، في حي من نفس المستوى.
## - وثيقة مستوطنة (Settlement Title) تسمح بشراء مستوطنة: بلا مالك، أو تملكها عصابة في حيّ استوليت عليه.
## - الوثائق تُشترى من السوق السوداء. وثائق المستوى 1 تُدفع «مستندات» تجدها في السرقات (تحديث 4 نوفمبر)،
##   ووثائق م2 وم3 بالمال. وثيقة قطعة م3 لا تُشترى إلا إن كنت تسكن مستوطنة م2.
## - مالك المستوطنة يأخذ ضريبة من غسيل سكانها (5%/7%/10% حسب المستوى) ويجمعها من لافتة قصره.
## - قاعدتك تنتقل إلى قطعتك: نظام أمان + صمامات إلكترونية (كل صمام يتطلب جهاز فك شفرة إضافياً)،
##   جهاز إنذار ينبّهك عند الاقتحام، وخزنة تحمي الرفوف (إلا من مفتاح رئيسي).
## - المداهمة الفيدرالية تصادر كل الأراضي والوثائق والمستندات.

const PLOTS := 4                         # القطعة 0 للمالك
const PLOT_TITLE := [{}, {"docs": 3}, {"price": 150000}, {"price": 500000}]
const SETTLE_TITLE := [{}, {"docs": 8}, {"price": 400000}, {"price": 1200000}]
const TENANT_TAX := [0.0, 0.05, 0.07, 0.10]
const NPC_TAX := [0, 700, 1600, 3500]    # ما يدفعه كل ساكن (كمبيوتر) لمالك المستوطنة كل دورة ضرائب
const TAX_PERIOD := 120.0
const SECURITY_COST := 30000
const FUSE_COST := 20000
const MAX_FUSES := 5
const ALARM_COST := 15000
const SAFE_COST := 40000
const SETTLE_NAMES := ["مستوطنة المرفأ", "مستوطنة الياسمين", "مستوطنة المصانع", "مستوطنة البحر", "مستوطنة القصر", "مستوطنة الذهب", "مستوطنة القطارات", "مستوطنة الصنوبر", "مستوطنة النهر"]
const NPC_NAMES := ["أبو خليل", "سامر", "نور", "رامي", "ليلى", "حمدي", "جواد", "منى", "كريم", "تيم", "سلمى", "زياد", "هالة", "وسيم", "باسل", "ديما"]

var game: Node
var settlements: Array = []      # {name, district, level, center, owner(-1 بلا مالك، 0 أنت، 1..3 عصابة)، owner_name, plots, tax_box, label}
var docs := 0
var plot_titles := [0, 0, 0, 0]  # حسب المستوى
var settle_titles := [0, 0, 0, 0]
var home := Vector2i(-1, -1)     # (المستوطنة، القطعة)
var security := false
var fuses := 0
var alarm := false
var safe := false
var _tax_t := TAX_PERIOD
var _tax_acc := 0.0
var _tenant_t := 150.0
var _root: Node3D
var _rng := RandomNumberGenerator.new()
var _house_mats: Array[StandardMaterial3D] = []


func _init(g: Node) -> void:
	game = g


# ---------------------------------------------------------------- البناء
func setup() -> void:
	_rng.seed = 7741
	_root = Node3D.new()
	_root.name = "Land"
	game.city.add_child(_root)
	for c in [Color("b9ab92"), Color("8f9aa3"), Color("c7b39a"), Color("9c8f7f"), Color("a7b0a0")]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_house_mats.append(m)
	var blocks: Array = game.city.settlement_blocks.duplicate()
	blocks.sort_custom(func(a, b): return a.district < b.district)
	for b in blocks:
		_make_settlement(b)
	_initial_owners()


func _make_settlement(b: Dictionary) -> void:
	var d: int = b.district
	var lvl: int = Gangs.LEVEL[d]
	var c: Vector3 = b.center
	var s := {"name": SETTLE_NAMES[d], "district": d, "level": lvl, "center": c, "owner": -1, "owner_name": "", "plots": [], "tax_box": 0}
	# أرضية ترابية/حصى للمستوطنة كلها
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color("3a342b")
	dirt.roughness = 1.0
	var g := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(Cfg.BLOCK - 8.0, 0.06, Cfg.BLOCK - 8.0)   # يبقى رصيف حول المستوطنة
	g.mesh = gm
	g.material_override = dirt
	g.position = c + Vector3(0, 0.18, 0)
	_root.add_child(g)
	var quads := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	for k in PLOTS:
		var q: Vector2i = quads[k]
		var pos := c + Vector3(q.x * 12.0, 0.15, q.y * 12.0)
		var sign_pos := c + Vector3(q.x * 23.2, 0.15, q.y * 12.0)
		var plot := {"pos": pos, "sx": q.x, "sign": sign_pos, "tenant": "", "house": null, "label": null}
		if k != 0:
			_fence(pos, q.x)
		plot.label = game.crime._label("", Color.WHITE, sign_pos + Vector3(0, 3.1, 0), 64)
		plot.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sign_post(sign_pos, q.x)
		game.city._zone_ring(sign_pos, Color("ffd36b") if k == 0 else Color("e6e6e6"), 0.9, 1.15)
		s.plots.append(plot)
		if k == 0:
			_build_house(plot, false, true)      # فيلا المالك (تُفتح لمالكها إن جعلها منزله)
	settlements.append(s)


func _fence(pos: Vector3, sx: int) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("5b4630")
	wood.roughness = 0.95
	for side in 4:
		var n := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][side] as Vector3
		if n.x == sx:
			continue                     # جهة الشارع مفتوحة
		var t := Vector3(-n.z, 0, n.x)
		for k in range(-4, 5):
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 1.1, 0.12)
			post.mesh = bm
			post.material_override = wood
			post.position = pos + n * 8.8 + t * (k * 2.1) + Vector3(0, 0.55, 0)
			_root.add_child(post)
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.06, 0.08, 17.6) if absf(n.x) > 0.5 else Vector3(17.6, 0.08, 0.06)
		rail.mesh = rm
		rail.material_override = wood
		rail.position = pos + n * 8.8 + Vector3(0, 0.9, 0)
		_root.add_child(rail)


func _sign_post(p: Vector3, sx: int) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2a2b30")
	m.metallic = 0.6
	m.roughness = 0.4
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 2.4
	post.mesh = cm
	post.material_override = m
	post.position = p + Vector3(-sx * 0.6, 1.2, 0)
	_root.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.9, 1.6)
	board.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("e9e3d2")
	bmat.emission_enabled = true
	bmat.emission = Color("e9e3d2")
	bmat.emission_energy_multiplier = 0.25
	board.material_override = bmat
	board.position = p + Vector3(-sx * 0.6, 2.1, 0)
	_root.add_child(board)


const HOUSE := Vector3(10, 3.2, 9)       # عرض (نحو الشارع) × ارتفاع الطابق × عمق
const VILLA := Vector3(14, 3.4, 13)
const WALL_T := 0.25

var inside_home := false                  # اللاعب داخل منزله الآن (للكاميرا والمطر)
var _menu_ctx := ""


## منزل يمكن دخوله: جدران حقيقية بفتحة باب، باب يُفتح لساكنه فقط، أرضية وسقف وإضاءة داخلية،
## وأثاث يعمل (طاولة الغسيل، الرفوف، الخزنة، لوحة الأمان) في منزلك. الفيلا = قصر مالك المستوطنة.
func _build_house(plot: Dictionary, mine: bool, villa := false) -> void:
	_clear_house(plot)
	var size: Vector3 = VILLA if villa else HOUSE
	var w := size.x
	var hh := size.y
	var d := size.z
	var t := WALL_T
	var h := Node3D.new()
	_root.add_child(h)
	h.position = plot.pos
	var sx: int = plot.sx
	var wall: StandardMaterial3D = _house_mats[_rng.randi() % _house_mats.size()]
	if mine:
		wall = _house_mats[0]
	if villa:
		wall = _mat(Color("d9cdb5"), 0.85)
	var wood := _mat(Color("6b4a2f"), 0.7)
	# الأرضية والسقف
	_hbox(h, Vector3(0, 0.08, 0), Vector3(w, 0.12, d), wood, false)
	_hbox(h, Vector3(0, hh + 0.1, 0), Vector3(w, 0.2, d), wall)
	# الجدران: خلفي، جانبيان، وأمامي بفتحة باب عرضها 1.6 م
	_hbox(h, Vector3(-sx * (w / 2.0 - t / 2.0), hh / 2.0, 0), Vector3(t, hh, d), wall)
	for zs in [-1, 1]:
		_hbox(h, Vector3(0, hh / 2.0, zs * (d / 2.0 - t / 2.0)), Vector3(w, hh, t), wall)
	var seg := (d - 1.6) / 2.0
	for zs in [-1, 1]:
		_hbox(h, Vector3(sx * (w / 2.0 - t / 2.0), hh / 2.0, zs * (0.8 + seg / 2.0)), Vector3(t, hh, seg), wall)
	_hbox(h, Vector3(sx * (w / 2.0 - t / 2.0), (2.4 + hh) / 2.0, 0), Vector3(t, hh - 2.4, 1.6), wall)
	# طابق علوي للفيلا (مصمت) ثم السقف الجملوني
	var top := hh + 0.2
	if villa:
		_hbox(h, Vector3(0, top + 1.6, 0), Vector3(w - 1.0, 3.2, d - 1.0), wall)
		top += 3.2
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 1.0, 2.4, d + 1.0)
	roof.mesh = pm
	roof.material_override = _mat(Color("2f4f7a") if mine else (Color("3b3a36") if villa else Color("6e2f22")), 0.8)
	roof.position = Vector3(0, top + 1.2, 0)
	h.add_child(roof)
	# نوافذ مضاءة على الجدران الجانبية والأمامية (من الخارج)
	var win := _mat(Color(1.0, 0.82, 0.5), 0.3)
	win.emission_enabled = true
	win.emission = Color(1.0, 0.78, 0.45)
	win.emission_energy_multiplier = 1.4
	for zs in [-1, 1]:
		for xo in [-w / 4.0, w / 4.0]:
			_hbox(h, Vector3(xo, 1.9, zs * (d / 2.0 + 0.01)), Vector3(1.3, 1.1, 0.05), win, false)
			if villa:
				_hbox(h, Vector3(xo, hh + 1.9, zs * (d / 2.0 - 0.49)), Vector3(1.3, 1.1, 0.05), win, false)
	for zo in [-d / 4.0 - 0.4, d / 4.0 + 0.4]:
		_hbox(h, Vector3(sx * (w / 2.0 + 0.01), 1.9, zo), Vector3(0.05, 1.1, 1.3), win, false)
	# الباب: مفصل على طرف الفتحة، يدور نحو الخارج عند اقتراب الساكن
	var pivot := Node3D.new()
	pivot.position = Vector3(sx * (w / 2.0 - t / 2.0), 0, -0.8)
	h.add_child(pivot)
	_hbox(pivot, Vector3(0, 1.2, 0.8), Vector3(0.08, 2.35, 1.56), _mat(Color("3b2a1d"), 0.6))
	plot.house = h
	plot.door = pivot
	plot.house_mine = mine
	plot.size = size
	plot.stations = []
	if mine:
		_furnish(plot, h, size)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _hbox(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = Cfg.LAYER_WORLD
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.position = pos
		sb.add_child(cs)
		parent.add_child(sb)
	return mi


## أثاث منزلك: كل قطعة لها نقطة تفاعل (E)
func _furnish(plot: Dictionary, h: Node3D, size: Vector3) -> void:
	var sx: int = plot.sx
	var w := size.x
	var hh := size.y
	var d := size.z
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 1.8
	lamp.omni_range = maxf(w, d)
	lamp.shadow_enabled = false
	lamp.position = Vector3(0, hh - 0.4, 0)
	h.add_child(lamp)
	_hbox(h, Vector3(0, hh - 0.05, 0), Vector3(0.6, 0.08, 0.6), _glow(Color(1.0, 0.9, 0.7)), false)
	_hbox(h, Vector3(sx * 0.6, 0.15, 0), Vector3(3.6, 0.02, 2.6), _mat(Color("7a2630"), 1.0), false)   # سجادة
	var metal := _mat(Color("2b2e33"), 0.35)
	metal.metallic = 0.8
	# طاولة الغسيل عند الجدار الخلفي + رزم المال عليها
	var desk_x := -sx * (w / 2.0 - 1.0)
	_hbox(h, Vector3(desk_x, 0.45, -d / 4.0), Vector3(1.2, 0.9, 2.4), _mat(Color("4b3a2a"), 0.6))
	_hbox(h, Vector3(desk_x + sx * 0.1, 0.98, -d / 4.0 - 0.6), Vector3(0.5, 0.16, 0.4), _glow(Color(0.3, 1.0, 0.5), 0.6), false)  # آلة عدّ النقود
	var money: Array = []
	for k in 6:
		var m := _hbox(h, Vector3(desk_x + (k % 2) * 0.3 - 0.15, 0.98 + (k / 2) * 0.11, -d / 4.0 + 0.3), Vector3(0.26, 0.1, 0.5), _mat(Color("4f8a4a"), 0.8), false)
		money.append(m)
	plot.money = money
	plot.stations.append({"kind": "desk", "pos": h.position + Vector3(desk_x + sx * 1.3, 0, -d / 4.0)})
	# الرفوف على الجدار الجانبي + صناديق الغنائم
	var rz := d / 2.0 - 0.55
	_hbox(h, Vector3(-sx * 0.5, 1.0, rz), Vector3(3.2, 2.0, 0.6), metal)
	var items: Array = []
	for row in 3:
		_hbox(h, Vector3(-sx * 0.5, 0.35 + row * 0.62, rz - 0.31), Vector3(3.2, 0.05, 0.05), metal, false)
		for k in 5:
			var b := _hbox(h, Vector3(-sx * 0.5 + (k - 2) * 0.6, 0.55 + row * 0.62, rz - 0.38), Vector3(0.45, 0.34, 0.3), _mat(Color("8a6f45"), 0.9), false)
			items.append(b)
	plot.rack_items = items
	plot.stations.append({"kind": "racks", "pos": h.position + Vector3(-sx * 0.5, 0, rz - 1.3)})
	# الخزنة (تظهر بعد شرائها)
	var safe_mesh := _hbox(h, Vector3(-sx * (w / 2.0 - 0.8), 0.55, rz - 0.2), Vector3(0.9, 1.1, 0.9), metal, false)
	plot.safe_mesh = safe_mesh
	plot.stations.append({"kind": "safe", "pos": h.position + Vector3(-sx * (w / 2.0 - 0.8), 0, rz - 1.3)})
	# لوحة نظام الأمان بجوار الباب (ضوء أخضر = محمي، أحمر = بلا أمان)
	var led := _glow(Color.RED)
	_hbox(h, Vector3(sx * (w / 2.0 - 0.3), 1.45, -1.7), Vector3(0.06, 0.55, 0.4), metal, false)
	_hbox(h, Vector3(sx * (w / 2.0 - 0.34), 1.6, -1.7), Vector3(0.04, 0.08, 0.2), led, false)
	plot.led = led
	plot.stations.append({"kind": "panel", "pos": h.position + Vector3(sx * (w / 2.0 - 1.1), 0, -1.7)})
	# أريكة وطاولة صغيرة
	_hbox(h, Vector3(sx * 0.9, 0.38, -d / 2.0 + 0.75), Vector3(2.4, 0.75, 0.9), _mat(Color("394a63"), 0.9))
	_hbox(h, Vector3(sx * 0.9, 0.25, -d / 2.0 + 2.0), Vector3(1.2, 0.5, 0.6), _mat(Color("5a4330"), 0.6))
	_update_interior(plot)


func _glow(c: Color, e := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## يعكس حالة قاعدتك داخل المنزل: رزم المال، الغنائم على الرفوف، الخزنة، لون لوحة الأمان
func _update_interior(plot: Dictionary) -> void:
	if not plot.get("house_mine", false) or plot.house == null:
		return
	var pool: float = game.crime.launder_pool
	var n_money := 0 if pool <= 0.0 else clampi(int(ceil(pool / 20000.0)), 1, 6)
	for i in plot.money.size():
		plot.money[i].visible = i < n_money
	var n_items: int = game.gangs.stash.size()
	for i in plot.rack_items.size():
		plot.rack_items[i].visible = i < mini(n_items, 15)
	plot.safe_mesh.visible = safe
	var c := Color(0.2, 1.0, 0.35) if security else Color(1.0, 0.15, 0.1)
	plot.led.albedo_color = c
	plot.led.emission = c


func _home_plot() -> Dictionary:
	if home.x < 0:
		return {}
	return settlements[home.x].plots[home.y]


func _is_inside(plot: Dictionary, p: Vector3) -> bool:
	if plot.is_empty() or plot.house == null:
		return false
	var size: Vector3 = plot.size
	var l: Vector3 = p - plot.pos
	return absf(l.x) < size.x / 2.0 - 0.1 and absf(l.z) < size.z / 2.0 - 0.1


## الباب والحالة الداخلية (كل إطار فيزيائي)
func _tick_home(dt: float) -> void:
	var p: Vector3 = game.player_pos()
	var hp := _home_plot()
	inside_home = game.player.car == null and _is_inside(hp, p)
	game.cam.indoor = inside_home
	if not hp.is_empty() and hp.house != null:
		var door: Node3D = hp.door
		var door_pos: Vector3 = hp.house.position + door.position
		var near := game.player.car == null and Vector2(p.x - door_pos.x, p.z - door_pos.z).length() < 3.2
		var target: float = hp.sx * PI / 2.0 * 0.95 if near else 0.0
		door.rotation.y = lerp_angle(door.rotation.y, target, minf(1.0, dt * 6.0))
		_update_interior(hp)


func _station_hint() -> String:
	var hp := _home_plot()
	if not inside_home or hp.is_empty():
		return ""
	var p: Vector3 = game.player_pos()
	var e := Input.is_action_just_pressed("interact")
	for st in hp.stations:
		var sp: Vector3 = st.pos
		if Vector2(p.x - sp.x, p.z - sp.z).length() > 1.4:
			continue
		match st.kind:
			"desk":
				if e:
					game.crime.open_laundering()
				return "طاولة الغسيل — اضغط E (قيد الغسيل: %s)" % Cfg.money(int(game.crime.launder_pool))
			"racks":
				if e:
					open_racks()
				return "الرفوف — اضغط E (%d/%d غنيمة)" % [game.gangs.stash.size(), Gangs.STASH_CAP]
			"safe":
				if not safe:
					return "مكان الخزنة — اشترِها من لوحة الأمان عند الباب"
				return "🗄 الخزنة تحمي الرفوف من المقتحمين (إلا من مفتاح رئيسي)"
			"panel":
				if e:
					open_panel()
				return "لوحة نظام الأمان — اضغط E (%s)" % ("محمي" if security else "بلا حماية")
	return "منزلك — اقترب من طاولة الغسيل أو الرفوف أو لوحة الأمان"


func open_racks() -> void:
	var gg: Gangs = game.gangs
	var cr: Crime = game.crime
	var sellable := cr.bag.filter(func(i): return i.kind != "deposit_key")
	var items: Array = [
		{"text": "خزّن الغنائم على الرفوف (%d غنيمة)" % sellable.size(), "enabled": not sellable.is_empty() and gg.stash.size() < Gangs.STASH_CAP, "cb": func(): gg._stash_bag(); open_racks()},
		{"text": "خذ الغنائم إلى الحقيبة (%d · %s)" % [gg.stash.size(), Cfg.money(gg.stash_value())], "enabled": not gg.stash.is_empty() and cr.bag.size() < Crime.BAG_SLOTS, "cb": func(): gg._take_stash(); open_racks()},
	]
	game.hud.open_menu("الرفوف", "%d/%d غنيمة · قيمتها %s%s" % [gg.stash.size(), Gangs.STASH_CAP, Cfg.money(gg.stash_value()), " · 🗄 محمية بخزنة" if safe else ""], items)


func open_panel() -> void:
	_menu_ctx = "panel"
	var items: Array = security_items()
	items.append_array(home_items())
	game.hud.open_menu("لوحة نظام الأمان", security_text() + base_subtitle(), items)


func _clear_house(plot: Dictionary) -> void:
	if plot.house != null and is_instance_valid(plot.house):
		plot.house.queue_free()
	plot.house = null


func _initial_owners() -> void:
	for s in settlements:
		var gang: int = game.gangs.owner_of[s.district]
		# بعض المستوطنات بلا مالك (يمكن شراؤها بوثيقة مستوطنة)، والباقي تملكه عصابة الحي
		s.owner = -1 if gang == 0 or _rng.randf() < 0.25 else gang
		s.owner_name = ""
		for k in range(1, PLOTS):
			s.plots[k].tenant = ""
			_clear_house(s.plots[k])
		if s.owner > 0:
			for k in range(1, PLOTS):
				if _rng.randf() < 0.5:
					_set_tenant(s, k, NPC_NAMES[_rng.randi() % NPC_NAMES.size()])
		_refresh(s)


func _set_tenant(s: Dictionary, k: int, who: String) -> void:
	s.plots[k].tenant = who
	if who == "":
		_clear_house(s.plots[k])
	else:
		_build_house(s.plots[k], Vector2i(settlements.find(s), k) == home)
	_refresh(s)


func owner_text(s: Dictionary) -> String:
	if s.owner == 0:
		return "أنت" if s.owner_name == "" else s.owner_name
	if s.owner > 0:
		return "عصابة " + Gangs.GANGS[s.owner].name
	return "بلا مالك"


func _refresh(s: Dictionary) -> void:
	var si := settlements.find(s)
	for k in PLOTS:
		var p: Dictionary = s.plots[k]
		var is_home := Vector2i(si, k) == home
		if p.house != null and p.get("house_mine", false) != is_home:
			_build_house(p, is_home, k == 0)     # أضف الأثاث أو أزله
		var l: Label3D = p.label
		if k == 0:
			l.text = "%s (مستوى %d)\nالمالك: %s" % [s.name, s.level, owner_text(s)]
			l.modulate = Color("ffd36b") * 1.5
		elif p.tenant == "":
			l.text = "للإيجار\nوثيقة قطعة مستوى %d" % s.level if s.owner != -1 else "قطعة فارغة\n(المستوطنة بلا مالك)"
			l.modulate = Color("9dffb0") * 1.4 if s.owner != -1 else Color(0.7, 0.7, 0.7)
		else:
			var mine: bool = Vector2i(settlements.find(s), k) == home
			l.text = "🏠 منزلك" if mine else "منزل %s" % p.tenant
			l.modulate = Color("7fc8ff") * 1.6 if mine else Color(0.9, 0.9, 0.9)


# ---------------------------------------------------------------- الاستعلامات
func base_pos() -> Vector3:
	if home.x >= 0:
		var p: Dictionary = settlements[home.x].plots[home.y]
		return p.sign + Vector3(-p.sx * 4.0, 0, 0)
	return game.city.safe_pos


func home_level() -> int:
	return settlements[home.x].level if home.x >= 0 else 0


func tenant_tax() -> float:
	if home.x < 0:
		return 0.0
	var s: Dictionary = settlements[home.x]
	if s.owner == 0 and (s.owner_name == "" or s.owner_name == game.net.my_name):
		return 0.0
	if s.owner == -1:
		return 0.0
	return TENANT_TAX[s.level]


func pay_tax(amount: float) -> void:
	var s: Dictionary = settlements[home.x]
	if game.net.is_online() and s.owner == 0 and s.owner_name != "":
		_tax_acc += amount                   # الغسيل يتم كل إطار بمبالغ صغيرة: نجمعها ونرسلها دفعات
		if _tax_acc >= 50.0:
			game.net.land_tax(s.owner_name, int(_tax_acc))
			_tax_acc -= int(_tax_acc)


func decoders_needed() -> int:
	return 1 + fuses if security else 0


func security_text() -> String:
	if not security:
		return "🔓 بلا نظام أمان"
	return "🔒 أمان + %d صمام (يحتاج المقتحم %d أجهزة فك شفرة)%s%s" % [fuses, decoders_needed(), " · 🔔 إنذار" if alarm else "", " · 🗄 خزنة" if safe else ""]


func base_title() -> String:
	if home.x >= 0:
		var s: Dictionary = settlements[home.x]
		return "منزلك — %s (مستوى %d)" % [s.name, s.level]
	return "المخبأ (الموتيل)"


func base_subtitle() -> String:
	var t := "\n📄 مستندات: %d · وثائق قطع (مستوى 1/2/3): %d/%d/%d · وثائق مستوطنات: %d/%d/%d" % [docs, plot_titles[1], plot_titles[2], plot_titles[3], settle_titles[1], settle_titles[2], settle_titles[3]]
	if home.x >= 0 and tenant_tax() > 0.0:
		t += "\n🏛 ضريبة مالك المستوطنة: %d%% من غسيلك" % int(tenant_tax() * 100)
	return t


# ---------------------------------------------------------------- عناصر القائمة
func security_items() -> Array:
	var items: Array = []
	if not security:
		items.append({"text": "نظام أمان (يحتاج المقتحم جهاز فك شفرة) — %s" % Cfg.money(SECURITY_COST), "enabled": game.bank >= SECURITY_COST, "cb": _buy.bind("security", SECURITY_COST)})
	elif fuses < MAX_FUSES:
		items.append({"text": "صمام إلكتروني %d/%d (+1 جهاز فك شفرة مطلوب) — %s" % [fuses + 1, MAX_FUSES, Cfg.money(FUSE_COST)], "enabled": game.bank >= FUSE_COST, "cb": _buy.bind("fuse", FUSE_COST)})
	if not alarm:
		items.append({"text": "جهاز إنذار (ينبّهك فور بدء الاقتحام) — %s" % Cfg.money(ALARM_COST), "enabled": game.bank >= ALARM_COST, "cb": _buy.bind("alarm", ALARM_COST)})
	if not safe:
		items.append({"text": "خزنة للرفوف (لا يفتحها إلا مفتاح رئيسي) — %s" % Cfg.money(SAFE_COST), "enabled": game.bank >= SAFE_COST, "cb": _buy.bind("safe", SAFE_COST)})
	return items


func home_items() -> Array:
	if home.x < 0:
		return []
	return [{"text": "اترك قطعتك في %s (تفقد الوثيقة ويُهدم المنزل)" % settlements[home.x].name, "enabled": true, "cb": _leave_plot}]


func _buy(what: String, cost: int) -> void:
	if game.bank < cost:
		return
	game.bank -= cost
	match what:
		"security": security = true
		"fuse": fuses += 1
		"alarm": alarm = true
		"safe": safe = true
	game.sfx.cash()
	game.save_game()
	if inside_home:
		open_panel()
	else:
		game.gangs.open_base()


func _leave_plot() -> void:
	var s: Dictionary = settlements[home.x]
	var k := home.y
	home = Vector2i(-1, -1)
	if k == 0:
		pass                              # القصر يبقى لك ما دمت تملك المستوطنة
	elif game.net.is_online():
		game.net.land_request("leave", settlements.find(s), k)
	else:
		_set_tenant(s, k, "")
	_refresh(s)
	game.hud.toast("تركت قطعتك — قاعدتك عادت إلى المخبأ", Color("ffd36b"))
	game.save_game()
	game.hud.close_menu()


## وثائق السوق السوداء
func market_items() -> Array:
	var items: Array = []
	for lvl in [1, 2, 3]:
		var pt: Dictionary = PLOT_TITLE[lvl]
		var ok := _can_afford(pt)
		var note := ""
		if lvl == 3 and home_level() != 2:
			ok = false
			note = " — تشترط أن تسكن مستوطنة مستوى 2"
		items.append({"text": "📜 وثيقة قطعة أرض مستوى %d — %s (لديك %d)%s" % [lvl, _cost_text(pt), plot_titles[lvl], note], "enabled": ok, "cb": _buy_title.bind("plot", lvl)})
	for lvl in [1, 2, 3]:
		var st: Dictionary = SETTLE_TITLE[lvl]
		items.append({"text": "🏛 وثيقة مستوطنة مستوى %d — %s (لديك %d)" % [lvl, _cost_text(st), settle_titles[lvl]], "enabled": _can_afford(st), "cb": _buy_title.bind("settle", lvl)})
	return items


func _cost_text(c: Dictionary) -> String:
	return "%d مستندات" % c.docs if c.has("docs") else Cfg.money(c.price)


func _can_afford(c: Dictionary) -> bool:
	if c.has("docs"):
		return docs >= c.docs
	return game.cash + game.bank >= c.price


func _buy_title(kind: String, lvl: int) -> void:
	var c: Dictionary = PLOT_TITLE[lvl] if kind == "plot" else SETTLE_TITLE[lvl]
	if not _can_afford(c) or (kind == "plot" and lvl == 3 and home_level() != 2):
		return
	if c.has("docs"):
		docs -= c.docs
	elif not game.crime._pay(c.price):
		return
	if kind == "plot":
		plot_titles[lvl] += 1
	else:
		settle_titles[lvl] += 1
	game.hud.toast("📜 اشتريت وثيقة %s مستوى %d" % ["قطعة أرض" if kind == "plot" else "مستوطنة", lvl], Color("ffd36b"))
	game.sfx.cash()
	game.save_game()
	game.crime.open_market()


## المستندات تأتي من السرقات (أكبر السرقات أكثر حظاً)
func on_robbery(total: int) -> void:
	var chance := clampf(total / 15000.0, 0.2, 1.0)
	var n := 0
	if randf() < chance:
		n += 1
	if total > 30000 and randf() < 0.6:
		n += 1
	if n > 0:
		docs += n
		game.hud.toast("📄 وجدت %d مستند%s بين الغنائم (لديك %d)" % [n, "ين" if n == 2 else "اً", docs], Color("d9c7ff"))


# ---------------------------------------------------------------- التفاعل عند اللافتات
func interact(_dt: float) -> String:
	if game.player.car != null or game.cop.on_duty:
		return ""
	if inside_home:
		return _station_hint()
	var p: Vector3 = game.player_pos()
	for si in settlements.size():
		var s: Dictionary = settlements[si]
		if absf(p.x - s.center.x) > 28.0 or absf(p.z - s.center.z) > 28.0:
			continue
		for k in PLOTS:
			var pl: Dictionary = s.plots[k]
			if Vector2(p.x - pl.sign.x, p.z - pl.sign.z).length() > 2.2:
				continue
			return _plot_hint(si, k)
	return ""


func _plot_hint(si: int, k: int) -> String:
	var s: Dictionary = settlements[si]
	var pl: Dictionary = s.plots[k]
	var e := Input.is_action_just_pressed("interact")
	var lvl: int = s.level
	var mine_settle: bool = s.owner == 0 and (s.owner_name == "" or (game.net.is_online() and s.owner_name == game.net.my_name))
	if Vector2i(si, k) == home:
		if e:
			game.gangs.open_base()
		return "منزلك — ادخل من الباب، أو اضغط E للقائمة السريعة"
	if k == 0:
		if mine_settle:
			if e:
				_owner_menu(si)
			return "قصرك في %s — اضغط E (الضرائب: %s)" % [s.name, Cfg.money(s.tax_box)]
		var why := _settle_block_reason(s)
		if why != "":
			return "%s (مستوى %d) · المالك: %s — %s" % [s.name, lvl, owner_text(s), why]
		if e:
			_buy_settlement(si)
		return "اضغط E لشراء %s بوثيقة مستوطنة مستوى %d" % [s.name, lvl]
	if pl.tenant != "":
		return "منزل %s" % pl.tenant
	if s.owner == -1:
		return "لا يمكن الاستئجار في مستوطنة بلا مالك — اشترِها بوثيقة مستوطنة مستوى %d من لافتة القصر" % lvl
	if game.wanted > 0:
		return "لا يمكنك الاستئجار وأنت مطلوب"
	if plot_titles[lvl] <= 0:
		return "قطعة للإيجار — تحتاج وثيقة قطعة أرض مستوى %d من السوق السوداء" % lvl
	if home.x >= 0:
		return "لديك قطعة في %s — اتركها أولاً من قائمة منزلك" % settlements[home.x].name
	if e:
		_rent(si, k)
	return "اضغط E لاستئجار القطعة بوثيقة مستوى %d (ضريبة الغسيل %d%% للمالك)" % [lvl, int(TENANT_TAX[lvl] * 100) if not mine_settle else 0]


func _settle_block_reason(s: Dictionary) -> String:
	if settle_titles[s.level] <= 0:
		return "تحتاج وثيقة مستوطنة مستوى %d" % s.level
	if game.wanted > 0:
		return "لا يمكنك الشراء وأنت مطلوب"
	if s.owner == 0:
		return "يملكها لاعب آخر"
	if s.owner > 0 and not game.gangs.is_mine(s.district):
		return "تملكها عصابة %s — استولِ على حي %s أولاً" % [Gangs.GANGS[s.owner].name, Gangs.DISTRICTS[s.district]]
	return ""


func _rent(si: int, k: int) -> void:
	var s: Dictionary = settlements[si]
	plot_titles[s.level] -= 1
	if game.net.is_online():
		game.net.land_request("rent", si, k)
		return
	home = Vector2i(si, k)
	_set_tenant(s, k, "أنت")
	game.hud.toast("🏠 استأجرت قطعة في %s — بنيت منزلك، وقاعدتك صارت هنا" % s.name, Color("7dff9e"))
	game.sfx.cash()
	game.save_game()


func _buy_settlement(si: int) -> void:
	var s: Dictionary = settlements[si]
	settle_titles[s.level] -= 1
	if game.net.is_online():
		game.net.land_request("buy", si, 0)
		return
	_take_settlement(si, "")


func _take_settlement(si: int, who: String) -> void:
	var s: Dictionary = settlements[si]
	var me: bool = who == "" or (game.net.is_online() and who == game.net.my_name)
	s.owner = 0
	s.owner_name = who
	s.tax_box = 0
	if me:
		# القصر يصبح منزلك (وتترك قطعتك المستأجرة إن وجدت)
		if home.x >= 0 and home.y > 0:
			var old: Dictionary = settlements[home.x]
			if game.net.is_online():
				game.net.land_request("leave", home.x, home.y)
			else:
				_set_tenant(old, home.y, "")
		home = Vector2i(si, 0)
		game.hud.toast("🏛 أصبحت مالك %s! سكانها يدفعون لك ضريبة — اجمعها من لافتة القصر" % s.name, Color("ffd36b"))
		game.sfx.cash()
		game.save_game()
	_refresh(s)


func _owner_menu(si: int) -> void:
	var s: Dictionary = settlements[si]
	var tenants: Array = []
	for k in range(1, PLOTS):
		if s.plots[k].tenant != "":
			tenants.append(s.plots[k].tenant)
	var items: Array = []
	items.append({"text": "اجمع الضرائب (%s) إلى حسابك البنكي" % Cfg.money(s.tax_box), "enabled": s.tax_box > 0, "cb": _collect.bind(si)})
	if home != Vector2i(si, 0):
		items.append({"text": "اجعل القصر منزلك", "enabled": home.x < 0, "cb": _make_home.bind(si)})
	game.hud.open_menu("قصر %s (مستوى %d)" % [s.name, s.level], "السكان (%d/%d): %s\nكل ساكن يدفع %s كل دقيقتين، و%d%% من غسيل اللاعبين" % [tenants.size(), PLOTS - 1, "، ".join(tenants) if not tenants.is_empty() else "لا أحد بعد", Cfg.money(NPC_TAX[s.level]), int(TENANT_TAX[s.level] * 100)], items)


func _make_home(si: int) -> void:
	home = Vector2i(si, 0)
	_refresh(settlements[si])
	game.save_game()
	game.hud.close_menu()


func _collect(si: int) -> void:
	var s: Dictionary = settlements[si]
	game.bank += s.tax_box
	game.hud.toast("💰 جمعت %s ضرائب من %s" % [Cfg.money(s.tax_box), s.name], Color("7dff9e"))
	s.tax_box = 0
	game.sfx.cash()
	game.check_win()
	game.save_game()
	_owner_menu(si)


# ---------------------------------------------------------------- الدورات الزمنية
func tick(dt: float) -> void:
	_tick_home(dt)
	_tax_t -= dt
	if _tax_t <= 0.0:
		_tax_t = TAX_PERIOD
		for s in settlements:
			if s.owner != 0 or (s.owner_name != "" and not (game.net.is_online() and s.owner_name == game.net.my_name)):
				continue
			var n := 0
			for k in range(1, PLOTS):
				var t: String = s.plots[k].tenant
				if t != "" and NPC_NAMES.has(t):
					n += 1
			s.tax_box += n * NPC_TAX[s.level]
	# سكان جدد (كمبيوتر) يستأجرون القطع الفارغة في المستوطنات المملوكة
	if game.net.is_online():
		return
	_tenant_t -= dt
	if _tenant_t <= 0.0:
		_tenant_t = randf_range(120.0, 220.0)
		for si in settlements.size():
			var s: Dictionary = settlements[si]
			if s.owner == -1 or randf() > 0.45:
				continue
			for k in range(1, PLOTS):
				if s.plots[k].tenant == "" and Vector2i(si, k) != home:
					_set_tenant(s, k, NPC_NAMES[randi() % NPC_NAMES.size()])
					if s.owner == 0:
						game.hud.toast("🏠 %s سكن في مستوطنتك %s" % [s.plots[k].tenant, s.name], Color("9dffb0"))
					break


## نتيجة مداهمة عصابة لقاعدتك: أجهزة فك الشفرة ضد الصمامات، والخزنة تحمي الرفوف
func resolve_raid(decoders: int, gang: String) -> void:
	var need := decoders_needed()
	if need > 0 and decoders < need:
		game.hud.toast("🔒 صمد نظام الأمان: عصابة %s احتاجت %d أجهزة فك شفرة ومعها %d" % [gang, need, decoders], Color("7dff9e"))
		return
	var cr: Crime = game.crime
	var lost: float = cr.launder_pool * 0.5
	cr.launder_pool -= lost
	var taken := 0
	var master_key := randf() < 0.25
	if not safe or master_key:
		taken = game.gangs.stash.size() / 2
		for k in taken:
			game.gangs.stash.pop_back()
	var msg := "💥 اخترقت عصابة %s قاعدتك: أخذوا %s من طاولة الغسيل" % [gang, Cfg.money(int(lost))]
	if taken > 0:
		msg += " و%d غنيمة من الرفوف%s" % [taken, " (معهم مفتاح رئيسي فتح الخزنة)" if safe else ""]
	elif safe:
		msg += " — الخزنة حمت الرفوف"
	game.hud.toast(msg + "\nالمال في البنك آمن.", Color("ff6b6b"))


## المداهمة الفيدرالية: مصادرة كل الأراضي والوثائق
func wipe() -> void:
	docs = 0
	plot_titles = [0, 0, 0, 0]
	settle_titles = [0, 0, 0, 0]
	home = Vector2i(-1, -1)
	security = false
	fuses = 0
	alarm = false
	safe = false
	for s in settlements:
		s.tax_box = 0
	_initial_owners()


# ---------------------------------------------------------------- الحفظ
func to_dict() -> Dictionary:
	var owned := []
	for s in settlements:
		var tenants := []
		for k in PLOTS:
			tenants.append(s.plots[k].tenant)
		owned.append({"owner": s.owner, "name": s.owner_name, "tax": s.tax_box, "tenants": tenants})
	return {"docs": docs, "plot_titles": plot_titles, "settle_titles": settle_titles, "home": [home.x, home.y],
		"security": security, "fuses": fuses, "alarm": alarm, "safe": safe, "settlements": owned}


func from_dict(d: Dictionary) -> void:
	docs = d.get("docs", 0)
	plot_titles = d.get("plot_titles", [0, 0, 0, 0])
	settle_titles = d.get("settle_titles", [0, 0, 0, 0])
	var h: Array = d.get("home", [-1, -1])
	home = Vector2i(h[0], h[1])
	security = d.get("security", security)
	fuses = d.get("fuses", fuses)
	alarm = d.get("alarm", false)
	safe = d.get("safe", false)
	var st: Array = d.get("settlements", [])
	if game.net.is_online():
		return                                 # ملكية الأراضي في اللعب الجماعي يحددها الخادم
	for i in mini(st.size(), settlements.size()):
		var s: Dictionary = settlements[i]
		s.owner = st[i].owner
		s.owner_name = st[i].get("name", "")
		s.tax_box = st[i].get("tax", 0)
		for k in range(1, PLOTS):
			var t: String = st[i].tenants[k]
			if t != s.plots[k].tenant:
				_set_tenant(s, k, t)
		_refresh(s)


# ---------------------------------------------------------------- اللعب الجماعي (الخادم يحدد الملكية)
## حالة الأراضي المشتركة: مالك كل مستوطنة (اسم لاعب أو "" = الافتراضي) وساكن كل قطعة
func mp_apply(settle_owner: Array, plot_tenant: Dictionary) -> void:
	for si in settlements.size():
		var s: Dictionary = settlements[si]
		# اللعب الجماعي: لا ملاك ولا سكان من الكمبيوتر — المستوطنة يشتريها لاعب ثم يستأجر الآخرون عنده
		var n: String = settle_owner[si] if si < settle_owner.size() else ""
		s.owner = 0 if n != "" else -1
		s.owner_name = n
		s.tax_box = 0
		for k in range(1, PLOTS):
			var key := "%d:%d" % [si, k]
			var t: String = plot_tenant.get(key, "")
			if t != s.plots[k].tenant:
				_set_tenant(s, k, t)
		_refresh(s)
	# منزلي حسب الخادم
	var mine := Vector2i(-1, -1)
	for si in settlements.size():
		if settlements[si].owner == 0 and settlements[si].owner_name == game.net.my_name:
			mine = Vector2i(si, 0)
	for key in plot_tenant:
		if plot_tenant[key] == game.net.my_name:
			var parts: PackedStringArray = (key as String).split(":")
			mine = Vector2i(int(parts[0]), int(parts[1]))
	home = mine
	for s in settlements:
		_refresh(s)
