class_name TrainingGiant
extends StaticBody3D
## Grosser Test-Gegner (~14 m) mit mehreren Lock-Punkten (LockPoint) fuer
## Hard-Lock und Mausrad-Ziel-Wechsel. Baut Koerper, Kollision und Punkte selbst.
## Steht mit dem Gesicht in +Z (Richtung Spawn).

signal defeated

@export var max_hp := 3000.0
@export var respawn_time := 4.0

var hp := 3000.0
var hits_taken := 0
var last_damage := 0.0
var last_point := ""

var _mat: StandardMaterial3D
var _label: Label3D
var _meshes: Array[MeshInstance3D] = []
var _shapes := {}
var _flash := 0.0
var _dmg_show := 0.0
var _down_t := 0.0

## [name, art, groesse, position]
const PARTS := [
	["BeinL", "box", Vector3(1.6, 6.0, 1.6), Vector3(-1.4, 3.0, 0.0)],
	["BeinR", "box", Vector3(1.6, 6.0, 1.6), Vector3(1.4, 3.0, 0.0)],
	["Torso", "box", Vector3(4.5, 5.0, 2.5), Vector3(0.0, 8.5, 0.0)],
	["ArmL", "box", Vector3(1.2, 5.5, 1.2), Vector3(-3.0, 8.2, 0.0)],
	["ArmR", "box", Vector3(1.2, 5.5, 1.2), Vector3(3.0, 8.2, 0.0)],
	["Kopf", "sphere", Vector3(1.4, 0, 0), Vector3(0.0, 12.4, 0.0)],
]

## [label, position, damage_mult, koerperteil, rahmen-radius] – Punkte sitzen knapp vor der
## Oberflaeche und haengen unter der CollisionShape3D ihres Koerperteils (folgen der Hitbox).
const POINTS := [
	["Kopf", Vector3(0.0, 12.6, 1.45), 1.0, "Kopf", 1.2],
	["Nacken", Vector3(0.0, 11.3, -1.4), 1.0, "Kopf", 0.9],
	["Brust", Vector3(0.0, 9.5, 1.3), 1.0, "Torso", 1.6],
	["Schulter L", Vector3(-3.0, 10.6, 0.65), 1.0, "ArmL", 0.9],
	["Schulter R", Vector3(3.0, 10.6, 0.65), 1.0, "ArmR", 0.9],
	["Knie L", Vector3(-1.4, 3.0, 0.85), 1.0, "BeinL", 0.9],
	["Knie R", Vector3(1.4, 3.0, 0.85), 1.0, "BeinR", 0.9],
]


func _ready() -> void:
	hp = max_hp
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.75, 0.35, 0.35)
	_mat.emission_enabled = true
	for p: Array in PARTS:
		var mi := MeshInstance3D.new()
		var cs := CollisionShape3D.new()
		if p[1] == "box":
			var bm := BoxMesh.new()
			bm.size = p[2]
			mi.mesh = bm
			var bs := BoxShape3D.new()
			bs.size = p[2]
			cs.shape = bs
		else:
			var sm := SphereMesh.new()
			sm.radius = p[2].x
			sm.height = p[2].x * 2.0
			mi.mesh = sm
			var ss := SphereShape3D.new()
			ss.radius = p[2].x
			cs.shape = ss
		mi.name = p[0]
		mi.position = p[3]
		mi.material_override = _mat
		cs.name = "Shape_" + String(p[0])
		cs.position = p[3]
		add_child(mi)
		add_child(cs)
		_meshes.append(mi)
		_shapes[p[0]] = cs
	for p: Array in POINTS:
		var lp := LockPoint.new()
		lp.name = "LP_" + String(p[0]).replace(" ", "")
		lp.label = p[0]
		lp.damage_mult = p[2]
		lp.radius = p[4]
		var part: CollisionShape3D = _shapes[p[3]]
		lp.position = p[1] - part.position
		part.add_child(lp)
	_label = Label3D.new()
	_label.position = Vector3(0, 15.0, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 64
	_label.outline_size = 14
	add_child(_label)
	_update_label()


func is_lockable() -> bool:
	return _down_t <= 0.0


func take_hit(damage: float, _dir: Vector3, source: Node) -> void:
	if _down_t > 0.0:
		return
	hits_taken += 1
	hp -= damage
	last_damage = damage
	last_point = ""
	if source is GuardianController and not (source as GuardianController).knife.last_hit.is_empty():
		last_point = (source as GuardianController).knife.last_hit.get("point", "")
	_flash = 0.15
	_dmg_show = 1.5
	if hp <= 0.0:
		_down_t = respawn_time
		for m in _meshes:
			m.visible = false
		defeated.emit()
	_update_label()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
	_mat.emission = Color(1, 1, 1) * (_flash / 0.15) * 2.0 if _flash > 0.0 else Color.BLACK
	if _dmg_show > 0.0:
		_dmg_show -= delta
		if _dmg_show <= 0.0:
			_update_label()
	if _down_t > 0.0:
		_down_t -= delta
		if _down_t <= 0.0:
			hp = max_hp
			for m in _meshes:
				m.visible = true
			_update_label()


func _update_label() -> void:
	var t := "RIESE  %d" % maxf(hp, 0.0) if _down_t <= 0.0 else "RIESE  ..."
	if _dmg_show > 0.0:
		t += "\n-%d %s" % [last_damage, last_point]
	_label.text = t
