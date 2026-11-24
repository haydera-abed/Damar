class_name LandPlotData
extends Resource
## قطعة أرض داخل مستوطنة. بعد الاستئجار تصبح قاعدة يُوضع فيها معدات (مثل طاولة الغسيل).

@export var id := ""
@export var tenant_id := ""
@export var rented_at_unix := 0
@export var equipment: Array[String] = []           # مثل "laundering_desk", "cargo_bench", "safe"


func is_vacant() -> bool:
	return tenant_id == ""


func has_equipment(kind: String) -> bool:
	return equipment.has(kind)


func to_dict() -> Dictionary:
	return {"id": id, "tenant": tenant_id, "rented_at": rented_at_unix, "equipment": Array(equipment)}


static func from_dict(d: Dictionary) -> LandPlotData:
	var r := LandPlotData.new()
	r.id = d.get("id", "")
	r.tenant_id = d.get("tenant", "")
	r.rented_at_unix = int(d.get("rented_at", 0))
	for e in d.get("equipment", []):
		r.equipment.append(String(e))
	return r
