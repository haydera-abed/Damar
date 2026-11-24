extends Node
## TravelManager (Autoload): التنقل السريع بين النقاط الأربع الرئيسية.
## يبث travel_started ثم travel_finished؛ وإن ضُبط مسار مشهد للنقطة ينتقل إليه (change_scene_to_file).
## قيود: لا تنقل وأنت مطلوب أو في السجن، المنزل يتطلب أرضاً، ولا تغادر مدينة السطو بغنائم لم تُخرجها.

enum Hub { HOME, SALES_CENTER, MOTEL, HEIST_CITY }

signal travel_started(from_hub: int, to_hub: int, seconds: float)
signal travel_finished(hub: int)
signal travel_denied(to_hub: int, reason: String)

const HUB_NAMES := {Hub.HOME: "المنزل/القاعدة", Hub.SALES_CENTER: "مركز المبيعات", Hub.MOTEL: "موتيل الصحراء", Hub.HEIST_CITY: "مدينة السطو"}
const TRAVEL_SECONDS := 2.0

var current_hub: Hub = Hub.MOTEL
var hub_scenes := {}                 # Hub -> "res://…tscn" (اختياري؛ فارغ = بلا تبديل مشهد)
var traveling := false


func can_travel(to_hub: Hub) -> String:
	if traveling:
		return "أنت في الطريق بالفعل"
	if GameState.in_prison:
		return "أنت في السجن"
	if to_hub == current_hub:
		return "أنت هنا بالفعل"
	if GameState.wanted > 0:
		return "لا تنقل سريع وأنت مطلوب — اختفِ أولاً"
	if to_hub == Hub.HOME and not LandManager.has_home():
		return "لا تملك قاعدة: استأجر قطعة أرض أولاً"
	if current_hub == Hub.HEIST_CITY and HeistCityManager.has_unextracted():
		return "معك غنائم لم تُخرجها — توجّه إلى نقطة إخراج"
	return ""


func travel_to(to_hub: Hub, instant := false) -> bool:
	var why := can_travel(to_hub)
	if why != "":
		travel_denied.emit(to_hub, why)
		return false
	traveling = true
	travel_started.emit(current_hub, to_hub, 0.0 if instant else TRAVEL_SECONDS)
	if instant:
		_arrive(to_hub)
	else:
		get_tree().create_timer(TRAVEL_SECONDS).timeout.connect(_arrive.bind(to_hub), CONNECT_ONE_SHOT)
	return true


func _arrive(to_hub: Hub) -> void:
	current_hub = to_hub
	traveling = false
	var path: String = hub_scenes.get(to_hub, "")
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	travel_finished.emit(to_hub)
	GameState.save_state()


func reset_state() -> void:
	current_hub = Hub.MOTEL
	traveling = false


func to_state_dict() -> Dictionary:
	return {"hub": current_hub}


func from_state_dict(d: Dictionary) -> void:
	current_hub = int(d.get("hub", Hub.MOTEL)) as Hub


func _ready() -> void:
	GameState.register_module("travel", self)
