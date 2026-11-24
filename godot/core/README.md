# طبقة المنطق الأساسية (core) — بنية أنظمة مستوحاة من ROB RUN

طبقة منطق وبيانات مستقلة عن المشاهد: **Resources** للبيانات، **Autoloads** للحالة العامة، و**Signals** فقط للتواصل مع الواجهة.
الميكانيكيات تحاكي ROB RUN كما تصفها أدلة اللاعبين، بأسماء أصلية للأماكن والشخصيات.

## البنية

```
core/
  resources/      بيانات (Custom Resources) قابلة للحفظ: to_dict / from_dict
    state_data.gd        StateData      الولاية: 10 مقاطعات + وقت بدء الموسم
    district_data.gd     DistrictData   مقاطعة بمستوى 1..3 + عشيرة مسيطرة + مستوطنات
    settlement_data.gd   SettlementData مستوطنة (مالك لاعب/عشيرة/لا أحد) + نسبة ضريبة + قطع
    land_plot_data.gd    LandPlotData   قطعة: الساكن، تاريخ الإيجار، المعدات (طاولة الغسيل…)
    quest_data.gd        QuestData      مهمة يومية بشرط نفوذ
    shipment_data.gd     ShipmentData   شحنة سوق سوداء (سعر، مدة وصول، نفوذ، مكافأة حصرية)
    barter_recipe.gd     BarterRecipe   وصفة مقايضة (عناصر + كاش ← معدات)
    heist_target_data.gd HeistTargetData هدف سطو (مدة، أداة، إنذار، جدول غنائم)
    item_db.gd           ItemDB         كتالوج العناصر (قيمة البيع، «ساخنة» تُصادر)
  data/
    balance.gd           Balance        كل أرقام التوازن في مكان واحد
    state_factory.gd     StateFactory   يولّد ولاية (4×م1، 4×م2، 2×م3؛ مستوطنتان × 10 قطع)
  autoload/              (مسجّلة في project.godot بهذا الترتيب)
    game_state.gd        GameState
    land_manager.gd      LandManager      (+ اللابتوب التجاري)
    economy_manager.gd   EconomyManager
    travel_manager.gd    TravelManager
    heist_city_manager.gd HeistCityManager
    prison_manager.gd    PrisonManager
    motel_manager.gd     MotelManager
  ui/core_panel.gd       CorePanel  لوحة تستمع للإشارات فقط (مثال على الفصل)
tests/core_tests.tscn    اختبار منطقي شامل (49 فحصاً)
tests/core_persist.tscn  اختبار الحفظ الحقيقي على القرص عبر تشغيلين
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
- 4 أحياء: وسط المدينة، الشاطئ المشمس، الحديقة، الميناء (الرابع افتراض — رسالة المواصفات انقطعت).
- `start_heist(id)` يستهلك الأداة المطلوبة ويرفع الإنذار؛ الغنائم تذهب إلى حقيبة **غير مؤمّنة**.
  الإنذار يستدعي الشرطة بمرور الوقت. `begin_extraction(point)` + ثبات 4 ثوانٍ ← تُنقل الغنائم إلى المخزون.
  القبض عليك يُفقدك ما لم تُخرجه.
- إشارات: `entered_city` `heist_started` `heist_progress` `heist_completed` `heist_failed` `alarm_raised`
  `police_arrived` `extraction_started` `extraction_progress` `extracted` `loot_lost`.

## ربط الواجهة
الواجهة تستمع فقط، ولا يعرف أي مدير بوجودها:
```gdscript
func _ready() -> void:
    EconomyManager.bank_changed.connect(func(v): bank_label.text = str(v))
    LandManager.land_error.connect(func(r): toast(r))
    PrisonManager.sentenced.connect(_on_sentenced)
```
انظر `core/ui/core_panel.gd` كمثال كامل.

## الاختبار
```
godot --headless --path godot res://tests/core_tests.tscn -- --core-test
godot --headless --path godot res://tests/core_persist.tscn -- --core-persist-test --phase=1
godot --headless --path godot res://tests/core_persist.tscn -- --core-persist-test --phase=2
```

## الحالة الحالية (بصراحة)
- هذه الطبقة تعمل وتُختبر مستقلة، لكن **اللعبة ثلاثية الأبعاد الحالية ما زالت تستخدم أنظمتها القديمة**
  (`scripts/land.gd` و`house.gd` و`gangs.gd`…). ربطها بهذه الطبقة (نقل الاقتصاد والأراضي والسجن إليها) خطوة تالية.
- اللعب الجماعي لا يستخدم هذه الطبقة بعد (الخادم في `scripts/net.gd`).
