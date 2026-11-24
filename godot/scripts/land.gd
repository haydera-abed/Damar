class_name Land
extends Node
## الأراضي والمستوطنات (مقتبسة من نظام ROB RUN كما تصفه أدلة اللاعبين):
## - في كل حي مستوطنة مسوّرة لها بوابة: فيلا المالك و10 قطع للإيجار، على كل قطعة فارغة لافتة إيجار.
## - وثيقة قطعة أرض (Land Plot Title) تسمح باستئجار قطعة واحدة في مستوطنة لها مالك، في حي من نفس المستوى.
## - وثيقة مستوطنة (Settlement Title) تسمح بشراء مستوطنة: بلا مالك، أو تملكها عصابة في حيّ استوليت عليه.
## - الوثائق تُشترى من السوق السوداء. وثائق المستوى 1 تُدفع «مستندات» تجدها في السرقات (تحديث 4 نوفمبر)،
##   ووثائق م2 وم3 بالمال. وثيقة قطعة م3 لا تُشترى إلا إن كنت تسكن مستوطنة م2.
## - مالك المستوطنة يأخذ ضريبة من غسيل سكانها (5%/7%/10% حسب المستوى) ويجمعها من لافتة قصره.
## - قاعدتك تنتقل إلى قطعتك: نظام أمان + صمامات إلكترونية (كل صمام يتطلب جهاز فك شفرة إضافياً)،
##   جهاز إنذار ينبّهك عند الاقتحام، وخزنة تحمي الرفوف (إلا من مفتاح رئيسي).
## - المداهمة الفيدرالية تصادر كل الأراضي والوثائق والمستندات.

const PLOTS := 7                         # القطعة 0 = فيلا المالك، و6 قطع كبيرة للإيجار (15×14 م: منزل + ملحق + فناء)
const PLOT_TITLE := [{}, {"docs": 3}, {"price": 150000}, {"price": 500000}]
const SETTLE_TITLE := [{}, {"docs": 8}, {"price": 400000}, {"price": 1200000}]
const TENANT_TAX := [0.0, 0.05, 0.07, 0.10]
const NPC_TAX := [0, 700, 1600, 3500]    # ما يدفعه كل ساكن (كمبيوتر) لمالك المستوطنة كل دورة ضرائب
const TAX_PERIOD := 120.0
const PLOT_RESEARCH := [0, 15000, 60000, 200000]     # البحث يفتح الوثيقة للشراء (شجرة الشحنات في ROB RUN)
const SETTLE_RESEARCH := [0, 30000, 120000, 400000]
const EVICT_DECODERS := 5                            # حق الطرد: أجهزة فك شفرة + مال
const EVICT_PRICE := 50000
const SECURITY_COST := 30000
const FUSE_COST := 20000
const MAX_FUSES := 5
const ALARM_COST := 15000
const SAFE_COST := 40000
const SETTLE_NAMES := ["مستوطنة المرفأ", "مستوطنة الياسمين", "مستوطنة المصانع", "مستوطنة البحر", "مستوطنة القصر", "مستوطنة الذهب", "مستوطنة القطارات", "مستوطنة الصنوبر", "مستوطنة النهر"]
const NPC_NAMES := ["أبو خليل", "سامر", "نور", "رامي", "ليلى", "حمدي", "جواد", "منى", "كريم", "تيم", "سلمى", "زياد", "هالة", "وسيم", "باسل", "ديما"]

var game: Node
var settlements: Array = []      # {name, district, level, center, owner(-1 بلا مالك، 0 أنت، 1..3 عصابة)، owner_name, plots, tax_box, label}
## المستندات وخزنة الموتيل تعيش في طبقة المنطق (GameState / MotelManager)
var docs: int:
	get:
		return GameState.item_count("document")
	set(v):
		GameState.inventory["document"] = maxi(0, v)
		GameState.inventory_changed.emit("document", maxi(0, v))
var plot_titles := [0, 0, 0, 0]  # حسب المستوى
var settle_titles := [0, 0, 0, 0]
var home := Vector2i(-1, -1)     # (المستوطنة، القطعة)
var security := false
var fuses := 0
var alarm := false
var safe := false                # (قديم) الخزنة صارت أثاثاً في مخطط البناء
var house: House
var _bushes_spawned := false
var pickups: Array = []          # شتلات في الحدائق وشحنات سقطت على الأرض: {pos, node, kind, item, t}
## الأبحاث تعيش في LandManager (طبقة المنطق)
var researched: Dictionary:
	get:
		return LandManager.researched
	set(v):
		LandManager.researched = v
var motel_cash: int:
	get:
		return MotelManager.stash_cash
	set(v):
		MotelManager.stash_cash = maxi(0, v)
		MotelManager.stash_changed.emit(MotelManager.stash_cash)
var eviction_rights := 0
var waypoint := Vector3.INF      # مسار نحو لافتة قطعة اخترتها من خريطة المستوطنة
var _beacon: MeshInstance3D
var _evict := {}                 # اقتحام جارٍ: {si, k, t, need}
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
	house = House.new(self)
	_root = Node3D.new()
	_root.name = "Land"
	game.city.add_child(_root)
	for c in [Color("b9ab92"), Color("8f9aa3"), Color("c7b39a"), Color("9c8f7f"), Color("a7b0a0")]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_house_mats.append(m)
	_beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 60.0
	_beacon.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	_beacon.material_override = bm
	_beacon.visible = false
	_root.add_child(_beacon)
	var blocks: Array = game.city.settlement_blocks.duplicate()
	blocks.sort_custom(func(a, b): return a.district < b.district)
	for b in blocks:
		_make_settlement(b)
	_initial_owners()


## مستوطنة مسوّرة كما في ROB RUN: سور وبوابة على أحد الجوانب، «منزل البداية» (فيلا المالك) في الطرف المقابل،
## و10 قطع حول ساحة وسطى، أبوابها نحو الساحة ولافتة إيجار أمام كل قطعة.
## نمطان للتصميم: البوابة على محور X (النمط أ) أو Z (النمط ب) حسب موقع المستوطنة.
func _make_settlement(b: Dictionary) -> void:
	var d: int = b.district
	var lvl: int = Gangs.LEVEL[d]
	var c: Vector3 = b.center
	var to_center := -c
	var gate := Vector3(signf(to_center.x) if to_center.x != 0.0 else 1.0, 0, 0) if absf(to_center.x) >= absf(to_center.z) else Vector3(0, 0, signf(to_center.z) if to_center.z != 0.0 else 1.0)
	var side := Vector3(-gate.z, 0, gate.x)
	var s := {"name": SETTLE_NAMES[d], "district": d, "level": lvl, "center": c, "owner": -1, "owner_name": "", "plots": [], "tax_box": 0,
		"gate": c + gate * 22.6, "gate_dir": gate, "layout": "أ" if absf(gate.x) > 0.5 else "ب"}
	# الأرضية: ساحة ترابية وممر مرصوف من البوابة إلى الفيلا
	_hbox(_root, c + Vector3(0, 0.18, 0), Vector3(45.0, 0.06, 45.0), _mat(Color("3a342b"), 1.0), false)
	var path_len := 36.0
	_hbox(_root, c + Vector3(0, 0.2, 0) + gate * 4.0, (Vector3(absf(gate.x) * path_len + absf(side.x) * 4.0, 0.05, absf(gate.z) * path_len + absf(side.z) * 4.0)), _mat(Color("6f6a62"), 0.9), false)
	# السور والبوابة
	var wall_m := _mat(Color("8c8172"), 0.95)
	for n in [gate, -gate, side, -side]:
		var t := Vector3(-n.z, 0, n.x)
		var along := Vector3(absf(t.x), 0, absf(t.z))
		var thick := Vector3(absf(n.x), 0, absf(n.z)) * 0.4
		if n == gate:
			for sg in [-1, 1]:
				var seg := 19.6
				_hbox(_root, c + n * 22.6 + t * sg * (3.0 + seg / 2.0) + Vector3(0, 1.3, 0), along * seg + thick + Vector3(0, 2.6, 0), wall_m)
				_hbox(_root, c + n * 22.6 + t * sg * 3.0 + Vector3(0, 1.8, 0), Vector3(0.7, 3.6, 0.7), _mat(Color("5d544a"), 0.8))
		else:
			_hbox(_root, c + n * 22.6 + Vector3(0, 1.3, 0), along * 45.6 + thick + Vector3(0, 2.6, 0), wall_m)
	var gl: Label3D = game.crime._label("%s\n(مستوى %d · النمط %s)" % [s.name, lvl, s.layout], Color("ffd36b"), c + gate * 23.4 + Vector3(0, 4.4, 0), 90)
	gl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 6 قطع كبيرة (3 على كل جانب من الممر)، أبوابها نحو الممر، والفيلا في الطرف المقابل للبوابة
	var inward := -gate
	var slots: Array = [{"c": c + inward * 17.5, "face": gate}]
	for sv in [-1, 1]:
		for u in [-15.0, 0.0, 15.0]:
			slots.append({"c": c + inward * u + side * (sv * 15.5), "face": -side * sv})
	for k in slots.size():
		var face: Vector3 = slots[k].face
		var lat := Vector3(-face.z, 0, face.x)
		var pos: Vector3 = slots[k].c + Vector3(0, 0.15, 0)
		var sign_pos := pos + face * 6.4 + lat * 5.2 if k > 0 else pos + face * 6.2 + lat * 2.6
		var plot := {"pos": pos, "face": face, "lat": lat, "sign": sign_pos, "tenant": "", "house": null, "label": null, "slot": k}
		if k > 0:
			_hbox(_root, pos + Vector3(0, 0.07, 0), Vector3(absf(face.x) * 14.0 + absf(lat.x) * 15.0, 0.05, absf(face.z) * 14.0 + absf(lat.z) * 15.0), _mat(Color("4a4238"), 1.0), false)
			_plot_fence(pos, face, lat)
		plot.label = game.crime._label("", Color.WHITE, sign_pos + Vector3(0, 3.1, 0), 64)
		plot.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sign_post(sign_pos, face)
		game.city._zone_ring(sign_pos, Color("ffd36b") if k == 0 else Color("e6e6e6"), 0.9, 1.15)
		s.plots.append(plot)
		if k == 0:
			_build_house(plot, false, true)      # فيلا المالك (تُفتح لمالكها إن جعلها منزله)
	settlements.append(s)


## سياج منخفض على جانبي القطعة (الواجهة نحو الممر مفتوحة)
func _plot_fence(pos: Vector3, face: Vector3, lat: Vector3) -> void:
	var wood := _mat(Color("5b4630"), 0.95)
	for zs in [-1, 1]:
		var a: Vector3 = pos + lat * float(zs) * 7.45 + Vector3(0, 0.5, 0)
		_hbox(_root, a, Vector3(absf(face.x) * 14.0 + absf(lat.x) * 0.1, 1.0, absf(face.z) * 14.0 + absf(lat.z) * 0.1), wood, false)


func _sign_post(p: Vector3, face: Vector3) -> void:
	var m := _mat(Color("2a2b30"), 0.4)
	m.metallic = 0.6
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 2.4
	post.mesh = cm
	post.material_override = m
	post.position = p + Vector3(0, 1.2, 0)
	_root.add_child(post)
	var bmat := _mat(Color("e9e3d2"), 0.6)
	bmat.emission_enabled = true
	bmat.emission = Color("e9e3d2")
	bmat.emission_energy_multiplier = 0.25
	var tt := Vector3(-face.z, 0, face.x)
	_hbox(_root, p + Vector3(0, 2.1, 0), Vector3(absf(tt.x) * 1.6 + absf(face.x) * 0.06, 0.9, absf(tt.z) * 1.6 + absf(face.z) * 0.06), bmat, false)


const HOUSE := Vector3(7, 3.0, 7)         # عمق (من الباب للخلف) × ارتفاع الطابق × عرض
const VILLA := Vector3(8, 3.4, 10.6)
const WALL_T := 0.25

var inside_home := false                  # اللاعب داخل منزله الآن (للكاميرا والمطر)
var _menu_ctx := ""


## منزل يمكن دخوله: جدران حقيقية بفتحة باب، باب يُفتح لساكنه فقط، أرضية وسقف وإضاءة داخلية،
## وأثاث يعمل (طاولة الغسيل، الرفوف، الخزنة، لوحة الأمان) في منزلك. الفيلا = قصر مالك المستوطنة.
func _build_house(plot: Dictionary, mine: bool, villa := false) -> void:
	_clear_house(plot)
	var size: Vector3 = House.TIER_SIZE[4] if villa else (house.house_size() if mine else House.TIER_SIZE[2])
	var w := size.x
	var hh := size.y
	var d := size.z
	var t := WALL_T
	var h := Node3D.new()
	_root.add_child(h)
	var face: Vector3 = plot.face
	h.position = plot.pos
	if not villa:
		# المنزل في مؤخرة القطعة على جانب، والملحق بجواره، والفناء أمامهما
		h.position = plot.pos + face * (-7.0 + w / 2.0 + 0.3) + plot.lat * (-7.5 + 0.4 + d / 2.0)
	h.rotation.y = atan2(-face.z, face.x)        # المحور المحلي +X = اتجاه الباب
	var sx := 1
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
	if not mine and not villa and _rng.randf() < 0.4:
		# بعض السكان لهم ملحق مغلق (للشكل فقط)
		var ax := Node3D.new()
		_root.add_child(ax)
		ax.rotation.y = h.rotation.y
		ax.position = plot.pos + face * (-7.0 + 3.75 + 0.3) + plot.lat * (7.5 - 0.4 - 2.5)
		_hbox(ax, Vector3(0, 1.5, 0), House.ANNEX_SIZE, _mat(Color("8f8676"), 0.9))
		plot.npc_annex = ax
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
	plot.annex_node = null
	if mine:
		house.furnish(plot, h, size)
		if house.annex != "" and not villa:
			var a := Node3D.new()
			_root.add_child(a)
			a.rotation.y = h.rotation.y
			a.position = plot.pos + face * (-7.0 + House.ANNEX_SIZE.x / 2.0 + 0.3) + plot.lat * (7.5 - 0.4 - House.ANNEX_SIZE.z / 2.0)
			house.build_annex(plot, a)


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


func _glow(c: Color, e := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _home_plot() -> Dictionary:
	if home.x < 0:
		return {}
	return settlements[home.x].plots[home.y]


func _is_inside(plot: Dictionary, p: Vector3) -> bool:
	if plot.is_empty() or plot.house == null:
		return false
	var size: Vector3 = plot.size
	var l: Vector3 = (plot.house as Node3D).transform.affine_inverse() * p
	if absf(l.x) < size.x / 2.0 - 0.1 and absf(l.z) < size.z / 2.0 - 0.1:
		return true
	var a = plot.get("annex_node")
	if a != null and is_instance_valid(a):
		var la: Vector3 = (a as Node3D).transform.affine_inverse() * p
		return absf(la.x) < House.ANNEX_SIZE.x / 2.0 - 0.1 and absf(la.z) < House.ANNEX_SIZE.z / 2.0 - 0.1
	return false


## الباب والحالة الداخلية (كل إطار فيزيائي)
func set_waypoint(si: int, k: int) -> void:
	waypoint = settlements[si].plots[k].sign
	_beacon.position = waypoint + Vector3(0, 30, 0)
	_beacon.visible = true
	game.hud.toast("📍 حُدّد المسار إلى القطعة %d في %s (العلامة الزرقاء)" % [k, settlements[si].name], Color("7fe6ff"))


func _tick_waypoint() -> void:
	if waypoint == Vector3.INF:
		return
	var p: Vector3 = game.player_pos()
	if Vector2(p.x - waypoint.x, p.z - waypoint.z).length() < 2.5:
		waypoint = Vector3.INF
		_beacon.visible = false
		game.hud.toast("وصلت إلى القطعة", Color("7fe6ff"))


func _tick_home(dt: float) -> void:
	_tick_waypoint()
	var p: Vector3 = game.player_pos()
	var hp := _home_plot()
	inside_home = game.player.car == null and _is_inside(hp, p)
	game.cam.indoor = inside_home
	if not hp.is_empty() and hp.house != null:
		var door: Node3D = hp.door
		var door_pos: Vector3 = hp.house.transform * door.position
		var near := game.player.car == null and Vector2(p.x - door_pos.x, p.z - door_pos.z).length() < 3.2
		var target: float = PI / 2.0 * 0.95 if near else 0.0
		door.rotation.y = lerp_angle(door.rotation.y, target, minf(1.0, dt * 6.0))
		house.update_visuals()


func _station_hint() -> String:
	var hp := _home_plot()
	if not inside_home or hp.is_empty():
		return ""
	var p: Vector3 = game.player_pos()
	var e := Input.is_action_just_pressed("interact")
	var best := {}
	var bd := 1.4
	for st in hp.stations:
		var sp: Vector3 = st.pos
		var dd := Vector2(p.x - sp.x, p.z - sp.z).length()
		if dd < bd:
			bd = dd
			best = st
	if not best.is_empty():
		return house.station_hint(best.kind, e)
	return "منزلك — الحاسوب، الإسعافات، مخطط البناء، طاولة الغسيل… اقترب من أي منها"


func open_panel() -> void:
	_menu_ctx = "panel"
	var items: Array = security_items()
	items.append_array(home_items())
	game.hud.open_menu("لوحة نظام الأمان", security_text() + base_subtitle(), items)


func _clear_house(plot: Dictionary) -> void:
	if plot.house != null and is_instance_valid(plot.house):
		plot.house.queue_free()
	plot.house = null
	for key in ["annex_node", "npc_annex"]:
		if plot.get(key) != null and is_instance_valid(plot[key]):
			plot[key].queue_free()
		plot[key] = null


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
	s.plots[k].fuses = randi() % 4 if NPC_NAMES.has(who) else 1
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
		return p.sign
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
	return "🔒 أمان + %d صمام (يحتاج المقتحم %d أجهزة فك شفرة)%s%s" % [fuses, decoders_needed(), " · 🔔 إنذار" if alarm else "", (" · 🗄 خزائن: %d" % house.count("safe")) if house.count("safe") > 0 else ""]


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
	elif fuses < house.max_fuses():
		items.append({"text": "صمام إلكتروني %d/%d (+1 جهاز فك شفرة مطلوب) — %s" % [fuses + 1, house.max_fuses(), Cfg.money(FUSE_COST)], "enabled": game.bank >= FUSE_COST, "cb": _buy.bind("fuse", FUSE_COST)})
	if not alarm:
		items.append({"text": "جهاز إنذار (ينبّهك فور بدء الاقتحام) — %s" % Cfg.money(ALARM_COST), "enabled": game.bank >= ALARM_COST, "cb": _buy.bind("alarm", ALARM_COST)})
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


## موتيل الصحراء (صاحبه «رفيق»): نقطة البداية. يحفظ النقود فقط؛ الغنائم وطاولة الغسيل تحتاج منزلاً.
## خدمات الموتيل الأخرى يديرها MotelManager (طبقة المنطق): المقايضة، المهام اليومية، الشحنات، الروليت.
func open_motel() -> void:
	TravelManager.current_hub = TravelManager.Hub.MOTEL
	var items: Array = [
		{"text": "اترك نقودك عند رفيق (%s) — لا تُصادر عند القبض عليك" % Cfg.money(game.cash), "enabled": game.cash > 0 and game.wanted == 0, "cb": _motel_deposit},
		{"text": "خذ نقودك (%s)" % Cfg.money(motel_cash), "enabled": motel_cash > 0, "cb": _motel_take},
		{"text": "🚪 الباب المريب (مقايضة)", "enabled": true, "cb": open_barter},
		{"text": "📋 مهام اليوم", "enabled": true, "cb": open_quests},
		{"text": "📦 الشحنات", "enabled": true, "cb": open_shipments},
		{"text": "🎰 طاولة الروليت (حد الرهان %s)" % Cfg.money(MotelManager.bet_cap()), "enabled": true, "cb": open_roulette},
		{"text": "اغسل عند رفيق بنصف القيمة: %s ← %s في البنك (حتى $100,000)" % [Cfg.money(mini(game.cash, 100000)), Cfg.money(mini(game.cash, 100000) / 2)], "enabled": game.cash > 0 and game.wanted == 0, "cb": _motel_launder},
	]
	var sub := "محفوظ هنا: %s\nالموتيل يحفظ النقود فقط. لتخزين الغنائم وغسل الأموال تحتاج منزلاً على قطعة أرض:\nابحث عن الوثيقة في السوق السوداء، اشترِها، ثم استأجر قطعة من مستوطنة (L لخريطة المستوطنة)." % Cfg.money(motel_cash)
	if home.x >= 0:
		sub += "\n🏠 منزلك في %s" % settlements[home.x].name
	game.hud.open_menu("موتيل رفيق", sub, items)


## المقايضة: مفاتيح الودائع وسبائك الذهب في الحقيبة تنتقل إلى المخزون لتُستخدم في الوصفات
func open_barter() -> void:
	var cr: Crime = game.crime
	for it in cr.bag.duplicate():
		if it.kind == "deposit_key" or it.kind == "gold":
			cr.bag.erase(it)
			GameState.add_item("deposit_key" if it.kind == "deposit_key" else "gold_bar")
	var items: Array = []
	for r in MotelManager.recipes:
		var parts := []
		for k in r.inputs:
			parts.append("%d %s (معك %d)" % [int(r.inputs[k]), ItemDB.item_name(k), GameState.item_count(k)])
		var locked: bool = r.required_authority > PrisonManager.authority_level()
		items.append({"text": "%s ⇐ %s%s%s" % [r.title, " + ".join(parts), (" + " + Cfg.money(r.cash_cost)) if r.cash_cost > 0 else "", ("  🔒 نفوذ %d" % r.required_authority) if locked else ""],
			"enabled": not locked and GameState.has_items(r.inputs) and game.cash + game.bank >= r.cash_cost, "cb": func() -> void:
				MotelManager.barter(r.id)
				open_barter()})
	items.append({"text": "↩ رجوع", "enabled": true, "cb": open_motel})
	game.hud.open_menu("🚪 الباب المريب", "يقايضك %s على عناصر نادرة. النفوذ يفتح وصفات أكثر (نفوذك: %d)." % [MotelManager.OWNER_NAME, PrisonManager.authority_level()], items)


func open_quests() -> void:
	MotelManager.refresh_daily()
	var items: Array = []
	for qid in MotelManager.active_quests:
		var q: QuestData = MotelManager._quest(qid)
		var prog: int = mini(int(MotelManager.progress.get(qid, 0)), q.target_amount)
		var done: bool = MotelManager.done.get(qid, false)
		items.append({"text": "%s %s — %d/%d · المكافأة %s" % ["✅" if done else "▫", q.title, prog, q.target_amount, Cfg.money(q.reward_cash)], "enabled": false, "cb": func() -> void: pass})
	items.append({"text": "↩ رجوع", "enabled": true, "cb": open_motel})
	game.hud.open_menu("📋 مهام اليوم", "تتجدد كل يوم، وتظهر مهام أصعب مع ارتفاع نفوذك. التقدم يُحتسب تلقائياً.", items)


func open_shipments() -> void:
	var items: Array = []
	var avail := MotelManager.available_shipments()
	for sh in MotelManager.shipment_catalog:
		var ok: bool = avail.has(sh)
		var parts := []
		for k in sh.contents:
			parts.append("%d %s" % [int(sh.contents[k]), ItemDB.item_name(k)])
		items.append({"text": "%s — %s (%s) · تصل بعد %d د%s" % [sh.title, Cfg.money(sh.price), "، ".join(parts), sh.delivery_seconds / 60, "" if ok else "  🔒"], "enabled": ok and game.cash + game.bank >= sh.price, "cb": func() -> void:
			MotelManager.order_shipment(sh.id)
			open_shipments()})
	var pending := []
	for o in MotelManager.orders:
		pending.append("%s (%d ث)" % [o.id, maxi(0, int(o.eta) - int(Time.get_unix_time_from_system()))])
	items.append({"text": "↩ رجوع", "enabled": true, "cb": open_motel})
	game.hud.open_menu("📦 شحنات السوق السوداء", "الشحنات تصل بالوقت الحقيقي (حتى واللعبة مغلقة). بعضها حصري لمكافآت السجن.
في الطريق: %s" % ("، ".join(pending) if not pending.is_empty() else "لا شيء"), items)


func open_roulette() -> void:
	var cap := MotelManager.bet_cap()
	var items: Array = []
	for amount in [1000, 5000, cap]:
		for kind in ["red", "black", "even", "odd"]:
			var label: String = {"red": "أحمر ×2", "black": "أسود ×2", "even": "زوجي ×2", "odd": "فردي ×2"}[kind]
			items.append({"text": "راهن %s على %s" % [Cfg.money(amount), label], "enabled": game.cash >= amount, "cb": func() -> void:
				MotelManager.spin(amount, kind)
				open_roulette()})
	items.append({"text": "راهن %s على الرقم 7 (×36)" % Cfg.money(1000), "enabled": game.cash >= 1000, "cb": func() -> void:
		MotelManager.spin(1000, "number", 7)
		open_roulette()})
	items.append({"text": "↩ رجوع", "enabled": true, "cb": open_motel})
	game.hud.open_menu("🎰 الروليت", "تراهن بالكاش الذي معك (%s). حد الرهان %s ويرتفع مع نفوذك." % [Cfg.money(game.cash), Cfg.money(cap)], items)


func _motel_launder() -> void:
	var amt := mini(game.cash, 100000)
	game.cash -= amt
	game.bank += amt / 2
	game.hud.toast("غسلت %s عند رفيق → %s في البنك" % [Cfg.money(amt), Cfg.money(amt / 2)], Color("7dff9e"))
	game.check_win()
	game.save_game()
	open_motel()


func _motel_deposit() -> void:
	motel_cash += game.cash
	game.cash = 0
	game.save_game()
	open_motel()


func _motel_take() -> void:
	game.cash += motel_cash
	motel_cash = 0
	game.save_game()
	open_motel()


## وثائق السوق السوداء
func market_items() -> Array:
	var items: Array = []
	for kind in ["plot", "settle"]:
		for lvl in [1, 2, 3]:
			if researched.get("%s%d" % [kind, lvl], false):
				continue
			var rc: int = (PLOT_RESEARCH if kind == "plot" else SETTLE_RESEARCH)[lvl]
			items.append({"text": "🔬 بحث: وثيقة %s مستوى %d — %s (يفتحها للشراء)" % ["قطعة أرض" if kind == "plot" else "مستوطنة", lvl, Cfg.money(rc)], "enabled": game.cash + game.bank >= rc, "cb": _research.bind(kind, lvl)})
	items.append({"text": "📜 حق طرد — %d أجهزة فك شفرة + %s (لديك %d، ومعك %d جهاز)" % [EVICT_DECODERS, Cfg.money(EVICT_PRICE), eviction_rights, game.crime.tools.get("decoder", 0)], "enabled": game.crime.tools.get("decoder", 0) >= EVICT_DECODERS and game.cash + game.bank >= EVICT_PRICE, "cb": _buy_eviction})
	for lvl in [1, 2, 3]:
		if not researched.get("plot%d" % lvl, false):
			continue
		var pt: Dictionary = PLOT_TITLE[lvl]
		var ok := _can_afford(pt)
		var note := ""
		if lvl == 3 and home_level() != 2:
			ok = false
			note = " — تشترط أن تسكن مستوطنة مستوى 2"
		items.append({"text": "📜 وثيقة قطعة أرض مستوى %d — %s (لديك %d)%s" % [lvl, _cost_text(pt), plot_titles[lvl], note], "enabled": ok, "cb": _buy_title.bind("plot", lvl)})
	for lvl in [1, 2, 3]:
		if not researched.get("settle%d" % lvl, false):
			continue
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
	if not researched.get("%s%d" % [kind, lvl], false) or not _can_afford(c) or (kind == "plot" and lvl == 3 and home_level() != 2):
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


func _research(kind: String, lvl: int) -> void:
	var cost: int = (PLOT_RESEARCH if kind == "plot" else SETTLE_RESEARCH)[lvl]
	if not game.crime._pay(cost):
		return
	researched["%s%d" % [kind, lvl]] = true
	game.hud.toast("🔬 اكتمل البحث: صار بإمكانك شراء وثيقة %s مستوى %d" % ["قطعة أرض" if kind == "plot" else "مستوطنة", lvl], Color("9fd0ff"))
	game.sfx.cash()
	game.save_game()
	game.crime.open_market()


func _buy_eviction() -> void:
	if game.crime.tools.get("decoder", 0) < EVICT_DECODERS or not game.crime._pay(EVICT_PRICE):
		return
	game.crime.tools["decoder"] -= EVICT_DECODERS
	eviction_rights += 1
	game.hud.toast("📜 حصلت على حق طرد — اقتحم منزل ساكن لتطرده", Color("ffd36b"))
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
	if total > 5000 and randf() < 0.3:
		game.crime.bag.append(house._crate_item())
		game.hud.toast("📦 وجدت شحنة مغلقة — افتحها على طاولة الشحنات أو بعها للمشتري (لا تُشهر سلاحاً وهي معك!)", Color("ffd36b"))
	if total < 8000 and randf() < 0.4:
		house.reagents += 1
		game.hud.toast("⚗ وجدت كاشفاً كيميائياً (لديك %d)" % house.reagents, Color("d9c7ff"))
	if n > 0:
		docs += n
		game.hud.toast("📄 وجدت %d مستند%s بين الغنائم (لديك %d)" % [n, "ين" if n == 2 else "اً", docs], Color("d9c7ff"))


# ---------------------------------------------------------------- التفاعل عند اللافتات
func interact(_dt: float) -> String:
	if game.player.car != null or game.cop.on_duty:
		return ""
	if inside_home:
		return _station_hint()
	var ph := _pickup_hint()
	if ph != "":
		return ph
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
		return _evict_hint(si, k)
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


## اقتحام منزل ساكن وطرده: حق طرد + أجهزة فك شفرة بعدد صماماته + 8 ثوانٍ بينما يدافع عنه حراس
func _evict_hint(si: int, k: int) -> String:
	var s: Dictionary = settlements[si]
	var pl: Dictionary = s.plots[k]
	var need: int = 1 + pl.get("fuses", 0)
	if eviction_rights <= 0:
		return "منزل %s — تحتاج «حق طرد» من السوق السوداء لاقتحامه وطرده" % pl.tenant
	var have: int = game.crime.tools.get("decoder", 0)
	if have < need:
		return "منزل %s — اقتحامه يحتاج %d أجهزة فك شفرة (معك %d)" % [pl.tenant, need, have]
	if Input.is_action_pressed("interact"):
		if _evict.is_empty() or _evict.si != si or _evict.k != k:
			_evict = {"si": si, "k": k, "t": 0.0, "need": need}
			game.gangs._spawn_guards(pl.sign, 1 + randi() % 3, 2)
			game.set_wanted(maxi(game.wanted, 2), "🚨 اقتحام منزل %s!" % pl.tenant)
		_evict.t += get_physics_process_delta_time() / 8.0
		game.robbing = game.city.stores[0]
		game.rob_prog = _evict.t
		game.rob_label = "اقتحام منزل %s (%d أجهزة فك شفرة)" % [pl.tenant, need]
		if _evict.t >= 1.0:
			_do_evict(si, k, need)
		return ""
	_evict = {}
	return "اضغط مطولاً E لاقتحام منزل %s وطرده (حق طرد + %d أجهزة فك شفرة)" % [pl.tenant, need]


func _do_evict(si: int, k: int, need: int) -> void:
	var s: Dictionary = settlements[si]
	var who: String = s.plots[k].tenant
	_evict = {}
	eviction_rights -= 1
	game.crime.tools["decoder"] = game.crime.tools.get("decoder", 0) - need
	var loot: int = randi_range(5000, 20000) * int(s.level)
	game.cash += loot
	if game.net.is_online() and not NPC_NAMES.has(who):
		game.net.land_request("evict", si, k)
	else:
		_set_tenant(s, k, "")
	game.hud.toast("🚪 طردت %s من %s ووجدت %s نقداً على طاولته" % [who, s.name, Cfg.money(loot)], Color("ffd36b"))
	game.save_game()


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
	# جمع الضرائب يُبلَّغ به الجميع: قتلة العصابات ينتظرونك عند البوابة
	if game.net.is_online():
		game.net.land_alert(s.gate, "💰 %s يجمع الضرائب في %s الآن!" % [game.net.my_name, s.name])
	elif not game.cop.on_duty:
		game.gangs._spawn_guards(s.gate - s.gate_dir * 3.0, 1 + randi() % 3, 1 + s.level)
		game.hud.toast("⚠ انتشر خبر جمعك للضرائب — مسلحون ينتظرونك عند بوابة %s" % s.name, Color("ff6b6b"))
	game.alerts.append([s.gate, 40.0])
	_owner_menu(si)


# ---------------------------------------------------------------- الدورات الزمنية
func tick(dt: float) -> void:
	_tick_home(dt)
	house.tick(dt)
	_tick_pickups(dt)
	_tax_t -= dt
	if _tax_t <= 0.0:
		_tax_t = TAX_PERIOD
		for s in settlements:
			if s.owner != 0 or (s.owner_name != "" and not (game.net.is_online() and s.owner_name == game.net.my_name)):
				continue
			if s.tax_box > 0:
				continue                         # كما في ROB RUN: لا ضرائب جديدة حتى تجمع الرصيد الحالي
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
	var extra: String = house.raid_losses(randf() < 0.25)
	var msg := "💥 اخترقت عصابة %s قاعدتك: أخذوا %s من طاولة الغسيل" % [gang, Cfg.money(int(lost))]
	if extra != "":
		msg += " و" + extra
	game.hud.toast(msg + "\nالمال في البنك آمن.", Color("ff6b6b"))


## المداهمة الفيدرالية: مصادرة كل الأراضي والوثائق
func wipe() -> void:
	docs = 0
	researched = {}
	motel_cash = 0
	eviction_rights = 0
	waypoint = Vector3.INF
	if _beacon:
		_beacon.visible = false
	plot_titles = [0, 0, 0, 0]
	settle_titles = [0, 0, 0, 0]
	home = Vector2i(-1, -1)
	security = false
	fuses = 0
	alarm = false
	safe = false
	house.wipe()
	_clear_pickups("cargo")
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
	return {"docs": docs, "researched": researched, "motel": motel_cash, "evict": eviction_rights, "plot_titles": plot_titles, "settle_titles": settle_titles, "home": [home.x, home.y],
		"security": security, "fuses": fuses, "alarm": alarm, "settlements": owned, "house": house.to_dict()}


func from_dict(d: Dictionary) -> void:
	if not game.core_owned:
		docs = d.get("docs", 0)
	if d.has("researched"):                 # حفظ قديم فقط؛ الأبحاث الآن في LandManager
		researched = d.researched
	if not game.core_owned:
		motel_cash = d.get("motel", 0)
	eviction_rights = d.get("evict", 0)
	plot_titles = d.get("plot_titles", [0, 0, 0, 0])
	settle_titles = d.get("settle_titles", [0, 0, 0, 0])
	var h: Array = d.get("home", [-1, -1])
	home = Vector2i(h[0], h[1])
	security = d.get("security", security)
	fuses = d.get("fuses", fuses)
	alarm = d.get("alarm", false)
	house.from_dict(d.get("house", {}))
	if d.get("safe", false) and not house.slots.has("safe"):
		house.slots.append("safe")      # ترحيل: الخزنة القديمة صارت أثاثاً
	if home.y >= PLOTS:
		home = Vector2i(-1, -1)          # حفظ من تصميم أقدم للمستوطنة
	var st: Array = d.get("settlements", [])
	if game.net.is_online():
		return                                 # ملكية الأراضي في اللعب الجماعي يحددها الخادم
	for i in mini(st.size(), settlements.size()):
		var s: Dictionary = settlements[i]
		s.owner = st[i].owner
		s.owner_name = st[i].get("name", "")
		s.tax_box = st[i].get("tax", 0)
		for k in range(1, mini(PLOTS, st[i].tenants.size())):
			var t: String = st[i].tenants[k]
			if t != s.plots[k].tenant:
				_set_tenant(s, k, t)
		_refresh(s)


# ---------------------------------------------------------------- التوحيد مع طبقة المنطق (LandManager / SettlementData)
## الولاية في GameState تُبنى من مستوطنات هذا العالم: 9 مقاطعات بمستوياتها + «الصحراء» (الموتيل) = 10.
## مصدر الحقيقة المحفوظ صار core_state.json (يُمسح مع الولاية في السجن الفيدرالي):
##   - الهيكل (مالك كل مستوطنة، ساكن كل قطعة، ضريبة غير مجموعة، المعدات) ← SettlementData / LandPlotData
##   - منزلك والأبحاث ← LandManager.home_* و researched؛ السندات ← مخزون GameState
##   - بقية تفاصيل العالم (المنزل، الأمان…) ← LandManager.world_data
func settlement_id(si: int) -> String:
	return "w_s%d" % si


func plot_id(si: int, k: int) -> String:
	return "w_s%d_p%d" % [si, k]


func is_world_state(st: StateData) -> bool:
	return st != null and not st.districts.is_empty() and st.districts[0].id.begins_with("w_d")


func build_world_state(state_id: String) -> StateData:
	var st := StateData.new()
	st.id = state_id
	st.display_name = StateFactory.STATE_NAMES.get(state_id, state_id)
	st.started_at_unix = int(Time.get_unix_time_from_system())
	for d in 9:
		var dd := DistrictData.new()
		dd.id = "w_d%d" % d
		dd.display_name = Gangs.DISTRICTS[d]
		dd.level = Gangs.LEVEL[d]
		dd.clan_owner = Gangs.GANGS[game.gangs.owner_of[d]].name if game.gangs.owner_of.size() > d else ""
		for si in settlements.size():
			if settlements[si].district == d:
				dd.settlements.append(_settlement_res(si))
		st.districts.append(dd)
	var desert := DistrictData.new()
	desert.id = "w_d9"
	desert.display_name = "الصحراء (الموتيل)"
	desert.level = 1
	st.districts.append(desert)
	return st


func _settlement_res(si: int) -> SettlementData:
	var s: Dictionary = settlements[si]
	var r := SettlementData.new()
	r.id = settlement_id(si)
	r.display_name = s.name
	r.level = s.level
	r.tax_rate = TENANT_TAX[s.level]
	for k in PLOTS:
		var p := LandPlotData.new()
		p.id = plot_id(si, k)
		r.plots.append(p)
	_mirror_settlement(si, r)
	return r


func _mirror_settlement(si: int, r: SettlementData) -> void:
	var s: Dictionary = settlements[si]
	if s.owner == 0:
		r.owner_type = SettlementData.OwnerType.PLAYER
		r.owner_id = GameState.player_id if s.owner_name == "" else s.owner_name
	elif s.owner > 0:
		r.owner_type = SettlementData.OwnerType.CLAN
		r.owner_id = Gangs.GANGS[s.owner].name
	else:
		r.owner_type = SettlementData.OwnerType.NONE
		r.owner_id = ""
	r.uncollected_tax = int(s.tax_box)
	for k in PLOTS:
		var p: LandPlotData = r.plots[k]
		var t: String = s.plots[k].tenant
		p.tenant_id = GameState.player_id if (t == "أنت" or Vector2i(si, k) == home) and k > 0 else t
		if k == 0 and s.owner == 0 and s.owner_name == "":
			p.tenant_id = GameState.player_id
		p.equipment.clear()
		if Vector2i(si, k) == home:
			p.equipment.append("laundering_desk")
			for e in house.slots:
				p.equipment.append(e)
			if house.annex != "":
				p.equipment.append("annex_" + house.annex)


## يدفع حالة العالم إلى طبقة المنطق (قبل كل حفظ)
func push_core() -> void:
	if game.net.is_online() or GameState.state == null or not is_world_state(GameState.state):
		return
	for si in settlements.size():
		var loc := GameState.state.locate_settlement(settlement_id(si))
		if not loc.is_empty():
			_mirror_settlement(si, loc[1])
	LandManager.home_settlement = settlement_id(home.x) if home.x >= 0 else ""
	LandManager.home_plot = plot_id(home.x, home.y) if home.x >= 0 else ""
	for lvl in [1, 2, 3]:
		for pair in [["title_plot_%d" % lvl, int(plot_titles[lvl])], ["title_settle_%d" % lvl, int(settle_titles[lvl])]]:
			if pair[1] > 0:
				GameState.inventory[pair[0]] = pair[1]
			else:
				GameState.inventory.erase(pair[0])
	var wd := to_dict()
	wd.erase("researched")
	LandManager.world_data = wd


## يقرأ حالة العالم من طبقة المنطق (عند التحميل)
func pull_core() -> void:
	if LandManager.world_data.is_empty():
		return
	from_dict(LandManager.world_data)
	for lvl in [1, 2, 3]:
		plot_titles[lvl] = GameState.item_count("title_plot_%d" % lvl)
		settle_titles[lvl] = GameState.item_count("title_settle_%d" % lvl)


## يُستدعى مرة عند بدء اللعبة: يبني ولاية العالم إن لم تكن موجودة، أو يستعيدها
func attach_core() -> void:
	GameState.state_builder = build_world_state
	GameState.saving.connect(push_core)
	if is_world_state(GameState.state):
		pull_core()
	else:
		var sid: String = GameState.state.id if GameState.state else GameState.DEFAULT_STATE
		var started: int = GameState.state.started_at_unix if GameState.state else int(Time.get_unix_time_from_system())
		GameState.state = build_world_state(sid)
		GameState.state.started_at_unix = started
		push_core()
		GameState.save_state()
	LandManager.laptop_tier_changed.emit(LandManager.laptop_tier())


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


# ---------------------------------------------------------------- خريطة المستوطنة المحلية (L)
func nearest_settlement() -> int:
	var p: Vector3 = game.player_pos()
	var best := 0
	var bd := INF
	for i in settlements.size():
		var d: float = (settlements[i].center - p).length()
		if d < bd:
			bd = d
			best = i
	return best


func open_map(si := -1) -> void:
	if si < 0:
		si = nearest_settlement()
	var s: Dictionary = settlements[si]
	var items: Array = []
	var free := 0
	for k in range(1, PLOTS):
		var pl: Dictionary = s.plots[k]
		var mine := Vector2i(si, k) == home
		var txt := ""
		if mine:
			txt = "🏠 القطعة %d — منزلك" % k
		elif pl.tenant != "":
			txt = "القطعة %d — منزل %s" % [k, pl.tenant]
		else:
			free += 1
			txt = "⬜ القطعة %d — فارغة%s" % [k, " (للإيجار)" if s.owner != -1 else " (المستوطنة بلا مالك)"]
		items.append({"text": txt + "  ← حدّد المسار", "enabled": true, "cb": _pick.bind(si, k)})
	items.append({"text": "🏛 الفيلا (منزل البداية) — المالك: %s  ← حدّد المسار" % owner_text(s), "enabled": true, "cb": _pick.bind(si, 0)})
	items.append({"text": "◀ المستوطنة التالية", "enabled": true, "cb": open_map.bind((si + 1) % settlements.size())})
	var sub := "%s · مستوى %d · النمط %s · المالك: %s\nقطع فارغة: %d من 6 · تحتاج وثيقة قطعة مستوى %d · الرمادي = فارغة، الأزرق = منزلك، الأبيض = مسكونة" % [
		s.name, s.level, s.layout, owner_text(s), free, s.level]
	game.hud.open_menu("خريطة المستوطنة", sub, items)
	var view := MapView.new()
	view.land = self
	view.si = si
	game.hud.menu_list.add_child(view)
	game.hud.menu_list.move_child(view, 0)


func _pick(si: int, k: int) -> void:
	set_waypoint(si, k)
	game.close_menu()


## رسم المستوطنة من الأعلى (البوابة في الأسفل). النقر على قطعة يحدد المسار إليها
class MapView extends Control:
	var land: Land
	var si := 0
	const SZ := 330.0

	func _init() -> void:
		custom_minimum_size = Vector2(SZ, SZ)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _to_map(p: Vector3) -> Vector2:
		var s: Dictionary = land.settlements[si]
		var g: Vector3 = s.gate_dir
		var side := Vector3(-g.z, 0, g.x)
		var l: Vector3 = p - s.center
		var k := (SZ - 20.0) / 48.0
		return Vector2(size.x / 2.0 + l.dot(side) * k, SZ / 2.0 + l.dot(g) * k)

	func _plot_rect(pl: Dictionary, villa: bool) -> Rect2:
		var k := (SZ - 20.0) / 48.0
		var c := _to_map(pl.pos)
		var half := Vector2(6.5, 4.0) * k if villa else Vector2(6.8, 7.3) * k   # القطع 14×15 م
		return Rect2(c - half, half * 2.0)

	func _draw() -> void:
		var s: Dictionary = land.settlements[si]
		var k := (SZ - 20.0) / 48.0
		var c := Vector2(size.x / 2.0, SZ / 2.0)
		draw_rect(Rect2(c - Vector2(22.6, 22.6) * k, Vector2(45.2, 45.2) * k), Color("2b261f"))
		draw_rect(Rect2(c - Vector2(22.6, 22.6) * k, Vector2(45.2, 45.2) * k), Color("8c8172"), false, 3.0)
		# البوابة (فتحة في الأسفل) والممر
		draw_rect(Rect2(c + Vector2(-3.0, 21.0) * k, Vector2(6.0, 3.5) * k), Color("2b261f"))
		draw_rect(Rect2(c + Vector2(-2.0, -12.0) * k, Vector2(4.0, 34.0) * k), Color("6f6a62"))
		var font := get_theme_default_font()
		draw_string(font, c + Vector2(-14, 24.5 * k + 14), "GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffd36b"))
		for i in s.plots.size():
			var pl: Dictionary = s.plots[i]
			var r := _plot_rect(pl, i == 0)
			var col := Color("8a8a8a")
			if i == 0:
				col = Color("ffd36b") if s.owner == 0 else Color("b59a5a")
			elif Vector2i(si, i) == land.home:
				col = Color("4aa3ff")
			elif pl.tenant != "":
				col = Color("e8e8e8")
			elif s.owner == -1:
				col = Color("555555")
			draw_rect(r, col)
			draw_rect(r, Color(0, 0, 0, 0.6), false, 1.5)
			if land.waypoint != Vector3.INF and pl.sign.distance_to(land.waypoint) < 0.1:
				draw_rect(r.grow(3), Color("7fe6ff"), false, 3.0)
			draw_string(font, r.get_center() + Vector2(-6, 6), "V" if i == 0 else str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
		# موقعك
		var me := _to_map(land.game.player_pos())
		if Rect2(Vector2.ZERO, Vector2(size.x, SZ)).has_point(me):
			draw_circle(me, 5.0, Color("ff5a3d"))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var s: Dictionary = land.settlements[si]
			for i in s.plots.size():
				if _plot_rect(s.plots[i], i == 0).has_point(e.position):
					land._pick(si, i)
					return


# ---------------------------------------------------------------- الالتقاط: شتلات الحدائق والشحنات الساقطة
## شجيرات برية في الحدائق وعلى زوايا الأرصفة (كما في ROB RUN: تجدها في أنحاء المدينة)
func _spawn_bushes() -> void:
	var inner: Array = game.city.blocks.filter(func(b): return absf(b.center.x) < Cfg.HALF and absf(b.center.y) < Cfg.HALF and not b.get("settlement", false))
	for b in inner:
		if b.park:
			for k in 2:
				_add_pickup(Vector3(b.center.x + _rng.randf_range(-16, 16), 0.2, b.center.y + _rng.randf_range(-16, 16)), "bush", {})
		elif _rng.randf() < 0.35:
			var sx := 1.0 if _rng.randf() < 0.5 else -1.0
			var sz := 1.0 if _rng.randf() < 0.5 else -1.0
			_add_pickup(Vector3(b.center.x + sx * 22.0, 0.2, b.center.y + sz * 22.0), "bush", {})


func _add_pickup(pos: Vector3, kind: String, item: Dictionary) -> void:
	var n := Node3D.new()
	_root.add_child(n)
	n.position = pos
	if kind == "bush":
		_hbox(n, Vector3(0, 0.45, 0), Vector3(0.9, 0.9, 0.9), _mat(Color("3f8f3a"), 0.9), false)
		_hbox(n, Vector3(0, 1.0, 0), Vector3(0.5, 0.4, 0.5), _glow(Color(0.4, 1.0, 0.4), 0.4), false)
	else:
		_hbox(n, Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), _mat(Color("7c5a2c"), 0.9), false)
	pickups.append({"pos": pos, "node": n, "kind": kind, "item": item, "t": 0.0})


func _clear_pickups(kind: String) -> void:
	for pk in pickups.duplicate():
		if pk.kind == kind:
			pk.node.queue_free()
			pickups.erase(pk)


func _tick_pickups(dt: float) -> void:
	if not _bushes_spawned:
		_bushes_spawned = true
		_spawn_bushes()
	for pk in pickups:
		if pk.kind == "bush" and not pk.node.visible:
			pk.t -= dt
			if pk.t <= 0.0:
				pk.node.visible = true            # نبتت شجيرة جديدة
	# إشهار السلاح وأنت تحمل شحنة يُسقطها
	if game.weapons.aiming and game.player.car == null:
		var cr: Crime = game.crime
		var dropped := 0
		for it in cr.bag.duplicate():
			if it.kind == "cargo":
				cr.bag.erase(it)
				_add_pickup(game.player_pos() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), "cargo", it)
				dropped += 1
		if dropped > 0:
			game.hud.toast("📦 أشهرت سلاحك فسقطت %d شحنة من يدك! (التقطها بـ E)" % dropped, Color("ffb36b"))


func _pickup_hint() -> String:
	var p: Vector3 = game.player_pos()
	for pk in pickups:
		if not pk.node.visible or Vector2(p.x - pk.pos.x, p.z - pk.pos.z).length() > 1.8:
			continue
		if Input.is_action_just_pressed("interact"):
			if pk.kind == "bush":
				house.bushes += 1
				pk.node.visible = false
				pk.t = 300.0
				game.hud.toast("🌱 قطفت شتلة (معك %d) — ازرعها في غرفة الزراعة" % house.bushes, Color("9dffb0"))
			else:
				if game.crime.bag.size() >= Crime.BAG_SLOTS:
					return "الحقيبة ممتلئة"
				game.crime.bag.append(pk.item)
				pk.node.queue_free()
				pickups.erase(pk)
			return ""
		return "اضغط E لقطف الشتلة" if pk.kind == "bush" else "اضغط E لالتقاط الشحنة"
	return ""
