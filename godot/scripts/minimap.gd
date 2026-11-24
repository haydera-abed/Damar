class_name Minimap
extends Control
## خريطة مصغّرة دائرية تدور مع الكاميرا: المربعات، المتاجر ($)، المخبأ (H)، والشرطة.

var game: Node
const SCALE := 0.65


func _to_map(p: Vector3, c: Vector2) -> Vector2:
	var pp: Vector3 = game.player_pos()
	var yaw: float = game.cam.yaw
	var v := Vector2(p.x - pp.x, p.z - pp.z)
	var fwd := v.x * sin(yaw) + v.y * cos(yaw)
	var right := v.x * -cos(yaw) + v.y * sin(yaw)
	return c + Vector2(right, -fwd) * SCALE


func _draw() -> void:
	if game == null or game.player == null:
		return
	var r := size.x / 2.0
	var c := Vector2(r, r)
	draw_circle(c, r, Color("0d0f14"))
	draw_circle(c, r - 3, Color("4a4f5a"))
	# المربعات السكنية
	for b in game.city.blocks:
		var ctr := Vector3(b.center.x, 0, b.center.y)
		var pts := PackedVector2Array()
		for corner in [Vector3(-25, 0, -25), Vector3(25, 0, -25), Vector3(25, 0, 25), Vector3(-25, 0, 25)]:
			pts.append(_to_map(ctr + corner, c))
		var inside := false
		for q in pts:
			if (q - c).length() < r * 1.5:
				inside = true
		if inside:
			var poly := _clip(pts, c, r - 3)
			if poly.size() >= 3:
				var base := Color("1f3d24") if b.park else Color("1a1d24")
				var bc := Vector3(b.center.x, 0, b.center.y)
				if absf(bc.x) < Cfg.HALF and absf(bc.z) < Cfg.HALF:
					var gc: Color = Gangs.GANGS[game.gangs.owner_of[game.gangs.district_at(bc)]].color
					base = base.lerp(gc, 0.22)
				draw_colored_polygon(poly, base)
	# الأيقونات
	for s in game.city.stores:
		var col: Color = s.def.color if s.cooldown <= 0.0 else Color(0.35, 0.35, 0.35)
		var lbl: String = {"police": "P", "gallery": "A", "showroom": "C"}.get(s.type, "$")
		_icon(s.pos, c, r, col, 9.0 if s.type in ["bank", "police"] else 7.0, lbl, s.cooldown <= 0.0 and s.type != "shop")
	for f in game.crime.fences:
		_icon(f, c, r, Color("39e27d"), 6.5, "$", true)
	_icon(game.crime.dealer_pos, c, r, Color("ff9b3b"), 6.0, "B", true)
	for i in 9:
		_icon(game.gangs.flags[i], c, r, Gangs.GANGS[game.gangs.owner_of[i]].color, 4.0, "", false)
	for m in game.gangs.members:
		if is_instance_valid(m) and not m.dead:
			_icon(m.global_position, c, r, Color("ff2d2d"), 3.5, "", false)
	_icon(game.city.safe_pos, c, r, Color("3dff7a"), 8.0, "H", true)
	var blink := int(game.time * 4.0) % 2 == 0
	for car in game.cars:
		if car.police:
			_icon(car.global_position, c, r, (Color("ff3030") if blink else Color("3060ff")) if car.chase else Color("8fa8ff"), 4.5, "", false)
	for rb in game.cop.robbers:
		if not rb.dead and not rb.arrested:
			_icon(rb.global_position, c, r, Color("ff2d2d") if blink else Color("ffffff"), 5.0, "", true)
	for a in game.alerts:
		_icon(a[0], c, r, Color("ff2d2d") if blink else Color("ffcf3a"), 7.0, "!", true)
	var me_cop: bool = game.cop.on_duty
	for id in game.net.remotes:
		var rp: RemotePlayer = game.net.remotes[id]
		if rp.role == "cop":
			_icon(rp.global_position, c, r, Color("3d7bff"), 5.0, "", false)
		elif rp.wanted > 0 and me_cop:
			_icon(rp.global_position, c, r, Color("ff2d2d"), 5.5, "", true)
		elif not me_cop:
			_icon(rp.global_position, c, r, Color("eeeeee"), 4.0, "", false)
	for o in game.officers:
		_icon(o.global_position, c, r, Color("6f9bff"), 3.0, "", false)
	# اللاعب
	var h: float = game.player.car.heading() if game.player.car else game.player.facing
	var a: float = -(h - game.cam.yaw)
	var tip := Vector2(0, -10).rotated(a)
	var l := Vector2(-7, 8).rotated(a)
	var rr := Vector2(7, 8).rotated(a)
	var back := Vector2(0, 3).rotated(a)
	draw_colored_polygon(PackedVector2Array([c + tip, c + rr, c + back, c + l]), Color.WHITE)
	draw_arc(c, r - 1.5, 0, TAU, 64, Color(1, 1, 1, 0.25), 3.0)


func _clip(pts: PackedVector2Array, c: Vector2, r: float) -> PackedVector2Array:
	var circle := PackedVector2Array()
	for i in 32:
		circle.append(c + Vector2(r, 0).rotated(TAU * i / 32.0))
	var res := Geometry2D.intersect_polygons(pts, circle)
	return res[0] if res.size() > 0 else PackedVector2Array()


func _icon(p: Vector3, c: Vector2, r: float, col: Color, size: float, label: String, edge: bool) -> void:
	var m := _to_map(p, c)
	var d := m - c
	var lim := r - size - 4.0
	if d.length() > lim:
		if not edge:
			return
		m = c + d.normalized() * lim
	draw_circle(m, size, col)
	if label != "":
		var f := get_theme_default_font()
		draw_string(f, m + Vector2(-size * 0.45, size * 0.55), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size * 1.4), Color.BLACK)
