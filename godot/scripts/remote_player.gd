class_name RemotePlayer
extends Node3D
## لاعب آخر على الشبكة: دمية تعرض موقعه وحركته بسلاسة (استيفاء بين اللقطات)،
## مع بطاقة اسم ونجوم مطلوبية، وسيارته إن كان يقود، والقناع والاستسلام.

const INTERP_DELAY := 0.12      # نعرض الماضي القريب لنستوفي بين لقطتين

var game: Node
var peer_id := 0
var pname := ""
var role := "criminal"
var human: Human
var tag: Label3D
var car: Car
var car_model := ""
var flags := 0
var health := 100.0
var wanted := 0
var dead := false              # للتوافق مع أهداف الأسلحة المحلية (غير مستخدم للإصابة)
var _snaps: Array = []         # [t, pos, yaw, speed, car_xf]


func setup(g: Node, id: int, n: String, r: String) -> void:
	game = g
	peer_id = id
	pname = n
	role = r
	human = Human.new()
	add_child(human)
	human.setup("cop" if role == "cop" else "thief", role != "cop")
	tag = Label3D.new()
	tag.font = game.city.font
	tag.font_size = 56
	tag.pixel_size = 0.006
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.outline_size = 10
	tag.position = Vector3(0, 2.35, 0)
	add_child(tag)
	_update_tag()


func _update_tag() -> void:
	var stars := ""
	for i in wanted:
		stars += "★"
	var auth: int = int(game.net.peers.get(peer_id, {}).get("auth", 0))
	var crown := ("  👑%d" % auth) if auth > 0 else ""     # النفوذ الدائم (سنوات السجن الفيدرالي)
	tag.text = ("🚔 " if role == "cop" else "") + pname + crown + ("\n" + stars if stars != "" else "")
	tag.modulate = Color("6fa0ff") if role == "cop" else (Color("ffcf3a") if wanted > 0 else Color.WHITE)


func set_role(r: String) -> void:
	if r == role:
		return
	role = r
	human.set_role("cop" if r == "cop" else "thief")
	_update_tag()


func push(t: float, pos: Vector3, yaw: float, speed: float, f: int, model: String, car_xf: Transform3D, hp: float, w: int) -> void:
	_snaps.append([t, pos, yaw, speed, car_xf])
	if _snaps.size() > 20:
		_snaps.pop_front()
	if f != flags or w != wanted:
		flags = f
		wanted = w
		human.set_mask(f & Net.F_MASK != 0)
		human.set_hands_up(f & Net.F_SURRENDER != 0)
		if f & Net.F_DOWNED != 0 and human.current != "death":
			human.play_once("death")
		elif f & Net.F_DOWNED == 0 and human.current == "death":
			human.play("idle")
		_update_tag()
	health = hp
	if model != car_model:
		_set_car(model)


func _set_car(model: String) -> void:
	car_model = model
	if car != null and is_instance_valid(car):
		game.remove_car(car)
		car = null
	if model != "":
		# سيارة دمية: تصطدم بها لكن حركتها من الشبكة فقط
		car = game._make_car(model, model == "police_car", Car.AI.PARKED, Transform3D.IDENTITY)
		car.puppet = true
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
	human.visible = model == ""
	tag.position = Vector3(0, 2.35 if model == "" else 2.9, 0)


func _process(_dt: float) -> void:
	if _snaps.size() < 2:
		if _snaps.size() == 1:
			global_position = _snaps[0][1]
		return
	var rt: float = Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var a: Array = _snaps[0]
	var b: Array = _snaps[1]
	for i in range(_snaps.size() - 1):
		if _snaps[i + 1][0] >= rt:
			a = _snaps[i]
			b = _snaps[i + 1]
			break
		a = _snaps[i + 1]
		b = _snaps[i + 1]
	var span: float = maxf(b[0] - a[0], 0.0001)
	var k := clampf((rt - a[0]) / span, 0.0, 1.0)
	global_position = (a[1] as Vector3).lerp(b[1], k)
	human.rotation.y = lerp_angle(a[2], b[2], k)
	if car != null and is_instance_valid(car):
		var xa: Transform3D = a[4]
		var xb: Transform3D = b[4]
		car.global_transform = xa.interpolate_with(xb, k)
		global_position = car.global_position
	if flags & Net.F_DOWNED == 0:
		human.animate(lerpf(a[3], b[3], k), flags & Net.F_ROBBING != 0)


func cleanup() -> void:
	if car != null and is_instance_valid(car):
		game.remove_car(car)
	queue_free()
