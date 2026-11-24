class_name Hud
extends CanvasLayer
## واجهة اللعب العربية + القوائم (البداية، الإيقاف، الاعتقال، الفوز).

signal start_pressed
signal continue_pressed

var game: Node
var root: Control
var cash_l: Label
var bank_l: Label
var goal_bar: ProgressBar
var stars_l: Label
var wanted_l: Label
var lose_bar: ProgressBar
var arrest_box: VBoxContainer
var arrest_bar: ProgressBar
var toast_l: Label
var hint_l: Label
var prog_box: VBoxContainer
var prog_l: Label
var prog_bar: ProgressBar
var speed_box: PanelContainer
var speed_l: Label
var stam_box: VBoxContainer
var stam_bar: ProgressBar
var minimap: Minimap
var menus := {}
var bust_text: Label
var _toast_t := 0.0


func _ready() -> void:
	layer = 1
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# التخطيط يدوي (LTR)، والنص العربي يُرسم من اليمين لليسار تلقائياً
	add_child(root)
	_build_hud()
	_build_menus()


# ---------------------------------------------------------------- أدوات
func _style(bg: Color, radius := 12, border := Color(1, 1, 1, 0.08)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _label(text := "", size := 18, color := Color.WHITE, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(l)
	return l


func _bar(color: Color, w := 200.0, h := 8.0, parent: Node = null) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	b.max_value = 1.0
	b.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(6)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(6)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.fill_mode = ProgressBar.FILL_BEGIN_TO_END
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(b)
	return b


func _place(c: Control, preset: int, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.position += offset


# ---------------------------------------------------------------- الواجهة
func _build_hud() -> void:
	var hud := Control.new()
	hud.name = "Hud"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	menus["hud"] = hud

	# المال (أعلى اليمين)
	var money := PanelContainer.new()
	money.add_theme_stylebox_override("panel", _style(Color(0.03, 0.04, 0.07, 0.65)))
	var mv := VBoxContainer.new()
	money.add_child(mv)
	for pair in [["معك", "cash"], ["في المخبأ", "bank"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 28)
		var v := _label("$0", 20, Color("7dff9e"), row)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		_label(pair[0], 18, Color(1, 1, 1, 0.7), row)
		if pair[1] == "cash":
			cash_l = v
		else:
			bank_l = v
		mv.add_child(row)
	goal_bar = _bar(Color("39e27d"), 220, 8, mv)
	_label("الهدف: " + Cfg.money(Cfg.GOAL), 13, Color(1, 1, 1, 0.6), mv).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	goal_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	hud.add_child(money)
	_place(money, Control.PRESET_TOP_RIGHT, Vector2(-16, 16))

	# النجوم (أعلى اليسار)
	var wbox := VBoxContainer.new()
	stars_l = _label("", 34, Color("ffcf3a"), wbox)
	stars_l.layout_direction = Control.LAYOUT_DIRECTION_LTR
	wanted_l = _label("", 15, Color(1, 1, 1, 0.85), wbox)
	lose_bar = _bar(Color("3aa0ff"), 170, 6, wbox)
	hud.add_child(wbox)
	_place(wbox, Control.PRESET_TOP_LEFT, Vector2(16, 10))

	# شريط الاعتقال
	arrest_box = VBoxContainer.new()
	arrest_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var al := _label("يتم القبض عليك! اهرب!", 24, Color("ff5c5c"), arrest_box)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrest_bar = _bar(Color("ff3b3b"), 320, 10, arrest_box)
	hud.add_child(arrest_box)
	_place(arrest_box, Control.PRESET_CENTER_TOP, Vector2(0, 110))

	# رسالة منبثقة
	toast_l = _label("", 32, Color.WHITE, hud)
	toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(toast_l, Control.PRESET_CENTER_TOP, Vector2(0, 200))
	toast_l.add_theme_constant_override("outline_size", 10)

	# التلميح وشريط السرقة (أسفل الوسط)
	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	prog_box = VBoxContainer.new()
	prog_l = _label("", 18, Color.WHITE, prog_box)
	prog_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog_bar = _bar(Color("ffc83a"), 420, 12, prog_box)
	bottom.add_child(prog_box)
	var hp := PanelContainer.new()
	hp.add_theme_stylebox_override("panel", _style(Color(0.03, 0.04, 0.07, 0.7), 10))
	hint_l = _label("", 18, Color.WHITE, hp)
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(hp)
	hud.add_child(bottom)
	_place(bottom, Control.PRESET_CENTER_BOTTOM, Vector2(0, -30))

	# عداد السرعة واللياقة (أسفل اليمين)
	var br := VBoxContainer.new()
	speed_box = PanelContainer.new()
	speed_box.add_theme_stylebox_override("panel", _style(Color(0.03, 0.04, 0.07, 0.65), 60, Color(1, 1, 1, 0.15)))
	speed_box.custom_minimum_size = Vector2(120, 120)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_l = _label("0", 40, Color.WHITE, sv)
	speed_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var u := _label("كم/س", 14, Color(1, 1, 1, 0.6), sv)
	u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_box.add_child(sv)
	br.add_child(speed_box)
	stam_box = VBoxContainer.new()
	_label("اللياقة", 13, Color(1, 1, 1, 0.6), stam_box).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stam_bar = _bar(Color("3ab4ff"), 160, 8, stam_box)
	br.add_child(stam_box)
	hud.add_child(br)
	_place(br, Control.PRESET_BOTTOM_RIGHT, Vector2(-20, -20))

	# الخريطة المصغّرة (أسفل اليسار)
	minimap = Minimap.new()
	minimap.game = game
	minimap.custom_minimum_size = Vector2(210, 210)
	hud.add_child(minimap)
	minimap.anchor_left = 0.0
	minimap.anchor_right = 0.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = 16
	minimap.offset_right = 226
	minimap.offset_top = -226
	minimap.offset_bottom = -16


# ---------------------------------------------------------------- القوائم
func _overlay(key: String) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var card := PanelContainer.new()
	var st := _style(Color(0.05, 0.06, 0.1, 0.92), 18)
	st.content_margin_left = 34
	st.content_margin_right = 34
	st.content_margin_top = 26
	st.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel", st)
	card.custom_minimum_size = Vector2(620, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	menus[key] = bg
	bg.visible = false
	return v


func _button(text: String, parent: Node, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	var n := _style(Color("d8402a"), 12, Color(1, 0.6, 0.4, 0.4))
	n.content_margin_left = 40
	n.content_margin_right = 40
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color("f0583a")
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_menus() -> void:
	var m := _overlay("menu")
	_centered(_label("دمار", 72, Color("ff7a4d"), m))
	_centered(_label("مطاردة الليل", 24, Color(1, 1, 1, 0.8), m))
	_centered(_label("اسرق المتاجر والبنوك في مدينة لا تنام، اهرب من الشرطة، وخبّئ غنيمتك في المخبأ. اجمع %s لتصبح أخطر لص في المدينة." % Cfg.money(Cfg.GOAL), 17, Color(1, 1, 1, 0.9), m))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.layout_direction = Control.LAYOUT_DIRECTION_RTL
	for line in ["W A S D  —  الحركة / القيادة", "الفأرة  —  تدوير الكاميرا", "Shift  —  الركض", "E (مطولاً)  —  السرقة / الإيداع", "F  —  ركوب / نزول السيارة", "Space  —  فرامل اليد", "H  —  البوق", "R  —  المطر    M  —  الصوت"]:
		_label(line, 15, Color(1, 1, 1, 0.85), grid)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	m.add_child(gc)
	_centered(_label("💡 الأزقة الضيقة بين المباني لا تدخلها سيارات الشرطة. اختفِ عن أنظارهم لتزول النجوم، ولا يمكنك الإيداع وأنت مطلوب.", 14, Color(1, 1, 1, 0.6), m))
	_button("ابدأ اللعب", m, func(): start_pressed.emit())

	var b := _overlay("busted")
	_centered(_label("تم القبض عليك!", 52, Color("ff4b4b"), b))
	bust_text = _centered(_label("", 18, Color.WHITE, b))
	_button("العودة إلى المخبأ", b, func(): continue_pressed.emit())

	var p := _overlay("paused")
	_centered(_label("إيقاف مؤقت", 48, Color.WHITE, p))
	_button("متابعة", p, func(): continue_pressed.emit())

	var w := _overlay("win")
	_centered(_label("مبروك!", 60, Color("ffc83a"), w))
	_centered(_label("جمعت %s وأصبحت أخطر لص في المدينة. يمكنك مواصلة اللعب." % Cfg.money(Cfg.GOAL), 18, Color.WHITE, w))
	_button("متابعة اللعب", w, func(): continue_pressed.emit())


func show_state(s: String) -> void:
	for k in ["menu", "busted", "paused", "win"]:
		menus[k].visible = (k == s)
	menus["hud"].visible = s != "menu"


func toast(msg: String, color := Color.WHITE) -> void:
	toast_l.text = msg
	toast_l.add_theme_color_override("font_color", color)
	toast_l.modulate.a = 1.0
	_toast_t = 2.6
	_place(toast_l, Control.PRESET_CENTER_TOP, Vector2(0, 200))


func set_bust_text(t: String) -> void:
	bust_text.text = t


# ---------------------------------------------------------------- التحديث
func refresh(dt: float, hint: String) -> void:
	cash_l.text = Cfg.money(game.cash)
	bank_l.text = Cfg.money(game.bank)
	goal_bar.value = minf(1.0, float(game.bank) / Cfg.GOAL)
	var hiding: bool = game.wanted > 0 and game.last_seen > 0.8
	var stars := ""
	for i in 5:
		stars += "★" if i < game.wanted else "☆"
	stars_l.text = stars
	stars_l.modulate.a = 0.35 if hiding and fmod(game.time, 0.6) < 0.3 else 1.0
	wanted_l.text = "" if game.wanted == 0 else ("اختفيت عن أنظارهم… ابقَ مختبئاً" if hiding else "الشرطة تراك! اهرب واختبئ")
	lose_bar.visible = hiding
	lose_bar.value = game.last_seen / (5.0 + game.wanted * 2.5)
	arrest_box.visible = game.arrest > 0.01
	arrest_bar.value = game.arrest
	var car: Car = game.player.car
	speed_box.visible = car != null
	stam_box.visible = car == null
	if car:
		speed_l.text = str(roundi(absf(car.speed) * 3.6))
	stam_bar.value = game.player.stamina
	prog_box.visible = game.robbing != null
	if game.robbing:
		prog_l.text = "جارٍ سرقة %s…" % game.robbing.def.name
		prog_bar.value = game.rob_prog
	hint_l.text = hint
	hint_l.get_parent().visible = hint != ""
	if _toast_t > 0.0:
		_toast_t -= dt
		toast_l.modulate.a = clampf(_toast_t / 0.3, 0.0, 1.0)
	minimap.queue_redraw()
