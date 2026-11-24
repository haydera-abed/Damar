class_name Officer
extends CharacterBody3D
## شرطي راجل: ينزل من سيارته ويلاحق المشتبه به.
## - مطلوبية نجمة واحدة: يحاول الاعتقال دون إطلاق نار.
## - نجمتان فأكثر (أو إن أطلقتَ عليه): يطلق النار.
## - يقيّد المستسلم أو المُسقَط (أصفاد) ثم يعود لسيارته.

var game: Node
var car: Car
var human: Human
var returning := false
var facing := 0.0
var health := 100.0
var dead := false
var target: Node = null              # اللاعب أو لص يتحكم به الذكاء الاصطناعي
var _shoot_t := 1.0
var _dead_t := 0.0
var _hostile := false
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


func _target_pos() -> Vector3:
	if target != null and is_instance_valid(target) and target != game.player:
		return Vector3(target.global_position.x, 0, target.global_position.z)
	return game.player_pos()


func distance_to_player() -> float:
	var p: Vector3 = game.player_pos()
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func take_damage(dmg: float, from: Node) -> void:
	if dead:
		return
	health -= dmg
	_hostile = true
	if health <= 0.0:
		dead = true
		human.play_once("death")
		collision_layer = 0
		game.on_officer_down(self, from)


func _physics_process(dt: float) -> void:
	if game == null or not game.world_running():
		return
	if dead:
		_dead_t += dt
		if _dead_t > 20.0:
			if is_instance_valid(car):
				car.officer = null
			game.officers.erase(self)
			queue_free()
		return
	if not is_instance_valid(car):
		game.officers.erase(self)
		queue_free()
		return
	var chasing_player: bool = target == null or target == game.player
	var d_player := distance_to_player()
	if chasing_player:
		returning = game.wanted == 0 or not game.playing() or (not game.player_on_foot() and d_player > 5.0)
	else:
		returning = not is_instance_valid(target) or target.dead or target.arrested
	var tgt: Vector3 = car.global_position if returning else _target_pos()
	var to := Vector3(tgt.x - global_position.x, 0, tgt.z - global_position.z)
	var d := to.length()
	var can_shoot: bool = not returning and (_hostile or (chasing_player and game.wanted >= 2) or (not chasing_player and target.armed))
	var target_down: bool = chasing_player and (game.player.surrendered or game.player.downed)
	if not chasing_player and is_instance_valid(target):
		target_down = target.surrendered or target.downed
	# يتوقف ليطلق النار من مسافة متوسطة، ويقترب للتقييد إن استسلم الهدف
	var stop := 0.1 if returning else (1.0 if target_down or not can_shoot else 9.0)
	var spd := 5.0 if returning else 6.9
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
	human.animate(hs, not returning and d < 2.0 and target_down)

	# إطلاق النار
	_shoot_t -= dt
	if can_shoot and not target_down and d < 35.0 and _shoot_t <= 0.0:
		var eye := global_position + Vector3(0, 1.5, 0)
		var aim := _target_pos() + Vector3(0, 1.1, 0)
		if game.has_los(eye, aim):
			_shoot_t = randf_range(0.7, 1.3)
			var w: Dictionary = Weapons.CATALOG["police_rifle" if game.wanted >= 4 else "police_pistol"]
			# الدقة تقل مع المسافة والحركة
			var miss := 0.02 + d * 0.0025 + (0.03 if game.player.car == null and game.player.velocity.length() > 5.0 else 0.0)
			var dir := (aim - eye).normalized()
			dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * miss).normalized()
			game.weapons.shoot(eye, dir, w.range, w.damage * 0.55, self)
			game.on_gunshot(eye, false)

	if returning and (car.global_position - global_position).length() < 2.8:
		car.officer = null
		car.exit_cd = 5.0
		game.officers.erase(self)
		queue_free()
