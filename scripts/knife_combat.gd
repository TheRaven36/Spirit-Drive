class_name KnifeCombat
extends Node
## Jagdmesser – Grundstruktur fuer den Nahkampf (LMB / Xbox X).
##
## 3er-Combo mit Windup -> Active -> Recovery. Treffer per Kugel-Abfrage vor
## der Blickrichtung. Schaden skaliert mit dem Tempo (Flyby-Slashes) und
## blockiert das Movement nicht – der Flow bleibt erhalten.
## Ziele brauchen eine Methode `take_hit(damage: float, dir: Vector3, source: Node)`.

signal slash_started(combo_index: int)
signal hit_landed(target: Node, damage: float)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

@export var base_damage := 10.0
@export var combo_multipliers := PackedFloat32Array([1.0, 1.15, 1.6])
## +x Schaden pro m/s Geschwindigkeit (0.03 = +3 % pro m/s).
@export var speed_damage_bonus := 0.03
@export var dive_damage_mult := 3.0
@export var slash_windup := 0.04
@export var slash_active := 0.12
@export var slash_recovery := 0.12
@export var combo_window := 0.35
@export var hit_radius := 1.4
@export var hit_reach := 1.7
@export_flags_3d_physics var hit_mask := 1

var phase: Phase = Phase.IDLE
var combo_index := -1
## 0..1 waehrend eines Slashes, -1 im Leerlauf (fuer die Messer-Animation).
var swing_progress := -1.0

var _guardian: GuardianController
var _t := 0.0
var _since_last := 99.0
var _queued := false
var _already_hit: Dictionary = {}
var _shape := SphereShape3D.new()


func _ready() -> void:
	_guardian = get_parent() as GuardianController
	_shape.radius = hit_radius


func request_slash() -> void:
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
	var dir := _guardian.aim_forward()
	var center := _guardian.global_position + Vector3.UP * 0.4 + dir * hit_reach
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = hit_mask
	params.exclude = [_guardian.get_rid()]
	var results := _guardian.get_world_3d().direct_space_state.intersect_shape(params, 16)
	var mult := combo_multipliers[combo_index] if combo_index >= 0 else 1.0
	for r: Dictionary in results:
		var col: Object = r.collider
		if col == null or not col.has_method("take_hit"):
			continue
		var id := col.get_instance_id()
		if _already_hit.has(id):
			continue
		_already_hit[id] = true
		_deal(col as Node, mult, dir)


## Direkter Treffer, z. B. am Ende eines Sturzangriffs.
func strike(target: Node, mult: float) -> void:
	if target == null or not target.has_method("take_hit"):
		return
	_deal(target, mult * dive_damage_mult, _guardian.velocity.normalized())


func _deal(target: Node, mult: float, dir: Vector3) -> void:
	var speed := _guardian.velocity.length() if _guardian else 0.0
	var dmg := base_damage * mult * (1.0 + speed * speed_damage_bonus)
	target.take_hit(dmg, dir, _guardian)
	hit_landed.emit(target, dmg)
