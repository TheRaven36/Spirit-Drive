class_name GuardianController
extends CharacterBody3D
## Guardian – High-Speed-Controller (Attack-on-Titan-Style).
##
## Laufen / Sprinten / Air-Control / Dash / Grapple-Swing / Wall-Run.
## Physik laeuft in _physics_process, Kamera wird in _process ueber die
## interpolierte Transform nachgefuehrt (Physics-Interpolation ist im Projekt
## aktiv) -> keine Mikroruckler bei hohen Bildraten.

signal state_changed(new_state: State)

enum State { NORMAL, DASH, GRAPPLE, WALLRUN }

# --- Ground ---------------------------------------------------------------
@export_group("Ground")
@export var run_speed := 9.0
@export var sprint_speed := 17.0
@export var ground_accel := 80.0
@export var ground_friction := 10.0
## Wie schnell Ueber-Speed (aus Dash/Grapple) am Boden abgebaut wird.
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
## Anteil der Dash-Geschwindigkeit, der nach dem Dash erhalten bleibt.
@export var dash_exit_keep := 0.65

# --- Grapple --------------------------------------------------------------
@export_group("Grapple")
@export var grapple_range := 70.0
@export var grapple_reel_accel := 30.0
@export var grapple_boost_accel := 75.0
@export var grapple_steer_accel := 20.0
@export var grapple_min_length := 2.5
@export_flags_3d_physics var grapple_mask := 1

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
@export var camera_height := 0.7
@export var base_fov := 75.0
@export var max_fov := 102.0
@export var fov_speed_ref := 45.0

const RESPAWN_Y := -40.0

@onready var cam_rig: Node3D = $CameraRig
@onready var cam_pitch: Node3D = $CameraRig/Pitch
@onready var spring_arm: SpringArm3D = $CameraRig/Pitch/SpringArm3D
@onready var camera: Camera3D = $CameraRig/Pitch/SpringArm3D/Camera3D
@onready var visual: Node3D = $Visual

var state: State = State.NORMAL
var dash_charges := 2

## Fuer HUD/Debug: zeigt der Crosshair auf einen gueltigen Grapple-Punkt?
var aim_valid := false
var aim_point := Vector3.ZERO

var _yaw := 0.0
var _pitch := -0.15
var _coyote_t := 0.0
var _jump_buffer_t := 0.0
var _dash_t := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_speed_now := 0.0
var _anchor := Vector3.ZERO
var _rope_len := 0.0
var _wall_normal := Vector3.ZERO
var _wallrun_t := 0.0
var _wall_lost_t := 0.0
var _wallrun_lockout := 0.0
var _spawn := Vector3.ZERO
var _rope: MeshInstance3D


func _ready() -> void:
	GuardianInput.ensure_actions()
	_spawn = global_position
	dash_charges = dash_charges_max
	# Kamera-Rig von der Body-Transform loesen und selbst im _process fuehren.
	cam_rig.top_level = true
	cam_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	spring_arm.add_excluded_object(get_rid())
	camera.fov = base_fov
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_build_rope()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Input ----------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.45, 1.2)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _wish_dir() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v == Vector2.ZERO:
		return Vector3.ZERO
	return Basis(Vector3.UP, _yaw) * Vector3(v.x, 0.0, v.y).normalized()


func _cam_forward() -> Vector3:
	return -camera.global_basis.z


# --- Physics --------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_aim()
	var wish := _wish_dir()

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_t = jump_buffer_time
	if Input.is_action_just_pressed("reset"):
		_respawn()
		return
	if Input.is_action_just_pressed("grapple"):
		_try_grapple()
	elif Input.is_action_just_released("grapple") and state == State.GRAPPLE:
		_set_state(State.NORMAL)
	if Input.is_action_just_pressed("dash"):
		_try_dash(wish)

	match state:
		State.NORMAL:
			_process_normal(wish, delta)
		State.DASH:
			_process_dash(delta)
		State.GRAPPLE:
			_process_grapple(wish, delta)
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


func _process_normal(wish: Vector3, delta: float) -> void:
	var on_floor := is_on_floor()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)

	if on_floor:
		var target_speed := sprint_speed if Input.is_action_pressed("sprint") else run_speed
		var speed := horiz.length()
		if wish != Vector3.ZERO:
			if speed > target_speed and horiz.dot(wish) > 0.0:
				# Momentum aus Dash/Grapple erhalten, nur sanft abbauen + lenken.
				var new_speed := move_toward(speed, target_speed, overspeed_decay * delta)
				horiz = horiz.normalized().slerp(wish, 1.0 - exp(-8.0 * delta)) * new_speed
			else:
				horiz = horiz.move_toward(wish * target_speed, ground_accel * delta)
		else:
			horiz = horiz.lerp(Vector3.ZERO, 1.0 - exp(-ground_friction * delta))
	else:
		# Quake-artige Air-Control: in Wunschrichtung beschleunigen bis air_control_speed,
		# vorhandenes Momentum bleibt erhalten.
		if wish != Vector3.ZERO:
			var cur := horiz.dot(wish)
			var add := clampf(air_control_speed - cur, 0.0, air_accel * delta)
			horiz += wish * add
		horiz *= 1.0 - air_drag * delta

	velocity.x = horiz.x
	velocity.z = horiz.z

	if not on_floor:
		var g := gravity
		if velocity.y < 0.0:
			g *= fall_gravity_mult
		elif not Input.is_action_pressed("jump"):
			g *= 1.6  # variable Sprunghoehe
		velocity.y -= g * delta

	if _jump_buffer_t > 0.0 and _coyote_t > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_t = 0.0
		_coyote_t = 0.0


func _process_dash(delta: float) -> void:
	_dash_t -= delta
	velocity = _dash_dir * _dash_speed_now
	# Dash-Jump: Springen bricht den Dash ab und nimmt den Speed mit.
	if _jump_buffer_t > 0.0 and (is_on_floor() or _coyote_t > 0.0):
		velocity.y = jump_velocity
		_jump_buffer_t = 0.0
		_coyote_t = 0.0
		_set_state(State.NORMAL)
		return
	if _dash_t <= 0.0:
		velocity = _dash_dir * maxf(_dash_speed_now * dash_exit_keep, run_speed)
		_set_state(State.NORMAL)


func _process_grapple(wish: Vector3, delta: float) -> void:
	var to_anchor := _anchor - global_position
	var dist := to_anchor.length()
	if dist < grapple_min_length:
		# Am Ankerpunkt angekommen: kleiner Hop, Momentum bleibt.
		velocity.y = maxf(velocity.y, jump_velocity * 0.6)
		_set_state(State.NORMAL)
		return
	var dir := to_anchor / dist

	velocity.y -= gravity * delta
	var reel := grapple_boost_accel if Input.is_action_pressed("jump") else grapple_reel_accel
	velocity += dir * reel * delta
	velocity += wish * grapple_steer_accel * delta

	# Seil-Constraint: nach aussen gerichtete Geschwindigkeit entfernen -> Pendel/Swing.
	_rope_len = clampf(minf(_rope_len, dist), grapple_min_length, grapple_range)
	if dist >= _rope_len:
		var outward := -velocity.dot(dir)
		if outward > 0.0:
			velocity += dir * outward
		velocity += dir * (dist - _rope_len) * 8.0 * delta


func _process_wallrun(wish: Vector3, delta: float) -> void:
	_wallrun_t += delta
	var n := _wall_normal
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var along := horiz - n * horiz.dot(n)
	var speed := maxf(along.length(), wallrun_min_speed)
	if Input.is_action_pressed("sprint"):
		speed = move_toward(speed, maxf(speed, sprint_speed), 20.0 * delta)
	var dir := along.normalized() if along.length() > 0.01 else wish
	var vy := velocity.y - gravity * wallrun_gravity_mult * delta
	vy = move_toward(vy, 0.0, 10.0 * delta)
	velocity = dir * speed + Vector3.UP * vy - n * 2.0  # leicht an die Wand druecken

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


# --- Actions --------------------------------------------------------------
func _try_dash(wish: Vector3) -> void:
	if _dash_cd > 0.0 or dash_charges <= 0:
		return
	var dir := wish
	if dir == Vector3.ZERO:
		dir = _cam_forward()
		if is_on_floor():
			dir.y = 0.0
	dir = dir.normalized()
	dash_charges -= 1
	_dash_cd = dash_cooldown

	if state == State.GRAPPLE:
		# Gas-Stoss am Seil: Impuls, Grapple bleibt aktiv.
		velocity += dir * dash_speed * 0.6
		return

	var carry := maxf(velocity.dot(dir), 0.0)
	_dash_dir = dir
	_dash_speed_now = maxf(dash_speed, carry + dash_speed * 0.35)
	_dash_t = dash_time
	_set_state(State.DASH)


func _try_grapple() -> void:
	if not aim_valid:
		return
	_anchor = aim_point
	_rope_len = global_position.distance_to(_anchor)
	var dir := (_anchor - global_position).normalized()
	velocity += dir * 5.0
	if is_on_floor():
		velocity.y = maxf(velocity.y, 6.0)
	dash_charges = maxi(dash_charges, 1)
	_set_state(State.GRAPPLE)


func _update_aim() -> void:
	var from := camera.global_position
	var to := from + _cam_forward() * (grapple_range + spring_arm.spring_length)
	var query := PhysicsRayQueryParameters3D.create(from, to, grapple_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	aim_valid = not hit.is_empty() \
			and global_position.distance_to(hit.position) <= grapple_range
	if aim_valid:
		aim_point = hit.position


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


func _respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	_set_state(State.NORMAL)
	reset_physics_interpolation()


# --- Visuals (pro Frame, interpoliert) ------------------------------------
func _process(delta: float) -> void:
	var t := get_global_transform_interpolated()
	cam_rig.global_position = t.origin + Vector3.UP * camera_height
	cam_rig.rotation = Vector3(0.0, _yaw, 0.0)
	cam_pitch.rotation = Vector3(_pitch, 0.0, 0.0)

	var speed := velocity.length()
	var target_fov := lerpf(base_fov, max_fov, clampf(speed / fov_speed_ref, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.0 * delta))

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() > 1.0:
		var target_yaw := atan2(-horiz.x, -horiz.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))

	_update_rope(t.origin)


func _build_rope() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.95, 1.0)
	mesh.material = mat
	_rope = MeshInstance3D.new()
	_rope.mesh = mesh
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.top_level = true
	_rope.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rope.visible = false
	add_child(_rope)


func _update_rope(origin: Vector3) -> void:
	if state != State.GRAPPLE:
		_rope.visible = false
		return
	var from := origin + Vector3.UP * 0.3
	var seg := _anchor - from
	var length := seg.length()
	if length < 0.01:
		_rope.visible = false
		return
	var y_axis := seg / length
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis)
	_rope.global_transform = Transform3D(Basis(x_axis, y_axis * length, z_axis), from + seg * 0.5)
	_rope.visible = true
