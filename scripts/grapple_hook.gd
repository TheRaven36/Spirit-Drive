class_name GrappleHook
extends RefCounted
## Ein einzelnes Seil (Hueft-Werfer links oder rechts).
##
## Verwaltet Ankerpunkt, Ziel (Gegner) und die Knickpunkte, an denen sich das
## Seil um Geometrie legt (Bending). Die eigentliche Seilphysik rechnet der
## GuardianController, weil sie dessen Tuning-Werte braucht.
##
## Kette: anchor -> bends[0] -> bends[1] -> ... -> Spieler.
## Der letzte Knickpunkt ist der aktuelle physikalische Pivot.

enum Kind { HIP_LEFT, HIP_RIGHT }

const BEND_OFFSET := 0.12   # Knickpunkt leicht von der Kante weg
const BEND_EPS := 0.35      # Treffer so nah am Pivot zaehlen nicht als Hindernis
const MAX_BENDS := 8

var kind: Kind
var active := false
## true = Combat-Grapple (Hard-Lock + LMB halten): Seil zum Lock-Punkt, eigene Windengeschwindigkeit.
## false = normales Seil (RMB).
var combat := false
var target: Node3D = null
var target_offset := Vector3.ZERO
var anchor := Vector3.ZERO
var normal := Vector3.ZERO     # Oberflaechen-Normale am Anker (Decke: y < 0)
## Slack = Taste losgelassen, Doppel-Tap-Fenster laeuft: Seil haengt locker, keine Kraft.
var slack := false
var bends: Array[Vector3] = []
var rope_length := 0.0      # freie Laenge vom Pivot zum Spieler
var attach_height := 0.0

var _bend_lengths: Array[float] = []
var _bend_planes: Array[Vector3] = []   # Normale * Seite der Wickel-Ebene


func _init(hook_kind: Kind) -> void:
	kind = hook_kind


func attach(point: Vector3, surface_normal: Vector3, hit_target: Node3D, player_pos: Vector3,
		is_combat := false) -> void:
	active = true
	slack = false
	combat = is_combat
	normal = surface_normal
	target = hit_target
	anchor = point
	target_offset = hit_target.global_transform.affine_inverse() * point if hit_target else Vector3.ZERO
	bends.clear()
	_bend_lengths.clear()
	_bend_planes.clear()
	rope_length = player_pos.distance_to(point)
	attach_height = player_pos.y


func release() -> void:
	active = false
	slack = false
	combat = false
	target = null
	bends.clear()
	_bend_lengths.clear()
	_bend_planes.clear()


func anchor_world() -> Vector3:
	if is_instance_valid(target):
		anchor = target.global_transform * target_offset
	return anchor


func pivot() -> Vector3:
	return bends[-1] if not bends.is_empty() else anchor_world()


func has_bends() -> bool:
	return not bends.is_empty()


## Gesamtlaenge des Seils (fixe Segmente + freier Teil).
func total_length() -> float:
	var sum := rope_length
	for l in _bend_lengths:
		sum += l
	return sum


## Punktkette fuer das Rendering: Spieler-Hand -> ... -> Anker.
func render_points(hand: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array([hand])
	for i in range(bends.size() - 1, -1, -1):
		pts.append(bends[i])
	pts.append(anchor_world())
	return pts


## Bending: Seil um Geometrie wickeln bzw. wieder abwickeln.
func update_bends(space: PhysicsDirectSpaceState3D, pos: Vector3, velocity: Vector3,
		exclude: Array[RID], mask: int) -> void:
	var ex := exclude.duplicate()
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())

	# 1) Abwickeln: Spieler ist zurueck auf die andere Seite der Wickel-Ebene
	#    UND hat freie Sicht auf den vorherigen Punkt.
	if not bends.is_empty():
		var bend := bends[-1]
		var prev := anchor_world() if bends.size() == 1 else bends[-2]
		var plane := _bend_planes[-1]
		var crossed := plane == Vector3.ZERO or plane.dot(pos - bend) < 0.0
		if crossed and _is_clear(space, pos, prev, ex, mask):
			bends.pop_back()
			_bend_planes.pop_back()
			rope_length += _bend_lengths.pop_back()
			return

	# 2) Wickeln: Geometrie zwischen Spieler und Pivot?
	if bends.size() >= MAX_BENDS:
		return
	var p := pivot()
	var q := PhysicsRayQueryParameters3D.create(pos, p, mask, ex)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.position as Vector3).distance_to(p) < BEND_EPS:
		return
	var new_bend: Vector3 = hit.position + hit.normal * BEND_OFFSET
	var seg := p.distance_to(new_bend)
	if seg < BEND_EPS:
		return
	var n := (new_bend - p).cross(pos - new_bend)
	var plane_dir := Vector3.ZERO
	if n.length() > 0.0001:
		n = n.normalized()
		# Seite merken, in die sich der Spieler gerade bewegt -> Abwickeln beim Zurueckkreuzen.
		var side := signf(n.dot(velocity))
		plane_dir = n * (side if side != 0.0 else 1.0)
	bends.append(new_bend)
	_bend_lengths.append(seg)
	_bend_planes.append(plane_dir)
	# Freie Laenge nie kuerzer als die echte Distanz -> kein Ruck beim Wickeln.
	rope_length = maxf(rope_length - seg, pos.distance_to(new_bend))


func _is_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		exclude: Array[RID], mask: int) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	var hit := space.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(to) < BEND_EPS
