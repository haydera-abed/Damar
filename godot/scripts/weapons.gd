class_name Weapons
extends Node
## الأسلحة: تصويب (زر الفأرة الأيمن) وإطلاق (الأيسر)، رصاص بالأشعة (Hitscan) يصيب الجدران والسيارات والشخصيات،
## ومضة فوهة وأثر رصاصة وصوت. أهداف الشخصيات تُفحص كأسطوانات (أرخص من فيزياء كل شخصية).

const CATALOG := {
	"pistol": {"name": "مسدس", "price": 6000, "damage": 26.0, "rate": 0.32, "spread": 0.012, "pellets": 1, "range": 70.0},
	"smg": {"name": "رشاش خفيف", "price": 26000, "damage": 15.0, "rate": 0.09, "spread": 0.03, "pellets": 1, "range": 60.0},
	"shotgun": {"name": "بندقية خرطوش", "price": 18000, "damage": 13.0, "rate": 0.85, "spread": 0.09, "pellets": 7, "range": 30.0},
	"police_pistol": {"name": "مسدس الشرطة", "price": 0, "damage": 24.0, "rate": 0.3, "spread": 0.012, "pellets": 1, "range": 70.0},
	"police_rifle": {"name": "بندقية الشرطة", "price": 0, "damage": 20.0, "rate": 0.12, "spread": 0.02, "pellets": 1, "range": 90.0},
}

var game: Node
var owned: Array[String] = []
var current := ""
var ammo := 0
var aiming := false
var _cooldown := 0.0
var _flash: OmniLight3D
var _tracers: Array = []


func _init(g: Node) -> void:
	game = g


func _ready() -> void:
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1, 0.75, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	add_child(_flash)


func give(w: String) -> void:
	if not owned.has(w):
		owned.append(w)
	current = w
	if ammo < 30:
		ammo += 30


func cycle() -> void:
	if owned.is_empty():
		game.hud.toast("لا تملك سلاحاً — اشترِ من السوق السوداء")
		return
	var i := owned.find(current)
	current = "" if i == owned.size() - 1 else owned[i + 1]
	game.hud.toast("السلاح: " + (CATALOG[current].name if current != "" else "بلا سلاح"))


func drop_current() -> void:
	if current != "":
		owned.erase(current)
		current = ""


func to_dict() -> Dictionary:
	return {"owned": owned, "current": current, "ammo": ammo}


func from_dict(d: Dictionary) -> void:
	owned.assign(d.get("owned", []))
	current = d.get("current", "")
	ammo = d.get("ammo", 0)


func tick(dt: float) -> void:
	_cooldown -= dt
	_flash.light_energy = maxf(0.0, _flash.light_energy - dt * 60.0)
	for t in _tracers.duplicate():
		t[1] -= dt
		if t[1] <= 0.0:
			t[0].queue_free()
			_tracers.erase(t)
	aiming = game.playing() and game.player.car == null and current != "" and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not game.player.surrendered and not game.player.downed
	if aiming and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _cooldown <= 0.0:
		_fire_player()


func _fire_player() -> void:
	if ammo <= 0:
		_cooldown = 0.4
		game.hud.toast("نفدت الذخيرة")
		return
	var w: Dictionary = CATALOG[current]
	_cooldown = w.rate
	ammo -= 1
	var cam: Camera3D = game.cam
	var origin: Vector3 = game.player.global_position + Vector3(0, 1.45, 0)
	var aim_point := _aim_point(cam, w.range)
	for p in w.pellets:
		var dir: Vector3 = (aim_point - origin).normalized()
		dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * w.spread).normalized()
		shoot(origin, dir, w.range, w.damage, game.player)
		if game.net.is_online():
			game.net.shot(origin, dir, w.range, w.damage)
	game.on_gunshot(origin, true)


## النقطة التي يصوّب إليها مركز الشاشة
func _aim_point(cam: Camera3D, rng: float) -> Vector3:
	var vp := cam.get_viewport().get_visible_rect().size / 2.0
	var from := cam.project_ray_origin(vp)
	var dir := cam.project_ray_normal(vp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (rng + 10.0), Cfg.LAYER_WORLD | Cfg.LAYER_VEHICLES)
	var hit: Dictionary = game._space.intersect_ray(q)
	return hit.position if hit else from + dir * rng


## طلقة واحدة: تفحص الشخصيات ثم الجدران/السيارات، وتعيد الهدف المصاب
func shoot(origin: Vector3, dir: Vector3, rng: float, dmg: float, shooter: Node) -> Node:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng, Cfg.LAYER_WORLD | Cfg.LAYER_VEHICLES)
	var hit: Dictionary = game._space.intersect_ray(q)
	var end: Vector3 = hit.position if hit else origin + dir * rng
	var max_t := origin.distance_to(end)
	var best: Node = null
	var best_t := max_t
	for c in game.shootables():
		if c == shooter or not is_instance_valid(c) or c.get("dead") == true:
			continue
		var base: Vector3 = c.global_position
		var to := base + Vector3(0, 0.9, 0) - origin
		var t := to.dot(dir)
		if t < 0.0 or t > best_t:
			continue
		var closest := origin + dir * t
		var dh := Vector2(closest.x - base.x, closest.z - base.z).length()
		if dh < 0.42 and closest.y > base.y and closest.y < base.y + 1.85:
			best = c
			best_t = t
	if best:
		end = origin + dir * best_t
		best.take_damage(dmg, shooter)
	elif hit and hit.collider is Car:
		(hit.collider as Car).apply_impulse(dir * 60.0, end - (hit.collider as Car).global_position)
	_tracer(origin, end)
	_flash.global_position = origin + dir * 0.6
	_flash.light_energy = 4.0
	return best


func _tracer(a: Vector3, b: Vector3) -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(3.0, 2.4, 1.2)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(mi)
	_tracers.append([mi, 0.05])
