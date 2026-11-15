class_name LockPoint
extends Marker3D
## Anvisierbarer Trefferpunkt an einem Gegner (Hard-Lock + Mausrad-Wechsel).
## Schaden geht an den naechsten Eltern-Knoten mit `take_hit`.
## `damage_mult` ist der Haken fuer spaetere Schwachstellen-/Ruestungs-Mechaniken.
##
## Hitbox-Ausrichtung: Der Punkt haengt idealerweise direkt unter der
## CollisionShape3D seines Koerperteils und folgt ihr damit exakt (auch spaeter
## bei Animationen). Mit `center_on_shape` sitzt er genau in der Shape-Mitte.

@export var label := "Punkt"
@export var damage_mult := 1.0
## Radius (m) des Ziel-Rahmens im HUD.
@export var radius := 0.9
## true = Lock-Punkt = Mittelpunkt der Eltern-CollisionShape3D (statt eigener Position).
@export var center_on_shape := false


func _ready() -> void:
	add_to_group("lock_target")


func get_lock_point() -> Vector3:
	if center_on_shape and get_parent() is CollisionShape3D:
		return (get_parent() as Node3D).global_position
	return global_position


func get_lock_radius() -> float:
	return radius


func get_hit_receiver() -> Node:
	var n := get_parent()
	while n != null:
		if n.has_method("take_hit"):
			return n
		n = n.get_parent()
	return null


func is_lockable() -> bool:
	var r := get_hit_receiver()
	return r != null and (not r.has_method("is_lockable") or r.is_lockable())
