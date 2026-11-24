extends Node
## LandManager (Autoload): الملكية الهرمية مقاطعة ← مستوطنة ← قطعة، وسندات الأرض، والقاعدة، و«اللابتوب التجاري».
## مسار الحصول على أرض:
##   1) بحث «سند ملكية أرض» من اللابتوب (يفتحه للشراء)،  2) شراء السند (يدخل المخزون)،
##   3) العثور على قطعة شاغرة في مستوطنة لها مالك وفي مقاطعة بنفس مستوى السند،
##   4) توقيع الإيجار مقابل وثائق السوق السوداء (مستوى 1) أو كاش (مستوى 2 و3).
## درجة اللابتوب (I/II/III) = مستوى المقاطعة التي تملك فيها أرضاً (I إن لم تملك).

signal title_researched(level: int)
signal title_bought(level: int)
signal plot_rented(settlement_id: String, plot_id: String)
signal plot_left(settlement_id: String, plot_id: String)
signal equipment_placed(kind: String)
signal laptop_tier_changed(tier: int)
signal land_error(reason: String)

const EQUIPMENT := {
	"laundering_desk": {"name": "طاولة غسيل الأموال", "price": Balance.DESK_PRICE},
	"cargo_bench": {"name": "طاولة الشحنات", "price": 25000},
	"safe": {"name": "خزنة", "price": 40000},
}

var researched := {}                     # "plot1".."plot3" و"settle1".."settle3" -> true
var world_data := {}                     # بيانات العالم ثلاثي الأبعاد الإضافية (المنزل، الأمان…) — تُمسح مع الولاية
var home_settlement := ""
var home_plot := ""


func _ready() -> void:
	GameState.register_module("land", self)


# ---------------------------------------------------------------- الاستعلامات
func has_home() -> bool:
	return home_plot != "" and _home_plot_data() != null


func home_settlement_id() -> String:
	return home_settlement


func home_level() -> int:
	if not has_home():
		return 0
	return _locate(home_settlement)[1].level


func laptop_tier() -> int:
	return maxi(1, home_level())


func has_equipment(kind: String) -> bool:
	var p := _home_plot_data()
	return p != null and p.has_equipment(kind)


## ضريبة مالك المستوطنة على ما يُغسل في قاعدتك (لا ضريبة إن كنت المالك)
func settlement_tax(amount: float) -> float:
	if not has_home():
		return 0.0
	var s: SettlementData = _locate(home_settlement)[1]
	if s.owner_id == GameState.player_id:
		return 0.0
	var tax := amount * s.tax_rate
	s.uncollected_tax += int(tax)
	return tax


func can_use_laptop_item(item_id: String) -> bool:
	var it: Dictionary = Balance.LAPTOP_ITEMS.get(item_id, {})
	return not it.is_empty() and laptop_tier() >= int(it.tier)


# ---------------------------------------------------------------- اللابتوب: البحث والشراء
func research_title(level: int) -> bool:
	if researched.get("plot%d" % level, false):
		land_error.emit("سبق البحث عن هذا السند")
		return false
	if level > laptop_tier() + 1:
		land_error.emit("درجة اللابتوب %s لا تسمح بالبحث عن سند المستوى %d" % [tier_roman(laptop_tier()), level])
		return false
	if level == 3 and home_level() != 2:
		land_error.emit("سند المستوى 3 يتطلب أن تسكن أرضاً في مقاطعة مستوى 2")
		return false
	if not EconomyManager.spend(Balance.TITLE_RESEARCH[level]):
		return false
	researched["plot%d" % level] = true
	title_researched.emit(level)
	GameState.save_state()
	return true


func buy_title(level: int) -> bool:
	if not researched.get("plot%d" % level, false):
		land_error.emit("ابحث عن السند أولاً من اللابتوب التجاري")
		return false
	if not EconomyManager.spend(Balance.TITLE_PRICE[level]):
		return false
	GameState.add_item("title_plot_%d" % level)
	title_bought.emit(level)
	GameState.save_state()
	return true


# ---------------------------------------------------------------- الاستئجار
## يعيد "" إن كان الاستئجار ممكناً، وإلا سبب الرفض
func rent_check(settlement_id: String, plot_id: String) -> String:
	var loc := _locate(settlement_id)
	if loc.is_empty():
		return "مستوطنة غير موجودة"
	var s: SettlementData = loc[1]
	var p := s.find_plot(plot_id)
	if p == null:
		return "قطعة غير موجودة"
	if not s.has_owner():
		return "لا يمكن الاستئجار في مستوطنة بلا مالك"
	if not p.is_vacant():
		return "القطعة مشغولة"
	if has_home():
		return "لديك أرض بالفعل في هذه الولاية"
	if GameState.wanted > 0:
		return "لا يمكنك توقيع العقد وأنت مطلوب"
	if GameState.item_count("title_plot_%d" % s.level) <= 0:
		return "تحتاج سند ملكية أرض من المستوى %d" % s.level
	var cost: Dictionary = Balance.RENT_COST[s.level]
	if cost.has("documents") and GameState.item_count("document") < int(cost.documents):
		return "تحتاج %d وثائق سوق سوداء" % int(cost.documents)
	if cost.has("cash") and EconomyManager.dirty_cash + EconomyManager.bank_balance < int(cost.cash):
		return "تحتاج %d لتوقيع العقد" % int(cost.cash)
	return ""


func rent_plot(settlement_id: String, plot_id: String) -> bool:
	var why := rent_check(settlement_id, plot_id)
	if why != "":
		land_error.emit(why)
		return false
	var s: SettlementData = _locate(settlement_id)[1]
	var p := s.find_plot(plot_id)
	var cost: Dictionary = Balance.RENT_COST[s.level]
	if cost.has("documents"):
		GameState.remove_item("document", int(cost.documents))
	if cost.has("cash") and not EconomyManager.spend(int(cost.cash)):
		return false
	GameState.remove_item("title_plot_%d" % s.level)
	p.tenant_id = GameState.player_id
	p.rented_at_unix = int(Time.get_unix_time_from_system())
	home_settlement = settlement_id
	home_plot = plot_id
	plot_rented.emit(settlement_id, plot_id)
	laptop_tier_changed.emit(laptop_tier())
	GameState.save_state()
	return true


func leave_plot() -> void:
	var p := _home_plot_data()
	if p == null:
		return
	p.tenant_id = ""
	p.equipment.clear()
	var s := home_settlement
	var pid := home_plot
	home_settlement = ""
	home_plot = ""
	plot_left.emit(s, pid)
	laptop_tier_changed.emit(laptop_tier())
	GameState.save_state()


func place_equipment(kind: String) -> bool:
	var p := _home_plot_data()
	if p == null:
		land_error.emit("تحتاج قطعة أرض لبناء قاعدتك")
		return false
	if p.has_equipment(kind):
		land_error.emit("موجودة بالفعل")
		return false
	if not EconomyManager.spend(int(EQUIPMENT[kind].price)):
		return false
	p.equipment.append(kind)
	equipment_placed.emit(kind)
	GameState.save_state()
	return true


## قائمة القطع الشاغرة القابلة للاستئجار في الولاية (للخريطة/الواجهة)
func vacant_rentable(level := 0) -> Array:
	var out := []
	if GameState.state == null:
		return out
	for d in GameState.state.districts:
		if level != 0 and d.level != level:
			continue
		for s in d.settlements:
			if not s.has_owner():
				continue
			for p in s.vacant_plots():
				out.append({"district": d.id, "settlement": s.id, "plot": p.id, "level": d.level})
	return out


static func tier_roman(t: int) -> String:
	return ["", "I", "II", "III"][clampi(t, 0, 3)]


func _locate(settlement_id: String) -> Array:
	if GameState.state == null:
		return []
	return GameState.state.locate_settlement(settlement_id)


func _home_plot_data() -> LandPlotData:
	if home_plot == "":
		return null
	var loc := _locate(home_settlement)
	if loc.is_empty():
		return null
	return (loc[1] as SettlementData).find_plot(home_plot)


# ---------------------------------------------------------------- وحدة الولاية
func reset_state() -> void:
	researched = {}
	world_data = {}
	home_settlement = ""
	home_plot = ""
	laptop_tier_changed.emit(laptop_tier())


func to_state_dict() -> Dictionary:
	return {"researched": researched, "settlement": home_settlement, "plot": home_plot, "world": world_data}


func from_state_dict(d: Dictionary) -> void:
	researched = d.get("researched", {})
	world_data = d.get("world", {})
	home_settlement = d.get("settlement", "")
	home_plot = d.get("plot", "")
