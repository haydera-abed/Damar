class_name Human
extends Node3D
## شخصية متحركة (نموذج Quaternius) مع ألوان حسب الدور: لص أو شرطي.

const MODEL := preload("res://assets/models/worker.glb")
const ROLES := {
	"thief": {"Shirt": Color("1d1e22"), "Pants": Color("1c2638"), "Hair": Color("111111"), "Socks": Color("222222")},
	"cop": {"Shirt": Color("1d3466"), "Pants": Color("121a2b"), "Hair": Color("0e1a36"), "Socks": Color("111111")},
	"dealer": {"Shirt": Color("5a1f14"), "Pants": Color("222222"), "Hair": Color("111111"), "Socks": Color("111111")},
	"clerk": {"Shirt": Color("c9c3b4"), "Pants": Color("2b2f3a"), "Hair": Color("3a2a20"), "Socks": Color("222222")},
	"robber": {"Shirt": Color("2f3a1f"), "Pants": Color("1a1a1a"), "Hair": Color("111111"), "Socks": Color("111111")},
	"civ_a": {"Shirt": Color("7a2f2f"), "Pants": Color("2a3350"), "Hair": Color("2a1e16"), "Socks": Color("eeeeee")},
	"civ_b": {"Shirt": Color("dad6cc"), "Pants": Color("4b4b4b"), "Hair": Color("1b1b1b"), "Socks": Color("333333")},
	"civ_c": {"Shirt": Color("2e5d74"), "Pants": Color("8a7a62"), "Hair": Color("5b3d22"), "Socks": Color("dddddd")},
	"civ_d": {"Shirt": Color("c9a23a"), "Pants": Color("1f2a3a"), "Hair": Color("101010"), "Socks": Color("222222")},
}
const ANIMS := {"idle": "HumanArmature|Man_Idle", "walk": "HumanArmature|Man_Walk", "run": "HumanArmature|Man_Run", "rob": "HumanArmature|Man_Punch", "death": "HumanArmature|Man_Death"}
const LOOPED := ["idle", "walk", "run", "rob"]
const TARGET_HEIGHT := 1.8

static var _mat_cache := {}
static var _scale := 0.0
static var _foot := 0.0
static var _loops_set := false

var anim: AnimationPlayer
var current := ""
var bag: MeshInstance3D
var _mesh: MeshInstance3D
var mask: MeshInstance3D
var hands_label: Label3D


func setup(role: String, with_bag := false) -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	if not _loops_set:
		_loops_set = true
		for k in LOOPED:
			anim.get_animation(ANIMS[k]).loop_mode = Animation.LOOP_LINEAR
	var mesh_i: MeshInstance3D = model.find_child("BaseHuman", true, false)
	if _scale == 0.0:
		# الطول الحقيقي يُقاس من عظام الهيكل (الرأس والقدم) لا من الشبكة
		var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
		var xf := Car._xf_to(sk, model)
		var head := (xf * sk.get_bone_global_rest(sk.find_bone("Head"))).origin
		var foot := (xf * sk.get_bone_global_rest(sk.find_bone("Foot.L"))).origin
		_scale = (TARGET_HEIGHT - 0.2) / maxf(head.y - foot.y, 0.001)
		_foot = -foot.y * _scale + 0.08
	model.scale = Vector3.ONE * _scale
	model.position.y = _foot
	_mesh = mesh_i
	set_role(role)
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	play("idle")
	if with_bag:
		bag = MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.42, 0.46, 0.22)
		bag.mesh = b
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("3e4a2a")
		bm.roughness = 1.0
		bag.material_override = bm
		bag.position = Vector3(0, 1.25, -0.24)
		bag.visible = false
		add_child(bag)




## تبديل الزي (لص ↔ شرطي ↔ مدني)
func set_role(role: String) -> void:
	var mesh_i := _mesh
	var key := role
	if not _mat_cache.has(key):
		var mats := {}
		for s in mesh_i.mesh.get_surface_count():
			var src := mesh_i.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			var cols: Dictionary = ROLES[role]
			if cols.has(src.resource_name):
				m.albedo_color = cols[src.resource_name]
			m.roughness = 0.85
			if src.resource_name.contains("Skin"):
				# جلد: تشتت تحت السطح خفيف يمنع مظهر البلاستيك
				m.subsurf_scatter_enabled = true
				m.subsurf_scatter_strength = 0.35
				m.roughness = 0.55
			elif src.resource_name.contains("Shirt") or src.resource_name.contains("Pants"):
				m.roughness = 0.95
				m.rim_enabled = true
				m.rim = 0.25
				m.rim_tint = 0.6
			mats[s] = m
		_mat_cache[key] = mats
	for s in _mat_cache[key]:
		mesh_i.set_surface_override_material(s, _mat_cache[key][s])


func play(kind: String) -> void:
	if kind == current:
		return
	current = kind
	anim.play(ANIMS[kind], 0.22)


## حركة لا تتكرر (السقوط)
func play_once(kind: String) -> void:
	current = kind
	anim.speed_scale = 1.0
	anim.play(ANIMS[kind], 0.15)


## قناع (Balaclava) مثبّت على عظمة الرأس فيتحرك معها
func set_mask(on: bool) -> void:
	if mask == null:
		var sk: Skeleton3D = find_child("Skeleton3D", true, false)
		var att := BoneAttachment3D.new()
		att.bone_name = "Head"
		sk.add_child(att)
		mask = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.135
		sm.height = 0.3
		mask.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.03, 0.03, 0.035)
		m.roughness = 1.0
		mask.material_override = m
		att.add_child(mask)
		# تعويض مقياس النموذج: المرفق يرث مقياس الهيكل
		var inv := 1.0 / _scale
		mask.scale = Vector3.ONE * inv
		mask.position = Vector3(0, 0.12 * inv, 0.01 * inv)
	mask.visible = on


func set_hands_up(on: bool) -> void:
	if hands_label == null:
		hands_label = Label3D.new()
		hands_label.text = "✋"
		hands_label.font_size = 96
		hands_label.pixel_size = 0.006
		hands_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hands_label.position = Vector3(0, 2.25, 0)
		add_child(hands_label)
	hands_label.visible = on


## اختيار الحركة حسب السرعة
func animate(speed: float, robbing := false) -> void:
	if current == "death":
		return
	if robbing:
		play("rob")
		anim.speed_scale = 1.0
	elif speed > 5.4:
		play("run")
		anim.speed_scale = clampf(speed / 7.5, 0.7, 1.4)
	elif speed > 0.35:
		play("walk")
		anim.speed_scale = clampf(speed / 2.6, 0.6, 2.2)
	else:
		play("idle")
		anim.speed_scale = 1.0
