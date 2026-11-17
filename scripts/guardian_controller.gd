class_name GuardianController
extends CharacterBody3D
## Guardian – High-Speed-Controller.
##
## Movement: Laufen / Sprint / Air-Control / Wall-Run.
## Shift:    Sprint am Boden.
## Seile:    Dual-Hip-Grapple auf RMB / LT (zwei Werfer an linker + rechter Huefte).
##           - Klick/Halten: Haken der naechsten freien Huefte (abwechselnd L/R).
##             Straffes Seil, Winde zieht mit Basis 0.4 ein.
##           - Zwei Seile: Zugkraefte werden vektoriell addiert (gleicher Anker = 2x
##             Beschleunigung, gegenueberliegend = Querkraefte heben sich auf).
##           - Winde am Seil: W = Turbo (2.5x Basis), S = starres Seil (Laenge fix,
##             Winde steht, Schwung bleibt erhalten – reines Pendeln auf festem Radius).
##             A / D = seitlich quer zum Seil ausweichen / schwingen.
##           - Doppel-Tap: zweiter Haken an zweiter Oberflaeche, zwei straffe Seile.
##           Seile wickeln sich um Geometrie (Bending) und loesen sich nie von selbst.
## Kampf:    Zwei Targeting-Modi, beide immer aktiv:
##           - Free-Flow (ohne Lock): LMB halten greift automatisch den Gegner
##             unter/nahe dem Fadenkreuz in Grapple-Reichweite (Auto-Grab) und zieht
##             heran, LMB loslassen = Momentum-Slash im Anflug.
##           - Ziel-Auswahl (Mausrad-Klick / R3): waehlt das Ziel unterm Fadenkreuz
##             und gibt einen Kamera-Snap-Impuls darauf – danach ist die Kamera sofort
##             wieder frei. Erneut druecken = erneuter Snap. Loesen: Doppelklick ODER
##             gedrueckt halten (lock_clear_hold) – der Feld-Spirit kehrt dann zurueck.
##             Mausrad = Trefferpunkt-Wechsel am gewaehlten Gegner (Nacken, Knie ...).
##             Die Auswahl bleibt bis 3x Grapple-Reichweite bestehen (ausserhalb der
##             Reichweite grau, kein Seil), danach wird sie automatisch geloescht.
##             LMB halten = Seil zum gewaehlten Punkt, loslassen = Schlag.
##           LMB-Doppelklick (+ halten) = zweites Combat-Seil an dasselbe Ziel.
##           Ganz nah am Ziel (< auto_grab_min_dist) schlaegt LMB direkt zu.
## Gegner-Anflug (Carving): Kein Snap – eine Lenk-Beschleunigung dreht die vorhandene
##           Geschwindigkeit zum Ziel, der Betrag bleibt. Schwerkraft wirkt am Gegner nur entlang
##           der Zielrichtung (Sturzflug ja, Durchsacken nein).
##           Ein Seil = carve_turn_rate (weite Kurve), zwei Seile am selben Gegner (LMB-/RMB-Doppelklick
##           oder RMB + LMB) = doppelte Lenk- und Zugkraft -> halber Wenderadius (r = v / omega).
## Kamera:   P = Third-/First-Person, nahtlos ueberblendet.
##
## Physik in _physics_process, Kamera/Visuals in _process ueber die
## interpolierte Transform (Physics-Interpolation aktiv) -> keine Mikroruckler.

signal state_changed(new_state: State)
signal camera_mode_changed(first_person: bool)
## Ein Hueft-Haken wurde abgefeuert / eingeholt (HUD-Indikatoren, FX).
signal hook_fired(hook: GrappleHook)
signal hook_released(hook: GrappleHook)
## Hard-Lock gesetzt, gewechselt (Mausrad) oder geloest (null) – Befehl an den Feld-Spirit.
signal hard_lock_changed(target: Node3D)

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
## S am Seil = starres Seil: Laenge wird eingefroren (kein Einholen, kein Nachlassen),
## kein Daempfen – der Spieler pendelt verlustfrei auf festem Radius um den Pivot.
## Zugkraft (Beschleunigung, m/s²) EINER Winde bei Faktor 1.0. Basis-Einzug = x reel_base_mult,
## Turbo = zusaetzlich x reel_turbo_mult, Combat = x combat_reel_mult. Jede Winde zieht entlang
## ihrer Huefte->Anker-Richtung; die Kraefte beider Seile werden vektoriell addiert
## (gleiche Richtung = 2x Beschleunigung, gegenueberliegend = seitliche Anteile heben sich auf).
## Die Kraft faellt linear ab, je naeher die Seil-Einzugsgeschwindigkeit an der Linien-
## geschwindigkeit der Winde (winch_speed) liegt -> realistischer Motor, keine Endlos-Beschleunigung.
@export var reel_force := 200.0
## Wie hart das straffe Seil Ueberdehnung korrigiert (1/s) und kurz vor hang_length abbremst.
@export var rope_response := 40.0
## Gauss-Seidel-Iterationen fuer die Seil-Constraints (zwei Seile loesen sich gegenseitig auf).
@export var rope_solver_iterations := 4
## Ab dieser Restlaenge stoppt die Winde – man haengt am Anker.
@export var hang_length := 2.5
@export var rope_min_length := 1.5
## A / D am Seil: seitliche Steuerung quer zum Seil.
@export var rope_steer_accel := 24.0
## Nach dem Loslassen haengt das Seil so lange locker (keine Kraft) – Fenster fuer den Doppel-Tap.
@export var double_tap_window := 0.2
## Nachlade-Zeit eines Hueft-Werfers nach dem Einholen (s). Die andere Huefte
## bleibt frei -> Seil-Ketten L/R im Wechsel laufen ohne Wartezeit.
@export var hook_cooldown := 0.3
## Mindestabstand der beiden Anker beim Doppel-Tap. 0 = beide Haken duerfen an denselben
## Punkt/Pfeiler (doppelte Zugkraft).
@export var dual_min_separation := 0.0

# --- Hard-Lock / Combat-Grapple (Mausrad-Klick / R3, LMB) ----------------
@export_group("Combat Grapple")
## Windengeschwindigkeit des Combat-Seils = reel_speed * combat_reel_mult (W/S wirken auch hier).
@export var combat_reel_mult := 1.0
@export var combat_pull_impulse := 6.0
## Max. Seillaenge des Combat-Seils = grapple_range * diesem Faktor.
@export var lock_keep_range_mult := 1.3
## Zeitfenster (s): Der Schlag nutzt das staerkste Anflug-Momentum dieser Spanne,
## damit ein Aufprall kurz vor dem Schlag-Start den Bonus nicht verschluckt.
@export var momentum_memory := 0.12
## Unter dieser Distanz zum Ziel feuert LMB kein Seil, sondern schlaegt direkt (Messer-Reichweite).
@export var auto_grab_min_dist := 4.5

# --- Gegner-Anflug: Carving statt Snap ---------------------------------
@export_group("Enemy Dash")
## Lenk-Drehrate (rad/s) pro Seil am Gegner: dreht die Geschwindigkeit zum Ziel, ohne sie zu
## bremsen (Zentripetal-Beschleunigung = Rate * Tempo). Wenderadius = Tempo / (Rate * Seile).
@export var carve_turn_rate := 3.5
## LMB-Anflug auf den Hard-Lock: konstanter Zusatz-Zug zum Ziel (m/s², additiv zu Schwerkraft,
## Momentum und Seil – wie ein Gas-Schub). Kalibriert ueber v² = v0² + 2·a·d:
## 50 m Anflug mit 100 m/s -> ~110 m/s am Ziel (a = (110² - 100²) / 100 = 21).
@export var attack_reel_boost_accel := 21.0

# --- Free-Flow Auto-Grab (LMB ohne Hard-Lock) ------------------------------
@export_group("Auto Grab")
## Grosszuegiger Fang-Kegel um das Fadenkreuz fuer den Auto-Grab.
@export var auto_grab_cone_deg := 9.0
## Mindest-Fang-Radius (m) um den Fadenkreuz-Strahl.
@export var auto_grab_radius := 3.5

# --- Ziel-Auswahl (Hard-Lock) & Kamera-Snap -------------------------------
@export_group("Hard Lock")
## Bis zu dieser Distanz laesst sich ein Ziel waehlen/durchschalten (auch ausserhalb
## der Grapple-Reichweite – dann grau).
@export var lock_acquire_range := 120.0
## Auswahl wird geloescht, sobald das Ziel weiter als grapple_range * Faktor entfernt ist.
@export var lock_expire_range_mult := 3.0
## Dauer des Kamera-Snap-Impulses (s). Danach gehoert die Kamera wieder dem Spieler.
@export var snap_duration := 0.22
## So lange Mausrad-Klick / R3 halten, um die Auswahl zu loesen (s).
@export var lock_clear_hold := 0.5
## Zweiter Klick auf eine bestehende Auswahl innerhalb dieses Fensters (s) = Auswahl loesen.
@export var lock_double_click := 0.3
## Fang-Kegel fuer das Combat-/Auto-Grab-Fenster waechst mit dem Tempo (Grad pro m/s) ...
@export var speed_cone_per_mps := 0.06
## ... bis maximal so viele Grad zusaetzlich.
@export var speed_cone_max_bonus := 5.0

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
## Hueft-Werfer relativ zur Spieler-Mitte (seitlich / Hoehe).
const HIP_SIDE := 0.38
const HIP_UP := -0.15
const PITCH_MIN := -1.45
const PITCH_MAX := 1.35
const ROPE_COLOR := Color(0.55, 0.95, 1.0)
const ROPE_COLOR_COMBAT := Color(1.0, 0.45, 0.25)
const ROPE_COLOR_TURBO := Color(1.0, 0.8, 0.3)

@onready var cam_rig: Node3D = $CameraRig
@onready var cam_pitch: Node3D = $CameraRig/Pitch
@onready var spring_arm: SpringArm3D = $CameraRig/Pitch/SpringArm3D
@onready var camera: Camera3D = $CameraRig/Pitch/SpringArm3D/Camera3D
@onready var visual: Node3D = $Visual
@onready var body_mesh: GeometryInstance3D = $Visual/Body
@onready var knife: KnifeCombat = $Knife
@onready var knife_tp: Node3D = $Visual/KnifePivot
@onready var knife_fp: Node3D = $CameraRig/Pitch/SpringArm3D/Camera3D/ViewKnife
## Optionale Komponenten (Coop-ready: pro Guardian, keine Singletons).
@onready var health: HealthComponent = get_node_or_null("Health") as HealthComponent
@onready var spirit_roster: SpiritRosterComponent = get_node_or_null("SpiritRoster") as SpiritRosterComponent

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

## Bester Lock-Kandidat im Kegel um das Fadenkreuz (unsichtbar).
var lock_target: Node3D = null
## Eingerasteter Hard-Lock (Mausrad-Klick / R3). Bleibt bis zum Loesen bestehen –
## auch ausserhalb der Grapple-Reichweite (siehe hard_lock_in_range()).
var hard_lock: Node3D = null:
	set(v):
		if v != hard_lock:
			hard_lock = v
			hard_lock_changed.emit(v)
## Free-Flow: Gegner/Trefferpunkt, den LMB ohne Hard-Lock greifen wuerde.
var auto_grab_target: Node3D = null
## Collider unter dem Fadenkreuz (Auto-Aim-Treffer) und Trefferposition.
var aim_collider: Object = null
var aim_hit_pos := Vector3.ZERO

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
## Feste Reihenfolge fuer den Mausrad-Wechsel (sonst springt die Sortierung mit der Kamera).
var _cycle_order: Array[Node3D] = []
## [zeit, geschwindigkeit] vor move_and_slide – Anflug-Momentum fuer den Schlag.
var _vel_history: Array = []
## Summe der Seil-Zugkraefte im letzten Physik-Frame (m/s², fuer HUD/Tests).
var pull_force := Vector3.ZERO
var _clock := 0.0
## Kamera-Snap: Fortschritt (s), -1 = kein Snap. Start-Winkel fuer die Ueberblendung.
var _snap_t := -1.0
var _snap_from := Vector2.ZERO
var _lock_hold_t := -1.0
## _clock-Zeit des letzten Lock-Klicks auf eine bestehende Auswahl (Doppelklick-Erkennung).
var _lock_press_at := -INF
## LMB-Doppelklick: Haltedauer seit dem letzten Druck, Fenster nach einem kurzen Klick (-1 = aus).
var _attack_held_t := 0.0
var _combat_tap_t := -1.0


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
	for h in hooks:
		h.cooldown_time = hook_cooldown
		h.fired.connect(hook_fired.emit)
		h.released.connect(hook_released.emit)
	if spirit_roster:
		spirit_roster.weapon_spirit_changed.connect(knife.set_weapon_spirit)
		knife.set_weapon_spirit(spirit_roster.weapon_spirit())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =========================================================================
# Input
# =========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_turn_camera(event.relative * mouse_sensitivity)
	elif event.is_action_pressed("toggle_camera"):
		toggle_camera()
	elif event.is_action_pressed("hard_lock"):
		press_target_button()
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


## Spieler dreht die Kamera – ein laufender Snap wird sofort abgebrochen.
func _turn_camera(amount: Vector2) -> void:
	_snap_t = -1.0
	_yaw -= amount.x
	_pitch = clampf(_pitch - amount.y, PITCH_MIN, PITCH_MAX)


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


## Mindestens ein gespanntes Seil (lockere Seile im Doppel-Tap-Fenster zaehlen nicht).
func any_hook_active() -> bool:
	return hooks.any(func(h: GrappleHook) -> bool: return h.active and not h.slack)


func hooks_out() -> int:
	return hooks.filter(func(h: GrappleHook) -> bool: return h.active).size()


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

	_update_lock_button(delta)
	_update_hard_lock()
	_handle_hook_input(delta)
	_handle_attack_input(delta)
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

	_record_momentum(delta)
	move_and_slide()
	_post_move(wish, delta)

	if global_position.y < RESPAWN_Y:
		_respawn()


func _record_momentum(delta: float) -> void:
	_clock += delta
	_vel_history.append([_clock, velocity])
	while not _vel_history.is_empty() and _clock - _vel_history[0][0] > momentum_memory:
		_vel_history.pop_front()


## Staerkstes Momentum (vor Kollisionen) der letzten momentum_memory Sekunden.
func momentum_velocity() -> Vector3:
	var best := velocity
	for e: Array in _vel_history:
		if (e[1] as Vector3).length_squared() > best.length_squared():
			best = e[1]
	return best


func _tick_timers(delta: float) -> void:
	_coyote_t -= delta
	_jump_buffer_t -= delta
	_wallrun_lockout -= delta
	for h in hooks:
		h.tick(delta)


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
	var along := Vector3(velocity.x, 0.0, velocity.z).slide(n)
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
	if Vector3(velocity.x, 0.0, velocity.z).slide(n).length() < wallrun_min_speed:
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


## LMB halten = Combat-Seil zum Ziel + heranziehen, Loslassen = Messer-Schlag im Anflug.
## Ziel: Hard-Lock (falls aktiv und in Reichweite), sonst Free-Flow-Auto-Grab unterm
## Fadenkreuz. Kein greifbares Ziel = normaler Slash. Waehrend LMB gehalten wird,
## greift das Seil sofort zu, sobald ein Ziel greifbar wird (z. B. zurueck in Reichweite).
## Doppelklick: Ein kurzer Klick (< double_tap_window) schlaegt nicht sofort, sondern laesst
## das Seil weiterziehen; ein zweiter Klick im Fenster haengt das zweite Seil an dasselbe Ziel.
## Ohne zweiten Klick folgt der Schlag am Fensterende.
func _handle_attack_input(delta: float) -> void:
	_attack_held_t += delta
	if _combat_tap_t >= 0.0:
		_combat_tap_t += delta
		if _combat_tap_t > double_tap_window:
			_release_combat_slash()
	if Input.is_action_just_pressed("attack"):
		_attack_held_t = 0.0
		if _combat_tap_t >= 0.0 and combat_hook() != null:
			_combat_tap_t = -1.0
			_fire_combat_hook(combat_hook().target)
		elif combat_hook() == null and not _try_combat_grab():
			knife.request_slash(_strike_target())
	elif Input.is_action_just_released("attack"):
		if _attack_held_t < double_tap_window and combat_hooks_out() == 1:
			_combat_tap_t = 0.0
		else:
			_release_combat_slash()
	elif Input.is_action_pressed("attack") and combat_hook() == null:
		_try_combat_grab()


## Combat-Seile loesen und den Momentum-Schlag auf ihr Ziel ausfuehren.
func _release_combat_slash() -> void:
	_combat_tap_t = -1.0
	var ch := combat_hook()
	if ch == null:
		return
	var tgt: Node3D = ch.target if is_instance_valid(ch.target) else null
	_release_combat_hooks()
	knife.request_slash(tgt)
	_refresh_state()


## Ziel, das LMB gerade greifen wuerde (Hard-Lock hat Vorrang). null = nichts greifbar.
func combat_grab_target() -> Node3D:
	var t := auto_grab_target
	if hard_lock != null:
		if not hard_lock_in_range():
			return null
		t = hard_lock
	if not is_instance_valid(t):
		return null
	var d := global_position.distance_to(_lock_point_of(t))
	if d < auto_grab_min_dist or d > grapple_range:
		return null
	return t


## Ziel fuer einen direkten Schlag ohne Seil (Lock oder Auto-Ziel in Messer-Naehe).
func _strike_target() -> Node3D:
	var locked: Node3D = hard_lock if is_hard_locked() else null
	var t: Node3D = locked if locked != null else auto_grab_target
	if is_instance_valid(t) and global_position.distance_to(_lock_point_of(t)) <= knife.lock_strike_reach:
		return t
	return locked


func _try_combat_grab() -> bool:
	if combat_hook() != null:
		return true  # es gibt immer nur ein Combat-Seil
	var t := combat_grab_target()
	return t != null and _fire_combat_hook(t)


func combat_hooks_out() -> int:
	return hooks.filter(func(h: GrappleHook) -> bool: return h.active and h.combat).size()


func _release_combat_hooks() -> void:
	for h in hooks:
		if h.combat:
			h.release()


func rope_hooks_out() -> int:
	return hooks.filter(func(h: GrappleHook) -> bool: return h.active and not h.combat).size()


func combat_hook() -> GrappleHook:
	for h in hooks:
		if h.active and h.combat:
			return h
	return null


## Naechste freie (und nachgeladene) Huefte, abwechselnd links/rechts.
func _take_free_hip() -> GrappleHook:
	var order := [hook_right, hook_left] if _next_hip == hook_right else [hook_left, hook_right]
	for h: GrappleHook in order:
		if h.is_ready():
			_next_hip = hook_right if h == hook_left else hook_left
			return h
	return null


## Haengt die naechste freie Huefte an den Auto-Aim-Punkt. null = kein Ziel / keine Huefte frei.
func _attach_aim_hook() -> GrappleHook:
	if aim_kind == AimKind.NONE:
		return null
	var h := _take_free_hip()
	if h == null:
		return null
	var tgt: Node3D = aim_target if aim_kind == AimKind.ENEMY else null
	if tgt == null and aim_collider is Node3D and hit_receiver_of(aim_collider) != null:
		tgt = aim_collider  # Gegner-Koerper (z. B. Riese): Seil haengt am Gegner
	h.attach(aim_point, tgt, global_position)
	return h


func _fire_primary_hook() -> void:
	var h := _attach_aim_hook()
	if h == null:
		return
	_primary = h
	if is_on_floor():
		velocity.y = maxf(velocity.y, 4.0)
	_refresh_state()


func _fire_second_hook() -> void:
	if _primary == null or not _primary.active \
			or (dual_min_separation > 0.0
				and aim_point.distance_to(_primary.anchor_world()) < dual_min_separation):
		return  # kein zweites Ziel -> erster Haken bleibt einfach straff
	if _attach_aim_hook() != null:
		_refresh_state()


## Combat-Seil zum Ziel (Hard-Lock oder Auto-Grab). Sind beide Hueften belegt,
## wird ein RMB-Seil dafuer eingeholt – nie ein bestehendes Combat-Seil.
func _fire_combat_hook(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var p := _lock_point_of(target)
	if global_position.distance_to(p) > grapple_range:
		return false
	var h := _take_free_hip()
	if h == null:
		h = hook_left if _primary == hook_right else hook_right
		if h.combat:
			h = hook_right if h == hook_left else hook_left
		if h.combat:
			return false
		h.release()
	var first := combat_hooks_out() == 0  # Dash-Kick nur beim ersten Combat-Seil
	h.attach(p, target, global_position, true)
	if first:
		velocity += (p - global_position).normalized() * combat_pull_impulse
	if is_on_floor():
		velocity.y = maxf(velocity.y, 6.0)
	_refresh_state()
	return true


## W am Seil -> Turbo-Einzug.
func is_turbo() -> bool:
	return Input.is_action_pressed("move_forward") and any_hook_active()


## S am Seil (ohne W) -> starres Seil (feste Laenge, Winde steht).
func is_rope_rigid() -> bool:
	return Input.is_action_pressed("move_back") and not Input.is_action_pressed("move_forward") \
			and any_hook_active()


## Faktor der Winde: Basis bzw. Combat, x Turbo (W) – 0 bei starrem Seil (S).
func _winch_mult(h: GrappleHook) -> float:
	if is_rope_rigid():
		return 0.0
	var on_enemy := h != null and (h.combat or _enemy_of(h) != null)
	var m := combat_reel_mult if on_enemy else reel_base_mult
	return m * (reel_turbo_mult if is_turbo() else 1.0)


## Zugkraft (m/s²) der Winde eines Seils.
func winch_force(h: GrappleHook = null) -> float:
	return reel_force * _winch_mult(h)


## Linien-Geschwindigkeit der Winde (m/s): bis hierhin zieht sie.
func winch_speed(h: GrappleHook = null) -> float:
	return reel_speed * _winch_mult(h)


func _hip_side(h: GrappleHook) -> float:
	return -HIP_SIDE if h.kind == GrappleHook.Kind.HIP_LEFT else HIP_SIDE


## Huefte, an der das Seil sitzt (Weltposition) – Ursprung der Zugrichtung.
func hip_position(h: GrappleHook) -> Vector3:
	return global_position + Vector3.UP * HIP_UP + Basis(Vector3.UP, _yaw) * Vector3.RIGHT * _hip_side(h)


func _process_hooked(wish: Vector3, delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	for h in hooks:
		if h.active:
			h.update_bends(space, global_position, velocity, ex, grapple_mask)

	var on_enemy := enemy_hooks()
	if on_enemy == 0:
		velocity.y -= gravity * delta
	else:
		_enemy_gravity(delta)
		_carve_to_enemy(on_enemy, delta)
		_attack_boost(delta)
	if on_enemy < 2:
		_rope_steer(delta)
	if is_on_floor():
		_try_ground_jump()
	_solve_ropes(delta)


## Seil-Physik mit echter Vektor-Summe:
##   1) Jede aktive Winde i erzeugt eine Zugkraft  F_i = d_i * F_pull_i * (1 - v_i / v_max_i),
##      d_i = Richtung Huefte -> Anker, v_i = aktuelle Einzugsgeschwindigkeit dieses Seils.
##      F_total = F_links + F_rechts wird als Beschleunigung angewendet.
##      Gleiche Richtung -> doppelte Beschleunigung; gegenueberliegend -> Querkraefte heben
##      sich auf, gemeinsame Anteile (z. B. nach oben/vorne) addieren sich.
##   2) Straff: Seillaenge = min(Laenge, Distanz) – das Seil laesst nie nach.
##      Starr (S): Laenge eingefroren, F_pull = 0.
##   3) Constraints: kein Seil darf sich dehnen. Iterativ (Gauss-Seidel), damit zwei Seile
##      sich gegenseitig aufloesen statt gegeneinander zu kaempfen. Das Seil nimmt nur die
##      nach aussen gerichtete Radial-Geschwindigkeit – tangentialer Schwung bleibt erhalten.
func _solve_ropes(delta: float) -> void:
	var rigid := is_rope_rigid()
	var max_len := grapple_range * lock_keep_range_mult
	var live: Array[GrappleHook] = []
	for h in hooks:
		if h.active and not h.slack and global_position.distance_to(h.pivot()) > 0.01:
			live.append(h)
	# --- 1) Zugkraefte pro Seil, vektoriell summiert -----------------------
	var f_total := Vector3.ZERO
	for h in live:
		h.pull = Vector3.ZERO
		var f := winch_force(h)
		var vmax := winch_speed(h)
		if f <= 0.0 or vmax <= 0.0 or h.rope_length <= hang_length:
			continue
		var to_anchor := h.pivot() - hip_position(h)
		if to_anchor.length() < 0.01:
			continue
		var dir := to_anchor.normalized()
		# Kurz vor hang_length laeuft die Winde aus (kein Einschlag am Anker).
		var dist := global_position.distance_to(h.pivot())
		vmax = minf(vmax, maxf(dist - hang_length, 0.0) * rope_response)
		var v_in := velocity.dot(dir)
		var k := clampf(1.0 - v_in / maxf(vmax, 0.001), 0.0, 1.0)
		h.pull = dir * f * k
		f_total += h.pull
	pull_force = f_total
	velocity += f_total * delta
	# --- 2) Seillaengen ----------------------------------------------------
	for h in live:
		var dist := global_position.distance_to(h.pivot())
		if not rigid:
			h.rope_length = minf(h.rope_length, dist)
		h.rope_length = clampf(h.rope_length, rope_min_length, max_len)
	# --- 3) Laengen-Constraints (iterativ) ---------------------------------
	for it in rope_solver_iterations:
		for h in live:
			var to := h.pivot() - global_position
			var dist := to.length()
			var dir := to / dist
			var gap := dist - h.rope_length
			# gap <= 0: innerhalb des Radius frei, aber hoechstens bis an den Radius in diesem Frame.
			# gap > 0: Ueberdehnung sanft zurueckholen.
			var min_in := gap / maxf(delta, 0.0001) if gap <= 0.0 else minf(gap * rope_response, 6.0)
			var v_in := velocity.dot(dir)
			if v_in < min_in:
				velocity += dir * (min_in - v_in)
	# Straff auch fuer die Bewegung dieses Frames: Laenge folgt der vorhergesagten Distanz.
	if not rigid:
		var next := global_position + velocity * delta
		for h in live:
			h.rope_length = clampf(minf(h.rope_length, next.distance_to(h.pivot())), rope_min_length, max_len)


## Gegner, an dem ein straffes Seil haengt (Schadens-Empfaenger), sonst null.
func _enemy_of(h: GrappleHook) -> Node:
	if not h.active or h.slack or not is_instance_valid(h.target):
		return null
	return hit_receiver_of(h.target)


## Beide Seile straff am selben Gegner (Doppelklick).
func is_dual_locked() -> bool:
	var e := _enemy_of(hook_left)
	return e != null and e == _enemy_of(hook_right)


## Seile am Gegner: 2 = beide am selben Gegner, 1 = genau eins, 0 = keins (oder zwei Gegner).
func enemy_hooks() -> int:
	if is_dual_locked():
		return 2
	return 1 if hooks.filter(func(h: GrappleHook) -> bool: return _enemy_of(h) != null).size() == 1 else 0


## Anflugpunkt: zwei Seile = Mitte beider Pivots (symmetrischer Zug), ein Seil = dessen Pivot.
func enemy_goal() -> Vector3:
	if is_dual_locked():
		return (hook_left.pivot() + hook_right.pivot()) * 0.5
	for h in hooks:
		if _enemy_of(h) != null:
			return h.pivot()
	return Vector3.INF


## Am Gegner: Schwerkraft nur entlang der Zielrichtung, wenn das Ziel unten liegt (Sturzflug
## beschleunigt weiter). Der Anteil quer dazu entfaellt -> kein Durchsacken unter die Anflugbahn.
func _enemy_gravity(delta: float) -> void:
	var dir := global_position.direction_to(enemy_goal())
	velocity += dir * maxf(-dir.y, 0.0) * gravity * delta


## Carving: dreht die Geschwindigkeit mit carve_turn_rate x Seile Richtung Ziel, der Betrag
## bleibt -> die Flugkurve biegt sich ein statt auf eine Linie zu springen.
## Innerhalb von hang_length nicht mehr – dort uebernehmen Aufprall und Schlag.
func _carve_to_enemy(hooks_on_enemy: int, delta: float) -> void:
	var goal := enemy_goal()
	if global_position.distance_to(goal) <= hang_length or velocity.length() < 0.1:
		return
	var dir := global_position.direction_to(goal)
	var axis := velocity.cross(dir)
	if axis.length_squared() < 0.000001:  # genau weg vom Ziel: beliebige Querachse
		axis = velocity.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	var angle := minf(velocity.angle_to(dir), carve_turn_rate * hooks_on_enemy * delta)
	velocity = velocity.rotated(axis.normalized(), angle)


## LMB-Anflug auf den Hard-Lock: additiver Zug entlang der Zielrichtung (Gas-Schub).
## Kein Override – Schwerkraft (Sturzflug) und Momentum bleiben voll erhalten.
func _attack_boost(delta: float) -> void:
	var ch := combat_hook()
	if ch == null or not is_hard_locked() or hit_receiver_of(ch.target) != hit_receiver_of(hard_lock):
		return
	var goal := enemy_goal()
	if global_position.distance_to(goal) <= hang_length:
		return
	velocity += global_position.direction_to(goal) * attack_reel_boost_accel * delta


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
		lateral = lateral.slide(axis.normalized())
	velocity += lateral * rope_steer_accel * delta


func _release_rope_hooks() -> void:
	for h in hooks:
		if not h.combat:
			h.release()
	_primary = null


func _release_all_hooks() -> void:
	_release_rope_hooks()
	_release_combat_hooks()
	_grace_t = -1.0


# =========================================================================
# Auto-Aim (Kegel um das Fadenkreuz)
# =========================================================================
func _update_aim() -> void:
	_update_aim_point()
	_update_auto_grab()


## Free-Flow: welchen Gegner/Trefferpunkt wuerde LMB ohne Hard-Lock greifen?
## 1) Gegner exakt unterm Fadenkreuz, 2) Fadenkreuz liegt auf dem Koerper eines
## Gegners mit Trefferpunkten -> naechster sichtbarer Punkt, 3) grosszuegiger Kegel.
func _update_auto_grab() -> void:
	auto_grab_target = null
	if aim_kind == AimKind.ENEMY and is_instance_valid(aim_target):
		auto_grab_target = aim_target
		return
	var space := get_world_3d().direct_space_state
	var start := _aim_start()
	if aim_collider != null and aim_kind == AimKind.POINT:
		var best_d := INF
		for t in _lockables_within(grapple_range):
			if hit_receiver_of(t) != aim_collider:
				continue
			var p := _lock_point_of(t)
			var dd := p.distance_to(aim_hit_pos)
			if dd < best_d and _has_line_of_sight(space, start, t, p):
				best_d = dd
				auto_grab_target = t
		if auto_grab_target != null:
			return
	var speed_bonus := minf(velocity.length() * speed_cone_per_mps, speed_cone_max_bonus)
	auto_grab_target = _find_lock_target(space, start, aim_forward(), grapple_range,
			auto_grab_cone_deg + speed_bonus, auto_grab_radius)


## Startpunkt der Ziel-Strahlen: auf Spielerhoehe entlang des Kamera-Strahls ->
## in Third-Person wird nichts zwischen Kamera und Spieler getroffen. In First-Person ~ Kamera.
func _aim_start() -> Vector3:
	var cam_pos := camera.global_position
	var fwd := aim_forward()
	return cam_pos + fwd * maxf((global_position - cam_pos).dot(fwd), 0.0)


func _update_aim_point() -> void:
	aim_kind = AimKind.NONE
	aim_target = null
	aim_assisted = false
	aim_collider = null
	var fwd := aim_forward()
	var start := _aim_start()
	var space := get_world_3d().direct_space_state

	# 1) Lock-Kandidat: Gegner im Kegel, Fang-Radius = max(assist_radius, Distanz * tan(Kegel))
	lock_target = _find_lock_target(space, start, fwd, grapple_range, assist_cone_deg, assist_radius)

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
	aim_collider = col
	aim_hit_pos = hit.position
	if col is Node3D and (col as Node3D).is_in_group("lock_target") and _is_lockable(col):
		aim_kind = AimKind.ENEMY
		aim_target = col as Node3D
		aim_point = _lock_point_of(aim_target)
	else:
		aim_kind = AimKind.POINT
		aim_point = (hit.position as Vector3) + (hit.normal as Vector3) * 0.05
	aim_assisted = assisted


func _find_lock_target(space: PhysicsDirectSpaceState3D, start: Vector3, fwd: Vector3,
		max_range: float, cone_deg: float, radius: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var tan_cone := tan(deg_to_rad(cone_deg))
	for t in _lockables_within(max_range):
		var p := _lock_point_of(t)
		var v := p - start
		var along := v.dot(fwd)
		if along <= 0.0:
			continue
		var perp := (v - fwd * along).length()
		var allowed := maxf(radius, along * tan_cone)
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


## Alle anvisierbaren Ziele (Gruppe "lock_target"), deren Lock-Punkt hoechstens max_range entfernt ist.
func _lockables_within(max_range: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("lock_target"):
		var t := n as Node3D
		if t != null and _is_lockable(t) and global_position.distance_to(_lock_point_of(t)) <= max_range:
			out.append(t)
	return out


## Ziel-Punkt eines Lock-Ziels: eigener Lock-Punkt (Koerperteil/Hitbox) oder
## Mitte seiner Kollisions-Shapes – nie ein versetzter Mesh-Origin.
func _lock_point_of(t: Node3D) -> Vector3:
	return t.get_lock_point() if t.has_method("get_lock_point") else hitbox_center(t)


## Radius (m) des Ziel-Rahmens.
func lock_radius_of(t: Node3D) -> float:
	return t.get_lock_radius() if t.has_method("get_lock_radius") else 1.0


## Mittelpunkt der direkten CollisionShape3D-Kinder (Fallback: eigene Position).
static func hitbox_center(n: Node3D) -> Vector3:
	var parts := KnifeCombat.body_parts(n)
	if parts.is_empty():
		return n.global_position
	var sum := Vector3.ZERO
	for c in parts:
		sum += c.global_position
	return sum / parts.size()


func _is_lockable(t: Object) -> bool:
	return not t.has_method("is_lockable") or t.is_lockable()


# =========================================================================
# Hard-Lock & Ziel-Wechsel
# =========================================================================
## Mausrad-Klick / R3: ohne Auswahl das Ziel unterm Fadenkreuz waehlen, dann
## Kamera-Snap-Impuls auf das gewaehlte Ziel. Loesen: Doppelklick auf die bestehende
## Auswahl (lock_double_click) oder gedrueckt halten (lock_clear_hold, _update_lock_button()).
func press_target_button() -> void:
	if is_hard_locked() and _clock - _lock_press_at <= lock_double_click:
		_lock_press_at = -INF
		_lock_hold_t = -1.0
		release_hard_lock()
		return
	# Nur ein Klick auf eine schon bestehende Auswahl startet das Doppelklick-Fenster –
	# Auswaehlen + sofortiger Snap-Klick loest also nicht versehentlich.
	_lock_press_at = _clock if is_hard_locked() else -INF
	_lock_hold_t = 0.0
	if not is_hard_locked():
		var t := lock_target
		if t == null:
			t = _find_lock_target(get_world_3d().direct_space_state, _aim_start(), aim_forward(),
					lock_acquire_range, assist_cone_deg, assist_radius)
		hard_lock = t
		_cycle_order.clear()
	snap_camera_to_target()


## Kamera-Snap-Impuls: richtet die Kamera in snap_duration weich auf das gewaehlte Ziel.
func snap_camera_to_target() -> void:
	if not is_hard_locked():
		return
	_snap_t = 0.0
	_snap_from = Vector2(_yaw, _pitch)


func is_snapping() -> bool:
	return _snap_t >= 0.0


func _update_lock_button(delta: float) -> void:
	if _lock_hold_t < 0.0:
		return
	if not Input.is_action_pressed("hard_lock"):
		_lock_hold_t = -1.0
		return
	_lock_hold_t += delta
	if _lock_hold_t >= lock_clear_hold:
		_lock_hold_t = -1.0
		release_hard_lock()


func release_hard_lock() -> void:
	hard_lock = null
	_snap_t = -1.0
	_cycle_order.clear()


func lock_expire_range() -> float:
	return grapple_range * lock_expire_range_mult


func is_hard_locked() -> bool:
	return hard_lock != null and is_instance_valid(hard_lock)


## Lock-Ziel in Grapple-Reichweite? (false = Rahmen grau, kein Combat-Seil)
func hard_lock_in_range() -> bool:
	return is_hard_locked() and global_position.distance_to(_lock_point_of(hard_lock)) <= grapple_range


## Mausrad: durch alle anvisierbaren Ziele/Trefferpunkte schalten.
## Ohne Lock rastet der erste Scroll das beste Ziel ein. Die Reihenfolge wird beim
## ersten Scroll festgelegt (Naehe zum Fadenkreuz) und danach beibehalten – sonst
## wuerde die mitdrehende Lock-Kamera die Sortierung bei jedem Schritt umwerfen.
func cycle_lock(step: int) -> void:
	var list := lock_candidates()
	# Gegner mit mehreren Trefferpunkten gewaehlt -> nur durch dessen Punkte schalten.
	if is_hard_locked():
		var rc := hit_receiver_of(hard_lock)
		var parts: Array[Node3D] = []
		for t in list:
			if hit_receiver_of(t) == rc:
				parts.append(t)
		if not parts.has(hard_lock):
			parts.append(hard_lock)
		if parts.size() > 1:
			list = parts
	var order: Array[Node3D] = []
	for t in _cycle_order:
		if is_instance_valid(t) and (list.has(t) or t == hard_lock):
			order.append(t)
	for t in list:
		if not order.has(t):
			order.append(t)
	_cycle_order = order
	if order.is_empty():
		return
	var i := order.find(hard_lock)
	if i == -1:
		hard_lock = lock_target if lock_target != null and order.has(lock_target) else order[0]
		return
	hard_lock = order[posmod(i + step, order.size())]


## Alle anvisierbaren Ziele (bis lock_acquire_range) mit Sichtlinie, sortiert nach
## Winkel zum Fadenkreuz (naechstes zuerst).
func lock_candidates() -> Array[Node3D]:
	var fwd := aim_forward()
	var start := _aim_start()
	var space := get_world_3d().direct_space_state
	var scored: Array = []
	for t in _lockables_within(lock_acquire_range):
		var p := _lock_point_of(t)
		var v := p - start
		if v.dot(fwd) <= 0.0 or not _has_line_of_sight(space, start, t, p):
			continue
		scored.append([fwd.angle_to(v.normalized()), t])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array[Node3D] = []
	for e in scored:
		out.append(e[1])
	return out


## Auswahl faellt weg, wenn das Ziel verschwindet/besiegt ist oder weiter als
## lock_expire_range_mult x Grapple-Reichweite entfernt ist (Auto-Clear).
func _update_hard_lock() -> void:
	if hard_lock == null:
		return
	if not is_instance_valid(hard_lock) or not _is_lockable(hard_lock) \
			or global_position.distance_to(_lock_point_of(hard_lock)) > lock_expire_range():
		release_hard_lock()
		_release_combat_hooks()


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
	release_hard_lock()
	_lock_hold_t = -1.0
	global_position = _spawn
	velocity = Vector3.ZERO
	_vel_history.clear()
	_set_state(State.NORMAL)
	if health:
		health.reset()
	reset_physics_interpolation()


# =========================================================================
# Kamera & Visuals (pro Frame, interpoliert)
# =========================================================================
func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_turn_camera(look * stick_sensitivity * delta)

	_cam_blend = move_toward(_cam_blend, 1.0 if first_person else 0.0,
			delta / maxf(camera_switch_time, 0.01))
	var b := smoothstep(0.0, 1.0, _cam_blend)
	_apply_camera_blend(b)

	var t := get_global_transform_interpolated()
	var pivot := t.origin + Vector3.UP * lerpf(tp_height, fp_height, b)
	if is_snapping():
		_update_camera_snap(pivot, delta)
	cam_rig.global_position = pivot
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


## Kamera-Snap: blendet Yaw/Pitch in snap_duration auf das (ggf. bewegte) Ziel –
## inkl. Schulter-Versatz und Spring-Arm-Laenge, dann ist die Kamera wieder frei.
func _update_camera_snap(pivot: Vector3, delta: float) -> void:
	if not is_hard_locked():
		_snap_t = -1.0
		return
	_snap_t += delta
	var goal := lock_view_angles(pivot, _lock_point_of(hard_lock))
	if goal == Vector2.INF:
		_snap_t = -1.0
		return
	var a := clampf(_snap_t / maxf(snap_duration, 0.01), 0.0, 1.0)
	var k := smoothstep(0.0, 1.0, a)
	_yaw = lerp_angle(_snap_from.x, goal.x, k)
	_pitch = lerpf(_snap_from.y, goal.y, k)
	if a >= 1.0:
		_snap_t = -1.0


## Yaw/Pitch (x/y), bei denen die Kamera von `pivot` aus genau auf `target` zielt.
## Vector2.INF, wenn das Ziel direkt ueber/unter dem Spieler liegt (Yaw undefiniert).
func lock_view_angles(pivot: Vector3, target: Vector3) -> Vector2:
	# Kamera-Versatz im Pitch-Raum (Schulter + Spring-Arm), unabhaengig von Yaw/Pitch.
	var local_off := cam_pitch.global_transform.affine_inverse() * camera.global_position
	var yaw := _yaw
	var pitch := _pitch
	for i in 10:
		var cam_pos := pivot + Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * local_off
		var v := target - cam_pos
		var flat := Vector2(v.x, v.z).length()
		if flat < 0.3:
			return Vector2.INF
		yaw = atan2(-v.x, -v.z)
		pitch = clampf(atan2(v.y, flat), PITCH_MIN, PITCH_MAX)
	return Vector2(yaw, pitch)


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
	var hip_up := lerpf(HIP_UP, -0.35, b)  # Werfer sitzen an der Huefte
	var n := 0
	for h in hooks:
		if not h.active:
			continue
		var color := _rope_color(h)
		var pts := h.render_points(origin + Vector3.UP * hip_up + right * _hip_side(h))
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			if n >= MAX_ROPE_SEGMENTS or seg.length() < 0.01:
				continue
			_rope_mm.set_instance_transform(n, _segment_transform(pts[i], seg))
			_rope_mm.set_instance_color(n, color)
			n += 1
	_rope_mm.visible_instance_count = n


func _rope_color(h: GrappleHook) -> Color:
	if h.combat:
		return ROPE_COLOR_COMBAT
	if h.slack:
		return ROPE_COLOR * 0.5
	return ROPE_COLOR_TURBO if is_turbo() else ROPE_COLOR


## Einheits-Zylinder (Hoehe 1, entlang Y) von `from` ueber das Segment `seg` strecken.
func _segment_transform(from: Vector3, seg: Vector3) -> Transform3D:
	var y_axis := seg.normalized()
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	return Transform3D(Basis(x_axis, seg, x_axis.cross(y_axis)), from + seg * 0.5)
