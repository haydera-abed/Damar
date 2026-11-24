class_name CityDistrictData
extends Resource
## حيّ من أحياء مدينة السطو: مبانيه القابلة للسطو، وسيارات التهريب (نقاط تأمين الغنائم) فيه.

@export var id: String = ""
@export var display_name: String = ""
@export var buildings: Array[HeistTargetData] = []
@export var fence_cars: Array[String] = []              # معرّفات سيارات التهريب في هذا الحي


func find_building(target_id: String) -> HeistTargetData:
	for b in buildings:
		if b.id == target_id:
			return b
	return null
