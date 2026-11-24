class_name StateData
extends Resource
## «الولاية»: عالم يُمسح أسبوعياً (المداهمة الفيدرالية). تضم 10 مقاطعات بمستويات 1..3.

@export var id := ""
@export var display_name := ""
@export var districts: Array[DistrictData] = []
@export var started_at_unix := 0                  # بداية الموسم (لحساب المداهمة بعد 7 أيام)


func find_district(district_id: String) -> DistrictData:
	for d in districts:
		if d.id == district_id:
			return d
	return null


## يعيد [المقاطعة، المستوطنة] لمستوطنة معينة
func locate_settlement(settlement_id: String) -> Array:
	for d in districts:
		var s := d.find_settlement(settlement_id)
		if s:
			return [d, s]
	return []


func all_settlements() -> Array[SettlementData]:
	var out: Array[SettlementData] = []
	for d in districts:
		out.append_array(d.settlements)
	return out


func to_dict() -> Dictionary:
	var arr := []
	for d in districts:
		arr.append(d.to_dict())
	return {"id": id, "name": display_name, "districts": arr, "started_at": started_at_unix}


static func from_dict(d: Dictionary) -> StateData:
	var r := StateData.new()
	r.id = d.get("id", "")
	r.display_name = d.get("name", "")
	r.started_at_unix = int(d.get("started_at", 0))
	for dd in d.get("districts", []):
		r.districts.append(DistrictData.from_dict(dd))
	return r
