class_name LockPoint
extends Marker3D
## Anvisierbarer Trefferpunkt an einem Gegner (Hard-Lock + Mausrad-Wechsel).
## Schaden geht an den naechsten Eltern-Knoten mit `take_hit`.
## `damage_mult` ist der Haken fuer spaetere Schwachstellen-/Ruestungs-Mechaniken.

@export var label := "Punkt"
@export var damage_mult := 1.0


func _ready() -> void:
	add_to_group("lock_target")


func get_lock_point() -> Vector3:
	return global_position


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
