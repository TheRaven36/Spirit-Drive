class_name KnifeCombat
extends Node
## Jagdmesser – Grundstruktur fuer den Nahkampf (LMB / Xbox X).
##
## 3er-Combo mit Windup -> Active -> Recovery. Treffer per Kugel-Abfrage vor
## der Blickrichtung. Blockiert das Movement nicht – der Flow bleibt erhalten.
## Ziele brauchen eine Methode `take_hit(damage: float, dir: Vector3, source: Node)`.
##
## Lock-Slash: request_slash(lock_node) bindet den Schlag an einen Lock-Punkt
## (Hard-Lock). Ist der Punkt waehrend der Active-Phase in lock_strike_reach,
## trifft der Schlag ihn direkt (Anflug-Schlag) – inkl. damage_mult des Punkts.
##
## MOMENTUM-SCHADEN (compute_damage):
##   Schaden = min_damage * Combo * Speed-Faktor * Sturzflug-Faktor * Punkt-Faktor
##   (Geschwindigkeit = Momentum beim Schlag-Start, also im Anflug)
##   - Speed-Faktor = 1 + speed_scale * (Speed / speed_ref) ^ speed_exponent
##     Stillstand = 1x (minimaler Base-Damage), Vorbeiflug steigt ueberproportional.
##   - Sturzflug-Faktor (High-Hit): nur bei steilem Fall von oben
##     (Abwaertsspeed >= plunge_min_down_speed, Steilheit >= plunge_min_verticality).
##     Exponentiell: verdoppelt sich je plunge_step m/s zusaetzlicher Fallgeschwindigkeit,
##     mal Steilheit, mal turbo_bonus im Turbo-Pull.
##   Das Info-Dictionary (speed_mult, plunge_mult, is_plunge, ...) ist die Basis fuer
##   spaetere Schwachstellen-/Ruestungs-Mechaniken.

signal slash_started(combo_index: int)
signal hit_landed(target: Node, damage: float, info: Dictionary)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

@export_group("Damage")
## Schaden im Stillstand.
@export var min_damage := 5.0
@export var combo_multipliers := PackedFloat32Array([1.0, 1.15, 1.6])
## Bei speed_ref m/s gibt es +speed_scale (1.0 = +100 %), darueber ueberproportional.
@export var speed_ref := 20.0
@export var speed_scale := 1.0
@export var speed_exponent := 1.5
@export_subgroup("Plunge (Sturzflug von oben)")
@export var plunge_min_down_speed := 15.0
@export var plunge_min_verticality := 0.6
## Basis der Exponentialkurve: x2 je plunge_step m/s zusaetzlicher Fallgeschwindigkeit.
@export var plunge_base := 2.0
@export var plunge_step := 10.0
@export var turbo_bonus := 1.25
@export_group("Timing")
@export var slash_windup := 0.04
@export var slash_active := 0.12
@export var slash_recovery := 0.12
@export var combo_window := 0.35
@export_group("Hitbox")
@export var hit_radius := 1.4
@export var hit_reach := 1.7
@export_flags_3d_physics var hit_mask := 1
## Reichweite des Lock-Slashs (Spieler-Mitte bis Lock-Punkt).
@export var lock_strike_reach := 4.0

var phase: Phase = Phase.IDLE
var combo_index := -1
## 0..1 waehrend eines Slashes, -1 im Leerlauf (fuer die Messer-Animation).
var swing_progress := -1.0
## Letzter Treffer (fuer HUD/Debug): {damage, speed, speed_mult, plunge_mult, is_plunge}
var last_hit: Dictionary = {}

var _guardian: GuardianController
var _t := 0.0
var _since_last := 99.0
var _queued := false
var _already_hit: Dictionary = {}
var _shape := SphereShape3D.new()
var _lock: Node3D = null
## Momentum im Moment des Schlag-Starts (Anflug) – Basis fuer den Schaden,
## damit ein Aufprall in den Frames danach den Bonus nicht verschluckt.
var _swing_velocity := Vector3.ZERO
var _swing_turbo := false


func _ready() -> void:
	_guardian = get_parent() as GuardianController
	_shape.radius = hit_radius


func request_slash(lock: Node3D = null) -> void:
	_lock = lock
	match phase:
		Phase.IDLE, Phase.RECOVERY:
			_start_slash()
		_:
			_queued = true


func is_attacking() -> bool:
	return phase != Phase.IDLE


func _start_slash() -> void:
	if _since_last <= combo_window and combo_index < combo_multipliers.size() - 1:
		combo_index += 1
	else:
		combo_index = 0
	phase = Phase.WINDUP
	_t = 0.0
	if _guardian:
		_swing_velocity = _guardian.velocity
		_swing_turbo = _guardian.is_turbo()
	_queued = false
	_already_hit.clear()
	slash_started.emit(combo_index)


func _physics_process(delta: float) -> void:
	_since_last += delta
	if phase == Phase.IDLE:
		swing_progress = -1.0
		return
	_t += delta
	var total := slash_windup + slash_active + slash_recovery
	swing_progress = clampf(_t / total, 0.0, 1.0)
	match phase:
		Phase.WINDUP:
			if _t >= slash_windup:
				phase = Phase.ACTIVE
		Phase.ACTIVE:
			_sweep_hits()
			if _t >= slash_windup + slash_active:
				phase = Phase.RECOVERY
				_since_last = 0.0
		Phase.RECOVERY:
			if _queued:
				_start_slash()
			elif _t >= total:
				phase = Phase.IDLE
				swing_progress = -1.0


func _sweep_hits() -> void:
	if _guardian == null:
		return
	var mult := combo_multipliers[combo_index] if combo_index >= 0 else 1.0
	var dir := _guardian.aim_forward()
	# Lock-Slash: direkter Treffer auf den Lock-Punkt im Anflug
	if is_instance_valid(_lock):
		var lp: Vector3 = _lock.get_lock_point() if _lock.has_method("get_lock_point") else _lock.global_position
		dir = (lp - _guardian.global_position).normalized()
		var receiver := GuardianController.hit_receiver_of(_lock)
		if receiver and _guardian.global_position.distance_to(lp) <= lock_strike_reach \
				and not _already_hit.has(receiver.get_instance_id()):
			_already_hit[receiver.get_instance_id()] = true
			_deal(receiver, mult, dir, _lock)
	var center := _guardian.global_position + Vector3.UP * 0.4 + dir * hit_reach
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = hit_mask
	params.exclude = [_guardian.get_rid()]
	var results := _guardian.get_world_3d().direct_space_state.intersect_shape(params, 16)
	for r: Dictionary in results:
		var col: Object = r.collider
		if col == null or not col.has_method("take_hit"):
			continue
		var id := col.get_instance_id()
		if _already_hit.has(id):
			continue
		_already_hit[id] = true
		# Treffer am Koerper des gelockten Ziels zaehlt fuer den Lock-Punkt.
		var point: Node3D = _lock if is_instance_valid(_lock) \
				and GuardianController.hit_receiver_of(_lock) == col else null
		_deal(col as Node, mult, dir, point)


## Momentum-Schaden aus Geschwindigkeit (siehe Kopfkommentar).
func compute_damage(vel: Vector3, combo_mult := 1.0, turbo := false) -> Dictionary:
	var speed := vel.length()
	var speed_mult := 1.0 + speed_scale * pow(speed / maxf(speed_ref, 0.01), speed_exponent)
	var down := maxf(-vel.y, 0.0)
	var verticality := down / maxf(speed, 0.001)
	var plunge_mult := 1.0
	var is_plunge := down >= plunge_min_down_speed and verticality >= plunge_min_verticality
	if is_plunge:
		plunge_mult = pow(plunge_base, 1.0 + (down - plunge_min_down_speed) / plunge_step) * verticality
		if turbo:
			plunge_mult *= turbo_bonus
	return {
		"damage": min_damage * combo_mult * speed_mult * plunge_mult,
		"speed": speed,
		"speed_mult": speed_mult,
		"plunge_mult": plunge_mult,
		"is_plunge": is_plunge,
	}


func _deal(target: Node, mult: float, dir: Vector3, point: Node3D = null) -> void:
	var info := compute_damage(_swing_velocity, mult, _swing_turbo)
	var point_mult: float = point.damage_mult if point is LockPoint else 1.0
	info.damage *= point_mult
	info["point_mult"] = point_mult
	info["point"] = (point as LockPoint).label if point is LockPoint else ""
	last_hit = info
	target.take_hit(info.damage, dir, _guardian)
	hit_landed.emit(target, info.damage, info)
