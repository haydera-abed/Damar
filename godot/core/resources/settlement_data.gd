class_name SettlementData
extends Resource
## مستوطنة يملكها لاعب أو عشيرة، وداخلها قطع أراضٍ. لا يُسمح بالاستئجار إلا إن كان لها مالك.

enum OwnerType { NONE, PLAYER, CLAN }

@export var id := ""
@export var display_name := ""
@export_range(1, 3) var level := 1
@export var owner_type: OwnerType = OwnerType.NONE
@export var owner_id := ""
@export_range(0.0, 0.5) var tax_rate := 0.05          # نسبة المالك من غسيل السكان
@export var plots: Array[LandPlotData] = []
@export var uncollected_tax := 0                      # لا تتراكم ضرائب جديدة حتى تُجمع (كما في ROB RUN)


func has_owner() -> bool:
	return owner_type != OwnerType.NONE and owner_id != ""


func vacant_plots() -> Array[LandPlotData]:
	var out: Array[LandPlotData] = []
	for p in plots:
		if p.is_vacant():
			out.append(p)
	return out


func find_plot(plot_id: String) -> LandPlotData:
	for p in plots:
		if p.id == plot_id:
			return p
	return null


func to_dict() -> Dictionary:
	var arr := []
	for p in plots:
		arr.append(p.to_dict())
	return {"id": id, "name": display_name, "level": level, "owner_type": owner_type, "owner": owner_id, "tax": tax_rate, "plots": arr, "untaxed": uncollected_tax}


static func from_dict(d: Dictionary) -> SettlementData:
	var r := SettlementData.new()
	r.id = d.get("id", "")
	r.display_name = d.get("name", "")
	r.level = int(d.get("level", 1))
	r.owner_type = int(d.get("owner_type", OwnerType.NONE)) as OwnerType
	r.owner_id = d.get("owner", "")
	r.tax_rate = float(d.get("tax", 0.05))
	r.uncollected_tax = int(d.get("untaxed", 0))
	for pd in d.get("plots", []):
		r.plots.append(LandPlotData.from_dict(pd))
	return r
