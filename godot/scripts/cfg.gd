class_name Cfg
## إعدادات اللعبة الثابتة + أدوات شبكة الشوارع

const N := 6                    # عدد المربعات السكنية في كل اتجاه
const BLOCK := 50.0             # حجم المربع السكني (م)
const ROAD := 16.0              # عرض الشارع (م)
const CELL := BLOCK + ROAD
const HALF := N * CELL / 2.0
const BOUND := HALF + ROAD / 2.0 - 1.2
const LANE := 3.6               # إزاحة المسار عن منتصف الشارع
const GOAL := 250000
const POLICE_TARGET := [2, 2, 3, 5, 7, 9]
const NONE := Vector2i(-1, -1)

const LAYER_WORLD := 1
const LAYER_VEHICLES := 2
const LAYER_CHARS := 4

const STORE_TYPES := {
	"shop":  {"name": "سوبرماركت",     "value": [700, 1600],    "time": 4.0,  "heat": 1, "cd": 60.0,  "color": Color("30d5ff"), "h": 7.0},
	"gas":   {"name": "محطة وقود",     "value": [1100, 2600],   "time": 5.0,  "heat": 2, "cd": 75.0,  "color": Color("ffa21f"), "h": 7.0},
	"jewel": {"name": "مجوهرات",       "value": [7000, 15000],  "time": 7.0,  "heat": 3, "cd": 120.0, "color": Color("ff3fd0"), "h": 9.0},
	"bank":  {"name": "البنك المركزي", "value": [30000, 60000], "time": 10.0, "heat": 5, "cd": 200.0, "color": Color("45ff8a"), "h": 16.0},
}
const STORE_LIST := ["bank", "jewel", "jewel", "gas", "gas", "gas", "shop", "shop", "shop", "shop", "shop", "shop"]
const CAR_MODELS := ["sedan", "sedan_sports", "suv", "suv_luxury", "taxi", "van", "hatchback_sports", "delivery_van"]


static func node_pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * CELL - HALF, 0.0, n.y * CELL - HALF)


static func nearest_node(p: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi((p.x + HALF) / CELL), 0, N), clampi(roundi((p.z + HALF) / CELL), 0, N))


static func neighbors(n: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if n.x > 0: out.append(Vector2i(n.x - 1, n.y))
	if n.x < N: out.append(Vector2i(n.x + 1, n.y))
	if n.y > 0: out.append(Vector2i(n.x, n.y - 1))
	if n.y < N: out.append(Vector2i(n.x, n.y + 1))
	return out


## نقطة الوصول عند التقاطع t على مسار اليمين (القادم من التقاطع p)
static func lane_point(p: Vector2i, t: Vector2i) -> Vector3:
	var c := node_pos(t)
	if p == NONE:
		return c
	var dx := t.x - p.x
	var dz := t.y - p.y
	return Vector3(c.x - dz * LANE, 0.0, c.z + dx * LANE)


static func heading_of(v: Vector3) -> float:
	return atan2(v.x, v.z)


static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "$" + s + out
