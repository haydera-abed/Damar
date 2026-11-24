# طبقة المنطق الأساسية (core) — بنية أنظمة مستوحاة من ROB RUN

طبقة منطق وبيانات مستقلة عن المشاهد: **Resources** للبيانات، **Autoloads** للحالة العامة، و**Signals** فقط للتواصل مع الواجهة.
الميكانيكيات تحاكي ROB RUN كما تصفها أدلة اللاعبين، بأسماء أصلية للأماكن والشخصيات.

## هيكلة المجلدات

```
res://
├── scripts/
│   ├── resources/                 بيانات (Custom Resources) — to_dict / from_dict للحفظ
│   │   ├── state_data.gd             StateData        الولاية: 10 مقاطعات + بداية الموسم
│   │   ├── district_data.gd          DistrictData     مقاطعة م1..م3 + عشيرة + مستوطنات
│   │   ├── settlement_data.gd        SettlementData   مستوطنة (مالك لاعب/عشيرة/لا أحد) + ضريبة + قطع
│   │   ├── land_plot_data.gd         LandPlotData     قطعة: الساكن، تاريخ الإيجار، المعدات
│   │   ├── city_district_data.gd     CityDistrictData حيّ في مدينة السطو: مبانٍ + سيارات تهريب
│   │   ├── heist_target_data.gd      HeistTargetData  مبنى قابل للسطو (أداة، إنذار، هدف كبير، غنائم)
│   │   ├── quest_data.gd             QuestData        مهمة يومية بشرط نفوذ
│   │   ├── shipment_data.gd          ShipmentData     شحنة سوق سوداء
│   │   ├── barter_recipe.gd          BarterRecipe     وصفة مقايضة
│   │   └── item_db.gd                ItemDB           كتالوج العناصر
│   ├── data/
│   │   ├── balance.gd                Balance          كل أرقام التوازن
│   │   └── state_factory.gd          StateFactory     مولّد الولايات
│   ├── autoloads/                 (مسجّلة في project.godot بهذا الترتيب)
│   │   ├── game_state.gd             GameState
│   │   ├── land_manager.gd           LandManager      (+ اللابتوب التجاري)
│   │   ├── economy_manager.gd        EconomyManager
│   │   ├── travel_manager.gd         TravelManager
│   │   ├── heist_city_manager.gd     HeistCityManager (المقابل الأصلي لـ LootyBayManager)
│   │   ├── prison_manager.gd         PrisonManager
│   │   └── motel_manager.gd          MotelManager     (المقابل الأصلي لـ LennyMotelManager)
│   ├── ui/core_panel.gd           CorePanel: واجهة تستمع للإشارات فقط
│   └── tests/                     سكربتات الاختبار
└── scenes/
    ├── ui/core_panel.tscn         مشهد اللوحة (اسحبه إلى أي مشهد)
    └── tests/core_tests.tscn, core_persist.tscn
```

## الحفظ على مستويين
| الملف | المحتوى | المسح |
|---|---|---|
| `user://core_state.json` | الولاية، المخزون، وكل «وحدات الولاية» (الاقتصاد، الأرض، الموتيل، السطو، الموقع) | يُمسح عند السجن الفيدرالي |
| `user://core_profile.json` | سنوات السجن، النفوذ، المكافآت الدائمة، الولايات التي زرتها | **لا يُمسح أبداً** |

كل مدير يسجّل نفسه بـ `GameState.register_module(name, self)` ويوفّر `to_state_dict / from_state_dict / reset_state`،
فيُحفظ ويُستعاد ويُصفَّر مع الولاية تلقائياً. حفظ دوري كل 30 ثانية وعند الإغلاق.

## الأنظمة والإشارات

### 1) الولاية والتنقل — `GameState`, `TravelManager`
- 10 مقاطعات بمستويات 1/2/3، المداهمة الفيدرالية بعد 7 أيام حقيقية من بدء الولاية (`seconds_until_wipe`).
- التنقل السريع بين 4 نقاط: `Hub.HOME` و`Hub.SALES_CENTER` و`Hub.MOTEL` و`Hub.HEIST_CITY`.
  الرفض إن كنت مطلوباً أو في السجن، والمنزل يتطلب أرضاً، ولا مغادرة لمدينة السطو بغنائم لم تُخرجها.
  `hub_scenes` يربط كل نقطة بمشهد (اختياري).
- إشارات: `state_started` `state_loaded` `state_wiped` `inventory_changed` `wanted_changed` `profile_changed` `federal_raid_due`
  و`travel_started` `travel_finished` `travel_denied`.
- **اللابتوب التجاري:** درجته I/II/III = مستوى المقاطعة التي تملك فيها أرضاً (`LandManager.laptop_tier()`).

### 2) الأراضي — `LandManager`
- مقاطعة ← مستوطنة ← قطعة. الحصول على أرض: `research_title(level)` ثم `buy_title(level)` ثم `rent_plot(settlement, plot)`.
- لا استئجار في مستوطنة بلا مالك؛ السند بمستوى المقاطعة؛ الدفع وثائق سوق سوداء (م1) أو كاش (م2، م3).
- سند م3 لا يُبحث إلا إن كنت تسكن مقاطعة م2.
- `place_equipment("laundering_desk")` ثم `EconomyManager.deposit_to_desk(amount)`.
- إشارات: `title_researched` `title_bought` `plot_rented` `plot_left` `equipment_placed` `laptop_tier_changed` `land_error`.

### طاولة الغسيل — `EconomyManager`
- `dirty_cash` (معك، تصادره الشرطة) ← الطاولة ← `bank_balance` (آمن).
- الغسيل يُحسب **بفارق الوقت الحقيقي** `Time.get_unix_time_from_system()`: عند التحميل يُحسب ما غُسل أثناء الإغلاق
  ويُبث `laundered(amount, offline=true)`. ضريبة مالك المستوطنة تُخصم وتتراكم في `uncollected_tax`.
- مركز المبيعات: `sell_item` / `sell_all_loot` (في `Hub.SALES_CENTER` فقط).
- إشارات: `dirty_cash_changed` `bank_changed` `desk_changed` `laundered` `tax_paid` `item_sold` `economy_error`.

### 3) الموتيل — `MotelManager` (صاحبه «رفيق»)
- خزنة الكاش (`stash_deposit/withdraw`)، المقايضة عند الباب المريب (`barter`)، المهام اليومية (3 مهام بحسب اليوم والنفوذ،
  تتقدم تلقائياً من إشارات الأنظمة الأخرى)، الشحنات (`order_shipment` — تصل بالوقت الحقيقي حتى أثناء الإغلاق)،
  والروليت (`spin` بحد أقصى للرهان يرتفع مع النفوذ).
- إشارات: `stash_changed` `barter_done` `barter_failed` `quests_refreshed` `quest_progress` `quest_completed`
  `shipment_ordered` `shipment_delivered` `roulette_result` `motel_error`.

### 4) السجن والنفوذ والمسح — `PrisonManager`
- `police_arrest()`: الاعتقال العادي يصادر الحقيبة فقط (الكاش المحمول والمسروقات وغنائم السطو غير المُخرجة).
- `surrender_to_feds()` أو المداهمة الأسبوعية: تُصادر كل الثروة والممتلكات وتتحول إلى سنوات:
  سنة + سنة لكل 250,000، بحد أقصى 40 للحكم الواحد. السنوات تراكمية دائمة وترفع النفوذ (عتبات 5/15/35/70/120)
  وتفتح مكافآت دائمة (وشوم، مظاهر، شحنات حصرية).
- `escape(state_id)`: ولاية جديدة من الصفر مع بقاء النفوذ.
- إشارات: `police_arrested` `sentenced` `authority_level_up` `released`.

### 5) مدينة السطو — `HeistCityManager` («ميناء سافيرن»)
- 4 أحياء (`CityDistrictData`): وسط المدينة، الشاطئ المشمس، حي الحديقة، تلال الأرز — لكل حي مبانٍ وسيارة تهريب.
- حالات اللاعب: `is_masked` (`set_masked`)، `is_wanted` (من `GameState.wanted`)، `bag_inventory` (غير مؤمّنة).
- `start_heist(id)`: يستهلك الأداة ويرفع الإنذار. **بلا قناع** ترتفع مطلوبيتك (الكاميرات). **الأهداف الكبرى**
  (خزنة البنك، قصر التلال) تطلق `city_alarm_triggered` وتجعلك مطلوباً بالمستوى 4 فوراً.
- `extract_loot("fence_car", car_id, sell)`: ثبات 4 ثوانٍ عند سيارة تهريب ← تأمين الغنائم في المخزون (أو بيعها فوراً).
  `extract_loot("city_exit")`: الخروج من المدينة (التنقل السريع) يؤمّنها تلقائياً — والخروج ممنوع وأنت مطلوب.
- `on_player_busted_or_killed()`: **مقنّع داخل المدينة ← تُمسح الحقيبة كلها**؛ بلا قناع (لم يتعرّف عليك أحد) ← تبقى.
- إشارات: `entered_city` `left_city` `mask_changed` `wanted_state_changed` `heist_started` `heist_progress`
  `heist_completed` `heist_failed` `alarm_raised` `city_alarm_triggered` `police_arrived` `bag_changed`
  `extraction_started` `extraction_progress` `extracted` `loot_lost`.

## ربط الواجهة
الواجهة تستمع فقط، ولا يعرف أي مدير بوجودها:
```gdscript
func _ready() -> void:
    EconomyManager.bank_changed.connect(func(v): bank_label.text = str(v))
    LandManager.land_error.connect(func(r): toast(r))
    PrisonManager.sentenced.connect(_on_sentenced)
```
انظر `scripts/ui/core_panel.gd` و`scenes/ui/core_panel.tscn` كمثال كامل.

## الاختبار
```
godot --headless --path godot res://scenes/tests/core_tests.tscn -- --core-test
godot --headless --path godot res://scenes/tests/core_persist.tscn -- --core-persist-test --phase=1
godot --headless --path godot res://scenes/tests/core_persist.tscn -- --core-persist-test --phase=2
```

## الربط باللعبة ثلاثية الأبعاد
| في اللعبة | أين تعيش البيانات الآن |
|---|---|
| `main.cash` / `main.bank` | خصائص تمرير إلى `EconomyManager.dirty_cash` / `bank_balance` |
| `crime.launder_pool` (طاولة الغسيل في المنزل) | `EconomyManager.desk_pool` — يُغسل بالوقت الحقيقي حتى واللعبة مغلقة؛ المعدّل (`rate_override_per_sec`) والضريبة (`tax_hook`) يزوّدهما نظام المنزل/الأحياء |
| `crime.tools` (الأدوات، أجهزة فك التشفير) | `GameState.inventory` |
| `land.docs` (المستندات) | `GameState.inventory["document"]` |
| `land.motel_cash` (خزنة الموتيل) | `MotelManager.stash_cash` |
| المداهمة الفيدرالية / الاستسلام (الإعدادات) | `PrisonManager.imprison` → `sentenced` → مسح العالم + قائمة اختيار الولاية → `escape()` |
| قائمة الموتيل | المقايضة والمهام اليومية والشحنات والروليت عبر `MotelManager` |
| التنقل السريع (مفتاح J) | `TravelManager` + نقل اللاعب إلى المنزل/المشتري/الموتيل/وسط المدينة |
| القناع (X) | `HeistCityManager.set_masked` |
| السرقات والبيع | تقدم المهام اليومية (`MotelManager.report`) |

- **الترحيل:** أول تشغيل بعد التحديث ينقل المال والأدوات والمستندات وخزنة الموتيل من `damar_save.cfg` مرة واحدة
  (`GameState.bridged`)، وبعدها المصدر هو `core_state.json`.
- **اللعب الجماعي:** تُعطَّل كتابة حفظ طبقة المنطق (`GameState.persistence = false`) ويُطبَّق ملف اللاعب من الخادم.

## ما لم يُربط بعد (بصراحة)
- مستوطنات اللعبة وقطعها ومنزلها (`land.gd`/`house.gd`) ما زالت نموذجها الخاص؛ `LandManager` يُستخدم في الاختبارات المنطقية فقط.
- مدينة السطو المنطقية (`HeistCityManager`) لا تقابلها مبانٍ ثلاثية الأبعاد بعد؛ السرقات في المدينة تمر عبر `crime.gd`.
- اللعب الجماعي لا يرسل بيانات طبقة المنطق عبر الشبكة.
