class_name GameCamera
extends Camera3D
## كاميرا الشخص الثالث: تدور بالفأرة، تبتعد مع السرعة، تعود خلف السيارة، ولا تخترق الجدران.

var game: Node
var yaw := 0.0
var pitch := 0.3
var last_mouse := -10.0
var shake := 0.0
var orbit := 0.0


func _unhandled_input(e: InputEvent) -> void:
	if game == null or not game.playing():
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		yaw -= m.relative.x * 0.0026
		pitch = clampf(pitch + m.relative.y * 0.002, -0.05, 1.1)
		last_mouse = game.time


func update_camera(dt: float) -> void:
	if game.state == "menu":
		orbit += dt * 0.04
		global_position = Vector3(cos(orbit) * 170.0, 75.0, sin(orbit) * 170.0)
		look_at(Vector3(0, 10, 0))
		return
	var car: Car = game.player.car
	var t: Vector3 = game.player_pos()
	var aiming: bool = game.weapons.aiming
	var ty := 1.5 if car else 1.65
	var dist := 9.5 + absf(car.speed) * 0.07 if car else (2.6 if aiming else 5.2)
	if car and game.time - last_mouse > 1.0:
		yaw = lerp_angle(yaw, car.heading(), minf(1.0, dt * 2.6))
		pitch = lerpf(pitch, 0.26, minf(1.0, dt * 1.5))
	var cp := cos(pitch)
	var off := Vector3(-sin(yaw) * cp * dist, sin(pitch) * dist + 0.4, -cos(yaw) * cp * dist)
	var target := Vector3(t.x, ty, t.z)
	if aiming:
		# فوق الكتف الأيمن
		target += Vector3(-cos(yaw), 0, sin(yaw)) * 0.6
	# منع اختراق المباني
	var q := PhysicsRayQueryParameters3D.create(target, target + off, Cfg.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var hd: float = (hit.position - target).length()
		off = off.normalized() * maxf(0.6, hd - 0.35)
	var want := target + off
	want.y = maxf(want.y, 0.5)
	if shake > 0.0:
		want += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.45
		shake = maxf(0.0, shake - dt * 2.5)
	global_position = global_position.lerp(want, 1.0 - exp(-dt * (9.0 if car else (30.0 if aiming else 16.0))))
	look_at(target + Vector3(0, 0.7 if car else 0.15, 0))
	var f := 64.0 + minf(absf(car.speed), 35.0) * 0.45 if car else (50.0 if aiming else 62.0)
	fov = lerpf(fov, f, minf(1.0, dt * 3.0))
