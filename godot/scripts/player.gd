class_name Player
extends CharacterBody3D
## اللص: مشي، ركض، لياقة. ركوب السيارات والسرقة يديرها main.gd.

const WALK := 4.6
const SPRINT := 8.2

var game: Node
var human: Human
var stamina := 1.0
var facing := 0.0
var robbing := false
var car: Car = null
var health := 100.0
var max_health := 100.0
var downed := false
var surrendered := false
var dead := false               # للتوافق مع أهداف الأسلحة
var _regen_t := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	collision_layer = Cfg.LAYER_CHARS
	collision_mask = Cfg.LAYER_WORLD | Cfg.LAYER_VEHICLES
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	human = Human.new()
	add_child(human)
	human.setup("thief", true)


func _physics_process(dt: float) -> void:
	if car != null or game == null or not game.playing():
		return
	var typing: bool = game.hud.chat_edit.visible
	var yaw: float = game.cam.yaw
	var f := Vector3(sin(yaw), 0, cos(yaw))
	var r := Vector3(-cos(yaw), 0, sin(yaw))
	var iv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var move := (f * iv.y + r * iv.x).limit_length(1.0)
	if robbing or downed or surrendered or typing:
		move = Vector3.ZERO
	# تجدد الصحة ببطء بعد 6 ثوانٍ بلا إصابة
	_regen_t += dt
	if _regen_t > 6.0 and not downed:
		health = minf(max_health, health + dt * 4.0)
	var sprint := Input.is_action_pressed("sprint") and move.length() > 0.1 and stamina > 0.03
	stamina = clampf(stamina + (-dt / 7.0 if sprint else dt / 5.0), 0.0, 1.0)
	var target := move * (SPRINT if sprint else WALK)
	var k := 1.0 - exp(-10.0 * dt)
	velocity.x = lerpf(velocity.x, target.x, k)
	velocity.z = lerpf(velocity.z, target.z, k)
	velocity.y = -1.0 if is_on_floor() else velocity.y - gravity * dt
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	if game.weapons.aiming:
		facing = lerp_angle(facing, yaw, minf(1.0, dt * 20.0))   # يواجه اتجاه التصويب
	elif hs > 0.3:
		facing = lerp_angle(facing, atan2(velocity.x, velocity.z), minf(1.0, dt * 12.0))
	human.rotation.y = facing
	if not downed:
		human.animate(hs, robbing)
	if human.bag:
		var bv: int = game.crime.bag_value()
		human.bag.visible = bv > 0 or game.crime.bag.size() > 0
		var bs := 0.7 + minf(bv / 60000.0, 1.0) * 0.8
		human.bag.scale = Vector3.ONE * bs


func take_damage(dmg: float, _from: Node) -> void:
	if downed or car != null:
		return
	health -= dmg
	_regen_t = 0.0
	game.on_player_hit(dmg)
	if health <= 0.0:
		health = 0.0
		downed = true
		human.play_once("death")
		game.on_player_downed()


func set_surrender(on: bool) -> void:
	surrendered = on
	human.set_hands_up(on)


func revive() -> void:
	downed = false
	surrendered = false
	health = max_health
	human.set_hands_up(false)
	human.play("idle")


func teleport(p: Vector3, yaw: float) -> void:
	global_position = p
	velocity = Vector3.ZERO
	facing = yaw
	human.rotation.y = yaw
