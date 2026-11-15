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
	await _test_rope_steering()
	await _test_dual_hooks()
	await _test_hip_alternation()
	await _test_target_lock_dive()
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
	_check(not g.is_turbo(), "Shift am Boden ohne Seil = Sprint, kein Turbo")
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
	_check(g.lock_target == d, "Lock-Kegel erfasst Dummy trotz Versatz (Tab)")
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
	print("Straffes Seil & Base-Pull (0.5x)")
	var r := await _grapple_tower(false, 60)
	var base: float = g.reel_speed * g.reel_base_mult
	_check(absf(r.approach - base) < 2.5, "zieht gleichmaessig mit Basis-Speed ein (%.1f / %.1f m/s)" % [r.approach, base])
	_check(r.max_slack < 0.05, "Seil laesst nie nach (max. Durchhang %.2f m)" % r.max_slack)
	_check(r.max_jolt < 4.0, "kein wildes Wegreissen (max. %.1f m/s pro Frame)" % r.max_jolt)
	await _frames(180)
	var h := _active_hook()
	_check(h != null and h.active, "Seil loest sich nicht von selbst (nach 4 s)")
	var dist := g.global_position.distance_to(h.pivot()) if h else INF
	_check(dist < g.hang_length + 1.5, "haengt am Ende ruhig am Anker (%.1f m)" % dist)
	_check(g.velocity.length() < 25.0, "kein Glitschen / Wegschleudern am Anker (%.1f m/s)" % g.velocity.length())
	Input.action_release("grapple")
	await _frames(2)
	_check(h.slack and not g.any_hook_active(), "Loslassen: sofort locker (Doppel-Tap-Fenster)")
	await _frames(int(g.double_tap_window * 60.0) + 3)
	_check(g.hooks_out() == 0, "nach dem Fenster komplett geloest")
	await _frames(120)


func _test_turbo_pull() -> void:
	print("Turbo-Pull (Shift am Seil)")
	var b := await _grapple_tower(false, 40)
	Input.action_release("grapple")
	await _frames(20)
	var t := await _grapple_tower(true, 40)
	_check(t.turbo_seen, "Shift am Seil schaltet auf Turbo")
	var ratio: float = t.approach / maxf(b.approach, 0.01)
	_check(ratio > 2.4 and ratio < 3.1, "Turbo = %.2fx Basis (%.1f vs %.1f m/s)" % [ratio, t.approach, b.approach])
	_check(t.covered > b.covered * 2.0, "zieht mit Wucht heran (%.1f m vs %.1f m)" % [t.covered, b.covered])
	Input.action_release("grapple")
	Input.action_release("sprint")
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
	Input.action_press("sprint")
	await _frames(2)
	_check(g.is_turbo(), "Turbo-Pull wirkt auch mit zwei Haken")
	Input.action_release("sprint")
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


func _test_target_lock_dive() -> void:
	print("Target-Lock / Combat-Grapple (Tab)")
	var d := _dummy_near(Vector3(0, 18, -60))
	await _place(Vector3(0, 1.2, -30), 0.0, 0.0)
	_aim_at(d.get_lock_point())
	await _process_frames(2)
	await _frames(3)
	_check(g.lock_target == d, "Ziel im Lock")
	var hits := d.hits_taken
	await _tap("target_lock")
	var dived := false
	for i in 150:
		await physics_frame
		var ch := g.combat_hook()
		if ch and ch.phase == GrappleHook.Phase.DIVE:
			dived = true
		if d.hits_taken > hits:
			break
	await _frames(1)
	_check(dived, "Sturzangriff von oben ausgeloest")
	_check(d.hits_taken > hits, "Sturzangriff trifft")
	var lh: Dictionary = g.knife.last_hit
	_check(not lh.is_empty() and lh.is_plunge and lh.damage > 100.0,
			"High-Hit mit Plunge-Bonus (%.0f Schaden, x%.1f)" % [lh.get("damage", 0.0), lh.get("plunge_mult", 0.0)])
	_check(g.combat_hook() == null and g.velocity.y > 5.0, "Abprall nach oben, Angriff abgeschlossen")
	await _frames(120)


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
func _grapple_tower(turbo: bool, n: int) -> Dictionary:
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, t.size.y * 0.3, 0))
	await _process_frames(2)
	await _frames(3)
	var a := g.aim_point
	var d0 := g.global_position.distance_to(a)
	Input.action_press("grapple")
	await _frames(2)
	if turbo:
		Input.action_press("sprint")
	var h := _active_hook()
	var max_slack := 0.0
	var max_jolt := 0.0
	var turbo_seen := false
	var prev := g.velocity
	var approach_sum := 0.0
	var approach_n := 0
	for i in n:
		await physics_frame
		turbo_seen = turbo_seen or g.is_turbo()
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
		"max_slack": max_slack, "max_jolt": max_jolt, "turbo_seen": turbo_seen,
	}


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	_release_all()
	g._release_all_hooks()
	g.global_position = pos
	g.velocity = Vector3.ZERO
	g._yaw = yaw
	g._pitch = pitch
	g._set_state(GuardianController.State.NORMAL)
	g.reset_physics_interpolation()
	await _process_frames(2)
	await _frames(2)


func _aim_at(p: Vector3) -> void:
	var cam := g.global_position + Vector3.UP * (g.fp_height if g.first_person else g.tp_height)
	var v := p - cam
	g._yaw = atan2(-v.x, -v.z)
	g._pitch = atan2(v.y, Vector2(v.x, v.z).length())


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
			"attack", "grapple", "target_lock"]:
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
