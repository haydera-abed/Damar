class_name HeistTargetData
extends Resource
## هدف سطو في مدينة السطو: مدته، أداته المطلوبة، مستوى الإنذار، وجدول الغنائم.

@export var id := ""
@export var title := ""
@export var district := ""
@export var duration := 6.0                      # ثوانٍ للتنفيذ
@export var required_tool := ""                  # يُستهلك من الحقيبة (مثل "drill")
@export_range(1, 5) var alarm_level := 1
@export var loot_table := {}                     # item_id -> [أدنى، أعلى]
@export var cooldown := 120.0
