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
##   (Geschwindigkeit = staerkstes Anflug-Momentum kurz vor dem Schlag-Start,
##    siehe GuardianController.momentum_velocity())
##   - Speed-Faktor = 1 + speed_scale * (Speed / speed_ref) ^ speed_exponent
##     Stillstand = 1x (minimaler Base-Damage), Vorbeiflug steigt ueberproportional.
##   - Sturzflug-Faktor (High-Hit): nur bei steilem Fall von oben
##     (Abwaertsspeed >= plunge_min_down_speed, Steilheit >= plunge_min_verticality).
##     Exponentiell: verdoppelt sich je plunge_step m/s zusaetzlicher Fallgeschwindigkeit,
##     mal Steilheit, mal turbo_bonus im Turbo-Pull.
##   Das Info-Dictionary (speed_mult, plunge_mult, is_plunge, ...) ist die Basis fuer
##   spaetere Schwachstellen-/Ruestungs-Mechaniken.
##
## TREFFER-SKALIERUNG (scale_for_target): der Rohschaden geht durch einen weichen
##   Deckel  Schaden = cap * tanh(roh / cap).  Kleine Treffer bleiben ~unveraendert,
##   ein Top-Sturzflug landet knapp unter dem Deckel.
##   - Standard-Ziele (Adds, Dummies): cap = hit_soft_cap (285 -> ~95 % eines 300-HP-Dummys).
##   - Bosse definieren get_hit_cap() (z. B. Riese: 15 % der Max-HP) -> dicker Brocken,
##     aber nie ein billiger One-Hit-Kill.
##
## PIERCING (Gegner mit mehreren Koerperteilen = mehrere CollisionShape3D):
##   - Epizentrum = Einschlagpunkt des Primaer-Treffers (Lock-Punkt bzw. naechster
##     Punkt des getroffenen Koerperteils). Das Primaer-Teil bekommt 100 %.
##   - Alle anderen Teile, die die Flugbahn seit Schlag-Start im Schlag-Radius
##     durchquert, bekommen Schaden proportional zur Distanz Epizentrum -> Teil:
##       Anteil = pierce_secondary_max * (1 - d / pierce_radius) ^ pierce_falloff_exp
##     (anliegendes Teil d~0 -> ~50 %, Rand bei ~3.6 m -> ~10 %, ab pierce_radius 0 %).
##   - Nicht durchquerte Teile (ausserhalb der Bahn / hinter dem Einschlag) = 0 %.
##   - Zusammen bekommen die Nebenteile hoechstens pierce_secondary_budget x Primaer.
##   - debug_hits: Konsolen-Tabelle + farbige Marker (Epizentrum weiss, Teile rot->gelb).
##
## HIT-WINDOW BEI HIGH-SPEED: Reichweite des Lock-Schlags und Kugel-Radius wachsen mit
##   dem Tempo, die Active-Phase verlaengert sich, und der Lock-Treffer prueft die ganze
##   Strecke seit dem letzten Physik-Frame (kein Durchtunneln bei 60+ m/s).
##
## WAFFEN-SPIRIT (set_weapon_spirit, gespeist vom SpiritRosterComponent):
##   Der gesockelte Spirit faerbt Klinge + Trail in seine theme_color und haengt
##   seinen special_effect_tag an jeden Treffer (info.effect_tag). Schaden (vor dem
##   Deckel) x weapon_damage_multiplier x Saeulen-Faktor (1.5 / 0.75 / 1.0), falls das
##   Ziel eine Saeule hat (Methode get_spirit_pillar() -> SpiritData.Pillar).
##   Leere Waffe (null, reiner Stahl): Silber-Trail, kein Saeulen-Faktor, dafuer
##   +steel_momentum_bonus bei High-Speed-Treffern (Schlag-Tempo >= steel_bonus_min_speed).
## RUESTUNG (Ziel mit is_armored()): Elementar-Faktoren prallen ab (gesockelt = 1.0x),
##   reiner Stahl bricht sie mit armor_break_multiplier. Gebrochen -> Saeulen-Faktor wieder voll.

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
@export_subgroup("Treffer-Deckel")
## Weicher Deckel pro Treffer fuer normale Ziele (Dummies/Adds).
@export var hit_soft_cap := 285.0
@export_group("Timing")
@export var slash_windup := 0.04
@export var slash_active := 0.12
@export var slash_recovery := 0.12
@export var combo_window := 0.35
@export_group("Hitbox")
@export var hit_radius := 1.4
@export var hit_reach := 1.7
@export_flags_3d_physics var hit_mask := 1
## Reichweite des Lock-Slashs (Spieler-Mitte bis Lock-Punkt) im Stand ...
@export var lock_strike_reach := 4.0
## ... plus Tempo * diese Zeit (s) – breiteres Fenster bei High-Speed ...
@export var speed_reach_time := 0.03
## ... maximal so viel zusaetzlich (m).
@export var speed_reach_max := 2.5
## Kugel-Radius waechst ebenfalls mit dem Tempo (m pro m/s, gedeckelt).
@export var speed_radius_per_mps := 0.015
@export var speed_radius_max := 1.0
## Active-Phase verlaengert sich bei Tempo (s pro m/s, gedeckelt).
@export var speed_active_per_mps := 0.0015
@export var speed_active_max := 0.08
@export_group("Piercing")
## Maximaler Anteil fuer ein direkt anliegendes Nebenteil (d = 0).
@export var pierce_secondary_max := 0.5
## Ab dieser Distanz (m) vom Epizentrum gibt es keinen Splash-Schaden mehr.
@export var pierce_radius := 4.5
## Form der Abnahme: 1 = linear, > 1 = faellt schneller ab.
@export var pierce_falloff_exp := 1.0
## Summe aller Nebenteile <= Budget x Primaer-Schaden (kein Vervielfachen am Boss).
@export var pierce_secondary_budget := 1.0
## Abtastschritt (m) entlang der Flugbahn.
@export var pierce_path_step := 0.4
@export_group("Reiner Stahl")
## Bonus der leeren Waffe bei High-Speed-Treffern (0.15 = +15 %).
@export var steel_momentum_bonus := 0.15
## Ab diesem Schlag-Tempo (m/s) gilt ein Treffer als High-Speed.
@export var steel_bonus_min_speed := 20.0
## Stahl gegen Ruestung (1.5 = +50 %). Schmiede-Upgrades erhoehen ihn.
@export var armor_break_multiplier := 1.5
@export_group("Debug")
## Konsolen-Ausgabe + Marker fuer Treffer-Zonen, Epizentrum und Prozentwerte.
@export var debug_hits := true
@export var debug_marker_time := 2.0

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
var _active_time := 0.12
var _prev_pos := Vector3.ZERO
## Flugbahn seit Schlag-Start (fuer Piercing).
var _path := PackedVector3Array()
## Piercing-Zustand des aktuellen Schlags.
var _pierce_receiver: CollisionObject3D = null
var _pierce_primary: CollisionShape3D = null
var _pierce_epicenter := Vector3.ZERO
var _pierce_damage := 0.0
var _pierce_dir := Vector3.ZERO
var _pierce_used := 0.0
var _pierce_done: Dictionary = {}   # shape instance id -> true
## Ergebnis des letzten Piercing-Schlags: [{part, pct, damage, dist, traversed, primary}]
var last_pierce: Array = []
## Aktuell gesockelter Spirit (null = blanke Klinge).
var weapon_spirit: SpiritData = null
## Farbe fuer Klingen-Glow und Slash-Trail (leere Waffe = Silber).
const STEEL_COLOR := Color(0.88, 0.9, 0.95)
var trail_color := STEEL_COLOR
var _blade_mat: StandardMaterial3D = null
## Leichter Slash-Trail: kleine Leucht-Quader entlang der Klingenspitze (1 Draw Call).
const TRAIL_POINTS := 12
const TRAIL_LIFETIME := 0.18
var _trail_mm: MultiMesh = null
var _trail_mmi: MultiMeshInstance3D = null
var _trail_pos := PackedVector3Array()
var _trail_age := PackedFloat32Array()


func _ready() -> void:
	_guardian = get_parent() as GuardianController
	_shape.radius = hit_radius
	_build_trail.call_deferred()


## Waffen-Sockel setzen: Klingen-Glow, Trail-Farbe, Element-Tag.
func set_weapon_spirit(spirit: SpiritData) -> void:
	weapon_spirit = spirit
	trail_color = spirit.theme_color if spirit else STEEL_COLOR
	if _guardian == null:
		return
	if _blade_mat == null:
		_blade_mat = StandardMaterial3D.new()
		_blade_mat.metallic = 0.9
		_blade_mat.roughness = 0.25
		_blade_mat.emission_enabled = true
		for pivot: Node3D in [_guardian.knife_tp, _guardian.knife_fp]:
			var blade := pivot.get_node_or_null("Blade") as GeometryInstance3D
			if blade:
				blade.material_override = _blade_mat
	_blade_mat.albedo_color = trail_color.lerp(Color(0.85, 0.88, 0.92), 0.4)
	_blade_mat.emission = trail_color
	_blade_mat.emission_energy_multiplier = 1.5 if spirit else 0.4  # Stahl: dezentes Silber
	if _trail_mm:
		(_trail_mm.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = trail_color


## Faktor der Waffe gegen `target`: gesockelt = Spirit-Multiplikator x Saeulen-Faktor (prallt an
## Ruestung ab), leer = Armor-Break gegen Ruestung x Stahl-Bonus bei High-Speed.
func element_multiplier(target: Node) -> float:
	if weapon_spirit == null:
		var armor := armor_break_multiplier if SpiritRosterComponent.is_armored(target) else 1.0
		return armor * (1.0 + steel_momentum_bonus if is_steel_bonus() else 1.0)
	return weapon_spirit.weapon_damage_multiplier \
			* SpiritRosterComponent.pillar_factor_against(weapon_spirit.pillar, target)


## Leere Waffe + aktueller Schlag schnell genug -> Stahl-Bonus.
func is_steel_bonus() -> bool:
	return weapon_spirit == null and _swing_velocity.length() >= steel_bonus_min_speed


func _build_trail() -> void:
	if _guardian == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = trail_color
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 0.06)
	mesh.material = mat
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	_trail_mm.mesh = mesh
	_trail_mm.instance_count = TRAIL_POINTS
	_trail_mm.visible_instance_count = 0
	_trail_mmi = MultiMeshInstance3D.new()
	_trail_mmi.name = "SlashTrail"
	_trail_mmi.top_level = true
	_trail_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mmi.multimesh = _trail_mm
	_guardian.add_child(_trail_mmi)
	_trail_mmi.global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if _trail_mm == null:
		return
	# Neue Trail-Punkte nur waehrend der Active-Phase an der sichtbaren Klinge.
	if phase == Phase.ACTIVE:
		var pivot: Node3D = _guardian.knife_fp if _guardian.first_person else _guardian.knife_tp
		var blade := pivot.get_node_or_null("Blade") as Node3D
		if blade:
			_trail_pos.append(blade.global_transform * Vector3(0, 0, -0.3))
			_trail_age.append(0.0)
	for i in _trail_age.size():
		_trail_age[i] += delta
	while not _trail_age.is_empty() and (_trail_age[0] > TRAIL_LIFETIME or _trail_age.size() > TRAIL_POINTS):
		_trail_age.remove_at(0)
		_trail_pos.remove_at(0)
	_trail_mm.visible_instance_count = _trail_pos.size()
	for i in _trail_pos.size():
		var k := 1.0 - _trail_age[i] / TRAIL_LIFETIME
		_trail_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * (0.4 + k)), _trail_pos[i]))
		_trail_mm.set_instance_color(i, Color(1, 1, 1, k))


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
	_path.clear()
	if _guardian:
		_swing_velocity = _guardian.momentum_velocity()
		_swing_turbo = _guardian.is_turbo()
		_prev_pos = _guardian.global_position
		_path.append(_prev_pos)
	_active_time = slash_active + minf(_swing_velocity.length() * speed_active_per_mps, speed_active_max)
	_queued = false
	_already_hit.clear()
	_pierce_receiver = null
	_pierce_primary = null
	_pierce_done.clear()
	_pierce_used = 0.0
	slash_started.emit(combo_index)


func _physics_process(delta: float) -> void:
	_since_last += delta
	if phase == Phase.IDLE:
		swing_progress = -1.0
		return
	_t += delta
	var total := slash_windup + _active_time + slash_recovery
	swing_progress = clampf(_t / total, 0.0, 1.0)
	match phase:
		Phase.WINDUP:
			if _guardian:
				_prev_pos = _guardian.global_position
				_path.append(_prev_pos)
			if _t >= slash_windup:
				phase = Phase.ACTIVE
		Phase.ACTIVE:
			_sweep_hits()
			if _t >= slash_windup + _active_time:
				_finish_pierce()
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
	var pos := _guardian.global_position
	var seg_from := _prev_pos
	_prev_pos = pos
	_path.append(pos)
	# Lock-Slash: direkter Treffer auf den Lock-Punkt im Anflug. Geprueft wird die ganze
	# Strecke seit dem letzten Frame -> bei High-Speed kein Vorbeirauschen ohne Treffer.
	if is_instance_valid(_lock):
		var lp: Vector3 = _guardian._lock_point_of(_lock)
		dir = (lp - pos).normalized()
		var receiver := GuardianController.hit_receiver_of(_lock)
		var closest := Geometry3D.get_closest_point_to_segment(lp, seg_from, pos)
		if receiver and closest.distance_to(lp) <= strike_reach() \
				and not _already_hit.has(receiver.get_instance_id()):
			_already_hit[receiver.get_instance_id()] = true
			var dmg := _deal(receiver, mult, dir, lp, _lock)
			_begin_pierce(receiver, _part_of_point(receiver, _lock, lp), lp, dmg, dir)
	_shape.radius = swing_radius()
	var center := pos + Vector3.UP * 0.4 + dir * hit_reach
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
		# Primaer-Teil = getroffene Shape, Epizentrum = naechster Punkt darauf.
		var part := _shape_of(col, r.get("shape", -1))
		var hit_pos := closest_point_on_part(part, pos) if part else (col as Node3D).global_position
		var dmg := _deal(col as Node, mult, dir, hit_pos, point)
		if part != null:
			_begin_pierce(col as Node, part, hit_pos, dmg, dir)
	_update_pierce()


# =========================================================================
# Piercing: Multi-Hit mit Distanz-Abfall um das Epizentrum
# =========================================================================
## Koerperteile eines Ziels = direkte CollisionShape3D-Kinder.
static func body_parts(receiver: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	if receiver == null:
		return out
	for c in receiver.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			out.append(c)
	return out


static func part_name(cs: CollisionShape3D) -> String:
	return String(cs.name).trim_prefix("Shape_")


## Abstand (m) von p zur Oberflaeche eines Koerperteils (0 = innen/anliegend).
static func part_distance(cs: CollisionShape3D, p: Vector3) -> float:
	return p.distance_to(closest_point_on_part(cs, p))


## Naechster Punkt eines Koerperteils zu p (Box, Kugel, Kapsel, Zylinder exakt).
static func closest_point_on_part(cs: CollisionShape3D, p: Vector3) -> Vector3:
	var xf := cs.global_transform
	var l := xf.affine_inverse() * p
	var sh := cs.shape
	var q := Vector3.ZERO  # unbekannte Shape -> Mittelpunkt
	if sh is BoxShape3D:
		var h := (sh as BoxShape3D).size * 0.5
		q = l.clamp(-h, h)
	elif sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		q = l if l.length() <= r else l.normalized() * r
	elif sh is CapsuleShape3D:
		var c := sh as CapsuleShape3D
		var half := maxf(c.height * 0.5 - c.radius, 0.0)
		var axis := Vector3(0.0, clampf(l.y, -half, half), 0.0)
		var off := l - axis
		q = l if off.length() <= c.radius else axis + off.normalized() * c.radius
	elif sh is CylinderShape3D:
		var cy := sh as CylinderShape3D
		var flat := Vector2(l.x, l.z)
		if flat.length() > cy.radius:
			flat = flat.normalized() * cy.radius
		q = Vector3(flat.x, clampf(l.y, -cy.height * 0.5, cy.height * 0.5), flat.y)
	return xf * q


## Splash-Anteil fuer ein Nebenteil mit Abstand d zum Epizentrum.
func pierce_falloff(d: float) -> float:
	var k := clampf(1.0 - d / maxf(pierce_radius, 0.01), 0.0, 1.0)
	return pierce_secondary_max * pow(k, pierce_falloff_exp)


## Schlag-Radius der Messer-Kugel und der Flugbahn (waechst mit dem Tempo).
func swing_radius() -> float:
	return hit_radius + minf(_swing_velocity.length() * speed_radius_per_mps, speed_radius_max)


func _shape_of(col: Object, shape_idx: int) -> CollisionShape3D:
	if not (col is CollisionObject3D) or shape_idx < 0 or body_parts(col as Node).size() < 2:
		return null
	var co := col as CollisionObject3D
	return co.shape_owner_get_owner(co.shape_find_owner(shape_idx)) as CollisionShape3D


## Koerperteil eines Lock-Punkts: Eltern-Shape oder das naechste Teil.
func _part_of_point(receiver: Node, point: Node3D, p: Vector3) -> CollisionShape3D:
	var parts := body_parts(receiver)
	if parts.size() < 2:
		return null
	if point != null and point.get_parent() is CollisionShape3D and parts.has(point.get_parent()):
		return point.get_parent()
	var best: CollisionShape3D = null
	var best_d := INF
	for cs in parts:
		var d := part_distance(cs, p)
		if d < best_d:
			best_d = d
			best = cs
	return best


func _begin_pierce(receiver: Node, primary: CollisionShape3D, epicenter: Vector3,
		damage: float, dir: Vector3) -> void:
	if primary == null or _pierce_receiver != null or not (receiver is CollisionObject3D):
		return
	_pierce_receiver = receiver
	_pierce_primary = primary
	_pierce_epicenter = epicenter
	_pierce_damage = damage
	_pierce_dir = dir
	_pierce_used = 0.0
	_pierce_done.clear()
	_pierce_done[primary.get_instance_id()] = true
	last_pierce = [_pierce_entry(primary, 1.0, damage, 0.0, true, true)]
	last_hit["part"] = part_name(primary)
	last_hit["epicenter"] = epicenter
	if debug_hits:
		print("[PIERCE] Epizentrum %s  Primaer %s = 100 %% (%.0f)" % [
				_v(epicenter), part_name(primary), damage])
		_marker(epicenter, Color.WHITE, 0.35)
		_marker(closest_point_on_part(primary, epicenter), Color(1, 0.15, 0.1), 0.3)
	_update_pierce()


## Prueft die bisherige Flugbahn: welche Nebenteile wurden durchquert?
func _update_pierce() -> void:
	if _pierce_receiver == null or not is_instance_valid(_pierce_receiver):
		return
	var radius := swing_radius()
	for cs in body_parts(_pierce_receiver):
		var id := cs.get_instance_id()
		if _pierce_done.has(id) or not _path_touches(cs, radius):
			continue
		_pierce_done[id] = true
		var d := part_distance(cs, _pierce_epicenter)
		var pct := minf(pierce_falloff(d), maxf(pierce_secondary_budget - _pierce_used, 0.0))
		var dmg := _pierce_damage * pct
		var entry := _pierce_entry(cs, pct, dmg, d, true)
		last_pierce.append(entry)
		if pct <= 0.0:
			if debug_hits:
				print("[PIERCE]   %-8s   0 %%  (%.2f m vom Epizentrum, ausserhalb Radius %.1f m)"
						% [entry.part, d, pierce_radius])
			continue
		_pierce_used += pct
		_pierce_receiver.take_hit(dmg, _pierce_dir, _guardian)
		var info := {"damage": dmg, "point": entry.part, "pct": pct, "pierce": true,
				"hit_position": closest_point_on_part(cs, _pierce_epicenter)}
		hit_landed.emit(_pierce_receiver, dmg, info)
		if debug_hits:
			print("[PIERCE]   %-8s %3d %%  %.0f Schaden  (%.2f m vom Epizentrum)"
					% [entry.part, roundi(pct * 100.0), dmg, d])
			_marker(closest_point_on_part(cs, _pierce_epicenter),
					Color(1.0, 0.2 + 0.8 * (1.0 - pct / maxf(pierce_secondary_max, 0.01)), 0.1), 0.25)


## Eintrag fuer last_pierce.
func _pierce_entry(cs: CollisionShape3D, pct: float, damage: float, dist: float,
		traversed: bool, primary := false) -> Dictionary:
	return {"part": part_name(cs), "pct": pct, "damage": damage, "dist": dist,
			"traversed": traversed, "primary": primary}


func _path_touches(cs: CollisionShape3D, radius: float) -> bool:
	for i in range(1, _path.size()):
		var a := _path[i - 1]
		var b := _path[i]
		var steps := maxi(1, ceili(a.distance_to(b) / maxf(pierce_path_step, 0.05)))
		for k in steps + 1:
			if part_distance(cs, a.lerp(b, float(k) / float(steps))) <= radius:
				return true
	return false


## Schlag-Ende: nicht durchquerte Teile als 0 % auflisten (Debug).
func _finish_pierce() -> void:
	if _pierce_receiver == null or not is_instance_valid(_pierce_receiver):
		return
	_update_pierce()
	for cs in body_parts(_pierce_receiver):
		if _pierce_done.has(cs.get_instance_id()):
			continue
		var d := part_distance(cs, _pierce_epicenter)
		last_pierce.append(_pierce_entry(cs, 0.0, 0.0, d, false))
		if debug_hits:
			print("[PIERCE]   %-8s   0 %%  (nicht durchquert, %.2f m vom Epizentrum)" % [part_name(cs), d])
	if debug_hits:
		var total := 0.0
		for e: Dictionary in last_pierce:
			total += e.damage
		print("[PIERCE] Summe %.0f Schaden an %s" % [total, _pierce_receiver.name])


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


## Debug-Gizmo: kleine leuchtende Kugel, verschwindet nach debug_marker_time.
func _marker(p: Vector3, col: Color, r: float) -> void:
	if _guardian == null or not _guardian.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true
	m.material = mat
	mi.mesh = m
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guardian.get_parent().add_child(mi)
	mi.global_position = p
	_guardian.get_tree().create_timer(debug_marker_time).timeout.connect(mi.queue_free)


## Reichweite des Lock-Schlags beim aktuellen Schlag-Momentum.
func strike_reach() -> float:
	return lock_strike_reach + minf(_swing_velocity.length() * speed_reach_time, speed_reach_max)


## Weicher Treffer-Deckel: ~linear fuer kleine Werte, naehert sich `cap` an.
static func soft_cap(raw: float, cap: float) -> float:
	return cap * tanh(raw / maxf(cap, 0.001))


## Deckel fuer ein Ziel: Bosse liefern get_hit_cap(), sonst hit_soft_cap.
func hit_cap_for(target: Node) -> float:
	if target != null and target.has_method("get_hit_cap"):
		return target.get_hit_cap()
	return hit_soft_cap


## Rohschaden (inkl. Punkt-Faktor) -> endgueltiger Schaden am Ziel.
func scale_for_target(raw: float, target: Node) -> float:
	return soft_cap(raw, hit_cap_for(target))


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


## hit_pos = Trefferstelle am Koerperteil (Damage-Numbers).
func _deal(target: Node, mult: float, dir: Vector3, hit_pos: Vector3, point: Node3D = null) -> float:
	var info := compute_damage(_swing_velocity, mult, _swing_turbo)
	var lp := point as LockPoint
	var point_mult := lp.damage_mult if lp else 1.0
	var elem_mult := element_multiplier(target)
	info["raw_damage"] = info.damage * point_mult * elem_mult
	info["element_mult"] = elem_mult
	info["element"] = weapon_spirit.element_name() if weapon_spirit else ""
	info["effect_tag"] = weapon_spirit.special_effect_tag if weapon_spirit else ""
	info["steel_bonus"] = is_steel_bonus()
	info["armor_hit"] = SpiritRosterComponent.is_armored(target)
	info["hit_cap"] = hit_cap_for(target)
	info.damage = scale_for_target(info.raw_damage, target)
	info["point_mult"] = point_mult
	info["point"] = lp.label if lp else ""
	info["hit_position"] = hit_pos
	last_hit = info
	target.take_hit(info.damage, dir, _guardian)
	hit_landed.emit(target, info.damage, info)
	return info.damage
