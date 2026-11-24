class_name DistrictData
extends Resource
## مقاطعة داخل الولاية. مستواها (1..3) يحدد وثيقة الأرض المطلوبة، ومستوى «اللابتوب التجاري»
## الذي يفتحه امتلاك أرض فيها، وتكلفة الاستئجار.

@export var id := ""
@export var display_name := ""
@export_range(1, 3) var level := 1
@export var clan_owner := ""                       # العشيرة المسيطرة (للضرائب ونسبة الغسيل)
@export var settlements: Array[SettlementData] = []


func find_settlement(settlement_id: String) -> SettlementData:
	for s in settlements:
		if s.id == settlement_id:
			return s
	return null


func to_dict() -> Dictionary:
	var arr := []
	for s in settlements:
		arr.append(s.to_dict())
	return {"id": id, "name": display_name, "level": level, "clan": clan_owner, "settlements": arr}


static func from_dict(d: Dictionary) -> DistrictData:
	var r := DistrictData.new()
	r.id = d.get("id", "")
	r.display_name = d.get("name", "")
	r.level = int(d.get("level", 1))
	r.clan_owner = d.get("clan", "")
	for sd in d.get("settlements", []):
		r.settlements.append(SettlementData.from_dict(sd))
	return r
