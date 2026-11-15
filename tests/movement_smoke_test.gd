extends SceneTree
## Headless-Smoke-Test fuer den Guardian (Movement, Kamera, Seile, Lock, Messer).
## Aufruf: godot --headless --path . --script res://tests/movement_smoke_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

var _fails := 0
var arena: Node
var g: GuardianController


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	arena = load("res://scenes/test_arena.tscn").instantiate()
	root.add_child(arena)
	g = arena.get_node("Guardian")
	await _frames(30)

	await _test_basic_movement()
	await _test_camera_toggle()
	await _test_knife()
	await _test_damage_curve()
	await _test_aim_and_lock()
	await _test_taut_rope_base_pull()
	await _test_turbo_pull()
	await _test_brake()
	await _test_rope_steering()
	await _test_dual_hooks()
	await _test_hip_alternation()
	await _test_hard_lock_toggle()
	await _test_lock_cycling_giant()
	await _test_lock_slash_loop()
	await _test_giant_point_hit()
	await _test_hitbox_alignment()
	await _test_auto_grab_free_flow()
	await _test_auto_grab_hold()
	await _test_hard_lock_camera()
	await _test_hard_lock_out_of_range()
	await _test_rope_bending()
	await _test_wallrun()

	print("SMOKE TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


# --- Tests ----------------------------------------------------------------
func _test_basic_movement() -> void:
	print("Movement")
	_check(g.is_on_floor(), "steht nach Spawn auf dem Boden")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	var hs := Vector2(g.velocity.x, g.velocity.z).length()
	_check(hs >= 23.0, "Sprint = richtiges Rennen (%.1f m/s)" % hs)
	_check(not g.is_turbo(), "Sprint am Boden loest keinen Turbo aus")
	_check(not InputMap.has_action("dash"), "kein Dash mehr")
	_release_all()
	await _frames(60)
	await _tap("jump", 3)
	_check(g.velocity.y > 5.0 and not g.is_on_floor(), "Sprung hebt ab")
	await _frames(90)


func _test_camera_toggle() -> void:
	print("Kamera")
	await _place(Vector3(0, 1.2, 0), 0.0, -0.1)
	g.toggle_camera()
	await _process_frames(40)
	_check(g.first_person and g.spring_arm.spring_length < 0.05, "First-Person: Kamera im Kopf")
	for i in 40:
		g.velocity = Vector3(0, 0, -40)
		await process_frame
	_check(g.camera.fov > g.base_fov_fp + 5.0, "First-Person: FOV-Effekt bei Speed (%.1f)" % g.camera.fov)
	g.velocity = Vector3.ZERO
	g.toggle_camera()
	await _process_frames(40)
	_check(not g.first_person and absf(g.spring_arm.spring_length - g.tp_distance) < 0.05,
			"zurueck auf Third-Person")


func _test_knife() -> void:
	print("Messer (LMB)")
	var d := _dummy_near(Vector3(7, 1, -20))
	await _place(Vector3(7, 1.2, -17.8), 0.0, -0.1)
	var hp_before := d.hp
	await _tap("attack")
	await _frames(15)
	var dmg := hp_before - d.hp
	_check(dmg > 0.0, "Slash trifft Dummy")
	_check(absf(dmg - g.knife.min_damage) < 0.6, "Stillstand = minimaler Base-Damage (%.1f)" % dmg)
	_check(g.hooks_out() == 0, "LMB loest keinen Grapple aus")
	await _tap("attack")
	await _frames(4)
	_check(g.knife.combo_index == 1, "Combo zaehlt hoch (%d)" % g.knife.combo_index)
	await _frames(30)


func _test_damage_curve() -> void:
	print("Momentum-Schaden")
	var k := g.knife
	var d0: float = k.compute_damage(Vector3.ZERO).damage
	var d20: float = k.compute_damage(Vector3(0, 0, -20)).damage
	var d40: float = k.compute_damage(Vector3(0, 0, -40)).damage
	var p40: Dictionary = k.compute_damage(Vector3(0, -40, -4))
	var p60: Dictionary = k.compute_damage(Vector3(0, -60, -4), 1.0, true)
	print("    0 m/s %.0f | 20 m/s %.0f | 40 m/s flach %.0f | 40 m/s Sturz %.0f | 60 m/s Turbo-Sturz %.0f"
			% [d0, d20, d40, p40.damage, p60.damage])
	_check(d0 < d20 and d20 < d40, "Schaden steigt mit der Geschwindigkeit")
	_check(d40 / d20 > 2.0 * 0.9, "ueberproportional (40 vs 20 m/s: x%.2f)" % (d40 / d20))
	_check(p40.is_plunge and p40.damage > d40 * 3.0, "Sturzflug von oben = High-Hit (x%.1f vs flach)" % (p40.damage / d40))
	_check(p60.damage > p40.damage * 3.0, "exponentiell mit Fallgeschwindigkeit (x%.1f)" % (p60.damage / p40.damage))
	_check(not k.compute_damage(Vector3(0, -40, -60)).is_plunge, "flacher Vorbeiflug zaehlt nicht als Sturzflug")


func _test_aim_and_lock() -> void:
	print("Auto-Aim & Target-Lock")
	var d := _dummy_near(Vector3(0, 1, -40))
	await _place(Vector3(2.0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	_check(g.lock_target == d, "Lock-Kegel erfasst Dummy trotz Versatz")
	_check(g.aim_kind != GuardianController.AimKind.ENEMY, "RMB-Seil rastet NICHT auf den Gegner ein")
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, 4, 0))
	var space := g.get_world_3d().direct_space_state
	var missed := false
	for i in 200:
		g._yaw += 0.002
		await _process_frames(1)
		await _frames(1)
		var cam := g.camera.global_position
		var fwd := g.aim_forward()
		var start := cam + fwd * maxf((g.global_position - cam).dot(fwd), 0.0)
		if g._ray(space, start, start + fwd * g.grapple_range).is_empty():
			missed = true
			break
	g._yaw += 0.01
	await _process_frames(1)
	await _frames(2)
	_check(missed and g.aim_kind == GuardianController.AimKind.POINT and g.aim_assisted,
			"Turmkante knapp verfehlt -> unsichtbarer Assist rastet ein")


func _test_taut_rope_base_pull() -> void:
	print("Straffes Seil & Base-Pull (0.4)")
	var r := await _grapple_tower("", 60)
	var base: float = g.reel_speed * g.reel_base_mult
	_check(absf(r.approach - base) < 2.5, "zieht gleichmaessig mit Basis-Speed ein (%.1f / %.1f m/s)" % [r.approach, base])
	_check(r.max_slack < 0.05, "Seil laesst nie nach (max. Durchhang %.2f m)" % r.max_slack)
	_check(r.max_jolt < 4.0, "kein wildes Wegreissen (max. %.1f m/s pro Frame)" % r.max_jolt)
	await _frames(180)
	var h := _active_hook()
	_check(h != null and h.active, "Seil loest sich nicht von selbst (nach 4 s)")
	var dist := g.global_position.distance_to(h.pivot()) if h else INF
	_check(dist < g.hang_length + 3.0, "haengt am Ende nah am Anker (%.1f m, pendelt frei)" % dist)
	_check(g.velocity.length() < 25.0, "kein Glitschen / Wegschleudern am Anker (%.1f m/s)" % g.velocity.length())
	Input.action_release("grapple")
	await _frames(2)
	_check(h.slack and not g.any_hook_active(), "Loslassen: sofort locker (Doppel-Tap-Fenster)")
	await _frames(int(g.double_tap_window * 60.0) + 3)
	_check(g.hooks_out() == 0, "nach dem Fenster komplett geloest")
	await _frames(120)


func _test_turbo_pull() -> void:
	print("Turbo-Einzug (W am Seil)")
	var b := await _grapple_tower("", 40)
	Input.action_release("grapple")
	await _frames(20)
	var t := await _grapple_tower("move_forward", 40)
	_check(t.turbo_seen, "W am Seil schaltet auf Turbo")
	var ratio: float = t.approach / maxf(b.approach, 0.01)
	_check(ratio > 2.2 and ratio < 2.8, "Turbo = %.2fx Basis (%.1f vs %.1f m/s)" % [ratio, t.approach, b.approach])
	_check(t.covered > b.covered * 1.8, "zieht deutlich schneller heran (%.1f m vs %.1f m)" % [t.covered, b.covered])
	_release_all()
	await _frames(int(g.double_tap_window * 60.0) + 3)
	await _frames(120)


func _test_brake() -> void:
	print("Bremse (S am Seil)")
	var r := await _grapple_tower("move_back", 60)
	_check(r.brake_seen, "S am Seil bremst die Winde")
	_check(r.approach < g.reel_speed * g.reel_brake_mult + 1.0,
			"Winde fast still (%.1f m/s, Basis %.1f)" % [r.approach, g.reel_speed * g.reel_base_mult])
	_check(r.max_slack < 0.1, "Seil bleibt dabei straff (max. Durchhang %.2f m)" % r.max_slack)
	_release_all()
	await _frames(int(g.double_tap_window * 60.0) + 3)
	await _frames(120)


func _test_rope_steering() -> void:
	print("WASD am Seil")
	var lat := []
	for steer in ["", "move_left", "move_right"]:
		await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
		var t := _closest_tower()
		_aim_at(t.pos + Vector3(0, t.size.y * 0.3, 0))
		await _process_frames(2)
		await _frames(3)
		var right := g.cam_rig.global_basis.x
		var p0 := g.global_position
		Input.action_press("grapple")
		if steer != "":
			Input.action_press(steer)
		await _frames(45)
		lat.append((g.global_position - p0).dot(right))
		_release_all()
		await _frames(int(g.double_tap_window * 60.0) + 3)
		await _frames(90)
	_check(lat[1] < lat[0] - 1.5 and lat[2] > lat[0] + 1.5,
			"A/D lenken die Flugbahn (links %.1f | neutral %.1f | rechts %.1f m)" % [lat[1], lat[0], lat[2]])


func _test_dual_hooks() -> void:
	print("Dual-Hooks (Doppel-Tap)")
	_first_person(true)
	await _place(Vector3(-60, 4.0, 100), 0.0, 0.0)
	_aim_at(Vector3(-62.5, 9.0, 97.0))
	await _process_frames(2)
	await _frames(1)
	Input.action_press("grapple")
	await _frames(4)
	Input.action_release("grapple")
	await _frames(2)
	_aim_at(Vector3(-57.5, 9.0, 103.0))
	await _process_frames(2)
	await _frames(1)
	Input.action_press("grapple")
	await _frames(2)
	_check(g.hooks_out() == 2 and g.hook_left.active and g.hook_right.active,
			"Doppel-Tap: beide Hueft-Haken draussen")
	_check(not g.hook_left.slack and not g.hook_right.slack, "beide Seile straff")
	Input.action_press("move_forward")
	await _frames(2)
	_check(g.is_turbo(), "W-Turbo wirkt auch mit zwei Haken")
	Input.action_release("move_forward")
	await _frames(25)  # einpendeln (inkl. Aufprall an der Decke)
	var jitter := 0.0
	var prev := g.velocity
	for i in 40:
		await physics_frame
		jitter = maxf(jitter, (g.velocity - prev).length())
		prev = g.velocity
	_check(jitter < 1.5, "zwei Seile kaempfen nicht gegeneinander (max. dv %.2f m/s)" % jitter)
	_check(g.get("dual_mode") == null and g.get("slingshot_charge") == null, "kein Slingshot/Nest mehr im Code")
	Input.action_release("grapple")
	await _frames(int(g.double_tap_window * 60.0) + 3)
	_check(g.hooks_out() == 0, "Loslassen loest beide Haken")
	await _frames(60)
	_first_person(false)


func _test_hip_alternation() -> void:
	print("Hueft-Wechsel links/rechts")
	var used := []
	for i in 2:
		await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
		var t := _closest_tower()
		_aim_at(t.pos + Vector3(0, t.size.y * 0.3, 0))
		await _process_frames(2)
		await _frames(3)
		Input.action_press("grapple")
		await _frames(2)
		used.append(_active_hook())
		Input.action_release("grapple")
		await _frames(int(g.double_tap_window * 60.0) + 3)
	_check(used[0] != null and used[1] != null and used[0] != used[1],
			"Klicks wechseln zwischen linker und rechter Huefte")


func _test_hard_lock_toggle() -> void:
	print("Hard-Lock (Mausrad-Klick / R3)")
	var d := _dummy_near(Vector3(0, 1, -40))
	await _place(Vector3(0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	_check(InputMap.has_action("hard_lock") and not InputMap.has_action("target_lock"), "Lock liegt auf eigener Taste (Tab entfernt)")
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Mausrad-Klick rastet das Ziel ein")
	g._yaw += 0.6
	await _process_frames(2)
	await _frames(3)
	_check(g.hard_lock == d, "Lock haelt, auch wenn das Fadenkreuz wegschaut")
	await _action_event("hard_lock")
	_check(g.hard_lock == null, "erneuter Klick loest den Hard-Lock")


func _test_lock_cycling_giant() -> void:
	print("Ziel-Wechsel per Mausrad (Riese)")
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	await _place(Vector3(0, 6.0, -62.0), 0.0, 0.0)
	_aim_at(giant.global_position + Vector3(0, 9.5, 1.3))
	await _process_frames(2)
	await _frames(3)
	var cands := g.lock_candidates()
	var labels := []
	for c in cands:
		if c is LockPoint:
			labels.append((c as LockPoint).label)
	print("    sichtbare Punkte: ", labels)
	_check(labels.size() >= 4, "Riese bietet mehrere anvisierbare Punkte (%d)" % labels.size())
	_check(not labels.has("Nacken"), "Nacken von vorne verdeckt (Sichtlinie)")
	await _action_event("lock_next")
	var first := g.hard_lock
	_check(first is LockPoint, "erster Scroll rastet einen Punkt ein (%s)" % _lname(first))
	var seen := {}
	for i in cands.size():
		seen[_lname(g.hard_lock)] = true
		await _action_event("lock_next")
	_check(seen.size() == cands.size(), "Mausrad schaltet durch alle Punkte (%d)" % seen.size())
	_check(g.hard_lock == first, "nach einer Runde wieder am Anfang (Wrap)")
	await _action_event("lock_prev")
	_check(g.hard_lock != first, "Mausrad hoch schaltet zurueck (%s)" % _lname(g.hard_lock))
	await _action_event("hard_lock")


func _test_lock_slash_loop() -> void:
	print("Combat-Grapple & Slash-Loop (LMB mit Hard-Lock)")
	var d := _dummy_near(Vector3(0, 1, -40))
	await _place(Vector3(0, 26.0, -33.0), 0.0, 0.0)
	_aim_at(d.get_lock_point())
	await _process_frames(2)
	await _frames(3)
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Ziel von oben im Hard-Lock")
	var hits := d.hits_taken
	Input.action_press("attack")
	await _frames(2)
	_check(g.combat_hook() != null and g.knife.phase == KnifeCombat.Phase.IDLE,
			"LMB halten: Seil zum Ziel, noch kein Schlag")
	Input.action_press("move_forward")  # W-Turbo in den Sturzflug
	var released := false
	for i in 120:
		await physics_frame
		if g.global_position.distance_to(d.get_lock_point()) < 3.2:
			Input.action_release("attack")
			released = true
			break
	Input.action_release("move_forward")
	await _frames(12)
	_check(released, "Guardian wird zum Ziel herangezogen")
	_check(g.combat_hook() == null, "LMB loslassen loest das Combat-Seil")
	_check(d.hits_taken > hits, "Schlag im Anflug trifft")
	var lh: Dictionary = g.knife.last_hit
	_check(not lh.is_empty() and lh.is_plunge and lh.damage > 100.0,
			"High-Speed-Sturzflug = High-Hit (%.0f Schaden, Plunge x%.1f)" % [lh.get("damage", 0.0), lh.get("plunge_mult", 0.0)])
	await _action_event("hard_lock")
	await _frames(120)


func _test_giant_point_hit() -> void:
	print("Lock-Punkt-Treffer am Riesen")
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	await _place(Vector3(0, 8.0, -70.0), 0.0, 0.0)
	var chest: LockPoint = giant.find_child("LP_Brust", true, false)
	_aim_at(chest.global_position)
	await _process_frames(2)
	await _frames(3)
	await _action_event("hard_lock")
	if g.hard_lock != chest:
		g.hard_lock = chest  # Kegel kann einen Nachbarpunkt bevorzugen
	var hits := giant.hits_taken
	Input.action_press("attack")
	for i in 150:
		await physics_frame
		if g.global_position.distance_to(chest.global_position) < 3.0:
			break
	Input.action_release("attack")
	await _frames(12)
	_check(giant.hits_taken > hits, "Riese nimmt Schaden ueber den Lock-Punkt")
	_check(g.knife.last_hit.get("point", "") == "Brust", "Treffer wird dem Punkt zugeordnet (%s)" % g.knife.last_hit.get("point", "-"))
	await _action_event("hard_lock")
	await _frames(90)


func _test_hitbox_alignment() -> void:
	print("Hitbox-Ausrichtung")
	var d := _dummy_near(Vector3(0, 1, -40))
	var shape: CollisionShape3D = d.get_node("Shape")
	_check(d.get_lock_point().distance_to(shape.global_position) < 0.001,
			"Dummy-Lock-Punkt = Mitte der Kollisions-Kapsel")
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	var chest: LockPoint = giant.find_child("LP_Brust", true, false)
	_check(chest != null and chest.get_parent() is CollisionShape3D \
			and chest.get_parent().name == "Shape_Torso", "Riesen-Punkt haengt an der Torso-Hitbox")
	_check(chest != null and chest.get_hit_receiver() == giant, "Punkt leitet Schaden an den Riesen")
	var head: LockPoint = giant.find_child("LP_Kopf", true, false)
	var head_shape: CollisionShape3D = giant.get_node("Shape_Kopf")
	var r := (head_shape.shape as SphereShape3D).radius
	var surf := head.global_position.distance_to(head_shape.global_position)
	_check(surf > r - 0.1 and surf < r + 0.3, "Kopf-Punkt sitzt auf der Kopf-Hitbox (%.2f m / r %.2f)" % [surf, r])


func _test_auto_grab_free_flow() -> void:
	print("Free-Flow Auto-Grab (LMB ohne Hard-Lock)")
	var d := _dummy_near(Vector3(0, 1, -40))
	await _place(Vector3(1.5, 24.0, -33.0), 0.0, 0.0)
	# Fadenkreuz bewusst ~1.5 m neben das Ziel -> grosszuegiger Fang-Kegel muss greifen.
	_aim_at(d.get_lock_point() + Vector3(1.5, 0.8, 0))
	await _process_frames(2)
	await _frames(3)
	_check(g.hard_lock == null, "kein Hard-Lock aktiv")
	_check(g.auto_grab_target == d, "Fadenkreuz nahe am Gegner = Auto-Grab-Ziel")
	var hits := d.hits_taken
	Input.action_press("attack")
	await _frames(2)
	var ch := g.combat_hook()
	_check(ch != null and ch.target == d and g.knife.phase == KnifeCombat.Phase.IDLE,
			"LMB halten: Seil greift den Gegner ohne Lock, noch kein Schlag")
	var released := false
	for i in 150:
		await physics_frame
		if g.global_position.distance_to(d.get_lock_point()) < 3.2:
			Input.action_release("attack")
			released = true
			break
	await _frames(12)
	_check(released, "Auto-Grab zieht zum Gegner heran")
	_check(g.combat_hook() == null, "LMB loslassen loest das Seil")
	var lh: Dictionary = g.knife.last_hit
	_check(d.hits_taken > hits and lh.get("speed", 0.0) > 15.0
			and lh.get("damage", 0.0) > g.knife.min_damage * 5.0,
			"Momentum-Slash trifft (%.0f Schaden bei %.0f m/s, Plunge x%.1f)"
			% [lh.get("damage", 0.0), lh.get("speed", 0.0), lh.get("plunge_mult", 0.0)])
	_check(lh.get("is_plunge", false), "Sturz von oben zaehlt als Plunge (Dive-Winkel)")
	_revive(d)
	# Kein Ziel unterm Fadenkreuz -> normaler Slash, kein Seil
	await _place(Vector3(0, 1.2, 0), 0.0, 1.2)
	await _tap("attack")
	await _frames(2)
	_check(g.combat_hook() == null and g.knife.is_attacking(), "ohne Ziel: LMB = normaler Slash")
	await _frames(40)


func _test_auto_grab_hold() -> void:
	print("Auto-Grab beim Halten")
	var d := _dummy_near(Vector3(0, 1, -40))
	await _place(Vector3(0, 1.2, -12.0), 0.0, 1.2)  # Blick in den Himmel
	Input.action_press("attack")
	await _frames(3)
	_check(g.combat_hook() == null, "LMB gehalten, noch kein Ziel")
	_aim_at(d.get_lock_point())
	await _process_frames(2)
	await _frames(3)
	var ch := g.combat_hook()
	_check(ch != null and ch.target == d, "Ziel kommt ins Fadenkreuz -> Seil greift sofort")
	Input.action_release("attack")
	await _frames(40)


func _test_hard_lock_camera() -> void:
	print("Hard-Lock-Kamera")
	var d := _dummy_near(Vector3(0, 1, -40))
	var hud = arena.get_node("HUD")
	_check(hud.get("_lock") == null and hud.reticle is LockReticle, "Lock-UI = reiner Rahmen ohne Text-Label")
	await _place(Vector3(0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Ziel eingerastet")
	# Freies Umsehen wird ueberschrieben: Kamera dreht zurueck aufs Ziel.
	g._yaw += 0.9
	g._pitch += 0.4
	Input.action_press("look_right")
	await _process_frames(90)
	Input.action_release("look_right")
	var err := _cam_error_deg(d.get_lock_point())
	_check(err < 1.0, "Kamera bleibt auf das Ziel gerichtet (%.2f°)" % err)
	_check(g.hard_lock_in_range() and hud.reticle.visible and hud.reticle.in_range
			and hud.reticle.current_color() == LockReticle.COL_IN_RANGE, "Rahmen farbig in Reichweite")
	var center: Vector2 = g.get_viewport().get_visible_rect().size * 0.5
	var proj := g.camera.unproject_position(d.get_node("Shape").global_position)
	_check(hud.reticle.center.distance_to(proj) < 0.5, "Rahmen sitzt exakt auf der Hitbox-Mitte")
	_check(hud.reticle.center.distance_to(center) < 6.0,
			"Hitbox liegt unterm Fadenkreuz (%.1f px)" % hud.reticle.center.distance_to(center))
	# Ziel-Wechsel am Riesen: Kamera folgt dem neuen Punkt
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	await _action_event("hard_lock")
	await _place(Vector3(0, 6.0, -62.0), 0.0, 0.0)
	_aim_at(giant.global_position + Vector3(0, 9.5, 1.3))
	await _process_frames(2)
	await _frames(3)
	await _action_event("lock_next")
	var a := g.hard_lock
	await _action_event("lock_next")
	var b := g.hard_lock
	await _process_frames(90)
	err = _cam_error_deg(g._lock_point_of(b))
	_check(a != b and b is LockPoint and err < 1.0,
			"Mausrad wechselt Punkt, Kamera folgt (%s -> %s, %.2f°)" % [_lname(a), _lname(b), err])
	var order := []
	for i in 6:
		order.append(_lname(g.hard_lock))
		await _action_event("lock_next")
		await _process_frames(20)
	var uniq := {}
	for n in order:
		uniq[n] = true
	_check(uniq.size() >= 4, "Wechsel bleibt stabil trotz mitdrehender Kamera (%s)" % ", ".join(order))
	await _action_event("hard_lock")


func _test_hard_lock_out_of_range() -> void:
	print("Hard-Lock ausserhalb der Reichweite")
	var d := _dummy_near(Vector3(0, 1, -40))
	var hud = arena.get_node("HUD")
	await _place(Vector3(0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Ziel eingerastet")
	await _place(Vector3(0, 1.2, 42.0), 0.0, 0.0)  # 82 m entfernt
	await _process_frames(90)
	await _frames(5)
	var dist := g.global_position.distance_to(d.get_lock_point())
	_check(g.hard_lock == d, "Lock bleibt bei %.0f m (Reichweite %.0f m)" % [dist, g.grapple_range])
	_check(not g.hard_lock_in_range() and hud.reticle.visible and not hud.reticle.in_range
			and hud.reticle.current_color() == LockReticle.COL_OUT_OF_RANGE, "Rahmen grau ausserhalb der Reichweite")
	var err := _cam_error_deg(d.get_lock_point())
	_check(err < 1.0, "Kamera bleibt auch ausser Reichweite auf dem Ziel (%.2f°)" % err)
	Input.action_press("attack")
	await _frames(3)
	_check(g.combat_hook() == null, "kein Seil ausserhalb der Reichweite")
	# zurueck in Reichweite, LMB noch gehalten -> Seil greift
	g.global_position = Vector3(0, 1.2, -12.0)
	g.reset_physics_interpolation()
	await _process_frames(2)
	await _frames(3)
	var ch := g.combat_hook()
	_check(ch != null and ch.target == d and hud.reticle.in_range, "zurueck in Reichweite: Rahmen farbig, Seil greift")
	Input.action_release("attack")
	await _frames(10)
	await _action_event("hard_lock")
	_check(g.hard_lock == null, "Klick loest den Lock")
	await _frames(60)


func _test_rope_bending() -> void:
	print("Seil-Bending")
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, t.size.y * 0.3, 0))
	await _process_frames(2)
	await _frames(3)
	Input.action_press("grapple")
	await _frames(2)
	var h := _active_hook()
	var mid := g.global_position.lerp(h.anchor_world(), 0.4)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = mid
	await _frames(2)
	_check(h.has_bends(), "Seil knickt am Hindernis (%d Knick)" % h.bends.size())
	var ex: Array[RID] = [g.get_rid()]
	var pivot := h.pivot()
	var q := PhysicsRayQueryParameters3D.create(g.global_position, pivot, 1, ex)
	var hit := g.get_world_3d().direct_space_state.intersect_ray(q)
	_check(hit.is_empty() or (hit.position as Vector3).distance_to(pivot) < 0.5,
			"freie Linie Spieler -> Pivot (kein Durchschneiden)")
	Input.action_release("grapple")
	wall.queue_free()
	await _frames(90)


func _test_wallrun() -> void:
	print("Wall-Run")
	await _place(Vector3(14.9, 4.0, -18.0), 0.0, 0.0)
	g.velocity = Vector3(2.0, 2.0, -14.0)
	Input.action_press("move_forward")
	Input.action_press("move_right")
	var ran := false
	for i in 30:
		await physics_frame
		if g.state == GuardianController.State.WALLRUN:
			ran = true
			break
	_check(ran, "Wall-Run startet an der Wand")
	await _frames(20)
	_check(g.state == GuardianController.State.WALLRUN and g.global_position.y > 2.0,
			"Wall-Run haelt die Hoehe (y=%.1f)" % g.global_position.y)
	await _tap("jump")
	_check(g.state == GuardianController.State.NORMAL and g.velocity.x < -5.0,
			"Wall-Jump stoesst ab (vx=%.1f)" % g.velocity.x)
	_release_all()


# --- Helpers --------------------------------------------------------------
## Seil an den naechsten Turm, n Frames halten. Misst Annaeherung, Durchhang, Ruck.
func _grapple_tower(key: String, n: int) -> Dictionary:
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, t.size.y * 0.3, 0))
	await _process_frames(2)
	await _frames(3)
	var a := g.aim_point
	var d0 := g.global_position.distance_to(a)
	Input.action_press("grapple")
	await _frames(2)
	if key != "":
		Input.action_press(key)
	var h := _active_hook()
	var max_slack := 0.0
	var max_jolt := 0.0
	var turbo_seen := false
	var brake_seen := false
	var prev := g.velocity
	var approach_sum := 0.0
	var approach_n := 0
	for i in n:
		await physics_frame
		turbo_seen = turbo_seen or g.is_turbo()
		brake_seen = brake_seen or g.is_braking()
		var dist := g.global_position.distance_to(h.pivot())
		max_slack = maxf(max_slack, h.rope_length - dist)
		if i > 10:
			max_jolt = maxf(max_jolt, (g.velocity - prev).length())
			if dist > g.hang_length + 4.0:
				approach_sum += g.velocity.dot((h.pivot() - g.global_position).normalized())
				approach_n += 1
		prev = g.velocity
	return {
		"approach": approach_sum / maxf(approach_n, 1),
		"covered": d0 - g.global_position.distance_to(a),
		"max_slack": max_slack, "max_jolt": max_jolt, "turbo_seen": turbo_seen, "brake_seen": brake_seen,
	}


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	_release_all()
	g._release_all_hooks()
	g.global_position = pos
	g.velocity = Vector3.ZERO
	g._yaw = yaw
	g._pitch = pitch
	g._vel_history.clear()
	g._set_state(GuardianController.State.NORMAL)
	g.reset_physics_interpolation()
	await _process_frames(2)
	await _frames(2)


func _aim_at(p: Vector3) -> void:
	var cam := g.global_position + Vector3.UP * (g.fp_height if g.first_person else g.tp_height)
	var v := p - cam
	g._yaw = atan2(-v.x, -v.z)
	g._pitch = atan2(v.y, Vector2(v.x, v.z).length())


func _action_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _process_frames(1)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _process_frames(1)
	await _frames(1)


## Winkel zwischen Kamera-Blick (Fadenkreuz) und Richtung Kamera -> Punkt.
func _cam_error_deg(p: Vector3) -> float:
	var v := p - g.camera.global_position
	return rad_to_deg(g.aim_forward().angle_to(v.normalized()))


## Dummy nach einem K.o.-Treffer sofort wieder aufstellen.
func _revive(d: TrainingDummy) -> void:
	d.hp = d.max_hp
	d._down_t = 0.0
	d._mesh.visible = true
	d._update_label()


func _lname(n: Node) -> String:
	if n is LockPoint:
		return (n as LockPoint).label
	return n.name if n else "-"


func _active_hook() -> GrappleHook:
	for h in g.hooks:
		if h.active:
			return h
	return null


func _first_person(on: bool) -> void:
	if g.first_person != on:
		g.toggle_camera()
	g._cam_blend = 1.0 if on else 0.0


func _dummy_near(p: Vector3) -> TrainingDummy:
	for c in arena.get_children():
		if c is TrainingDummy and (c as Node3D).global_position.distance_to(p) < 1.0:
			return c
	return null


func _closest_tower() -> Dictionary:
	var best := {}
	var best_d := INF
	for b: Dictionary in arena._boxes:
		if b.size.y > 20.0 and b.size.x > 3.5:
			var d: float = (b.pos as Vector3).length()
			if d < best_d:
				best_d = d
				best = b
	return best


func _tap(action: String, frames := 2) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump",
			"attack", "grapple"]:
		Input.action_release(a)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _process_frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, label: String) -> void:
	print(("  [OK]   " if ok else "  [FAIL] ") + label)
	if not ok:
		_fails += 1
