extends Node
## اختبار آلي لطبقة المنطق (core) بلا رسوميات:
##   godot --headless --path godot res://scenes/tests/core_tests.tscn -- --core-test
## يطبع "CORE …" لكل خطوة و"CORE RESULT pass/fail" في النهاية. لا يكتب على ملفات حفظ اللاعب.

var fails := 0
var panel: CorePanel


func check(name: String, cond: bool, info := "") -> void:
	print("CORE %s %s %s" % ["PASS" if cond else "FAIL", name, info])
	if not cond:
		fails += 1


func _ready() -> void:
	panel = CorePanel.new()
	add_child(panel)
	await get_tree().process_frame
	GameState.persistence = false
	GameState.profile = {"jail_years": 0, "sentences": 0, "authority": 0, "rewards": [], "visited_states": []}
	GameState.start_state("sahra", 12345)
	MotelManager.rng.seed = 7
	HeistCityManager.rng.seed = 7
	var st := GameState.state

	# 1) الولاية والمقاطعات
	var levels := []
	for d in st.districts:
		levels.append(d.level)
	check("state_10_districts", st.districts.size() == 10, str(levels))
	check("levels_1_2_3", levels.count(1) == 4 and levels.count(2) == 4 and levels.count(3) == 2)
	check("wipe_timer", GameState.seconds_until_wipe() > 6 * 86400, str(GameState.seconds_until_wipe()))

	# 2) التنقل السريع
	check("start_at_motel", TravelManager.current_hub == TravelManager.Hub.MOTEL)
	check("home_denied_without_plot", TravelManager.can_travel(TravelManager.Hub.HOME) != "", TravelManager.can_travel(TravelManager.Hub.HOME))
	GameState.set_wanted(2)
	check("travel_denied_wanted", not TravelManager.travel_to(TravelManager.Hub.HEIST_CITY, true))
	GameState.set_wanted(0)
	check("travel_heist_city", TravelManager.travel_to(TravelManager.Hub.HEIST_CITY, true) and HeistCityManager.in_city())

	# 5) مدينة السطو: القناع، الإنذار العام، الحقيبة غير المؤمّنة، القبض، والتأمين
	var city_alarms: Array = []
	HeistCityManager.city_alarm_triggered.connect(func(t: String, _d: String) -> void: city_alarms.append(t))
	check("four_districts", HeistCityManager.districts.size() == 4, str(HeistCityManager.districts.map(func(d): return d.display_name)))
	GameState.add_item("lockpick", 2)
	GameState.add_item("drill", 1)
	HeistCityManager.set_masked(true)
	check("heist_needs_tool_ok", HeistCityManager.start_heist("dt_jewelry"))
	HeistCityManager.step(8.0)
	check("loot_unsecured", HeistCityManager.has_unextracted() and GameState.item_count("jewelry") == 0, str(HeistCityManager.bag_inventory))
	check("cooldown", not HeistCityManager.start_heist("dt_jewelry"))
	HeistCityManager.start_heist("dt_bank")
	check("city_alarm_on_major", city_alarms == ["dt_bank"] and GameState.wanted >= HeistCityManager.CITY_ALARM_WANTED and HeistCityManager.is_wanted, "wanted=%d" % GameState.wanted)
	HeistCityManager.step(15.0)
	check("travel_denied_wanted_in_city", TravelManager.can_travel(TravelManager.Hub.SALES_CENTER) != "")
	var masked_bag := HeistCityManager.bag_value()
	var lost_masked := HeistCityManager.on_player_busted_or_killed()
	check("busted_masked_wipes_bag", lost_masked == masked_bag and lost_masked > 0 and not HeistCityManager.has_unextracted(), "lost=%d" % lost_masked)
	GameState.set_wanted(0)
	HeistCityManager.start_heist("sb_kiosk")                # بلا قناع
	HeistCityManager.step(5.0)
	var kept := HeistCityManager.bag_value()
	HeistCityManager.on_player_busted_or_killed()
	check("busted_unmasked_keeps_bag", HeistCityManager.bag_value() == kept and kept > 0, "kept=%d" % kept)
	GameState.set_wanted(0)
	check("extract_fence_car", HeistCityManager.extract_loot("fence_car", "fc_beach_pier"))
	HeistCityManager.step(Balance.EXTRACTION_HOLD + 0.1)
	check("extracted_secured", not HeistCityManager.has_unextracted() and GameState.item_count("cash_bundle") > 0 and GameState.wanted == 0)
	HeistCityManager.start_heist("pk_cafe")
	HeistCityManager.step(5.0)
	GameState.set_wanted(0)
	var cafe := HeistCityManager.bag_value()
	var cash_items_before := GameState.item_count("cash_bundle")

	# المبيعات (الخروج من المدينة يؤمّن ما في الحقيبة تلقائياً)
	check("sell_only_at_center", EconomyManager.sell_item("cash_bundle") == 0)
	TravelManager.travel_to(TravelManager.Hub.SALES_CENTER, true)
	check("city_exit_extracts", not HeistCityManager.has_unextracted() and GameState.item_count("cash_bundle") > cash_items_before, "cafe=%d" % cafe)
	var sold := EconomyManager.sell_all_loot()
	# قد تكتمل مهمة «بِع غنائم» فتضيف مكافأتها للكاش
	check("sold_loot_dirty_cash", sold > 0 and EconomyManager.dirty_cash >= sold and GameState.item_count("cash_bundle") == 0, "sold=%d cash=%d" % [sold, EconomyManager.dirty_cash])

	# 3) الموتيل: الخزنة، المقايضة، الروليت، الشحنات، المهام
	TravelManager.travel_to(TravelManager.Hub.MOTEL, true)
	EconomyManager.add_dirty(600000)
	var cash0 := EconomyManager.dirty_cash
	MotelManager.stash_deposit(100000)
	check("stash", MotelManager.stash_cash == 100000 and EconomyManager.dirty_cash == cash0 - 100000)
	var lost := PrisonManager.police_arrest()
	check("police_takes_bag_only", EconomyManager.dirty_cash == 0 and MotelManager.stash_cash == 100000, "lost=%d" % lost)
	MotelManager.stash_withdraw(100000)
	EconomyManager.add_dirty(900000)
	GameState.add_item("deposit_key", 2)
	check("barter_decoder", MotelManager.barter("decoder") and GameState.item_count("decoder") == 1)
	check("barter_locked_by_authority", not MotelManager.barter("eviction"))
	check("bet_cap", MotelManager.spin(MotelManager.bet_cap() + 1, "red") == -1 and MotelManager.bet_cap() == 10000)
	var before_bet := EconomyManager.dirty_cash
	var n := MotelManager.spin(5000, "red")
	check("roulette", n >= 0 and n <= 36, "n=%d cash %d -> %d" % [n, before_bet, EconomyManager.dirty_cash])
	check("shipments_by_authority", MotelManager.available_shipments().size() == 1, str(MotelManager.available_shipments().map(func(s): return s.id)))
	MotelManager.order_shipment("tools")
	MotelManager.check_deliveries(int(Time.get_unix_time_from_system()) + 400)
	check("shipment_delivered_offline", GameState.item_count("drill") >= 1 and MotelManager.orders.is_empty())
	MotelManager.refresh_daily(true)
	check("daily_quests", MotelManager.active_quests.size() == 3, str(MotelManager.active_quests))

	# 2) الأراضي: بحث ← شراء ← استئجار (مستوطنة لها مالك) ← طاولة غسيل
	var unowned: SettlementData = null
	var owned: SettlementData = null
	for s in st.districts[0].settlements + st.districts[1].settlements + st.districts[2].settlements + st.districts[3].settlements:
		if s.has_owner() and owned == null:
			owned = s
		if not s.has_owner() and unowned == null:
			unowned = s
	check("buy_before_research_denied", not LandManager.buy_title(1))
	check("research_l1", LandManager.research_title(1))
	check("research_l3_denied", not LandManager.research_title(3))
	check("buy_title_l1", LandManager.buy_title(1) and GameState.item_count("title_plot_1") == 1)
	if unowned:
		check("rent_unowned_denied", LandManager.rent_check(unowned.id, unowned.plots[0].id) != "", LandManager.rent_check(unowned.id, unowned.plots[0].id))
	var free: LandPlotData = owned.vacant_plots()[0]
	check("rent_needs_documents", LandManager.rent_check(owned.id, free.id) != "", LandManager.rent_check(owned.id, free.id))
	GameState.add_item("document", 3)
	var docs0 := GameState.item_count("document")
	check("rent_plot", LandManager.rent_plot(owned.id, free.id) and LandManager.has_home() and GameState.item_count("document") == docs0 - 3 and GameState.item_count("title_plot_1") == 0, "docs %d -> %d" % [docs0, GameState.item_count("document")])
	check("laptop_tier", LandManager.laptop_tier() == owned.level, LandManager.tier_roman(LandManager.laptop_tier()))
	check("travel_home_ok", TravelManager.can_travel(TravelManager.Hub.HOME) == "")
	check("desk_needs_equipment", not EconomyManager.deposit_to_desk(1000))
	LandManager.place_equipment("laundering_desk")
	check("desk_deposit", EconomyManager.deposit_to_desk(200000) and int(EconomyManager.desk_pool) == 200000)
	# الغسيل أثناء الإغلاق: محاكاة مرور ساعتين
	var bank0 := EconomyManager.bank_balance
	var now := int(Time.get_unix_time_from_system())
	EconomyManager.desk_last_unix = now - 7200
	var washed := EconomyManager.update_desk(now)
	check("offline_laundering", washed == 120000 and EconomyManager.bank_balance - bank0 == int(120000 * (1.0 - owned.tax_rate)), "washed=%d bank+%d tax=%d" % [washed, EconomyManager.bank_balance - bank0, owned.uncollected_tax])

	# حفظ/تحميل الولاية (عبر القواميس)
	var saved := {"state": st.to_dict(), "land": LandManager.to_state_dict()}
	var re := StateData.from_dict(saved.state)
	check("state_roundtrip", re.locate_settlement(owned.id)[1].find_plot(free.id).tenant_id == GameState.player_id and re.locate_settlement(owned.id)[1].find_plot(free.id).has_equipment("laundering_desk"))

	# 4) السجن الفيدرالي: الاستسلام ← سنوات ← نفوذ ← الهروب لولاية جديدة
	var wealth := EconomyManager.total_wealth() + MotelManager.stash_cash + PrisonManager._property_value()
	var years := PrisonManager.surrender_to_feds()
	check("sentence_years", years == PrisonManager.years_for(wealth) and years >= 2 and years <= 40, "wealth=%d years=%d" % [wealth, years])
	check("state_wiped", GameState.state == null and GameState.in_prison and EconomyManager.bank_balance == 0 and not LandManager.has_home())
	check("profile_kept", int(GameState.profile.jail_years) == years and PrisonManager.authority_level() >= 0, "authority=%d rewards=%s" % [PrisonManager.authority_level(), GameState.profile.rewards])
	check("cannot_travel_in_prison", TravelManager.can_travel(TravelManager.Hub.MOTEL) != "")
	check("escape_new_state", PrisonManager.escape("sahel") and GameState.state.id == "sahel" and not GameState.in_prison)
	check("authority_survives_wipe", int(GameState.profile.jail_years) == years)
	# حكم كبير جداً يُحدّ بـ40 سنة، ويرفع النفوذ ويفتح مكافآت وشحنات حصرية
	EconomyManager.add_bank(50000000)
	var y2 := PrisonManager.imprison("federal_raid")
	check("max_40_years", y2 == 40)
	check("rewards_unlocked", GameState.profile.rewards.has("shipment_contraband_crate"), str(GameState.profile.rewards))
	PrisonManager.escape("jabal")
	check("exclusive_shipment_unlocked", MotelManager.available_shipments().any(func(s): return s.id == "contraband"))
	check("bet_cap_grows", MotelManager.bet_cap() > 10000, str(MotelManager.bet_cap()))
	# المداهمة الأسبوعية تُطلق تلقائياً عند انتهاء المدة
	GameState.state.started_at_unix -= Balance.WIPE_PERIOD_SEC + 10
	GameState._raid_check = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check("weekly_raid_auto", GameState.in_prison)

	print("CORE RESULT %s (%d failures)" % ["pass" if fails == 0 else "fail", fails])
	get_tree().quit(1 if fails > 0 else 0)
