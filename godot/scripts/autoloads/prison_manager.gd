extends Node
## PrisonManager (Autoload): السجن الفيدرالي والنفوذ والمسح الأسبوعي.
## - الاعتقال العادي (شرطة): يصادر الحقيبة فقط (police_arrest).
## - السجن الفيدرالي: بالاستسلام للفيدراليين، أو بالمداهمة الأسبوعية (بعد 7 أيام من بدء الولاية).
##   تُصادر كل ثروتك وممتلكاتك في الولاية وتُحوَّل إلى «سنوات سجن»:
##   سنة أساسية + سنة لكل 250,000، بحد أقصى 40 سنة للحكم الواحد.
## - سنوات السجن تقدم دائم (في الملف الدائم) يرفع «النفوذ» ويفتح مكافآت دائمة (وشوم، مظاهر، شحنات حصرية).
## - الخروج: تختار ولاية جديدة، فتبدأ بيانات الولاية من الصفر مع بقاء النفوذ.

signal imprisoning(reason: String)     # قبل المصادرة (لتسجيل أفضل نتيجة مثلاً)
signal police_arrested(lost_value: int)
signal sentenced(years: int, confiscated_value: int, total_years: int, reason: String)
signal authority_level_up(level: int, rewards: Array)
signal released(state_id: String)

const STATES := ["sahra", "sahel", "jabal"]

var extra_wealth: Callable = Callable()  # ثروة إضافية تحسبها اللعبة (غنائم، رفوف، منزل…)


func _ready() -> void:
	GameState.federal_raid_due.connect(func(): imprison("federal_raid"))


func authority_level() -> int:
	return level_for_years(int(GameState.profile.jail_years))


## مستوى النفوذ لعدد سنوات (يستخدمه الخادم أيضاً)
static func level_for_years(years: int) -> int:
	var lvl := 0
	for i in Balance.AUTHORITY_THRESHOLDS.size():
		if years >= Balance.AUTHORITY_THRESHOLDS[i]:
			lvl = i
	return lvl


## المكافآت الدائمة التي تُفتح بالانتقال من مستوى إلى آخر
static func rewards_between(before: int, after: int) -> Array:
	var out := []
	for lvl in range(before + 1, after + 1):
		out.append_array(Balance.AUTHORITY_REWARDS.get(lvl, []))
	return out


func years_for(value: int) -> int:
	return clampi(Balance.PRISON_BASE_YEARS + value / Balance.PRISON_DOLLARS_PER_YEAR, 1, Balance.PRISON_MAX_YEARS_PER_SENTENCE)


## الاعتقال العادي من الشرطة: الحقيبة فقط
func police_arrest() -> int:
	var lost := EconomyManager.confiscate_carried()
	lost += HeistCityManager.lose_bag()
	GameState.set_wanted(0)
	police_arrested.emit(lost)
	return lost


func surrender_to_feds() -> int:
	return imprison("surrender")


func imprison(reason: String) -> int:
	if GameState.in_prison:
		return 0
	imprisoning.emit(reason)
	var value := EconomyManager.total_wealth() + MotelManager.stash_cash + _property_value()
	if extra_wealth.is_valid():
		value += int(extra_wealth.call())
	var years := years_for(value)
	var before := authority_level()
	var p: Dictionary = GameState.profile
	p.jail_years = int(p.jail_years) + years
	p.sentences = int(p.sentences) + 1
	var after := authority_level()
	p.authority = after
	var new_rewards := []
	for lvl in range(before + 1, after + 1):
		for r in Balance.AUTHORITY_REWARDS.get(lvl, []):
			if not p.rewards.has(r):
				p.rewards.append(r)
				new_rewards.append(r)
	GameState.save_profile()
	_release_property()
	GameState.wipe_state(reason)
	GameState.in_prison = true
	sentenced.emit(years, value, int(p.jail_years), reason)
	if after > before:
		authority_level_up.emit(after, new_rewards)
	return years


func available_states() -> Array:
	return STATES.duplicate()


## الهروب/الخروج إلى ولاية جديدة: بيانات ولاية جديدة، والتقدم الدائم باقٍ
func escape(state_id: String) -> bool:
	if not GameState.in_prison or not STATES.has(state_id):
		return false
	GameState.start_state(state_id)
	released.emit(state_id)
	return true


## قيمة الممتلكات: قطعة الأرض والمعدات المبنية عليها
func _property_value() -> int:
	if not LandManager.has_home():
		return 0
	var v := int(Balance.TITLE_PRICE[LandManager.home_level()])
	for e in LandManager._home_plot_data().equipment:
		v += int(LandManager.EQUIPMENT.get(e, {}).get("price", 0))
	return v


func _release_property() -> void:
	if LandManager.has_home():
		LandManager.leave_plot()
