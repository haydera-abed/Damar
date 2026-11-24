class_name HeistTargetData
extends Resource
## مبنى/هدف قابل للسطو في مدينة السطو.
## is_major = هدف كبير (مثل خزنة البنك): بدء السطو عليه يطلق إنذاراً عاماً للمدينة كلها.

@export var id: String = ""
@export var title: String = ""
@export var district: String = ""
@export var duration: float = 6.0                       # ثوانٍ للتنفيذ
@export var required_tool: String = ""                  # يُستهلك من المخزون (مثل "drill")
@export_range(1, 5) var alarm_level: int = 1
@export var is_major: bool = false
@export var loot_table: Dictionary = {}                 # item_id -> [أدنى، أعلى]
@export var cooldown: float = 120.0
