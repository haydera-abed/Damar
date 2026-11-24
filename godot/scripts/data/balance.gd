class_name Balance
extends RefCounted
## كل أرقام التوازن في مكان واحد (لتعديلها دون لمس المنطق).

# الولاية والموسم
const DISTRICTS_PER_STATE := 10
const DISTRICT_LEVELS := [1, 1, 1, 1, 2, 2, 2, 2, 3, 3]
const SETTLEMENTS_PER_DISTRICT := 2
const PLOTS_PER_SETTLEMENT := 10
const WIPE_PERIOD_SEC := 7 * 24 * 3600            # المداهمة الفيدرالية الأسبوعية

# سندات الأرض: بحث ثم شراء (اللابتوب التجاري). المستوى 1 يُدفع وثائق بعد تحديث 4 نوفمبر
const TITLE_RESEARCH := {1: 50000, 2: 200000, 3: 1000000}
const TITLE_PRICE := {1: 100000, 2: 800000, 3: 2000000}
const RENT_COST := {1: {"documents": 3}, 2: {"cash": 150000}, 3: {"cash": 500000}}

# طاولة الغسيل (تعمل أثناء إغلاق اللعبة)
const DESK_RATE_PER_HOUR := 60000.0
const DESK_CAP := {1: 300000, 2: 1000000, 3: 3000000}
const DESK_PRICE := 40000

# اللابتوب التجاري: الدرجة = أعلى مستوى مقاطعة لك فيها أرض (I بلا أرض)
const LAPTOP_ITEMS := {
	"lockpick": {"tier": 1, "price": 400},
	"drill": {"tier": 1, "price": 3000},
	"decoder": {"tier": 2, "price": 0, "barter_only": true},
	"title_plot_1": {"tier": 1, "research": true},
	"title_plot_2": {"tier": 2, "research": true},
	"title_plot_3": {"tier": 3, "research": true},
}

# الموتيل
const ROULETTE_BET_CAP := [10000, 25000, 50000, 100000, 250000]   # حسب مستوى النفوذ

# السجن والنفوذ (تقدم دائم لا يُمسح)
const PRISON_BASE_YEARS := 1
const PRISON_DOLLARS_PER_YEAR := 250000
const PRISON_MAX_YEARS_PER_SENTENCE := 40
const AUTHORITY_THRESHOLDS := [0, 5, 15, 35, 70, 120]             # سنوات تراكمية لكل مستوى نفوذ
const AUTHORITY_REWARDS := {
	1: ["tattoo_cell_block"],
	2: ["tattoo_barbed_wire", "shipment_contraband_crate"],
	3: ["outfit_prison_boss", "shipment_gold_run"],
	4: ["tattoo_kingpin", "shipment_armory"],
	5: ["outfit_legend", "shipment_legend"],
}

# مدينة السطو
const HEIST_ALARM_SECONDS := 25.0                 # كل مستوى إنذار يقرّب الشرطة
const EXTRACTION_HOLD := 4.0                      # ثوانٍ عند نقطة الإخراج
