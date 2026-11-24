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
var info_l: Label
var launder_l: Label
var health_bar: ProgressBar
var crosshair: Label
var dmg_flash: ColorRect
var jail_l: Label
var bribe_btns: Array[Button] = []
var release_btn: Button
var menu_title: Label
var menu_sub: Label
var menu_list: VBoxContainer
var name_edit: LineEdit
var ip_edit: LineEdit
var role_btn: OptionButton
var menu_status: Label
var chat_box: VBoxContainer
var chat_edit: LineEdit
var _chat_lines: Array = []
var _settings_btns := {}


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
	for pair in [["نقود قذرة", "cash"], ["الحساب البنكي", "bank"]]:
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
	launder_l = _label("", 13, Color("9fe8ff"), mv)
	launder_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	goal_bar = _bar(Color("39e27d"), 220, 8, mv)
	_label("الهدف: " + Cfg.money(Cfg.GOAL), 13, Color(1, 1, 1, 0.6), mv).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	goal_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	hud.add_child(money)
	_place(money, Control.PRESET_TOP_RIGHT, Vector2(-16, 16))

	# الدردشة (فوق الخريطة المصغّرة)
	chat_box = VBoxContainer.new()
	chat_box.custom_minimum_size = Vector2(420, 0)
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(chat_box)
	chat_box.anchor_left = 0.0
	chat_box.anchor_top = 1.0
	chat_box.anchor_bottom = 1.0
	chat_box.offset_left = 16
	chat_box.offset_top = -420
	chat_box.offset_bottom = -240
	chat_box.alignment = BoxContainer.ALIGNMENT_END
	chat_edit = _edit("اكتب رسالة… (Enter)", "", 420)
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_on_chat_submit)
	chat_box.add_child(chat_edit)

	# معلومات اللص (تحت المال)
	var ip := PanelContainer.new()
	ip.add_theme_stylebox_override("panel", _style(Color(0.03, 0.04, 0.07, 0.6)))
	var iv := VBoxContainer.new()
	ip.add_child(iv)
	info_l = _label("", 15, Color.WHITE, iv)
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_bar = _bar(Color("ff4b4b"), 220, 6, iv)
	health_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	hud.add_child(ip)
	_place(ip, Control.PRESET_TOP_RIGHT, Vector2(-16, 170))
	# علامة التصويب ووميض الإصابة
	crosshair = _label("+", 34, Color(1, 1, 1, 0.9), hud)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(crosshair, Control.PRESET_CENTER, Vector2(0, -8))
	dmg_flash = ColorRect.new()
	dmg_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(dmg_flash)

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
	for line in ["W A S D  —  الحركة / القيادة", "الفأرة  —  الكاميرا", "زر أيمن / أيسر  —  تصويب / إطلاق", "Q  —  تبديل السلاح", "X  —  القناع", "Z  —  الاستسلام", "E (مطولاً)  —  سرقة / تفاعل", "F  —  ركوب / نزول", "Shift  —  ركض   Space  —  فرامل اليد", "F2 الجودة · R الطقس · T الوقت"]:
		_label(line, 15, Color(1, 1, 1, 0.85), grid)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	m.add_child(gc)
	_centered(_label("💡 الغنائم تُباع للمشتري ($) خارج المدينة وأنت ملثّم، ثم تُغسل في المخبأ (H) لتصبح آمنة في حسابك البنكي. الأدوات والأسلحة من السوق السوداء.", 14, Color(1, 1, 1, 0.6), m))
	_button("لعب فردي", m, func(): start_pressed.emit())
	# --- اللعب الجماعي
	_centered(_label("— اللعب الجماعي عبر الإنترنت —", 18, Color("9fd0ff"), m))
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 10)
	name_edit = _edit("اسمك", "لاعب", 170)
	row1.add_child(name_edit)
	role_btn = OptionButton.new()
	role_btn.add_item("مجرم")
	role_btn.add_item("شرطي")
	role_btn.add_theme_font_size_override("font_size", 17)
	row1.add_child(role_btn)
	ip_edit = _edit("عنوان الخادم", "127.0.0.1", 170)
	row1.add_child(ip_edit)
	m.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 14)
	var hb := _button("استضافة لعبة", row2, func(): game.start_host(name_edit.text, ["criminal", "cop"][role_btn.selected]))
	var jb := _button("انضمام", row2, _join_pressed)
	for bb in [hb, jb]:
		bb.add_theme_font_size_override("font_size", 19)
		bb.add_theme_stylebox_override("normal", _style(Color("2b5bd8"), 12, Color(0.6, 0.8, 1, 0.4)))
	m.add_child(row2)
	menu_status = _centered(_label("", 14, Color(1, 1, 1, 0.7), m))

	var b := _overlay("busted")
	_centered(_label("تم القبض عليك!", 52, Color("ff4b4b"), b))
	bust_text = _centered(_label("", 17, Color.WHITE, b))
	jail_l = _centered(_label("", 22, Color("ffd36b"), b))
	for amt in [10000, 50000, 200000]:
		var bb := _button("رشوة الضابط %s" % Cfg.money(amt), b, func(): game.try_bribe(amt))
		bb.add_theme_font_size_override("font_size", 17)
		bb.add_theme_stylebox_override("normal", _style(Color(0.15, 0.17, 0.24), 10, Color(1, 1, 1, 0.15)))
		bribe_btns.append(bb)
	release_btn = _button("الخروج من السجن", b, func(): continue_pressed.emit())

	# قائمة تفاعلية عامة (السوق، الغسيل، الشرطة…)
	var u := _overlay("ui")
	menu_title = _centered(_label("", 40, Color("ff9b3b"), u))
	menu_sub = _centered(_label("", 15, Color(1, 1, 1, 0.75), u))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 360)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_list = VBoxContainer.new()
	menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_list.add_theme_constant_override("separation", 6)
	sc.add_child(menu_list)
	u.add_child(sc)
	_button("إغلاق (Esc)", u, func(): game.close_menu())

	var p := _overlay("paused")
	_centered(_label("إيقاف مؤقت", 48, Color.WHITE, p))
	_centered(_label("الإعدادات", 20, Color(1, 1, 1, 0.7), p))
	_settings_btns["quality"] = _button("", p, func(): game.cycle_quality())
	_settings_btns["weather"] = _button("", p, func(): game.cycle_weather())
	_settings_btns["time"] = _button("", p, func(): game.advance_time())
	_settings_btns["cycle"] = _button("", p, func(): game.toggle_day_cycle())
	_settings_btns["season"] = _button("", p, func(): game.toggle_season())
	for k in _settings_btns:
		var sb: Button = _settings_btns[k]
		sb.add_theme_font_size_override("font_size", 18)
		var st := _style(Color(0.15, 0.17, 0.24), 10, Color(1, 1, 1, 0.15))
		sb.add_theme_stylebox_override("normal", st)
		sb.custom_minimum_size = Vector2(380, 0)
	_centered(_label("اختصارات: F2 الجودة · R الطقس · T الوقت", 13, Color(1, 1, 1, 0.5), p))
	_button("متابعة", p, func(): continue_pressed.emit())

	var w := _overlay("win")
	_centered(_label("مبروك!", 60, Color("ffc83a"), w))
	_centered(_label("جمعت %s وأصبحت أخطر لص في المدينة. يمكنك مواصلة اللعب." % Cfg.money(Cfg.GOAL), 18, Color.WHITE, w))
	_button("متابعة اللعب", w, func(): continue_pressed.emit())


func refresh_settings() -> void:
	if _settings_btns.is_empty() or game.world == null:
		return
	_settings_btns["quality"].text = "جودة الرسوم: " + WorldEnv.QUALITY_NAMES[game.quality]
	_settings_btns["weather"].text = "الطقس: " + WorldEnv.WEATHER_NAMES[game.world.weather]
	_settings_btns["time"].text = "الوقت: %s  (+3 ساعات)" % game.world.clock_text()
	_settings_btns["cycle"].text = "دورة الليل والنهار: " + ("تعمل" if game.world.cycle_enabled else "متوقفة")
	_settings_btns["season"].text = "المواسم (مداهمة فيدرالية كل 7 أيام): " + ("مفعّلة · اليوم %d" % (game.gangs.day_count + 1) if game.gangs.season_mode else "متوقفة")


func _edit(ph: String, txt: String, w: float) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = ph
	e.text = txt
	e.custom_minimum_size = Vector2(w, 36)
	e.add_theme_font_size_override("font_size", 16)
	return e


func _join_pressed() -> void:
	game.net.my_name = name_edit.text
	game.net.my_role = ["criminal", "cop"][role_btn.selected]
	game.start_join(ip_edit.text)


func set_menu_status(t: String) -> void:
	menu_status.text = t


func add_chat(who: String, text: String, cop := false) -> void:
	var l := _label("%s: %s" % [who, text], 15, Color("9fd0ff") if cop else Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	chat_box.add_child(l)
	chat_box.move_child(chat_edit, -1)
	_chat_lines.append([l, 12.0])
	if _chat_lines.size() > 7:
		_chat_lines.pop_front()[0].queue_free()


func open_chat() -> void:
	if not game.net.is_online():
		return
	chat_edit.visible = true
	chat_edit.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_chat_submit(t: String) -> void:
	game.net.send_chat(t)
	chat_edit.text = ""
	chat_edit.visible = false
	chat_edit.release_focus()
	if game.state == "play":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func show_state(s: String) -> void:
	if s == "paused":
		refresh_settings()
	for k in ["menu", "busted", "paused", "win", "ui"]:
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


func update_jail(t: float, bank: int) -> void:
	jail_l.text = "مدة السجن المتبقية: %d ثانية" % ceili(t) if t > 0.0 else "انتهت مدة سجنك"
	for i in bribe_btns.size():
		bribe_btns[i].visible = t > 0.0
		bribe_btns[i].disabled = bank < [10000, 50000, 200000][i]
	release_btn.disabled = t > 0.0
	release_btn.text = "الخروج من السجن (مركز الشرطة)" if t <= 0.0 else "انتظر انتهاء المدة…"


func open_menu(title: String, sub: String, items: Array) -> void:
	menu_title.text = title
	menu_sub.text = sub
	for c in menu_list.get_children():
		c.queue_free()
	for it in items:
		var b := Button.new()
		b.text = it.text
		b.disabled = not it.enabled
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_stylebox_override("normal", _style(Color(0.13, 0.15, 0.22), 8, Color(1, 1, 1, 0.12)))
		b.add_theme_stylebox_override("hover", _style(Color(0.22, 0.25, 0.35), 8, Color(1, 0.6, 0.3, 0.5)))
		b.add_theme_stylebox_override("disabled", _style(Color(0.08, 0.08, 0.1), 8, Color(1, 1, 1, 0.05)))
		b.pressed.connect(it.cb)
		menu_list.add_child(b)
	if game.state != "ui":
		game.set_state("ui")


func close_menu() -> void:
	if menus.has("ui"):
		menus["ui"].visible = false


func flash_damage() -> void:
	dmg_flash.color.a = 0.35


# ---------------------------------------------------------------- التحديث
func refresh(dt: float, hint: String) -> void:
	cash_l.text = Cfg.money(game.cash)
	bank_l.text = Cfg.money(game.bank)
	var cr: Crime = game.crime
	launder_l.text = ("🧼 قيد الغسيل: %s" % Cfg.money(int(cr.launder_pool))) if cr.launder_pool > 0 else ""
	var w: Weapons = game.weapons
	var wtxt := "بلا سلاح" if w.current == "" else "%s · %d طلقة" % [Weapons.CATALOG[w.current].name, w.ammo]
	info_l.text = "%s   🎒 %d/%d (%s)\n⭐ السمعة %d (+%d%%)   🔫 %s\n🚩 أحياؤك %d/9%s" % ["🥷 ملثّم" if cr.masked else "👤 مكشوف", cr.bag.size(), Crime.BAG_SLOTS, Cfg.money(cr.bag_value()), cr.notoriety_level(), int(cr.fence_bonus() * 100), wtxt, game.gangs.owned_count(), "  👑 عرّاب المدينة" if game.gangs.is_godfather() else ""]
	health_bar.value = game.player.health / game.player.max_health
	if game.cop.on_duty:
		info_l.text = "🚔 مناوبة — %s · اعتقالات %d · %s\n🔫 %s" % [game.cop.rank_name(), game.cop.shift_arrests, Cfg.money(game.cop.shift_pay), wtxt]
	crosshair.visible = w.aiming
	dmg_flash.color.a = maxf(0.0, dmg_flash.color.a - dt * 0.8)
	goal_bar.value = minf(1.0, float(game.bank) / Cfg.GOAL)
	var hiding: bool = game.wanted > 0 and game.last_seen > 0.8
	var stars := ""
	for i in 5:
		stars += "★" if i < game.wanted else "☆"
	stars_l.text = stars
	stars_l.modulate.a = 0.35 if hiding and fmod(game.time, 0.6) < 0.3 else 1.0
	wanted_l.text = "" if game.wanted == 0 else ("⚠ المطلوب الأول — موقعك مكشوف!" if game.most_wanted_t > 0.0 else ("اختفيت عن أنظارهم… ابقَ مختبئاً" if hiding else "الشرطة تراك! اهرب واختبئ"))
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
		prog_l.text = "جارٍ: %s…" % game.rob_label
		prog_bar.value = game.rob_prog
	hint_l.text = hint
	hint_l.get_parent().visible = hint != ""
	for cl in _chat_lines:
		cl[1] -= dt
		cl[0].modulate.a = clampf(cl[1] / 2.0, 0.0, 1.0) if not chat_edit.visible else 1.0
	if _toast_t > 0.0:
		_toast_t -= dt
		toast_l.modulate.a = clampf(_toast_t / 0.3, 0.0, 1.0)
	minimap.queue_redraw()
