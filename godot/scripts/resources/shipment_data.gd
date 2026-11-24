class_name ShipmentData
extends Resource
## شحنة سوق سوداء تُطلب من الموتيل: تُدفع الآن وتصل بعد مدة. بعضها لا يُفتح إلا بمستوى نفوذ،
## وبعضها حصري لمكافآت السجن الدائمة.

@export var id := ""
@export var title := ""
@export var price := 0
@export var delivery_seconds := 600
@export var required_authority := 0
@export var exclusive_reward := ""               # إن كانت مكافأة سجن دائمة مطلوبة
@export var contents := {}                       # item_id -> عدد
