class_name TrainingDummy
extends StaticBody3D
## Trainings-Ziel fuer Target-Lock, Combat-Grapple und Messer.
## Gruppen: "lock_target" (Auto-Aim) und "damageable".

signal defeated

@export var max_hp := 300.0
@export var respawn_time := 3.0

var hp := 300.0
var hits_taken := 0
var last_damage := 0.0
var _dmg_show := 0.0

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape
@onready var _label: Label3D = $HpLabel
var _mat: StandardMaterial3D
var _flash := 0.0
var _down_t := 0.0
var _base_color := Color(0.95, 0.45, 0.25)


func _ready() -> void:
	add_to_group("lock_target")
	add_to_group("damageable")
	hp = max_hp
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _base_color
	_mat.emission_enabled = true
	_mesh.material_override = _mat
	_update_label()


## Lock-/Grapple-Punkt = Mitte der Kollisions-Kapsel (nicht Mesh-Origin + Versatz).
func get_lock_point() -> Vector3:
	return _shape.global_position


func get_lock_radius() -> float:
	var c := _shape.shape as CapsuleShape3D
	return c.height * 0.5 if c else 1.0


func is_lockable() -> bool:
	return _down_t <= 0.0


func take_hit(damage: float, _dir: Vector3, _source: Node) -> void:
	if _down_t > 0.0:
		return
	hits_taken += 1
	hp -= damage
	last_damage = damage
	_dmg_show = 1.2
	_flash = 0.15
	if hp <= 0.0:
		_down_t = respawn_time
		_mesh.visible = false
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
			_mesh.visible = true
			_update_label()


func _update_label() -> void:
	var t := "%d" % maxf(hp, 0.0) if _down_t <= 0.0 else "..."
	if _dmg_show > 0.0:
		t += "   -%d" % last_damage
	_label.text = t
