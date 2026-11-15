class_name GuardianController
extends CharacterBody3D
## Guardian – High-Speed-Controller.
##
## Movement: Laufen / Sprint / Air-Control / Dash / Wall-Run.
## Seile:    Q/E = Momentum-Swing links/rechts (Dying-Light-Style),
##           RMB = Target-Lock + Combat-Grapple (Sturzangriff auf Gegner).
##           Seile wickeln sich um Geometrie (Bending), loesen sich nie von
##           selbst und schiessen am Ankerpunkt im Bogen drueber (Rebound).
## Kampf:    LMB = Jagdmesser (siehe KnifeCombat).
## Kamera:   P = Third-/First-Person, nahtlos ueberblendet.
##
## Physik in _physics_process, Kamera/Visuals in _process ueber die
## interpolierte Transform (Physics-Interpolation aktiv) -> keine Mikroruckler.

signal state_changed(new_state: State)
signal camera_mode_changed(first_person: bool)

enum State { NORMAL, DASH, HOOKED, WALLRUN }
enum AimKind { NONE, POINT, ENEMY }

# --- Ground ---------------------------------------------------------------
@export_group("Ground")
@export var run_speed := 9.0
@export var sprint_speed := 17.0
@export var ground_accel := 80.0
@export var ground_friction := 10.0
## Wie schnell Ueber-Speed (aus Dash/Seil) am Boden abgebaut wird.
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

# --- Dash -----------------------------------------------------------------
@export_group("Dash")
@export var dash_speed := 32.0
@export var dash_time := 0.15
@export var dash_cooldown := 0.2
@export var dash_charges_max := 2
@export var dash_exit_keep := 0.65

# --- Seile allgemein ------------------------------------------------------
@export_group("Rope")
@export_flags_3d_physics var grapple_mask := 1
@export var rope_min_length := 1.5
@export var rope_stiffness := 8.0
@export var hook_steer_accel := 18.0
## Am Ankerpunkt: Abstand, ab dem der Rebound (Bogen drueber hinaus) ausloest.
@export var rebound_radius := 3.5
@export var rebound_up := 9.0
@export var rebound_rope_length := 7.0

# --- Combat-Grapple (RMB) -------------------------------------------------
@export_group("Combat Grapple")
@export var grapple_range := 70.0
@export var combat_pull_accel := 140.0
@export var combat_pull_impulse := 12.0
@export var combat_pull_max_speed := 48.0
@export var combat_reel_accel := 45.0
@export var dive_height := 4.0
@export var dive_speed := 42.0
@export var dive_hit_radius := 2.4
@export var dive_bounce := 13.0

# --- Momentum-Swing (Q/E) -------------------------------------------------
@export_group("Momentum Swing")
@export var swing_range := 45.0
## Strahlenfaecher (nur beim Tastendruck): Seitenwinkel von..bis, Hoehenwinkel.
@export var swing_side_min := 5.0
@export var swing_side_max := 65.0
@export var swing_fan_steps := 12
@export var swing_elevations := PackedFloat32Array([25.0, 35.0, 45.0, 55.0, 65.0, 78.0])
@export var swing_forward_accel := 14.0
## Ideale Distanz des Ankers vor dem Spieler (horizontal) und Minimum.
@export var swing_ideal_ahead := 14.0
@export var swing_min_ahead := 3.0
## Hoehen-Regler: Schwerkraft-Ausgleich (0..1), Feder und Daempfung.
@export var swing_gravity_comp := 1.0
@export var swing_height_comp := 12.0
@export var swing_height_damp := 3.0
@export var swing_reel_speed := 10.0
@export var swing_reel_accel := 25.0

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
var dash_charges := 2
var first_person := false

## Auto-Aim-Ergebnis (HUD + Combat-Grapple).
var aim_kind: AimKind = AimKind.NONE
var aim_point := Vector3.ZERO
var aim_target: Node3D = null
## true, wenn der Punkt per Assist eingerastet ist (nicht exakt unterm Fadenkreuz).
var aim_assisted := false

var hook_left := GrappleHook.new(GrappleHook.Kind.SWING_LEFT)
var hook_right := GrappleHook.new(GrappleHook.Kind.SWING_RIGHT)
var hook_combat := GrappleHook.new(GrappleHook.Kind.COMBAT)
var hooks: Array[GrappleHook] = [hook_left, hook_right, hook_combat]

var _yaw := 0.0
var _pitch := -0.15
var _cam_blend := 0.0
var _coyote_t := 0.0
var _jump_buffer_t := 0.0
var _dash_t := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_speed_now := 0.0
var _wall_normal := Vector3.ZERO
var _wallrun_t := 0.0
var _wall_lost_t := 0.0
var _wallrun_lockout := 0.0
var _spawn := Vector3.ZERO
var _rope_mm: MultiMesh
var _last_swing_height := 0.0
var _last_swing_release_ms := -100000


func _ready() -> void:
	GuardianInput.ensure_actions()
	_spawn = global_position
	dash_charges = dash_charges_max
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


func any_hook_active() -> bool:
	return hook_left.active or hook_right.active or hook_combat.active


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

	_handle_hook_input()
	if Input.is_action_just_pressed("attack"):
		knife.request_slash()
	if Input.is_action_just_pressed("dash"):
		_try_dash(wish)
	_refresh_state()

	match state:
		State.NORMAL:
			_process_normal(wish, delta)
		State.DASH:
			_process_dash(delta)
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
	_dash_cd -= delta
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


func _process_dash(delta: float) -> void:
	_dash_t -= delta
	velocity = _dash_dir * _dash_speed_now
	if _jump_buffer_t > 0.0 and (is_on_floor() or _coyote_t > 0.0):
		velocity.y = jump_velocity
		_jump_buffer_t = 0.0
		_coyote_t = 0.0
		_set_state(State.NORMAL)
		return
	if _dash_t <= 0.0:
		velocity = _dash_dir * maxf(_dash_speed_now * dash_exit_keep, run_speed)
		_set_state(State.NORMAL)


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
		dash_charges = maxi(dash_charges, 1)
		_set_state(State.NORMAL)
		return
	if _wallrun_t > wallrun_max_time or wish.dot(n) > 0.5:
		_wallrun_lockout = 0.25
		_set_state(State.NORMAL)


func _post_move(wish: Vector3, delta: float) -> void:
	if is_on_floor():
		_coyote_t = coyote_time
		dash_charges = dash_charges_max
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
		State.HOOKED:
			_check_dive_contact()


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


func _try_dash(wish: Vector3) -> void:
	if _dash_cd > 0.0 or dash_charges <= 0:
		return
	var dir := wish.normalized()
	if dir == Vector3.ZERO:
		dir = aim_forward()
		if is_on_floor():
			dir.y = 0.0
	dir = dir.normalized()
	dash_charges -= 1
	_dash_cd = dash_cooldown

	if any_hook_active():
		# Gas-Stoss am Seil: Impuls, Seile bleiben aktiv.
		velocity += dir * dash_speed * 0.6
		return

	var carry := maxf(velocity.dot(dir), 0.0)
	_dash_dir = dir
	_dash_speed_now = maxf(dash_speed, carry + dash_speed * 0.35)
	_dash_t = dash_time
	_set_state(State.DASH)


# =========================================================================
# Seile
# =========================================================================
func _handle_hook_input() -> void:
	if Input.is_action_just_pressed("hook_combat"):
		_fire_combat_hook()
	elif Input.is_action_just_released("hook_combat"):
		hook_combat.release()

	if Input.is_action_just_pressed("hook_left"):
		_fire_swing_hook(hook_left, 1.0)
	elif Input.is_action_just_released("hook_left"):
		_release_swing(hook_left)

	if Input.is_action_just_pressed("hook_right"):
		_fire_swing_hook(hook_right, -1.0)
	elif Input.is_action_just_released("hook_right"):
		_release_swing(hook_right)


func _release_swing(h: GrappleHook) -> void:
	if h.active:
		_last_swing_height = h.attach_height
		_last_swing_release_ms = Time.get_ticks_msec()
	h.release()


func _fire_combat_hook() -> void:
	if aim_kind == AimKind.NONE:
		return
	var tgt := aim_target if aim_kind == AimKind.ENEMY else null
	hook_combat.attach(aim_point, tgt, global_position)
	var dir := (aim_point - global_position).normalized()
	velocity += dir * combat_pull_impulse
	if is_on_floor():
		velocity.y = maxf(velocity.y, 6.0)
	dash_charges = maxi(dash_charges, 1)
	_refresh_state()


## side: +1 = links (Q), -1 = rechts (E).
func _fire_swing_hook(h: GrappleHook, side: float) -> void:
	var hit := _find_swing_anchor(side)
	if hit.is_empty():
		return
	h.attach(hit.position, null, global_position)
	if is_on_floor():
		velocity.y = maxf(velocity.y, 6.0)
		h.attach_height = global_position.y + 3.0
	else:
		# Fliessender Wechsel Q <-> E: Zielhoehe vom vorherigen Swing uebernehmen.
		var other := hook_right if h == hook_left else hook_left
		if other.active:
			h.attach_height = other.attach_height
		elif Time.get_ticks_msec() - _last_swing_release_ms < 700:
			h.attach_height = _last_swing_height
	_refresh_state()


func _find_swing_anchor(side: float) -> Dictionary:
	# Faecher aus Strahlen schraeg nach vorne-oben auf der jeweiligen Seite.
	# Bewertet wird, wie gut der Punkt einen Vorwaerts-Bogen ermoeglicht.
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * fp_height
	var fwd := _flat_forward()
	var best := {}
	var best_score := -INF
	for elev in swing_elevations:
		for step in swing_fan_steps + 1:
			var side_deg := lerpf(swing_side_min, swing_side_max, float(step) / float(swing_fan_steps))
			var yaw: float = _yaw + side * deg_to_rad(side_deg)
			var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(elev)) * Vector3.FORWARD
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * swing_range,
					grapple_mask, [get_rid()])
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var rel: Vector3 = (hit.position as Vector3) - origin
			var ahead := rel.dot(fwd)
			if rel.y < 1.5 or ahead < swing_min_ahead:
				continue
			var score := -absf(ahead - swing_ideal_ahead) + minf(rel.y, 15.0) * 0.3
			if score > best_score:
				best_score = score
				best = hit
	if not best.is_empty():
		best.position = (best.position as Vector3) + (best.normal as Vector3) * 0.05
	return best


func _process_hooked(wish: Vector3, delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	for h in hooks:
		if h.active:
			h.phase_time += delta
			h.update_bends(space, global_position, velocity, ex, grapple_mask)

	var diving := hook_combat.active and hook_combat.phase == GrappleHook.Phase.DIVE
	if not diving:
		velocity.y -= gravity * delta
		velocity += wish * hook_steer_accel * delta
		if is_on_floor():
			_try_ground_jump()

	if not diving:
		_swing_height_assist(delta)
	for h in hooks:
		if h.active:
			_apply_hook(h, delta)


func _apply_hook(h: GrappleHook, delta: float) -> void:
	var pos := global_position
	var to := h.pivot() - pos
	var dist := to.length()
	if dist < 0.01:
		return
	var dir := to / dist

	if h.kind == GrappleHook.Kind.COMBAT:
		_combat_forces(h, dir, dist, delta)
		if h.phase == GrappleHook.Phase.DIVE:
			return
	else:
		_swing_forces(h, dir, dist, delta)

	# Seil-Constraint: nach aussen gerichtete Geschwindigkeit entfernen -> Swing.
	h.rope_length = clampf(h.rope_length, rope_min_length, grapple_range)
	if dist >= h.rope_length:
		var outward := -velocity.dot(dir)
		if outward > 0.0:
			velocity += dir * outward
		velocity += dir * minf(dist - h.rope_length, 2.0) * rope_stiffness * delta


func _combat_forces(h: GrappleHook, dir: Vector3, dist: float, delta: float) -> void:
	match h.phase:
		GrappleHook.Phase.PULL:
			var goal := h.pivot()
			if is_instance_valid(h.target) and not h.has_bends():
				goal = _lock_point_of(h.target) + Vector3.UP * dive_height
			var to_goal := goal - global_position
			var gdist := to_goal.length()
			var gdir := to_goal / maxf(gdist, 0.001)
			if velocity.dot(gdir) < combat_pull_max_speed:
				velocity += gdir * combat_pull_accel * delta
			h.rope_length = minf(h.rope_length, dist)
			if not h.has_bends() and gdist < rebound_radius:
				if is_instance_valid(h.target):
					h.set_phase(GrappleHook.Phase.DIVE)
				else:
					_rebound(h, dist)
		GrappleHook.Phase.DIVE:
			if not is_instance_valid(h.target) or h.phase_time > 0.6:
				_end_dive(h, null)
				return
			var to_t := _lock_point_of(h.target) - global_position
			velocity = to_t.normalized() * dive_speed
			if to_t.length() < dive_hit_radius:
				_end_dive(h, h.target)
		GrappleHook.Phase.TETHER:
			if Input.is_action_pressed("jump"):
				h.rope_length = maxf(h.rope_length - swing_reel_speed * delta, rope_min_length)
				velocity += dir * combat_reel_accel * delta


func _rebound(h: GrappleHook, dist: float) -> void:
	# Am Ankerpunkt nicht stoppen: im Bogen drueber hinaus, Seil bleibt dran.
	h.set_phase(GrappleHook.Phase.TETHER)
	velocity += Vector3.UP * rebound_up
	h.rope_length = maxf(dist, rebound_rope_length)


func _end_dive(h: GrappleHook, hit_target: Node3D) -> void:
	if hit_target:
		knife.strike(hit_target, 1.0)
		var away := Vector3(velocity.x, 0.0, velocity.z).normalized() * 4.0
		velocity = away + Vector3.UP * dive_bounce
	h.set_phase(GrappleHook.Phase.TETHER)
	h.rope_length = maxf(global_position.distance_to(h.pivot()), rebound_rope_length)


func _check_dive_contact() -> void:
	if not (hook_combat.active and hook_combat.phase == GrappleHook.Phase.DIVE):
		return
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == hook_combat.target:
			_end_dive(hook_combat, hook_combat.target)
			return


func _swing_forces(h: GrappleHook, dir: Vector3, dist: float, delta: float) -> void:
	var y := global_position.y
	if h.attach_height - y > -0.5:
		h.rope_length = minf(h.rope_length, dist)  # Seil bleibt straff
	# Leertaste: aktiv einholen / Hoehe gewinnen (hebt die Zielhoehe an).
	if Input.is_action_pressed("jump") and not is_on_floor():
		h.rope_length -= swing_reel_speed * delta
		velocity += dir * swing_reel_accel * delta
		h.attach_height = maxf(h.attach_height, y)
	h.rope_length = maxf(h.rope_length, rope_min_length)
	# Momentum: tangential in Blickrichtung beschleunigen.
	var fwd := _flat_forward()
	var tangent := fwd - dir * fwd.dot(dir)
	if tangent.length() > 0.1:
		velocity += tangent.normalized() * swing_forward_accel * delta


## Hoehen-Regler fuer Q/E: haelt den Swing auf (nahezu) konstanter Hoehe.
## Wirkt einmal fuer alle aktiven Swing-Seile zusammen.
func _swing_height_assist(delta: float) -> void:
	var target_h := -INF
	for h in [hook_left, hook_right]:
		if h.active:
			target_h = maxf(target_h, h.attach_height)
	if target_h == -INF:
		return
	var drop := target_h - global_position.y
	if drop < -0.5:
		return  # ueber der Zielhoehe: freier Bogen nach oben
	var up := gravity * swing_gravity_comp + drop * swing_height_comp \
			- minf(velocity.y, 0.0) * swing_height_damp
	velocity.y += clampf(up, 0.0, gravity * 2.0) * delta


func _release_all_hooks() -> void:
	for h in hooks:
		h.release()


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

	# 1) Gegner im Kegel (Fang-Radius = max(assist_radius, Distanz * tan(Kegel)))
	var enemy := _find_lock_target(space, start, fwd)
	if enemy:
		aim_kind = AimKind.ENEMY
		aim_target = enemy
		aim_point = _lock_point_of(enemy)
		aim_assisted = true
		return

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
	else:
		aim_kind = AimKind.POINT
		aim_point = (hit.position as Vector3) + (hit.normal as Vector3) * 0.05
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
		# Sichtlinie pruefen
		var hit := _ray(space, start, p)
		if not hit.is_empty() and hit.collider != t \
				and (hit.position as Vector3).distance_to(p) > 0.8:
			continue
		best = t
		best_score = score
	return best


func _lock_point_of(t: Node3D) -> Vector3:
	return t.get_lock_point() if t.has_method("get_lock_point") else t.global_position


func _is_lockable(t: Object) -> bool:
	return not t.has_method("is_lockable") or t.is_lockable()


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
	var hand_up := lerpf(0.25, fp_height - 0.35, b)
	var n := 0
	for h in hooks:
		if not h.active:
			continue
		var side := 0.0
		var color := Color(1.0, 0.55, 0.3)
		if h.kind == GrappleHook.Kind.SWING_LEFT:
			side = -0.35
			color = Color(0.55, 0.95, 1.0)
		elif h.kind == GrappleHook.Kind.SWING_RIGHT:
			side = 0.35
			color = Color(0.55, 0.95, 1.0)
		var hand := origin + Vector3.UP * hand_up + right * side
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
