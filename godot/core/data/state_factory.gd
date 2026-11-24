class_name StateFactory
extends RefCounted
## يولّد ولاية جديدة: 10 مقاطعات (4×م1، 4×م2، 2×م3)، في كل منها مستوطنتان و10 قطع لكل مستوطنة.
## بعض المستوطنات تملكها عشائر من البداية، وبعضها بلا مالك (يشتريها لاعب).

const STATE_NAMES := {"sahra": "ولاية الصحراء", "sahel": "ولاية الساحل", "jabal": "ولاية الجبل"}
const DISTRICT_NAMES := ["الوادي", "الرمال", "النخيل", "السوق", "الميناء", "الجسر", "المصانع", "التلال", "القلعة", "القمة"]
const CLANS := ["الأفاعي", "ذئاب الميناء", "النسور السود"]


static func create(state_id: String, seed := 0) -> StateData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(state_id)
	var st := StateData.new()
	st.id = state_id
	st.display_name = STATE_NAMES.get(state_id, state_id)
	st.started_at_unix = int(Time.get_unix_time_from_system())
	for i in Balance.DISTRICTS_PER_STATE:
		var d := DistrictData.new()
		d.id = "%s_d%d" % [state_id, i]
		d.display_name = DISTRICT_NAMES[i % DISTRICT_NAMES.size()]
		d.level = Balance.DISTRICT_LEVELS[i]
		d.clan_owner = CLANS[rng.randi() % CLANS.size()] if rng.randf() < 0.6 else ""
		for k in Balance.SETTLEMENTS_PER_DISTRICT:
			var s := SettlementData.new()
			s.id = "%s_s%d" % [d.id, k]
			s.display_name = "مستوطنة %s %d" % [d.display_name, k + 1]
			s.level = d.level
			s.tax_rate = [0.0, 0.05, 0.07, 0.10][d.level]
			if rng.randf() < 0.55:
				s.owner_type = SettlementData.OwnerType.CLAN
				s.owner_id = CLANS[rng.randi() % CLANS.size()]
			for p in Balance.PLOTS_PER_SETTLEMENT:
				var plot := LandPlotData.new()
				plot.id = "%s_p%d" % [s.id, p]
				if s.has_owner() and rng.randf() < 0.3:
					plot.tenant_id = "npc_%d" % rng.randi_range(100, 999)
				s.plots.append(plot)
			d.settlements.append(s)
		st.districts.append(d)
	return st
