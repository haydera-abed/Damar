class_name QuestData
extends Resource
## مهمة يومية من الموتيل. تظهر فقط إن كان نفوذ اللاعب (authority_level) كافياً.

enum Objective { ROB_TARGETS, SELL_LOOT, LAUNDER_CASH, EXTRACT_LOOT, SURVIVE_HEIST }

@export var id := ""
@export var title := ""
@export var objective: Objective = Objective.ROB_TARGETS
@export var target_amount := 1
@export var required_authority := 0
@export var reward_cash := 0
@export var reward_items := {}                    # item_id -> عدد
