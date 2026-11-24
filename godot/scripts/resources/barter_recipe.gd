class_name BarterRecipe
extends Resource
## وصفة مقايضة عند «الباب المريب» في الموتيل: عناصر نادرة + كاش ← معدات متقدمة.

@export var id := ""
@export var title := ""
@export var inputs := {}                         # item_id -> عدد
@export var cash_cost := 0
@export var output_item := ""
@export var output_count := 1
@export var required_authority := 0
