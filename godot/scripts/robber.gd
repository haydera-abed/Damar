class_name Robber
extends CharacterBody3D
## لص يتحكم به الذكاء الاصطناعي (يظهر عندما تكون شرطياً في المناوبة):
## يذهب لمتجر، يسرقه (إنذار على الخريطة)، ثم يهرب. قد يكون مسلّحاً.
## إن صوّب عليه الشرطي قد يستسلم؛ المستسلم أو المُسقَط يُقيَّد بالأصفاد (E).

enum S { GOING, ROBBING, FLEEING, SURRENDERED, ARRESTED, DEAD, GUARD }

var game: Node
var mgr: Node                     # من يدير هذا اللص: Cop (بلاغات) أو Gangs (أفراد عصابة)
var anchor := Vector3.ZERO        # نقطة الحراسة لأفراد العصابات
var gang_color := Color.WHITE
var human: Human
var state := S.GOING
var store: City.StoreData
var health := 100.0
var armed := false
var dead := false
var downed := false
var surrendered := false
var arrested := false
var loot := 0
var _t := 0.0
var _flee_to := Vector3.ZERO
var _shoot_t := 1.5
var _gone_t := 0.0
var _node := Cfg.NONE
var _prev := Cfg.NONE
var _flee_t := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(g: Node, s: City.StoreData, manager: Node = null) -> void:
	game = g
	store = s
	mgr = manager if manager else g.cop
	armed = randf() < 0.45
	loot = randi_range(6000, 22000)


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
	human.setup("robber", true)
	human.set_mask(true)


func take_damage(dmg: float, from: Node) -> void:
	if dead:
		return
	health -= dmg
	armed = armed and health > 40.0
	if health <= 0.0:
		dead = true
		state = S.DEAD
		human.play_once("death")
		collision_layer = 0
		mgr.on_robber_down(self, from)
	elif from == game.player and state == S.FLEEING and randf() < 0.35 and mgr == game.cop:
		_surrender()


func _surrender() -> void:
	if state in [S.SURRENDERED, S.ARRESTED, S.DEAD]:
		return
	state = S.SURRENDERED
	surrendered = true
	velocity = Vector3.ZERO
	human.set_hands_up(true)
	game.hud.toast("اللص استسلم ✋ — اقترب واضغط E لتقييده", Color("9fd0ff"))


## يُستدعى عندما يصوّب الشرطي (اللاعب) نحوه
func threatened() -> void:
	if state == S.FLEEING and global_position.distance_to(game.player.global_position) < 16.0:
		if randf() < (0.025 if armed else 0.06):
			_surrender()


func cuff() -> void:
	state = S.ARRESTED
	arrested = true
	human.set_hands_up(false)
	collision_layer = 0


func _physics_process(dt: float) -> void:
	if game == null or not game.world_running():
		return
	if state in [S.DEAD, S.ARRESTED]:
		_gone_t += dt
		if _gone_t > (3.0 if state == S.ARRESTED else 18.0):
			mgr.remove_robber(self)
		return
	var tgt := global_position
	var spd := 0.0
	match state:
		S.GOING:
			tgt = store.pos
			spd = 3.0
			if global_position.distance_to(store.pos) < 1.6:
				state = S.ROBBING
				_t = 0.0
				mgr.on_robbery_started(self)
		S.ROBBING:
			_t += dt
			if _t > 9.0:
				state = S.FLEEING
				_node = Cfg.nearest_node(global_position)
				_flee_to = Cfg.node_pos(_node)
		S.FLEEING:
			tgt = _flee_to
			spd = 6.6
			_flee_t += dt
			if _flee_t > 45.0 and global_position.distance_to(game.player.global_position) > 40.0:
				mgr.on_robber_escaped(self)
				return
			if Vector2(global_position.x - _flee_to.x, global_position.z - _flee_to.z).length() < 2.5:
				# التقاطع التالي: الأبعد عن الشرطي
				var best := _node
				var bd := -1.0
				for n in Cfg.neighbors(_node):
					if n == _prev:
						continue
					var dd: float = Cfg.node_pos(n).distance_to(game.player.global_position) + randf() * 20.0
					if dd > bd:
						bd = dd
						best = n
				_prev = _node
				_node = best
				_flee_to = Cfg.node_pos(_node)
			# يطلق النار على الشرطي القريب
			_shoot_t -= dt
			var dp: float = global_position.distance_to(game.player.global_position)
			if armed and dp < 25.0 and _shoot_t <= 0.0 and game.player.car == null:
				var eye := global_position + Vector3(0, 1.5, 0)
				var aim: Vector3 = game.player.global_position + Vector3(0, 1.1, 0)
				if game.has_los(eye, aim):
					_shoot_t = randf_range(0.9, 1.6)
					var dir := (aim - eye).normalized()
					dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.04 + dp * 0.003)).normalized()
					game.weapons.shoot(eye, dir, 60.0, 11.0, self)
					game.on_gunshot(eye, false)
		S.SURRENDERED:
			spd = 0.0
		S.GUARD:
			# فرد عصابة: يحرس نقطته ويطلق النار على اللاعب إن اقترب
			var dp2: float = global_position.distance_to(game.player.global_position)
			tgt = anchor if dp2 > 30.0 else game.player.global_position
			spd = 0.0 if (dp2 < 12.0 or global_position.distance_to(anchor) < 1.0 and dp2 > 30.0) else 4.5
			_shoot_t -= dt
			if dp2 < 32.0 and _shoot_t <= 0.0 and game.playing() and not game.player.downed:
				var eye2 := global_position + Vector3(0, 1.5, 0)
				var aim2: Vector3 = game.player.global_position + Vector3(0, 1.1, 0)
				if game.has_los(eye2, aim2):
					_shoot_t = randf_range(0.8, 1.5)
					var dir2 := (aim2 - eye2).normalized()
					dir2 = (dir2 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.05 + dp2 * 0.003)).normalized()
					game.weapons.shoot(eye2, dir2, 60.0, 9.0, self)
					game.on_gunshot(eye2, false)
				if dp2 < 12.0:
					human.rotation.y = atan2(aim2.x - global_position.x, aim2.z - global_position.z)
	var to := Vector3(tgt.x - global_position.x, 0, tgt.z - global_position.z)
	var d := to.length()
	var want := to / d * spd if d > 0.3 and spd > 0.0 else Vector3.ZERO
	var k := 1.0 - exp(-8.0 * dt)
	velocity.x = lerpf(velocity.x, want.x, k)
	velocity.z = lerpf(velocity.z, want.z, k)
	velocity.y = -1.0 if is_on_floor() else velocity.y - gravity * dt
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 0.3:
		human.rotation.y = atan2(velocity.x, velocity.z)
	human.animate(hs, state == S.ROBBING)
