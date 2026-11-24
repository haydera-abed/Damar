class_name Civilian
extends Node3D
## مشاة على الأرصفة: يمشون حول المربعات السكنية، يهربون عند إطلاق النار، ويموتون إن أُصيبوا.
## بلا فيزياء (حركة على مسار) لأداء عالٍ مع عشرات المشاة.

const ROLES := ["civ_a", "civ_b", "civ_c", "civ_d"]

var game: Node
var human: Human
var health := 45.0
var dead := false
var block_c := Vector3.ZERO
var s := 0.0                    # الموضع على محيط المربع
var dir := 1.0
var speed := 1.3
var fleeing := 0.0
var _dead_t := 0.0
const OFFSET := 22.4            # بعد مسار المشي عن مركز المربع (على الرصيف)


func setup(g: Node, block_center: Vector3) -> void:
	game = g
	block_c = block_center
	s = randf() * OFFSET * 8.0
	dir = 1.0 if randf() < 0.5 else -1.0
	speed = randf_range(1.1, 1.6)
	human = Human.new()
	add_child(human)
	human.setup(ROLES[randi() % ROLES.size()])
	_place(0.0)


func _path_point(t: float) -> Vector3:
	var side := OFFSET * 2.0
	t = fposmod(t, side * 4.0)
	var k := int(t / side)
	var f := fmod(t, side) - OFFSET
	match k:
		0: return block_c + Vector3(f, 0, -OFFSET)
		1: return block_c + Vector3(OFFSET, 0, f)
		2: return block_c + Vector3(-f, 0, OFFSET)
		_: return block_c + Vector3(-OFFSET, 0, -f)


func _place(dt: float) -> void:
	var p := _path_point(s)
	var ahead := _path_point(s + dir * 0.5)
	global_position = Vector3(p.x, 0.15, p.z)
	var v := ahead - p
	if v.length() > 0.01:
		human.rotation.y = atan2(v.x, v.z)


func take_damage(dmg: float, from: Node) -> void:
	if dead:
		return
	health -= dmg
	fleeing = 12.0
	if health <= 0.0:
		dead = true
		human.play_once("death")
		game.on_civilian_killed(self, from)


func scare() -> void:
	if not dead:
		fleeing = 10.0


func _process(dt: float) -> void:
	if game == null or not game.world_running():
		return
	if dead:
		_dead_t += dt
		if _dead_t > 25.0:
			# يعود مشاة جدد في مكان آخر
			dead = false
			_dead_t = 0.0
			health = 45.0
			var b: Dictionary = game.city.blocks[randi() % game.city.blocks.size()]
			block_c = Vector3(b.center.x, 0, b.center.y)
			s = randf() * OFFSET * 8.0
			human.play("idle")
		return
	var spd := speed
	if fleeing > 0.0:
		fleeing -= dt
		spd = 5.5
	s += dir * spd * dt
	_place(dt)
	human.animate(spd)
