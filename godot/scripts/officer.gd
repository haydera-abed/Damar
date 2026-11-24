class_name Officer
extends CharacterBody3D
## شرطي راجل ينزل من سيارته ويلاحق اللص، ثم يعود إليها.

var game: Node
var car: Car
var human: Human
var returning := false
var facing := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	collision_layer = Cfg.LAYER_CHARS
	collision_mask = Cfg.LAYER_WORLD | Cfg.LAYER_VEHICLES
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	human = Human.new()
	add_child(human)
	human.setup("cop")


func distance_to_player() -> float:
	var p: Vector3 = game.player_pos()
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _physics_process(dt: float) -> void:
	if game == null or not game.world_running():
		return
	if not is_instance_valid(car):
		queue_free()
		return
	var d_player := distance_to_player()
	returning = game.wanted == 0 or not game.playing() or (not game.player_on_foot() and d_player > 5.0)
	var target: Vector3 = car.global_position if returning else game.player_pos()
	var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var d := to.length()
	var spd := 5.0 if returning else 6.9
	var stop := 0.1 if returning else 1.0
	var want := to / d * spd if d > stop else Vector3.ZERO
	var k := 1.0 - exp(-8.0 * dt)
	velocity.x = lerpf(velocity.x, want.x, k)
	velocity.z = lerpf(velocity.z, want.z, k)
	velocity.y = -1.0 if is_on_floor() else velocity.y - gravity * dt
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 0.3:
		facing = atan2(velocity.x, velocity.z)
	elif not returning:
		facing = atan2(to.x, to.z)
	human.rotation.y = facing
	human.animate(hs, not returning and d < 4.0)
	if returning and (car.global_position - global_position).length() < 2.8:
		car.officer = null
		car.exit_cd = 5.0
		game.officers.erase(self)
		queue_free()
