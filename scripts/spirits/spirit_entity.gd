class_name SpiritEntity
extends CharacterBody3D
## Aktiver Feld-Spirit als Greybox-Kampf-Monster (Kapsel + Visor = Blickrichtung).
##
## Kopplung an SEINEN Guardian (Coop-ready, keine Singletons):
##   - Daten/Farbe: guardian.spirit_roster.field_spirit_changed (Tasten 1/2/3)
##   - Befehle:     guardian.hard_lock_changed – Hard-Lock (auch Mausrad-Wechsel) = Fokus-Ziel,
##                  Lock geloest (Doppelklick / Halten) = Rueckruf zu FOLLOW_PROTECT.
##   - Leine:       Das Fokus-Ziel gilt nur, solange es in Grapple-Reichweite des Guardians liegt
##                  (Lock-Rahmen farbig). Grau = Spirit laeuft physisch zum Guardian zurueck und
##                  greift wieder an, sobald das Ziel zurueck in Reichweite ist. Kein Teleport –
##                  ausser als Notfall (> emergency_teleport_distance, unter die Map gefallen oder
##                  im FOLLOW_PROTECT stuck_time lang festgesteckt – z. B. vor einer Tunnel-Steigung).
##   - SafeZone:    Steht der Guardian in einer Area3D der Gruppe "safe_zone" (Homebase), bleibt
##                  der Spirit strikt in FOLLOW_PROTECT (kein Fokus-Ziel, kein Bodyguard).
##
## State-Machine:
##   FOLLOW_PROTECT  folgt dem Guardian am Boden (follow_min..follow_max Abstand). Bodyguard:
##                   kommt ein Gegner dem Guardian naeher als guard_radius, wird er angegriffen.
##   CHASE           laeuft zum Ziel (Fokus-Befehl oder Bodyguard-Ziel).
##   ATTACK          in Reichweite alle attack_interval s ein Lunge (kurzes Vorpreschen),
##                   Treffer ueber die Area3D-Hitbox: base_damage x Saeulen-Multiplikator.
##
## Kollision: Layer 2 -> Guardian-Raycasts/Messer (Maske 1) ignorieren den Spirit.

signal hit_landed(target: Node, damage: float, effect_tag: String, hit_position: Vector3)

enum State { FOLLOW_PROTECT, CHASE, ATTACK }

@export var guardian_path := NodePath("..")

@export_group("Movement")
@export var run_speed := 16.0
## Tempo, wenn der Guardian weit weg ist (High-Speed-Flug).
@export var catchup_speed := 32.0
@export var catchup_distance := 15.0
@export var accel := 60.0
@export var gravity := 30.0
@export var turn_speed := 10.0
## Nur Notfall: weiter weg (oder unter die Map gefallen) = neben den Guardian versetzen.
@export var emergency_teleport_distance := 150.0
## Notfall: so lange (s) im FOLLOW_PROTECT weit weg und kaum bewegt -> neben den Guardian.
@export var stuck_time := 3.0
## "Weit weg" fuer die Festgesteckt-Pruefung (m).
@export var stuck_distance := 18.0
@export var spawn_offset := Vector3(4.5, 0.0, 1.0)

@export_group("Follow / Protect")
@export var follow_min := 4.0
@export var follow_max := 6.0
## Gegner naeher am Guardian als das -> Bodyguard-Angriff.
@export var guard_radius := 8.0
## Bodyguard-Ziel wird erst bei diesem Abstand zum Guardian wieder losgelassen.
@export var guard_release_radius := 11.0

@export_group("Attack")
@export var attack_range := 3.2
@export var attack_interval := 1.8
@export var lunge_speed := 22.0
@export var lunge_time := 0.18
@export var base_damage := 40.0

## Rueckweich-Tempo (Anteil von run_speed), wenn der Spirit zu nah am Guardian steht.
const BACKOFF_FACTOR := 0.3
const POP_SCALE := 1.4
const POP_TIME := 0.25
const GLOW := 0.6

var state: State = State.FOLLOW_PROTECT
var spirit: SpiritData = null
## Fokus-Ziel vom Hard-Lock (Gegner oder LockPoint). null = kein Befehl.
var combat_target: Node3D = null
## Selbst gewaehltes Ziel im Bodyguard-Modus.
var guard_target: Node3D = null
var hits_dealt := 0

var _guardian: GuardianController
var _mat := StandardMaterial3D.new()
var _attack_cd := 0.0
var _lunge_t := 0.0
var _hit_this_lunge: Dictionary = {}
var _stuck_t := 0.0
var _stuck_from := Vector3.ZERO

@onready var _visual: Node3D = $Visual
@onready var _hitbox: Area3D = $Hitbox


func _ready() -> void:
	_guardian = get_node_or_null(guardian_path) as GuardianController
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = GLOW
	($Visual/Body as MeshInstance3D).material_override = _mat
	if _guardian:
		_bind_guardian.call_deferred()  # Guardian (Eltern-Node) ist erst nach uns ready


func _bind_guardian() -> void:
	add_collision_exception_with(_guardian)
	_guardian.hard_lock_changed.connect(_on_hard_lock_changed)
	var roster := _guardian.spirit_roster
	if roster:
		roster.field_spirit_changed.connect(set_spirit)
		set_spirit(roster.field_spirit())
	_place_next_to_guardian()


## Neuer Feld-Spirit: Farbe + Daten live tauschen, kurzer Scale-Pop.
func set_spirit(s: SpiritData) -> void:
	spirit = s
	visible = s != null
	if s == null:
		return
	_mat.albedo_color = s.theme_color
	_mat.emission = s.theme_color
	_visual.scale = Vector3.ONE * POP_SCALE
	create_tween().tween_property(_visual, "scale", Vector3.ONE, POP_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_hard_lock_changed(target: Node3D) -> void:
	combat_target = target
	guard_target = null


## Aktuelles Ziel: Fokus-Befehl hat Vorrang (nur in Grapple-Reichweite des Guardians,
## sonst Rueckweg zum Guardian), ohne Befehl Bodyguard.
func current_target() -> Node3D:
	if guardian_in_safe_zone():
		return null
	if _valid(combat_target):
		return combat_target if _guardian.hard_lock_in_range() else null
	return guard_target if _valid(guard_target) else null


func _physics_process(delta: float) -> void:
	if _guardian == null or spirit == null:
		return
	_attack_cd -= delta
	if _guardian.global_position.distance_to(global_position) > emergency_teleport_distance \
			or global_position.y < GuardianController.RESPAWN_Y or _is_stuck(delta):
		_place_next_to_guardian()
	_update_guard_target()
	var t := current_target()
	if t == null:
		state = State.FOLLOW_PROTECT
	else:
		state = State.ATTACK if _flat_dist(_target_point(t)) <= attack_range else State.CHASE
	if _lunge_t > 0.0:
		_process_lunge(delta)
	else:
		match state:
			State.FOLLOW_PROTECT:
				_process_follow(delta)
			State.CHASE:
				_run_towards(_target_point(t), _speed_for(_target_point(t)), delta)
			State.ATTACK:
				_process_attack(t, delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()


# --- States ---------------------------------------------------------------
func _process_follow(delta: float) -> void:
	var gp := _guardian.global_position
	var d := _flat_dist(gp)
	if d > follow_max:
		_run_towards(gp, _speed_for(gp), delta)
	elif d < follow_min:
		# Zu nah: langsam zuruecktreten, Blick nach aussen (Rueckendeckung).
		_run_towards(global_position * 2.0 - gp, run_speed * BACKOFF_FACTOR, delta)
	else:
		_brake(delta)
		_face(gp, delta)


func _process_attack(t: Node3D, delta: float) -> void:
	_brake(delta)
	var p := _target_point(t)
	_face(p, delta)
	if _attack_cd <= 0.0:
		_start_lunge(p)


func _start_lunge(p: Vector3) -> void:
	_attack_cd = attack_interval
	_lunge_t = lunge_time
	_hit_this_lunge.clear()
	var dir := _flat_dir(p)
	velocity.x = dir.x * lunge_speed
	velocity.z = dir.z * lunge_speed
	# Greybox-Animation: Kapsel streckt sich nach vorne und federt zurueck.
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(0.85, 0.85, 1.35), lunge_time * 0.5)
	tw.tween_property(_visual, "scale", Vector3.ONE, lunge_time)


func _process_lunge(delta: float) -> void:
	_lunge_t -= delta
	for body in _hitbox.get_overlapping_bodies():
		var rc := GuardianController.hit_receiver_of(body)
		if rc == null or rc == _guardian or _hit_this_lunge.has(rc.get_instance_id()):
			continue
		_hit_this_lunge[rc.get_instance_id()] = true
		_deal_hit(rc, _hit_position(rc))


## Trefferstelle = naechster Punkt des naechsten Koerperteils zur Hitbox-Mitte.
func _hit_position(receiver: Node) -> Vector3:
	var c := _hitbox.global_position
	var best := c
	var best_d := INF
	for cs in KnifeCombat.body_parts(receiver):
		var p := KnifeCombat.closest_point_on_part(cs, c)
		if p.distance_to(c) < best_d:
			best_d = p.distance_to(c)
			best = p
	return best


func _deal_hit(receiver: Node, hit_pos: Vector3) -> void:
	var mult := SpiritRosterComponent.pillar_factor_against(spirit.pillar, receiver)
	var dmg := base_damage * mult
	receiver.take_hit(dmg, -global_basis.z, self)
	hits_dealt += 1
	hit_landed.emit(receiver, dmg, spirit.special_effect_tag, hit_pos)
	print("[SPIRIT] %s trifft %s: %.0f (x%.1f) [%s]" % [
			spirit.spirit_name, receiver.name, dmg, mult, spirit.special_effect_tag])


# --- Ziele ----------------------------------------------------------------
## Bodyguard: naechsten Gegner im guard_radius um den Guardian waehlen,
## loslassen sobald er weiter als guard_release_radius weg ist.
func _update_guard_target() -> void:
	if _valid(combat_target) or guardian_in_safe_zone():
		guard_target = null
		return
	var gp := _guardian.global_position
	if _valid(guard_target) and gp.distance_to(_target_point(guard_target)) <= guard_release_radius:
		return
	guard_target = null
	var best := guard_radius
	for t in _guardian._lockables_within(guard_radius):
		var d := gp.distance_to(_target_point(t))
		if d <= best:
			best = d
			guard_target = t


func guardian_in_safe_zone() -> bool:
	for z in get_tree().get_nodes_in_group("safe_zone"):
		if (z as Area3D).overlaps_body(_guardian):
			return true
	return false


## Notfall-Erkennung: im FOLLOW_PROTECT weit vom Guardian und seit stuck_time kaum bewegt.
func _is_stuck(delta: float) -> bool:
	if state != State.FOLLOW_PROTECT or global_position.distance_to(_guardian.global_position) < stuck_distance \
			or global_position.distance_to(_stuck_from) > follow_min:
		_stuck_t = 0.0
		_stuck_from = global_position
		return false
	_stuck_t += delta
	return _stuck_t >= stuck_time


func _valid(t: Node3D) -> bool:
	return t != null and is_instance_valid(t) and _guardian._is_lockable(t)


func _target_point(t: Node3D) -> Vector3:
	return _guardian._lock_point_of(t)


# --- Bewegung -------------------------------------------------------------
func _speed_for(p: Vector3) -> float:
	return catchup_speed if _flat_dist(p) > catchup_distance else run_speed


func _run_towards(p: Vector3, speed: float, delta: float) -> void:
	var want := _flat_dir(p) * speed
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, accel * delta)
	velocity.x = h.x
	velocity.z = h.z
	_face(p, delta)


func _brake(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, accel * delta)
	velocity.x = h.x
	velocity.z = h.z


func _face(p: Vector3, delta: float) -> void:
	var dir := _flat_dir(p)
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(turn_speed * delta, 1.0))


func _flat_dir(p: Vector3) -> Vector3:
	var v := p - global_position
	v.y = 0.0
	return v.normalized()


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _place_next_to_guardian() -> void:
	_stuck_t = 0.0
	global_position = _guardian.global_position + Basis(Vector3.UP, _guardian._yaw) * spawn_offset
	velocity = Vector3.ZERO
	reset_physics_interpolation()
