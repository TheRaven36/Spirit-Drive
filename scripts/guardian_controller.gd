class_name GuardianController
extends CharacterBody3D
## Guardian – High-Speed-Controller.
##
## Movement: Laufen / Sprint / Air-Control / Wall-Run.
## Shift:    Sprint am Boden.
## Seile:    Dual-Hip-Grapple auf RMB / LT (zwei Werfer an linker + rechter Huefte).
##           - Klick/Halten: Haken der naechsten freien Huefte (abwechselnd L/R).
##             Straffes Seil, Winde zieht mit Basis 0.4 ein.
##           - Winde am Seil: W = Turbo (2.5x Basis), S = Bremse (~0.05).
##             A / D = seitlich quer zum Seil ausweichen / schwingen.
##           - Doppel-Tap: zweiter Haken an zweiter Oberflaeche, zwei straffe Seile.
##           Seile wickeln sich um Geometrie (Bending) und loesen sich nie von selbst.
## Lock:     Mausrad-Klick / R3 = Hard-Lock an/aus, Mausrad = Ziel-Wechsel.
##           Mit Hard-Lock: LMB halten = Seil zum Lock-Punkt + heranziehen,
##           LMB loslassen = Messer-Schlag im Anflug (Momentum-Schaden).
## Kampf:    LMB = Jagdmesser (siehe KnifeCombat).
## Kamera:   P = Third-/First-Person, nahtlos ueberblendet.
##
## Physik in _physics_process, Kamera/Visuals in _process ueber die
## interpolierte Transform (Physics-Interpolation aktiv) -> keine Mikroruckler.

signal state_changed(new_state: State)
signal camera_mode_changed(first_person: bool)

enum State { NORMAL, HOOKED, WALLRUN }
enum AimKind { NONE, POINT, ENEMY }

# --- Ground ---------------------------------------------------------------
@export_group("Ground")
@export var run_speed := 9.0
@export var sprint_speed := 24.0
@export var ground_accel := 110.0
@export var ground_friction := 10.0
## Wie schnell Ueber-Speed (aus Seil/Sturzflug) am Boden abgebaut wird.
@export var overspeed_decay := 18.0

# --- Air ------------------------------------------------------------------
@export_group("Air")
@export var gravity := 30.0
@export var fall_gravity_mult := 1.35
@export var jump_velocity := 11.5
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var air_accel := 28.0
@export var air_control_speed := 15.0
@export var air_drag := 0.04
@export var terminal_speed := 75.0

# --- Seil (RMB / LT) ------------------------------------------------------
@export_group("Rope")
@export_flags_3d_physics var grapple_mask := 1
@export var grapple_range := 70.0
## Referenz-Einzugsgeschwindigkeit der Winde (m/s) ...
@export var reel_speed := 24.0
## ... automatischer Basis-Einzug = 40 % davon: straff, haelt die Distanz, zieht nicht aggressiv.
@export var reel_base_mult := 0.4
## W am Seil: Turbo-Einzug = Faktor auf den Basis-Einzug.
@export var reel_turbo_mult := 2.5
## S am Seil: Bremse – Winde laeuft nur noch mit diesem Anteil (fast regungslos haengen).
@export var reel_brake_mult := 0.05
## Beim Bremsen wird auch der eigene Schwung gedaempft (1/s), damit man ruhig haengt.
@export var brake_damping := 3.5
## Wie hart das straffe Seil auf die Einzugsgeschwindigkeit nachregelt.
@export var rope_response := 40.0
## Ab dieser Restlaenge stoppt die Winde – man haengt am Anker.
@export var hang_length := 2.5
@export var rope_min_length := 1.5
## A / D am Seil: seitliche Steuerung quer zum Seil.
@export var rope_steer_accel := 24.0
## Nach dem Loslassen haengt das Seil so lange locker (keine Kraft) – Fenster fuer den Doppel-Tap.
@export var double_tap_window := 0.2
## Mindestabstand der beiden Anker beim Doppel-Tap (zweite Oberflaeche).
@export var dual_min_separation := 2.5

# --- Hard-Lock / Combat-Grapple (Mausrad-Klick / R3, LMB) ----------------
@export_group("Combat Grapple")
## Windengeschwindigkeit des Combat-Seils = reel_speed * combat_reel_mult (W/S wirken auch hier).
@export var combat_reel_mult := 1.0
@export var combat_pull_impulse := 6.0
## Hard-Lock bleibt bis zu grapple_range * diesem Faktor bestehen.
@export var lock_keep_range_mult := 1.3

# --- Auto-Aim -------------------------------------------------------------
@export_group("Aim Assist")
## Mindest-Radius um das Fadenkreuz, in dem Ziele einrasten.
@export var assist_radius := 2.5
## Kegel-Halbwinkel: bei grosser Distanz waechst der Fang-Radius mit.
@export var assist_cone_deg := 5.0
@export var assist_rays_per_ring := 8

# --- Wall-Run -------------------------------------------------------------
@export_group("Wall Run")
@export var wallrun_min_speed := 8.0
@export var wallrun_max_time := 1.6
@export var wallrun_gravity_mult := 0.12
@export var wall_jump_push := 12.0
@export var wall_jump_up := 10.0

# --- Camera ---------------------------------------------------------------
@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 3.2
@export var camera_switch_time := 0.25
@export var tp_distance := 4.5
@export var tp_shoulder := 0.6
@export var tp_height := 0.7
@export var fp_height := 0.65
@export var base_fov := 75.0
@export var max_fov := 102.0
@export var base_fov_fp := 85.0
@export var max_fov_fp := 108.0
@export var fov_speed_ref := 45.0

const RESPAWN_Y := -40.0
const MAX_ROPE_SEGMENTS := 32

@onready var cam_rig: Node3D = $CameraRig
@onready var cam_pitch: Node3D = $CameraRig/Pitch
@onready var spring_arm: SpringArm3D = $CameraRig/Pitch/SpringArm3D
@onready var camera: Camera3D = $CameraRig/Pitch/SpringArm3D/Camera3D
@onready var visual: Node3D = $Visual
@onready var body_mesh: GeometryInstance3D = $Visual/Body
@onready var knife: KnifeCombat = $Knife
@onready var knife_tp: Node3D = $Visual/KnifePivot
@onready var knife_fp: Node3D = $CameraRig/Pitch/SpringArm3D/Camera3D/ViewKnife

var state: State = State.NORMAL
var first_person := false

## Auto-Aim-Ergebnis (unsichtbar, nur fuer den Grapple).
var aim_kind: AimKind = AimKind.NONE
var aim_point := Vector3.ZERO
var aim_target: Node3D = null
## true, wenn der Punkt per Assist eingerastet ist (nicht exakt unterm Fadenkreuz).
var aim_assisted := false

var hook_left := GrappleHook.new(GrappleHook.Kind.HIP_LEFT)
var hook_right := GrappleHook.new(GrappleHook.Kind.HIP_RIGHT)
var hooks: Array[GrappleHook] = [hook_left, hook_right]

var aim_normal := Vector3.ZERO
## Bester Lock-Kandidat im Kegel um das Fadenkreuz (unsichtbar).
var lock_target: Node3D = null
## Eingerasteter Hard-Lock (Mausrad-Klick / R3). Bleibt bis zum Loesen bestehen.
var hard_lock: Node3D = null

var _yaw := 0.0
var _pitch := -0.15
var _cam_blend := 0.0
var _coyote_t := 0.0
var _jump_buffer_t := 0.0
var _wall_normal := Vector3.ZERO
var _wallrun_t := 0.0
var _wall_lost_t := 0.0
var _wallrun_lockout := 0.0
var _spawn := Vector3.ZERO
var _rope_mm: MultiMesh
var _next_hip: GrappleHook = null
var _primary: GrappleHook = null
var _grace_t := -1.0


func _ready() -> void:
	GuardianInput.ensure_actions()
	_spawn = global_position
	cam_rig.top_level = true
	cam_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	spring_arm.add_excluded_object(get_rid())
	spring_arm.spring_length = tp_distance
	camera.fov = base_fov
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_build_rope_renderer()
	_apply_camera_blend(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =========================================================================
# Input
# =========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.45, 1.35)
	elif event.is_action_pressed("toggle_camera"):
		toggle_camera()
	elif event.is_action_pressed("hard_lock"):
		toggle_hard_lock()
	elif event.is_action_pressed("lock_next"):
		cycle_lock(1)
	elif event.is_action_pressed("lock_prev"):
		cycle_lock(-1)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func toggle_camera() -> void:
	first_person = not first_person
	camera_mode_changed.emit(first_person)


func _wish_dir() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v == Vector2.ZERO:
		return Vector3.ZERO
	var dir := Basis(Vector3.UP, _yaw) * Vector3(v.x, 0.0, v.y)
	return dir.normalized() * minf(v.length(), 1.0)


## Blickrichtung der Kamera (Fadenkreuz) – in beiden Kamera-Modi gueltig.
func aim_forward() -> Vector3:
	return -camera.global_basis.z


func _flat_forward() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3.FORWARD


## Mindestens ein gespanntes Seil (lockere Seile im Doppel-Tap-Fenster zaehlen nicht).
func any_hook_active() -> bool:
	for h in hooks:
		if h.active and not h.slack:
			return true
	return false


func hooks_out() -> int:
	var n := 0
	for h in hooks:
		if h.active:
			n += 1
	return n


# =========================================================================
# Physics
# =========================================================================
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_aim()
	var wish := _wish_dir()

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_t = jump_buffer_time
	if Input.is_action_just_pressed("reset"):
		_respawn()
		return

	_update_hard_lock()
	_handle_hook_input(delta)
	_handle_attack_input()
	_refresh_state()

	match state:
		State.NORMAL:
			_process_normal(wish, delta)
		State.HOOKED:
			_process_hooked(wish, delta)
		State.WALLRUN:
			_process_wallrun(wish, delta)

	if velocity.length() > terminal_speed:
		velocity = velocity.normalized() * terminal_speed

	move_and_slide()
	_post_move(wish, delta)

	if global_position.y < RESPAWN_Y:
		_respawn()


func _tick_timers(delta: float) -> void:
	_coyote_t -= delta
	_jump_buffer_t -= delta
	_wallrun_lockout -= delta


func _refresh_state() -> void:
	if any_hook_active():
		if state != State.HOOKED:
			_set_state(State.HOOKED)
	elif state == State.HOOKED:
		_set_state(State.NORMAL)


func _process_normal(wish: Vector3, delta: float) -> void:
	var on_floor := is_on_floor()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)

	if on_floor:
		var target_speed := sprint_speed if Input.is_action_pressed("sprint") else run_speed
		var speed := horiz.length()
		if wish != Vector3.ZERO:
			if speed > target_speed and horiz.dot(wish) > 0.0:
				var new_speed := move_toward(speed, target_speed, overspeed_decay * delta)
				horiz = horiz.normalized().slerp(wish.normalized(), 1.0 - exp(-8.0 * delta)) * new_speed
			else:
				horiz = horiz.move_toward(wish * target_speed, ground_accel * delta)
		else:
			horiz = horiz.lerp(Vector3.ZERO, 1.0 - exp(-ground_friction * delta))
	else:
		_air_control(wish, horiz, delta)
		horiz = Vector3(velocity.x, 0.0, velocity.z)
		horiz *= 1.0 - air_drag * delta

	velocity.x = horiz.x
	velocity.z = horiz.z

	if not on_floor:
		var g := gravity
		if velocity.y < 0.0:
			g *= fall_gravity_mult
		elif not Input.is_action_pressed("jump"):
			g *= 1.6
		velocity.y -= g * delta

	_try_ground_jump()


func _air_control(wish: Vector3, horiz: Vector3, delta: float) -> void:
	if wish == Vector3.ZERO:
		return
	var dir := wish.normalized()
	var cur := horiz.dot(dir)
	var add := clampf(air_control_speed - cur, 0.0, air_accel * delta)
	velocity += dir * add


func _try_ground_jump() -> void:
	if _jump_buffer_t > 0.0 and _coyote_t > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_t = 0.0
		_coyote_t = 0.0


func _process_wallrun(wish: Vector3, delta: float) -> void:
	_wallrun_t += delta
	var n := _wall_normal
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var along := horiz - n * horiz.dot(n)
	var speed := maxf(along.length(), wallrun_min_speed)
	if Input.is_action_pressed("sprint"):
		speed = move_toward(speed, maxf(speed, sprint_speed), 20.0 * delta)
	var dir := along.normalized() if along.length() > 0.01 else wish.normalized()
	var vy := velocity.y - gravity * wallrun_gravity_mult * delta
	vy = move_toward(vy, 0.0, 10.0 * delta)
	velocity = dir * speed + Vector3.UP * vy - n * 2.0

	if _jump_buffer_t > 0.0:
		_jump_buffer_t = 0.0
		velocity = dir * speed + n * wall_jump_push
		velocity.y = wall_jump_up
		_wallrun_lockout = 0.3
		_set_state(State.NORMAL)
		return
	if _wallrun_t > wallrun_max_time or wish.dot(n) > 0.5:
		_wallrun_lockout = 0.25
		_set_state(State.NORMAL)


func _post_move(wish: Vector3, delta: float) -> void:
	if is_on_floor():
		_coyote_t = coyote_time
		if state == State.WALLRUN:
			_set_state(State.NORMAL)

	match state:
		State.NORMAL:
			_check_wallrun_start(wish)
		State.WALLRUN:
			if is_on_wall():
				_wall_normal = get_wall_normal()
				_wall_lost_t = 0.0
			else:
				_wall_lost_t += delta
				if _wall_lost_t > 0.1:
					_set_state(State.NORMAL)


func _check_wallrun_start(wish: Vector3) -> void:
	if is_on_floor() or not is_on_wall() or _wallrun_lockout > 0.0 or wish == Vector3.ZERO:
		return
	var n := get_wall_normal()
	if absf(n.y) > 0.3:
		return
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var along := horiz - n * horiz.dot(n)
	if along.length() < wallrun_min_speed:
		return
	_wall_normal = n
	_wallrun_t = 0.0
	_wall_lost_t = 0.0
	velocity.y = maxf(velocity.y, 3.0)
	_set_state(State.WALLRUN)


# =========================================================================
# Seile
# =========================================================================
func _handle_hook_input(delta: float) -> void:
	if _grace_t >= 0.0:
		_grace_t += delta

	# RMB / LT: straffes Seil
	if Input.is_action_just_pressed("grapple"):
		if _grace_t >= 0.0 and rope_hooks_out() > 0:
			# Doppel-Tap: Seile wieder straff, zweiter Haken feuert (falls frei).
			_grace_t = -1.0
			for h in hooks:
				if h.active and not h.combat:
					h.slack = false
			if rope_hooks_out() == 1:
				_fire_second_hook()
		elif rope_hooks_out() == 0:
			_fire_primary_hook()
	elif Input.is_action_just_released("grapple"):
		if rope_hooks_out() > 0:
			for h in hooks:
				if h.active and not h.combat:
					h.slack = true
			_grace_t = 0.0

	if _grace_t > double_tap_window:
		_grace_t = -1.0
		_release_rope_hooks()


## LMB: ohne Hard-Lock normaler Slash. Mit Hard-Lock: Halten = Combat-Seil zum
## Lock-Punkt + heranziehen, Loslassen = Messer-Schlag im Anflug.
func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		if hard_lock != null and _fire_combat_hook():
			return
		knife.request_slash()
	elif Input.is_action_just_released("attack"):
		var ch := combat_hook()
		if ch:
			var lock := hard_lock if is_instance_valid(hard_lock) else null
			ch.release()
			knife.request_slash(lock)
			_refresh_state()


func rope_hooks_out() -> int:
	var n := 0
	for h in hooks:
		if h.active and not h.combat:
			n += 1
	return n


func combat_hook() -> GrappleHook:
	for h in hooks:
		if h.active and h.combat:
			return h
	return null


## Naechste freie Huefte, abwechselnd links/rechts.
func _take_free_hip() -> GrappleHook:
	if _next_hip == null:
		_next_hip = hook_left
	var first := _next_hip
	var second := hook_right if first == hook_left else hook_left
	for h in [first, second]:
		if not h.active:
			_next_hip = hook_right if h == hook_left else hook_left
			return h
	return null


func _fire_primary_hook() -> void:
	if aim_kind == AimKind.NONE:
		return
	var h := _take_free_hip()
	if h == null:
		return
	var tgt := aim_target if aim_kind == AimKind.ENEMY else null
	h.attach(aim_point, aim_normal, tgt, global_position)
	_primary = h
	if is_on_floor():
		velocity.y = maxf(velocity.y, 4.0)
	_refresh_state()


func _fire_second_hook() -> void:
	if aim_kind == AimKind.NONE or _primary == null or not _primary.active \
			or aim_point.distance_to(_primary.anchor_world()) < dual_min_separation:
		return  # kein zweites Ziel -> erster Haken bleibt einfach straff
	var h := _take_free_hip()
	if h == null:
		return
	var tgt := aim_target if aim_kind == AimKind.ENEMY else null
	h.attach(aim_point, aim_normal, tgt, global_position)
	_refresh_state()


## Combat-Seil zum Hard-Lock-Punkt. Sind beide Hueften belegt, wird das aeltere
## RMB-Seil dafuer eingeholt.
func _fire_combat_hook() -> bool:
	if not is_instance_valid(hard_lock) or global_position.distance_to(_lock_point_of(hard_lock)) > grapple_range:
		return false
	var h := _take_free_hip()
	if h == null:
		h = hook_left if _primary == hook_right else hook_right
		h.release()
	var p := _lock_point_of(hard_lock)
	h.attach(p, Vector3.ZERO, hard_lock, global_position, true)
	velocity += (p - global_position).normalized() * combat_pull_impulse
	if is_on_floor():
		velocity.y = maxf(velocity.y, 6.0)
	_refresh_state()
	return true


## W am Seil -> Turbo-Einzug.
func is_turbo() -> bool:
	return Input.is_action_pressed("move_forward") and any_hook_active()


## S am Seil (ohne W) -> Bremse.
func is_braking() -> bool:
	return Input.is_action_pressed("move_back") and not Input.is_action_pressed("move_forward") \
			and any_hook_active()


## Aktuelle Einzugsgeschwindigkeit der Winde (m/s) fuer ein Seil.
func winch_speed(h: GrappleHook = null) -> float:
	if is_braking():
		return reel_speed * reel_brake_mult
	var base := reel_speed * (combat_reel_mult if h != null and h.combat else reel_base_mult)
	return base * (reel_turbo_mult if is_turbo() else 1.0)


func _process_hooked(wish: Vector3, delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	for h in hooks:
		if h.active:
			h.update_bends(space, global_position, velocity, ex, grapple_mask)

	velocity.y -= gravity * delta
	_rope_steer(delta)
	if is_braking():
		velocity *= exp(-brake_damping * delta)
	if is_on_floor():
		_try_ground_jump()
	_solve_ropes(delta)


## Straffe Seile mit Winde. Alle Seile werden aus derselben Ausgangs-
## Geschwindigkeit geloest und summiert -> zwei Seile kaempfen nicht gegeneinander.
func _solve_ropes(delta: float) -> void:
	var v0 := velocity
	var dv := Vector3.ZERO
	for h in hooks:
		if not h.active or h.slack:
			continue
		var speed := winch_speed(h)
		var to := h.pivot() - global_position
		var dist := to.length()
		if dist < 0.01:
			continue
		var dir := to / dist
		# Straff: das Seil laesst nie nach.
		h.rope_length = minf(h.rope_length, dist)
		# Winde: Laenge schrumpft gleichmaessig. Kommt der Spieler nicht hinterher
		# (z. B. zweites Seil haelt dagegen), laeuft sie nicht weiter davon -> kein Zerren.
		var max_gap := maxf(speed / rope_response, 0.05)
		if h.rope_length > hang_length:
			h.rope_length = maxf(h.rope_length - speed * delta, maxf(dist - max_gap, hang_length))
		h.rope_length = clampf(h.rope_length, rope_min_length, grapple_range * lock_keep_range_mult)
		var gap := dist - h.rope_length
		if gap <= 0.0 and v0.dot(dir) >= 0.0:
			continue
		var desired := minf(gap * rope_response, maxf(speed, 4.0))
		var radial_in := v0.dot(dir)
		if radial_in < desired:
			dv += dir * (desired - radial_in)
	velocity = v0 + dv


## A / D am Seil: seitlich quer zum Seil ausweichen / schwingen.
## (W / S bedienen die Winde und steuern hier nicht.)
func _rope_steer(delta: float) -> void:
	var side := Input.get_axis("move_left", "move_right")
	if absf(side) < 0.01:
		return
	var lateral := Basis(Vector3.UP, _yaw) * Vector3.RIGHT * side
	var axis := Vector3.ZERO
	for h in hooks:
		if h.active and not h.slack:
			axis += (h.pivot() - global_position).normalized()
	if axis.length() > 0.01:
		axis = axis.normalized()
		lateral -= axis * lateral.dot(axis)
	velocity += lateral * rope_steer_accel * delta


func _release_rope_hooks() -> void:
	for h in hooks:
		if not h.combat:
			h.release()
	_primary = null


func _release_all_hooks() -> void:
	for h in hooks:
		h.release()
	_grace_t = -1.0
	_primary = null


# =========================================================================
# Auto-Aim (Kegel um das Fadenkreuz)
# =========================================================================
func _update_aim() -> void:
	aim_kind = AimKind.NONE
	aim_target = null
	aim_assisted = false
	var cam_pos := camera.global_position
	var fwd := aim_forward()
	# Startpunkt auf Spielerhoehe entlang des Kamera-Strahls -> in Third-Person
	# wird nichts zwischen Kamera und Spieler getroffen. In First-Person ~ Kamera.
	var start := cam_pos + fwd * maxf((global_position - cam_pos).dot(fwd), 0.0)
	var space := get_world_3d().direct_space_state

	# 1) Target-Lock (Tab): Gegner im Kegel, Fang-Radius = max(assist_radius, Distanz * tan(Kegel))
	lock_target = _find_lock_target(space, start, fwd)

	# 2) Exakter Strahl unterm Fadenkreuz
	var hit := _ray(space, start, start + fwd * grapple_range)
	if _accept_aim_hit(hit):
		_set_aim_from_hit(hit, false)
		return

	# 3) Strahlenkegel um das Fadenkreuz (innerer Ring zuerst)
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	for ring: float in [0.5, 1.0]:
		var a := deg_to_rad(assist_cone_deg) * ring
		var best := {}
		var best_d := INF
		for k in assist_rays_per_ring:
			var phi := TAU * float(k) / float(assist_rays_per_ring)
			var d := (fwd * cos(a) + (right * cos(phi) + up * sin(phi)) * sin(a)).normalized()
			var h := _ray(space, start, start + d * grapple_range)
			if _accept_aim_hit(h):
				var dd := global_position.distance_to(h.position)
				if dd < best_d:
					best_d = dd
					best = h
		if not best.is_empty():
			_set_aim_from_hit(best, true)
			return


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, grapple_mask, [get_rid()])
	return space.intersect_ray(q)


func _accept_aim_hit(hit: Dictionary) -> bool:
	return not hit.is_empty() and global_position.distance_to(hit.position) <= grapple_range


func _set_aim_from_hit(hit: Dictionary, assisted: bool) -> void:
	var col: Object = hit.collider
	if col is Node3D and (col as Node3D).is_in_group("lock_target") and _is_lockable(col):
		aim_kind = AimKind.ENEMY
		aim_target = col as Node3D
		aim_point = _lock_point_of(aim_target)
		aim_normal = Vector3.ZERO
	else:
		aim_kind = AimKind.POINT
		aim_normal = hit.normal
		aim_point = (hit.position as Vector3) + aim_normal * 0.05
	aim_assisted = assisted


func _find_lock_target(space: PhysicsDirectSpaceState3D, start: Vector3, fwd: Vector3) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var tan_cone := tan(deg_to_rad(assist_cone_deg))
	for n in get_tree().get_nodes_in_group("lock_target"):
		var t := n as Node3D
		if t == null or not _is_lockable(t):
			continue
		var p := _lock_point_of(t)
		if global_position.distance_to(p) > grapple_range:
			continue
		var v := p - start
		var along := v.dot(fwd)
		if along <= 0.0:
			continue
		var perp := (v - fwd * along).length()
		var allowed := maxf(assist_radius, along * tan_cone)
		if perp > allowed:
			continue
		var score := perp / allowed + along * 0.002
		if score >= best_score:
			continue
		if not _has_line_of_sight(space, start, t, p):
			continue
		best = t
		best_score = score
	return best


func _lock_point_of(t: Node3D) -> Vector3:
	return t.get_lock_point() if t.has_method("get_lock_point") else t.global_position


func _is_lockable(t: Object) -> bool:
	return not t.has_method("is_lockable") or t.is_lockable()


# =========================================================================
# Hard-Lock & Ziel-Wechsel
# =========================================================================
## Mausrad-Klick / R3: Ziel unterm Fadenkreuz einrasten bzw. Lock loesen.
func toggle_hard_lock() -> void:
	if hard_lock != null:
		hard_lock = null
	elif lock_target != null:
		hard_lock = lock_target


## Mausrad: durch alle anvisierbaren Ziele/Trefferpunkte schalten.
## Ohne Lock rastet der erste Scroll das beste Ziel ein.
func cycle_lock(step: int) -> void:
	var list := lock_candidates()
	if list.is_empty():
		return
	var i := list.find(hard_lock)
	if i == -1:
		hard_lock = list[0] if lock_target == null or not list.has(lock_target) else lock_target
		return
	hard_lock = list[posmod(i + step, list.size())]


## Alle anvisierbaren Ziele in Reichweite mit Sichtlinie, sortiert nach Winkel
## zum Fadenkreuz (naechstes zuerst).
func lock_candidates() -> Array[Node3D]:
	var cam_pos := camera.global_position
	var fwd := aim_forward()
	var start := cam_pos + fwd * maxf((global_position - cam_pos).dot(fwd), 0.0)
	var space := get_world_3d().direct_space_state
	var scored: Array = []
	for n in get_tree().get_nodes_in_group("lock_target"):
		var t := n as Node3D
		if t == null or not _is_lockable(t):
			continue
		var p := _lock_point_of(t)
		if global_position.distance_to(p) > grapple_range:
			continue
		var v := p - start
		if v.dot(fwd) <= 0.0:
			continue
		if not _has_line_of_sight(space, start, t, p):
			continue
		scored.append([fwd.angle_to(v.normalized()), t])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array[Node3D] = []
	for e in scored:
		out.append(e[1])
	return out


func _update_hard_lock() -> void:
	if hard_lock == null:
		return
	if not is_instance_valid(hard_lock) or not _is_lockable(hard_lock) \
			or global_position.distance_to(_lock_point_of(hard_lock)) > grapple_range * lock_keep_range_mult:
		hard_lock = null
		var ch := combat_hook()
		if ch:
			ch.release()


func _has_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, t: Node3D, p: Vector3) -> bool:
	var hit := _ray(space, from, p)
	if hit.is_empty():
		return true
	if (hit.position as Vector3).distance_to(p) <= 0.8:
		return true
	# Ziel ist selbst der Koerper (z. B. Dummy). Lock-Punkte auf einem grossen Koerper
	# zaehlen nur, wenn der Strahl nahe am Punkt auftrifft (Nacken von vorne = verdeckt).
	return hit.collider == t


## Wer bekommt den Schaden? Ziel selbst (take_hit) oder Eltern eines LockPoints.
static func hit_receiver_of(t: Node) -> Node:
	if t == null:
		return null
	if t.has_method("take_hit"):
		return t
	if t.has_method("get_hit_receiver"):
		return t.get_hit_receiver()
	return null


# =========================================================================
# State / Respawn
# =========================================================================
func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


func _respawn() -> void:
	_release_all_hooks()
	hard_lock = null
	global_position = _spawn
	velocity = Vector3.ZERO
	_set_state(State.NORMAL)
	reset_physics_interpolation()


# =========================================================================
# Kamera & Visuals (pro Frame, interpoliert)
# =========================================================================
func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_yaw -= look.x * stick_sensitivity * delta
		_pitch = clampf(_pitch - look.y * stick_sensitivity * delta, -1.45, 1.35)

	_cam_blend = move_toward(_cam_blend, 1.0 if first_person else 0.0,
			delta / maxf(camera_switch_time, 0.01))
	var b := smoothstep(0.0, 1.0, _cam_blend)
	_apply_camera_blend(b)

	var t := get_global_transform_interpolated()
	cam_rig.global_position = t.origin + Vector3.UP * lerpf(tp_height, fp_height, b)
	cam_rig.rotation = Vector3(0.0, _yaw, 0.0)
	cam_pitch.rotation = Vector3(_pitch, 0.0, 0.0)

	var speed := velocity.length()
	var k := clampf(speed / fov_speed_ref, 0.0, 1.0)
	var target_fov := lerpf(lerpf(base_fov, base_fov_fp, b), lerpf(max_fov, max_fov_fp, b), k)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.0 * delta))

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var target_yaw := visual.rotation.y
	if b > 0.5:
		target_yaw = _yaw
	elif horiz.length() > 1.0:
		target_yaw = atan2(-horiz.x, -horiz.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))

	_animate_knife()
	_update_ropes(t.origin, b)


func _apply_camera_blend(b: float) -> void:
	spring_arm.spring_length = lerpf(tp_distance, 0.0, b)
	spring_arm.position = Vector3(lerpf(tp_shoulder, 0.0, b), 0.0, 0.0)
	var fp := b > 0.6
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if fp \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in visual.get_children():
		if c is GeometryInstance3D and c != body_mesh:
			(c as GeometryInstance3D).visible = not fp
	knife_tp.visible = not fp
	knife_fp.visible = fp


func _animate_knife() -> void:
	var p := knife.swing_progress
	var side := 1.0 if knife.combo_index % 2 == 0 else -1.0
	var angle := 0.0
	if p >= 0.0:
		angle = lerpf(-1.3, 1.3, smoothstep(0.0, 0.55, p)) * side
	knife_tp.rotation = Vector3(0.0, angle, 0.0)
	knife_fp.rotation = Vector3(0.0, angle * 0.8, -angle * 0.4)


# --- Seil-Rendering: alle Segmente aller Seile in EINEM MultiMesh ----------
func _build_rope_renderer() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	_rope_mm = MultiMesh.new()
	_rope_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rope_mm.use_colors = true
	_rope_mm.mesh = mesh
	_rope_mm.instance_count = MAX_ROPE_SEGMENTS
	_rope_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Ropes"
	mmi.multimesh = _rope_mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mmi)


func _update_ropes(origin: Vector3, b: float) -> void:
	var right := cam_rig.global_basis.x
	var hip_up := lerpf(-0.15, -0.35, b)  # Werfer sitzen an der Huefte
	var n := 0
	for h in hooks:
		if not h.active:
			continue
		var side := -0.38 if h.kind == GrappleHook.Kind.HIP_LEFT else 0.38
		var color := Color(0.55, 0.95, 1.0)
		if h.combat:
			color = Color(1.0, 0.45, 0.25)
		elif h.slack:
			color = Color(0.55, 0.95, 1.0) * 0.5
		elif is_turbo():
			color = Color(1.0, 0.8, 0.3)
		var hand := origin + Vector3.UP * hip_up + right * side
		var pts := h.render_points(hand)
		for i in pts.size() - 1:
			if n >= MAX_ROPE_SEGMENTS:
				break
			var a := pts[i]
			var seg := pts[i + 1] - a
			var length := seg.length()
			if length < 0.01:
				continue
			var y_axis := seg / length
			var x_axis := y_axis.cross(Vector3.UP)
			if x_axis.length() < 0.01:
				x_axis = y_axis.cross(Vector3.RIGHT)
			x_axis = x_axis.normalized()
			var z_axis := x_axis.cross(y_axis)
			_rope_mm.set_instance_transform(n, Transform3D(Basis(x_axis, y_axis * length, z_axis), a + seg * 0.5))
			_rope_mm.set_instance_color(n, color)
			n += 1
	_rope_mm.visible_instance_count = n
