class_name CorePanel
extends PanelContainer
## لوحة واجهة تستمع لإشارات الأنظمة فقط — لا تحتوي أي منطق لعب.
## مثال على فصل المنطق عن الواجهة: تُضاف لأي مشهد، ولا يعرف أي مدير بوجودها.

var _labels := {}
var _log: RichTextLabel


func _ready() -> void:
	custom_minimum_size = Vector2(430, 0)
	var v := VBoxContainer.new()
	add_child(v)
	for key in ["state", "hub", "cash", "bank", "desk", "land", "authority", "heist"]:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 14)
		v.add_child(l)
		_labels[key] = l
	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(420, 220)
	_log.scroll_following = true
	v.add_child(_log)
	# الاشتراك في الإشارات
	GameState.state_started.connect(func(s): _show("state", "الولاية: %s" % s.display_name); _say("بدأت ولاية جديدة: %s" % s.display_name))
	GameState.state_wiped.connect(func(r): _show("state", "الولاية: (مُسحت)"); _say("🏛 مُسحت الولاية: %s" % r))
	GameState.profile_changed.connect(func(p): _show("authority", "النفوذ: %d · سنوات السجن: %d · مكافآت: %s" % [int(p.authority), int(p.jail_years), ", ".join(p.rewards)]))
	EconomyManager.dirty_cash_changed.connect(func(a): _show("cash", "كاش قذر معك: %d" % a))
	EconomyManager.bank_changed.connect(func(a): _show("bank", "البنك: %d" % a))
	EconomyManager.desk_changed.connect(func(pool, rate, cap): _show("desk", "طاولة الغسيل: %d / %d (%d/ساعة)" % [pool, cap, int(rate)]))
	EconomyManager.laundered.connect(func(a, off): _say("🧼 غُسل %d%s" % [a, " أثناء غيابك" if off else ""]))
	EconomyManager.economy_error.connect(func(r): _say("⚠ " + r))
	EconomyManager.item_sold.connect(func(id, n, total): _say("💵 بعت %d × %s بـ %d" % [n, ItemDB.item_name(id), total]))
	LandManager.plot_rented.connect(func(s, p): _show("land", "الأرض: %s (لابتوب %s)" % [p, LandManager.tier_roman(LandManager.laptop_tier())]); _say("🏠 استأجرت %s" % p))
	LandManager.land_error.connect(func(r): _say("⚠ " + r))
	LandManager.title_researched.connect(func(l): _say("🔬 بحث سند المستوى %d" % l))
	LandManager.equipment_placed.connect(func(k): _say("🔧 وُضعت %s" % LandManager.EQUIPMENT[k].name))
	TravelManager.travel_finished.connect(func(h): _show("hub", "الموقع: %s" % TravelManager.HUB_NAMES[h]))
	TravelManager.travel_denied.connect(func(_h, r): _say("🚫 " + r))
	MotelManager.roulette_result.connect(func(n, c, bet, pay): _say("🎰 %d (%s) رهان %d ← %d" % [n, c, bet, pay]))
	MotelManager.barter_done.connect(func(_r, item, n): _say("🚪 مقايضة: %d × %s" % [n, ItemDB.item_name(item)]))
	MotelManager.quest_completed.connect(func(q, cash): _say("✅ مهمة %s (+%d)" % [q, cash]))
	MotelManager.shipment_delivered.connect(func(s, _c): _say("📦 وصلت شحنة %s" % s))
	PrisonManager.sentenced.connect(func(y, v, total, r): _say("⛓ حكم %d سنة (ثروة %d) — المجموع %d — %s" % [y, v, total, r]))
	PrisonManager.authority_level_up.connect(func(l, rw): _say("👑 نفوذ المستوى %d: %s" % [l, ", ".join(rw)]))
	HeistCityManager.heist_completed.connect(func(t, loot): _show("heist", "حقيبة السطو: %d" % HeistCityManager.bag_value()); _say("💰 %s: %s" % [t, loot]))
	HeistCityManager.extracted.connect(func(_i, v): _show("heist", "حقيبة السطو: 0"); _say("🚤 أُخرجت غنائم بقيمة %d" % v))
	HeistCityManager.alarm_raised.connect(func(l, d): _say("🚨 إنذار %d في %s" % [l, HeistCityManager.DISTRICTS[d]]))


func _show(key: String, text: String) -> void:
	_labels[key].text = text


func _say(text: String) -> void:
	_log.append_text(text + "\n")
