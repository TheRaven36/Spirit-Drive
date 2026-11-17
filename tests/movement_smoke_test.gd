extends SceneTree
## Headless-Smoke-Test fuer den Guardian (Movement, Kamera, Seile, Lock, Messer).
## Aufruf: godot --headless --path . --script res://tests/movement_smoke_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

const BOOST_SPOT := Vector3(0, 80, 0)

var _fails := 0
var arena: Node
var g: GuardianController


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	arena = load("res://scenes/test_arena.tscn").instantiate()
	root.add_child(arena)
	g = arena.get_node("Guardian")
	# Feld-Spirit stilllegen: sein Bodyguard-Angriff wuerde die Dummy-Messungen verfaelschen
	# (eigener Test: tests/spirit_entity_test.gd).
	g.get_node("SpiritEntity").process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(30)

	await _test_basic_movement()
	await _test_camera_toggle()
	await _test_knife()
	await _test_damage_curve()
	await _test_aim_and_lock()
	await _test_taut_rope_base_pull()
	await _test_turbo_pull()
	await _test_rigid_rope()
	await _test_rope_steering()
	await _test_dual_hooks()
	await _test_dual_force_sum()
	await _test_hip_alternation()
	await _test_hard_lock_toggle()
	await _test_lock_cycling_giant()
	await _test_lock_slash_loop()
	await _test_giant_point_hit()
	await _test_hitbox_alignment()
	await _test_auto_grab_free_flow()
	await _test_auto_grab_hold()
	await _test_enemy_carve_single_vs_dual()
	await _test_lmb_double_click()
	await _test_rmb_double_tap_enemy()
	await _test_giant_double_click_pierce()
	await _test_hard_lock_camera()
	await _test_hard_lock_out_of_range()
	await _test_free_camera_while_swinging()
	await _test_high_speed_hit_window()
	await _test_boss_damage_scaling()
	await _test_piercing_falloff()
	await _test_rope_bending()
	await _test_wallrun()
	await _test_attack_reel_boost()
	await _test_cave()

	print("SMOKE TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


# --- Tests ----------------------------------------------------------------
## Additiver Anflug-Schub: 50 m Combat-Anflug auf den Hard-Lock, Start 100 m/s (Tempo-Deckel
## dafuer kurz angehoben). Liefert die Geschwindigkeit beim Erreichen des Ziels.
func _boost_run(angle_deg: float, boost: float) -> float:
	var target := _dummy_near(Vector3(25, 12, 15))
	target.global_position = BOOST_SPOT  # freier Luftraum ueber allen Tuermen
	var goal := target.get_lock_point()
	var dir := Vector3(0, sin(deg_to_rad(angle_deg)), -cos(deg_to_rad(angle_deg)))
	await _place(goal - dir * 50.0, 0.0, 0.0)
	g.attack_reel_boost_accel = boost
	g.hard_lock = target
	g.velocity = dir * 100.0
	g._fire_combat_hook(target)
	var v0 := g.velocity.length()
	var v_end := 0.0
	for i in 60:
		await physics_frame
		v_end = g.velocity.length()
		if g.global_position.distance_to(goal) < 4.0:
			break
	g._release_all_hooks()
	g.release_hard_lock()
	target.global_position = Vector3(25, 12, 15)
	_revive(target)
	return v_end / v0 * 100.0  # Endtempo bezogen auf 100 m/s Start


func _test_cave() -> void:
	print("Hoehlen-Arena")
	var top: float = arena.max_pillar_height
	var ceil_y: float = arena.ceiling_height
	_check(top > 40.0 and is_equal_approx(ceil_y, 3.0 * top),
			"Decke auf 3 x hoechster Saeule (%.1f m = 3 x %.1f m)" % [ceil_y, top])
	var up := _cast(Vector3(0, 10, 0), Vector3(0, ceil_y + 20.0, 0))
	_check(not up.is_empty() and absf(up.position.y - ceil_y) < 0.05, "Decke hat Collision (Grapple-Anker)")
	var walls := 0
	for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var hit := _cast(Vector3(0, ceil_y - 5.0, 0), dir * 400.0 + Vector3(0, ceil_y - 5.0, 0))
		if not hit.is_empty() and absf((hit.position as Vector3).dot(dir) - arena.CAVE_HALF) < 0.05:
			walls += 1
	_check(walls == 4, "rundum geschlossene Waende bis unter die Decke (%d/4)" % walls)
	var megas := 0
	for m: Array in arena.MEGA_PILLARS:
		var c := Vector3(m[0], 0, m[1])
		var low := _cast(c + Vector3(30, 2, 0), c + Vector3(0, 2, 0))
		var high := _cast(c + Vector3(30, ceil_y - 2.0, 0), c + Vector3(0, ceil_y - 2.0, 0))
		if not low.is_empty() and not high.is_empty():
			megas += 1
	_check(megas >= 2 and megas <= 3, "%d Mega-Saeulen Boden -> Decke" % megas)
	var tite: Array = arena.STALACTITES[0]
	var under := _cast(Vector3(tite[0], 5, tite[1]), Vector3(tite[0], ceil_y + 5.0, tite[1]))
	_check(not under.is_empty() and absf(under.position.y - (ceil_y - tite[3])) < 0.05,
			"Stalaktit haengt %.0f m von der Decke" % tite[3])
	var mite: Array = arena.STALAGMITES[0]
	var over := _cast(Vector3(mite[0], ceil_y - 1.0, mite[1]), Vector3(mite[0], -1, mite[1]))
	_check(not over.is_empty() and absf(over.position.y - mite[3]) < 0.05, "Stalagmit ragt %.0f m auf" % mite[3])
	# Drei Riesen: 1.0x NATURE, 1.4x ORDER, 2.0x CYCLE
	var std: TrainingGiant = arena.get_node("TrainingGiant")
	var big: TrainingGiant = arena.get_node("GiantLarge")
	var titan: TrainingGiant = arena.get_node("TitanColossus")
	_check(std.size_scale == 1.0 and std.get_spirit_pillar() == SpiritData.Pillar.NATURE
			and big.size_scale == 1.4 and big.get_spirit_pillar() == SpiritData.Pillar.ORDER
			and titan.size_scale == 2.0 and titan.get_spirit_pillar() == SpiritData.Pillar.CYCLE,
			"3 Riesen: 1.0x NATURE, 1.4x ORDER, 2.0x CYCLE")
	_check(is_equal_approx(titan.height(), 2.0 * std.height()), "Titan doppelt so hoch (%.1f m)" % titan.height())
	var head := _cast(titan.global_position + Vector3(0, ceil_y - 1.0, 0), titan.global_position)
	_check(not head.is_empty() and absf(head.position.y - titan.height()) < 0.1,
			"Titan-Hitbox skaliert mit (Scheitel bei %.1f m)" % head.position.y)
	var kopf: LockPoint = titan.find_child("LP_Kopf", true, false)
	var std_kopf: LockPoint = std.find_child("LP_Kopf", true, false)
	_check(is_equal_approx(kopf.global_position.y, 2.0 * std_kopf.global_position.y)
			and is_equal_approx(kopf.radius, 2.0 * std_kopf.radius), "Lock-Punkte skaliert (Kopf %.1f m)" % kopf.global_position.y)
	_check(is_equal_approx(titan.max_hp, 2.0 * std.max_hp), "Titan-HP skaliert (%d)" % titan.max_hp)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [g.get_rid()])
	return g.get_world_3d().direct_space_state.intersect_ray(q)


func _test_attack_reel_boost() -> void:
	print("Anflug-Schub (LMB auf Hard-Lock, additiv)")
	var term := g.terminal_speed
	var accel := g.attack_reel_boost_accel
	g.terminal_speed = 500.0
	var flat_off := await _boost_run(0.0, 0.0)
	var flat_on := await _boost_run(0.0, accel)
	_check(absf(flat_off - 100.0) < 2.0, "ohne Schub: Tempo bleibt ~100 (%.1f)" % flat_off)
	_check(flat_on > 107.0 and flat_on < 113.0, "50 m Anflug: 100 -> ~110 (%.1f, +%.0f %%)" % [flat_on, flat_on - 100.0])
	var up_off := await _boost_run(30.0, 0.0)
	var down_off := await _boost_run(-30.0, 0.0)
	var up_on := await _boost_run(30.0, accel)
	var down_on := await _boost_run(-30.0, accel)
	# Schwerkraft-Anteil (v² - Differenz) bleibt mit Schub gleich -> additives Modell.
	var grav_off := down_off * down_off - up_off * up_off
	var grav_on := down_on * down_on - up_on * up_on
	_check(down_on > up_on and up_on > up_off and down_on > down_off,
			"Schub wirkt bergauf (%.1f -> %.1f) und im Sturzflug (%.1f -> %.1f)" % [up_off, up_on, down_off, down_on])
	_check(grav_off > 0.0 and absf(grav_on - grav_off) < grav_off * 0.1,
			"Schwerkraft-Differenz bleibt erhalten (v²: %.0f ohne / %.0f mit Schub)" % [grav_off, grav_on])
	g.terminal_speed = term
	g.attack_reel_boost_accel = accel
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
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


func _test_rigid_rope() -> void:
	print("Starres Seil (S am Seil)")
	var r := await _grapple_tower("move_back", 60)
	_check(r.rigid_seen and g.winch_speed() == 0.0, "S am Seil = starres Seil, Winde steht")
	_check(r.len_drift < 0.001, "Seillaenge bleibt fest, Winde holt nicht ein (Drift %.4f m)" % r.len_drift)
	_release_all()
	await _frames(int(g.double_tap_window * 60.0) + 3)
	await _frames(60)
	# Sauberes Pendel in der Luft: Anker 15 m ueber dem Spieler, 20 m/s seitlich.
	var res_rigid := await _air_swing(true)
	_check(res_rigid.len_drift < 0.001, "Seillaenge bleibt exakt (Drift %.4f m)" % res_rigid.len_drift)
	_check(res_rigid.max_stretch < 0.15, "fester Radius, kein Dehnen (max. %.3f m)" % res_rigid.max_stretch)
	_check(res_rigid.energy_ratio > 0.9 and res_rigid.energy_ratio < 1.05,
			"Schwung bleibt erhalten (Energie %.0f %%)" % (res_rigid.energy_ratio * 100.0))
	_check(res_rigid.swing_deg > 25.0, "pendelt sauber um den Anker (%.0f°)" % res_rigid.swing_deg)
	var res_free := await _air_swing(false)
	_check(res_free.len_drift > 1.0, "zum Vergleich ohne S: Winde holt ein (%.1f m)" % res_free.len_drift)


## Pendel-Messung: Spieler haengt an einem Luft-Anker, optional mit S gehalten.
func _air_swing(hold_s: bool) -> Dictionary:
	await _place(Vector3(0, 70.0, 0), 0.0, 0.0)
	var anchor := g.global_position + Vector3(0, 15.0, 0)
	g.hook_left.attach(anchor, null, g.global_position)
	g._primary = g.hook_left
	g.velocity = Vector3(20.0, 0, 0)
	g._refresh_state()
	if hold_s:
		Input.action_press("move_back")
	await physics_frame
	var h := g.hook_left
	var l0 := h.rope_length
	var e0 := 0.5 * g.velocity.length_squared() + g.gravity * g.global_position.y
	var max_stretch := 0.0
	var len_drift := 0.0
	var start_dir := (g.global_position - anchor).normalized()
	var max_angle := 0.0
	for i in 50:
		await physics_frame
		max_stretch = maxf(max_stretch, g.global_position.distance_to(anchor) - l0)
		len_drift = maxf(len_drift, absf(h.rope_length - l0))
		max_angle = maxf(max_angle, start_dir.angle_to((g.global_position - anchor).normalized()))
	var e1 := 0.5 * g.velocity.length_squared() + g.gravity * g.global_position.y
	Input.action_release("move_back")
	g._release_all_hooks()
	await _place(Vector3(0, 1.2, -10.0), 0.0, 0.0)
	await _frames(20)
	return {"len_drift": len_drift, "max_stretch": max_stretch, "energy_ratio": e1 / e0,
			"swing_deg": rad_to_deg(max_angle)}

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


func _test_dual_force_sum() -> void:
	print("Dual-Hooks: Kraft-Vektorsumme")
	var air := Vector3(0, 70.0, 0)
	# (a) gleicher Anker: doppelte Beschleunigung (Basis und Turbo)
	for turbo in [false, true]:
		var one := await _pull_step(air, [air + Vector3(0, 0, -30)], turbo)
		var two := await _pull_step(air, [air + Vector3(0, 0, -30), air + Vector3(0, 0, -30)], turbo)
		var r_f: float = two.force / maxf(one.force, 0.001)
		var r_a: float = two.accel / maxf(one.accel, 0.001)
		_check(r_f > 1.95 and r_f < 2.05 and r_a > 1.9 and r_a < 2.1,
				"%s: 2 Haken am selben Punkt = %.2fx Kraft, %.2fx Beschleunigung (%.0f vs %.0f m/s²)"
				% ["Turbo" if turbo else "Basis", r_f, r_a, two.accel, one.accel])
	# (b) symmetrisch links/rechts: Querkraft hebt sich auf, Zug entlang der Winkelhalbierenden
	var sym := await _pull_run(air, [air + Vector3(-10, 10, 0), air + Vector3(10, 10, 0)], 30)
	_check(absf(sym.force.x) < 0.01 and sym.force.y > 0.0,
			"links/rechts: Querkraefte heben sich auf (F = %s)" % _vs(sym.force))
	var f_single: float = g.winch_force()
	_check(absf(sym.force.y - 2.0 * f_single * cos(PI / 4.0)) < 0.05 * f_single,
			"gemeinsamer Anteil addiert sich (%.0f ≈ 2·F·cos45° = %.0f m/s²)" % [sym.force.y, 2.0 * f_single * cos(PI / 4.0)])
	_check(absf(sym.vel.x) < 0.05 and absf(sym.disp.x) < 0.05 and sym.disp.y > 1.0,
			"Spieler steigt gerade nach oben (seitlich %.3f m/s, %.3f m)" % [sym.vel.x, sym.disp.x])
	# (c) beliebiger Winkel: Summe = d1 + d2 (gleiche Kraft je Seil)
	var a1 := air + Vector3(-12, 8, -4)
	var a2 := air + Vector3(3, 6, -14)
	var ang := await _pull_step(air, [a1, a2], false)
	var hip_l := air + Vector3(-GuardianController.HIP_SIDE, GuardianController.HIP_UP, 0)  # Yaw 0
	var hip_r := air + Vector3(GuardianController.HIP_SIDE, GuardianController.HIP_UP, 0)
	var expect := ((a1 - hip_l).normalized() + (a2 - hip_r).normalized()) * g.winch_force()
	_check(ang.vec.distance_to(expect) < 0.5,
			"schraeg: F_total = F_links + F_rechts (%s ≈ %s)" % [_vs(ang.vec), _vs(expect)])
	# (d) S mit zwei Seilen: keine Zugkraft, beide Laengen fix, Schwung bleibt
	var rig := await _pull_run(air, [air + Vector3(-10, 15, 0), air + Vector3(10, 15, 0)], 50,
			Vector3(0, 0, 15), "move_back")
	_check(rig.max_force < 0.001, "S: Zugkraft = 0 auf beiden Seilen")
	_check(rig.len_drift < 0.001 and rig.max_stretch < 0.15,
			"S: beide Seillaengen fix (Drift %.4f m, Dehnung %.3f m)" % [rig.len_drift, rig.max_stretch])
	_check(rig.energy_ratio > 0.9 and rig.energy_ratio < 1.05,
			"S: Doppel-Pendel ohne Schwungverlust (Energie %.0f %%)" % (rig.energy_ratio * 100.0))
	# (e) Gameplay: Doppel-Tap auf denselben Pfeiler haengt beide Haken an
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	await _frames(int(g.hook_cooldown * 60.0) + 2)  # beide Werfer nachgeladen
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, t.size.y * 0.3, 0))
	await _process_frames(2)
	await _frames(1)
	Input.action_press("grapple")
	await _frames(4)
	Input.action_release("grapple")
	await _frames(2)
	Input.action_press("grapple")
	await _frames(2)
	_check(g.hooks_out() == 2 and g.hook_left.anchor_world().distance_to(g.hook_right.anchor_world()) < 0.5,
			"Doppel-Tap auf denselben Pfeiler: beide Haken am selben Punkt")
	_release_all()
	await _frames(int(g.double_tap_window * 60.0) + 3)
	await _frames(40)
	# (f) 2x Turbo auf eine Wand: kein Durchtunneln, Tempo gedeckelt
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	t = _closest_tower()
	var aim: Vector3 = t.pos + Vector3(0, t.size.y * 0.3, 0)
	_aim_at(aim)
	await _process_frames(2)
	await _frames(1)
	g._fire_primary_hook()
	g._fire_second_hook()
	_check(g.hooks_out() == 2, "zwei Haken fuer den Turbo-Test")
	Input.action_press("grapple")
	Input.action_press("move_forward")
	var inside := false
	var vmax := 0.0
	for i in 150:
		await physics_frame
		vmax = maxf(vmax, g.velocity.length())
		var l: Vector3 = (g.global_position - t.pos).abs()
		if l.x < t.size.x * 0.5 - 0.05 and l.y < t.size.y * 0.5 and l.z < t.size.z * 0.5 - 0.05:
			inside = true
	Input.action_release("move_forward")
	_check(not inside, "2x Turbo: kein Tunneln durch den Pfeiler")
	_check(vmax <= g.terminal_speed + 0.01, "Tempo bleibt gedeckelt (max. %.1f m/s)" % vmax)
	_release_all()
	await _frames(int(g.double_tap_window * 60.0) + 3)
	await _frames(60)


## Ein Physik-Frame mit Seilen an `anchors` (in der Luft, aus dem Stand). Liefert Zugkraft
## und gemessene Beschleunigung entlang der Kraft (ohne Schwerkraft-Anteil).
func _pull_step(pos: Vector3, anchors: Array, turbo: bool) -> Dictionary:
	await _hang_from(pos, anchors, Vector3.ZERO)
	if turbo:
		Input.action_press("move_forward")
	await physics_frame
	var f := g.pull_force
	var dv := g.velocity + Vector3.UP * g.gravity / 60.0  # Schwerkraft herausrechnen
	Input.action_release("move_forward")
	var res := {"force": f.length(), "vec": f, "accel": dv.dot(f.normalized()) * 60.0}
	await _unhang()
	return res


## Mehrere Frames haengen; misst Kraft, Versatz, Seil-Drift, Energie.
func _pull_run(pos: Vector3, anchors: Array, n: int, v0 := Vector3.ZERO, key := "") -> Dictionary:
	await _hang_from(pos, anchors, v0)
	if key != "":
		Input.action_press(key)
	var start := g.global_position
	var l0 := [g.hook_left.rope_length, g.hook_right.rope_length]
	var e0 := 0.5 * g.velocity.length_squared() + g.gravity * g.global_position.y
	var force := Vector3.ZERO
	var max_force := 0.0
	var len_drift := 0.0
	var max_stretch := 0.0
	for i in n:
		await physics_frame
		if i == 0:
			force = g.pull_force
		max_force = maxf(max_force, g.pull_force.length())
		for j in 2:
			var h: GrappleHook = g.hooks[j]
			len_drift = maxf(len_drift, absf(h.rope_length - l0[j]))
			max_stretch = maxf(max_stretch, g.global_position.distance_to(h.pivot()) - h.rope_length)
	if key != "":
		Input.action_release(key)
	var e1 := 0.5 * g.velocity.length_squared() + g.gravity * g.global_position.y
	var res := {"force": force, "max_force": max_force, "vel": g.velocity,
			"disp": g.global_position - start, "len_drift": len_drift, "max_stretch": max_stretch,
			"energy_ratio": e1 / e0}
	await _unhang()
	return res


func _hang_from(pos: Vector3, anchors: Array, v0: Vector3) -> void:
	await _place(pos, 0.0, 0.0)
	for i in anchors.size():
		var h: GrappleHook = g.hook_left if i == 0 else g.hook_right
		h.attach(anchors[i], null, g.global_position)
	g._primary = g.hook_left
	g.velocity = v0
	g._refresh_state()


func _unhang() -> void:
	g._release_all_hooks()
	await _place(Vector3(0, 1.2, -10.0), 0.0, 0.0)
	await _frames(3)


func _vs(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


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
	print("Ziel-Auswahl (Mausrad-Klick / R3)")
	var d := _dummy_near(Vector3(0, 1, -40))
	await _place(Vector3(0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	_check(InputMap.has_action("hard_lock") and not InputMap.has_action("target_lock"), "Auswahl liegt auf eigener Taste (Tab entfernt)")
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Klick waehlt das Ziel")
	g._yaw += 0.6
	await _process_frames(2)
	await _frames(3)
	_check(g.hard_lock == d, "Auswahl haelt, auch wenn das Fadenkreuz wegschaut")
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "erneuter Klick behaelt die Auswahl (= neuer Snap)")
	Input.action_press("hard_lock")
	await _frames(int(g.lock_clear_hold * 60.0) + 6)
	Input.action_release("hard_lock")
	await _frames(2)
	_check(g.hard_lock == null, "gedrueckt halten loest die Auswahl")
	# Doppelklick auf die bestehende Auswahl loest ebenfalls
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Klick waehlt erneut")
	await _frames(int(g.lock_double_click * 60.0) + 2)
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Einzelklick (nach dem Fenster) behaelt die Auswahl")
	await _action_event("hard_lock")
	_check(g.hard_lock == null, "Doppelklick (< %.1f s) loest die Auswahl" % g.lock_double_click)

func _test_lock_cycling_giant() -> void:
	print("Ziel-Wechsel per Mausrad (Riese)")
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	await _place(Vector3(0, 6.0, -62.0), 0.0, 0.0)
	_aim_at(giant.global_position + Vector3(0, 9.5, 1.3))
	await _process_frames(2)
	await _frames(3)
	var cands := g.lock_candidates()
	var labels := []
	for c in cands:  # nur Punkte DIESES Riesen (die anderen Riesen der Hoehle sind auch sichtbar)
		if c is LockPoint and GuardianController.hit_receiver_of(c) == giant:
			labels.append((c as LockPoint).label)
	print("    sichtbare Punkte: ", labels)
	_check(labels.size() >= 4, "Riese bietet mehrere anvisierbare Punkte (%d)" % labels.size())
	_check(not labels.has("Nacken"), "Nacken von vorne verdeckt (Sichtlinie)")
	await _action_event("lock_next")
	var first := g.hard_lock
	_check(first is LockPoint, "erster Scroll rastet einen Punkt ein (%s)" % _lname(first))
	var seen := {}
	for i in labels.size():
		seen[_lname(g.hard_lock)] = true
		await _action_event("lock_next")
	_check(seen.size() == labels.size(), "Mausrad schaltet durch alle Punkte des Riesen (%d)" % seen.size())
	_check(g.hard_lock == first, "nach einer Runde wieder am Anfang (Wrap)")
	await _action_event("lock_prev")
	_check(g.hard_lock != first, "Mausrad hoch schaltet zurueck (%s)" % _lname(g.hard_lock))
	_check(g.hard_lock is LockPoint, "Wechsel bleibt bei den Punkten des gewaehlten Gegners")
	g.release_hard_lock()


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
	g.release_hard_lock()
	_revive(d)
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
	g.release_hard_lock()
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


func _test_enemy_carve_single_vs_dual() -> void:
	print("Gegner-Anflug: Carving mit einem vs. zwei Seilen")
	var one := await _enemy_carve(1)
	var two := await _enemy_carve(2)
	for r: Dictionary in [one, two]:
		print("    %d Seil(e): Radius %.1f m, Zug %.0f m/s², max. Knick %.1f°/Frame (dv %.1f m/s), Tempo min %.0f %%, "
				% [r.n, r.radius, r.pull, r.max_turn, r.max_dv, r.min_speed * 100.0]
				+ "Abweichung %.1f m, Durchsacken %.1f m, Treffer %s nach %d Frames"
				% [r.dev, r.drop, r.reached, r.frames])
	_check(not one.dual and two.dual, "Doppel-Lock nur mit zwei Seilen am selben Gegner")
	_check(one.max_dv <= one.dv_bound and two.max_dv <= two.dv_bound,
			"kein Snap: jede Aenderung durch Zug + Lenkung erklaerbar (%.1f <= %.1f, %.1f <= %.1f m/s pro Frame)"
			% [one.max_dv, one.dv_bound, two.max_dv, two.dv_bound])
	_check(one.min_speed > 0.95 and two.min_speed > 0.95, "Tempo bleibt im Anflug erhalten (min. %.0f %% / %.0f %%)"
			% [one.min_speed * 100.0, two.min_speed * 100.0])
	_check(two.radius < one.radius * 0.65, "zwei Seile: deutlich engerer Wenderadius (%.1f m vs %.1f m)"
			% [two.radius, one.radius])
	_check(two.pull > one.pull * 1.8, "zwei Seile: ~doppelte Zugbeschleunigung (%.0f vs %.0f m/s²)" % [two.pull, one.pull])
	_check(one.dev > two.dev, "ein Seil schwingt in weiterem Bogen ein")
	_check(one.drop < 1.0 and two.drop < 1.0, "kein Durchsacken waehrend des Zugs")
	_check(one.reached and two.reached and two.frames <= one.frames, "beide treffen, zwei Seile schneller")


## Schneller Quer-Flug neben einem schwebenden Dummy, dann n Combat-Seile (wie LMB-(Doppel)klick).
func _enemy_carve(n: int) -> Dictionary:
	var d := _dummy_near(Vector3(0, 18, -60))
	await _place(Vector3(14, 18, -48), 0.0, 0.0)
	var goal := d.get_lock_point()
	var start := g.global_position
	var line := start.direction_to(goal)
	g.velocity = Vector3(12, 0, -14).normalized() * 22.0  # tangential am Ziel vorbei
	for i in n:
		g._fire_combat_hook(d)
	var speed0 := g.velocity.length()
	var res := {"n": n, "dual": g.is_dual_locked(), "pull": 0.0, "max_turn": 0.0, "max_dv": 0.0, "dv_bound": 0.0, "max_speed": 0.0, "min_speed": 1.0,
			"radius": 0.0, "dev": 0.0, "drop": 0.0, "reached": false, "frames": 0}
	var prev := g.velocity
	var heading0 := g.velocity
	for i in 120:
		await physics_frame
		if i == 0:
			res.pull = g.pull_force.length()
		res.max_turn = maxf(res.max_turn, rad_to_deg(prev.angle_to(g.velocity)))
		res.max_dv = maxf(res.max_dv, prev.distance_to(g.velocity))
		res.max_speed = maxf(res.max_speed, g.velocity.length())
		prev = g.velocity
		if i == 9:  # Wenderadius aus den ersten 10 Frames: r = v / omega
			res.radius = g.velocity.length() / (heading0.angle_to(g.velocity) / (10.0 / 60.0))
		var dist := g.global_position.distance_to(goal)
		if dist > g.hang_length + 1.0:
			res.min_speed = minf(res.min_speed, g.velocity.length() / speed0)
		var on_line := start + line * (g.global_position - start).dot(line)
		res.dev = maxf(res.dev, g.global_position.distance_to(on_line))
		res.drop = maxf(res.drop, on_line.y - g.global_position.y)
		res.frames = i + 1
		if dist < _strike_reach_at(g.velocity.length()):  # Schlag wuerde treffen
			res.reached = true
			break
	# Obergrenze pro Frame aus kontinuierlichen Kraeften: n Winden + Lenkung (omega * v) + Schwerkraft.
	var accel: float = n * (g.reel_force * g.combat_reel_mult * g.reel_turbo_mult + g.carve_turn_rate * res.max_speed) + g.gravity
	res.dv_bound = accel / 60.0
	g._release_all_hooks()
	_revive(d)
	return res


## Lock-Schlag-Reichweite des Messers bei diesem Tempo (wie KnifeCombat.strike_reach()).
func _strike_reach_at(speed: float) -> float:
	var k := g.knife
	return k.lock_strike_reach + minf(speed * k.speed_reach_time, k.speed_reach_max)


func _test_lmb_double_click() -> void:
	print("LMB-Doppelklick: zwei Combat-Seile + Schlag")
	var d := _dummy_near(Vector3(0, 18, -60))
	await _place(Vector3(14, 18, -48), 0.0, 0.0)
	_aim_at(d.get_lock_point())
	await _process_frames(2)
	await _frames(2)
	# Einzelklick: Seil zieht kurz, Schlag folgt am Ende des Doppelklick-Fensters
	await _tap("attack")
	await _frames(2)
	_check(g.combat_hooks_out() == 1 and not g.knife.is_attacking(), "kurzer Klick: ein Seil, Schlag wartet aufs Fenster")
	await _frames(14)
	_check(g.combat_hook() == null and g.knife.is_attacking(), "ohne zweiten Klick: Schlag am Fensterende")
	await _frames(30)
	# Doppelklick + halten
	await _place(Vector3(14, 18, -48), 0.0, 0.0)
	_aim_at(d.get_lock_point())
	await _process_frames(2)
	await _frames(2)
	var hits := d.hits_taken
	await _tap("attack")
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	_check(g.combat_hooks_out() == 2 and g.is_dual_locked() and not g.knife.is_attacking(),
			"Doppelklick + halten: beide Seile am Gegner, noch kein Schlag")
	var reached := false
	for i in 120:
		await physics_frame
		if g.global_position.distance_to(d.get_lock_point()) < 3.2:
			reached = true
			break
	Input.action_release("attack")
	await _frames(12)
	_check(reached and g.combat_hook() == null and d.hits_taken > hits, "Loslassen = Momentum-Schlag trifft")
	_revive(d)
	await _frames(5)


func _test_rmb_double_tap_enemy() -> void:
	print("RMB-Doppel-Tap auf den Gegner")
	var d := _dummy_near(Vector3(0, 18, -60))
	await _place(Vector3(14, 18, -48), 0.0, 0.0)
	_aim_at(d.get_lock_point())
	await _process_frames(2)
	await _frames(2)
	await _tap("grapple")
	await _frames(2)  # Loslassen registrieren -> Doppel-Tap-Fenster laeuft
	_check(g.hooks_out() == 1 and not g.is_dual_locked(), "erster Tap: ein Seil am Gegner")
	_aim_at(d.get_lock_point())
	await _process_frames(1)
	Input.action_press("grapple")
	await _frames(2)
	_check(g.hooks_out() == 2 and g.is_dual_locked(), "Doppel-Tap: beide Seile am Gegner")
	var y0 := g.global_position.y
	await _frames(15)
	_check(g.global_position.y > y0 - 0.5, "kein Durchsacken am Gegner")
	Input.action_press("attack")
	await _frames(2)
	_check(g.combat_hook() != null and g.is_dual_locked(), "LMB: Combat-Seil ersetzt ein RMB-Seil, beide bleiben am Gegner")
	Input.action_release("attack")
	await _frames(16)  # kurzer Klick -> Schlag nach dem Doppelklick-Fenster
	_check(g.combat_hook() == null and g.knife.is_attacking(), "LMB loslassen = Schlag")
	Input.action_release("grapple")
	g._release_all_hooks()
	_revive(d)
	await _frames(5)


func _test_giant_double_click_pierce() -> void:
	print("Doppelklick-Schlag am Riesen (Tempo-Skalierung + Piercing)")
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	await _place(Vector3(10, 9.5, -72.0), 0.0, 0.0)
	var chest: LockPoint = giant.find_child("LP_Brust", true, false)
	_aim_at(chest.global_position)
	await _process_frames(2)
	await _frames(3)
	await _action_event("hard_lock")
	g.hard_lock = chest
	var hits := giant.hits_taken
	await _tap("attack")
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	_check(g.combat_hooks_out() == 2 and g.is_dual_locked(), "Doppelklick greift den Riesen mit beiden Seilen")
	for i in 150:
		await physics_frame
		if g.global_position.distance_to(chest.global_position) < 3.0:
			break
	Input.action_release("attack")
	await _frames(15)
	var lh: Dictionary = g.knife.last_hit
	_check(giant.hits_taken > hits and lh.get("point", "") == "Brust", "Schlag trifft den Lock-Punkt (%s)" % lh.get("point", "-"))
	_check(lh.get("speed_mult", 0.0) > 1.5, "volle Tempo-Skalierung (Speed x%.1f bei %.0f m/s)"
			% [lh.get("speed_mult", 0.0), lh.get("speed", 0.0)])
	_check(g.knife.last_pierce.size() > 1, "Piercing wertet weitere Koerperteile aus (%d Eintraege)" % g.knife.last_pierce.size())
	g.release_hard_lock()
	giant.hp = giant.max_hp
	giant._down_t = 0.0
	await _frames(5)


func _test_hard_lock_camera() -> void:
	print("Freie Kamera + Kamera-Snap-Impuls")
	var d := _dummy_near(Vector3(0, 1, -40))
	var hud = arena.get_node("HUD")
	_check(hud.get("_lock") == null and hud.reticle is LockReticle, "Auswahl-UI = reiner Rahmen ohne Text-Label")
	await _place(Vector3(0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	await _action_event("hard_lock")
	await _process_frames(40)
	_check(g.hard_lock == d, "Ziel gewaehlt")
	var err := _cam_error_deg(d.get_lock_point())
	_check(err < 1.0 and not g.is_snapping(), "Snap richtet die Kamera aufs Ziel und endet (%.2f°)" % err)
	_check(g.hard_lock_in_range() and hud.reticle.visible and hud.reticle.in_range
			and hud.reticle.current_color() == LockReticle.COL_IN_RANGE, "Rahmen farbig in Reichweite")
	var proj := g.camera.unproject_position(d.get_node("Shape").global_position)
	_check(hud.reticle.center.distance_to(proj) < 0.5, "Rahmen sitzt exakt auf der Hitbox-Mitte")
	var center: Vector2 = g.get_viewport().get_visible_rect().size * 0.5
	_check(hud.reticle.center.distance_to(center) < 6.0,
			"nach dem Snap liegt die Hitbox unterm Fadenkreuz (%.1f px)" % hud.reticle.center.distance_to(center))
	# Danach ist die Kamera frei: Umsehen wird NICHT zurueckgezogen.
	g._yaw += 0.9
	await _process_frames(40)
	err = _cam_error_deg(d.get_lock_point())
	_check(err > 30.0 and g.hard_lock == d, "Kamera bleibt frei, Auswahl bleibt (%.0f° weg vom Ziel)" % err)
	var yaw0 := g._yaw
	Input.action_press("look_right")
	await _process_frames(20)
	Input.action_release("look_right")
	_check(absf(g._yaw - yaw0) > 0.2, "Stick dreht die Kamera trotz Auswahl")
	# Umsehen bricht einen laufenden Snap sofort ab
	await _action_event("hard_lock")
	Input.action_press("look_right")
	await _process_frames(3)
	Input.action_release("look_right")
	_check(not g.is_snapping(), "Umsehen bricht den Snap ab (Spieler hat Vorrang)")
	await _frames(int(g.lock_double_click * 60.0) + 2)  # kein Doppelklick (= Loesen)
	await _action_event("hard_lock")
	await _process_frames(40)
	_check(_cam_error_deg(d.get_lock_point()) < 1.0, "erneuter Klick = neuer Snap")
	g.release_hard_lock()
	# Trefferpunkt-Wechsel am Riesen + Snap auf den neuen Punkt
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	await _place(Vector3(0, 6.0, -62.0), 0.0, 0.0)
	_aim_at(giant.global_position + Vector3(0, 9.5, 1.3))
	await _process_frames(2)
	await _frames(3)
	await _action_event("hard_lock")
	var a := g.hard_lock
	await _action_event("lock_next")
	var b := g.hard_lock
	await _action_event("hard_lock")
	for i in 40:  # Messung direkt bei Snap-Ende (Spieler faellt danach weiter)
		if not g.is_snapping():
			break
		await process_frame
	await process_frame
	err = _cam_error_deg(g._lock_point_of(b))
	_check(a is LockPoint and b is LockPoint and a != b and g.hard_lock == b and err < 1.0,
			"Mausrad wechselt Punkt, Klick snappt darauf (%s -> %s, %.2f°)" % [_lname(a), _lname(b), err])
	g.release_hard_lock()

func _test_hard_lock_out_of_range() -> void:
	print("Auswahl ausserhalb der Reichweite / Auto-Clear")
	var d := _dummy_near(Vector3(0, 1, -40))
	var hud = arena.get_node("HUD")
	await _place(Vector3(0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Ziel gewaehlt")
	await _place(Vector3(0, 1.2, 42.0), PI, 0.0)  # 82 m entfernt, Blick zum Ziel
	await _process_frames(4)
	await _frames(3)
	var dist := g.global_position.distance_to(d.get_lock_point())
	_check(g.hard_lock == d, "Auswahl bleibt bei %.0f m (Reichweite %.0f m)" % [dist, g.grapple_range])
	_check(not g.hard_lock_in_range() and hud.reticle.visible and not hud.reticle.in_range
			and hud.reticle.current_color() == LockReticle.COL_OUT_OF_RANGE, "Rahmen grau ausserhalb der Reichweite")
	Input.action_press("attack")
	await _frames(3)
	_check(g.combat_hook() == null, "kein Seil ausserhalb der Reichweite")
	g.global_position = Vector3(0, 1.2, -12.0)
	g.reset_physics_interpolation()
	await _process_frames(2)
	await _frames(3)
	var ch := g.combat_hook()
	_check(ch != null and ch.target == d and hud.reticle.in_range, "zurueck in Reichweite: Rahmen farbig, Seil greift")
	Input.action_release("attack")
	await _frames(10)
	# knapp unter 3x Reichweite: bleibt
	var lim := g.lock_expire_range()
	await _place(d.get_lock_point() + Vector3(0, 0.2, lim - 5.0), PI, 0.0)
	await _frames(2)
	_check(g.hard_lock == d, "bei %.0f m (< 3x Reichweite) bleibt die Auswahl" % (lim - 5.0))
	# ueber 3x Reichweite: Auswahl + Rahmen weg
	g.global_position = d.get_lock_point() + Vector3(0, 0.2, lim + 5.0)
	g.reset_physics_interpolation()
	await _frames(2)
	await _process_frames(2)
	_check(g.hard_lock == null and not hud.reticle.visible,
			"ueber 3x Reichweite (%.0f m) wird die Auswahl geloescht, Rahmen weg" % (lim + 5.0))
	await _place(Vector3(0, 1.2, -10.0), 0.0, 0.0)
	await _frames(30)


func _test_free_camera_while_swinging() -> void:
	print("Freie Kamera beim Schwingen (mit Auswahl)")
	var d := _dummy_near(Vector3(0, 1, -40))
	await _place(Vector3(0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	await _action_event("hard_lock")
	_check(g.hard_lock == d, "Ziel gewaehlt")
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, 6, 0))
	await _process_frames(2)
	await _frames(2)
	Input.action_press("grapple")
	await _frames(10)
	var hooked := g.any_hook_active()
	var yaw0 := g._yaw
	Input.action_press("look_left")
	for i in 40:
		await physics_frame
		await process_frame
	Input.action_release("look_left")
	_check(hooked and g.any_hook_active(), "haengt am Seil")
	_check(absf(angle_difference(yaw0, g._yaw)) > 0.4 and g.hard_lock == d,
			"Kamera dreht beim Schwingen frei trotz Auswahl (%.2f rad)" % absf(angle_difference(yaw0, g._yaw)))
	Input.action_release("grapple")
	await _frames(20)
	g.release_hard_lock()
	await _frames(60)


func _test_high_speed_hit_window() -> void:
	print("High-Speed Hit-Window")
	var d := _dummy_near(Vector3(0, 1, -40))
	_revive(d)
	var k := g.knife
	# Vorbeiflug mit 70 m/s, 4.6 m seitlich vom Ziel (ueber der Stand-Reichweite von 4 m).
	await _place(Vector3(4.6, 1.3, -30.0), 0.0, 0.0)
	g.hard_lock = d
	var hits := d.hits_taken
	for i in 30:
		g.velocity = Vector3(0, 0, -70)
		if i == 4:
			k.request_slash(d)
		await physics_frame
	_check(d.hits_taken > hits, "Vorbeiflug mit 70 m/s trifft (Reichweite %.1f m statt %.1f m)"
			% [k.strike_reach(), k.lock_strike_reach])
	# Ueberflug 5.4 m ueber dem Ziel mit 75 m/s (1.25 m pro Frame, Strecken-Pruefung).
	_revive(d)
	await _place(Vector3(0.0, 6.4, -30.0), 0.0, 0.0)
	g.hard_lock = d
	hits = d.hits_taken
	for i in 30:
		g.velocity = Vector3(0, 0, -75)
		if i == 2:
			k.request_slash(d)
		await physics_frame
	_check(d.hits_taken > hits, "Ueberflug mit 75 m/s trifft (Strecken-Pruefung + Tempo-Reichweite)")
	g.release_hard_lock()
	await _place(Vector3(0, 1.2, -10.0), 0.0, 0.0)
	await _frames(20)
	# Ohne Tempo bleibt das Fenster eng
	k._swing_velocity = Vector3.ZERO
	_check(absf(k.strike_reach() - k.lock_strike_reach) < 0.01, "im Stand normale Reichweite (%.1f m)" % k.strike_reach())


func _test_boss_damage_scaling() -> void:
	print("Schadens-Skalierung (Adds vs. Boss)")
	var k := g.knife
	var d := _dummy_near(Vector3(0, 1, -40))
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	var top: Dictionary = k.compute_damage(Vector3(0, -74, -8), k.combo_multipliers[0], true)
	var mid: Dictionary = k.compute_damage(Vector3(0, -40, -4))
	var flat: Dictionary = k.compute_damage(Vector3(0, 0, -40))
	var top_dummy := k.scale_for_target(top.damage, d)
	var top_giant := k.scale_for_target(top.damage, giant)
	print("    Top-Sturz roh %.0f -> Dummy %.0f (%.0f %%) | Riese %.0f (%.1f %% von %.0f)"
			% [top.damage, top_dummy, top_dummy / d.max_hp * 100.0, top_giant,
			top_giant / giant.max_hp * 100.0, giant.max_hp])
	_check(top_dummy >= d.max_hp * 0.9 and top_dummy <= d.max_hp,
			"Top-Sturzflug = 90-100 %% eines Dummys (%.0f / %.0f)" % [top_dummy, d.max_hp])
	_check(top_giant > top_dummy and top_giant <= giant.max_hp * 0.15 + 0.5,
			"Boss: dicker Brocken, aber <= 15 %% der HP (%.0f)" % top_giant)
	_check(giant.max_hp / top_giant >= 6.0, "kein One-Hit-Kill am Boss (min. %d Top-Treffer)" % ceili(giant.max_hp / top_giant))
	_check(absf(k.scale_for_target(k.min_damage, d) - k.min_damage) < 0.01
			and absf(k.scale_for_target(flat.damage, d) - flat.damage) < 0.5,
			"kleine/normale Treffer bleiben unveraendert")
	var mid_dummy := k.scale_for_target(mid.damage, d)
	_check(mid_dummy > mid.damage * 0.6 and mid_dummy < top_dummy, "mittlerer Sturz bleibt stark (%.0f)" % mid_dummy)
	# Echter Treffer am Riesen: Schaden ist gedeckelt
	var hp0 := giant.hp
	giant.take_hit(0.0, Vector3.ZERO, null)
	var chest: LockPoint = giant.find_child("LP_Brust", true, false)
	k._swing_velocity = Vector3(0, -74, -8)
	k._swing_turbo = true
	k.combo_index = 0
	k._deal(giant, 1.0, Vector3.DOWN, chest.global_position, chest)
	var dealt := hp0 - giant.hp
	_check(dealt > 0.0 and dealt <= giant.max_hp * 0.15 + 0.5,
			"Treffer am Riesen gedeckelt (%.0f Schaden, roh %.0f)" % [dealt, k.last_hit.get("raw_damage", 0.0)])
	await _frames(10)

func _test_piercing_falloff() -> void:
	print("Piercing-Sturz durch den Riesen (Distanz-Abfall)")
	var k := g.knife
	_check(absf(k.pierce_falloff(0.0) - 0.5) < 0.001 and absf(k.pierce_falloff(3.6) - 0.1) < 0.01
			and k.pierce_falloff(k.pierce_radius + 0.1) == 0.0,
			"Abfall: anliegend 50 %, Rand (3.6 m) 10 %, ausserhalb Radius 0 %")
	var giant: TrainingGiant = arena.get_node("TrainingGiant")
	giant.hp = giant.max_hp
	giant._down_t = 0.0
	var chest: LockPoint = giant.find_child("LP_Brust", true, false)
	var x0 := giant.global_position + Vector3(0, 13.5, 2.3)  # senkrecht vor dem Riesen
	await _place(x0, 0.0, 0.0)
	var hp0 := giant.hp
	var started := false
	for i in 40:
		g.velocity = Vector3(0, -40, 0)
		if not started and i == 1:
			k.request_slash(chest)
			started = true
		await physics_frame
		if g.global_position.y < giant.global_position.y + 4.2:
			g.velocity = Vector3.ZERO
			break
	await _frames(20)
	var by := {}
	for e: Dictionary in k.last_pierce:
		by[e.part] = e
	print("    ", ", ".join(k.last_pierce.map(func(e): return "%s %d%%" % [e.part, roundi(e.pct * 100.0)])))
	var prim: Dictionary = by.get("Torso", {})
	_check(not prim.is_empty() and prim.primary and prim.pct == 1.0,
			"Primaer-Teil (Torso, Brust-Punkt) = 100 %% (%.0f)" % prim.get("damage", 0.0))
	var head: Dictionary = by.get("Kopf", {})
	var leg: Dictionary = by.get("BeinL", {})
	var arm: Dictionary = by.get("ArmL", {})
	_check(head.get("traversed", false) and head.pct > 0.2 and head.pct < 0.4,
			"Kopf (%.2f m vom Epizentrum) = %d %%" % [head.get("dist", 0.0), roundi(head.get("pct", 0.0) * 100.0)])
	_check(leg.get("traversed", false) and leg.pct > 0.05 and leg.pct < 0.15,
			"Bein am Rand (%.2f m) = %d %%" % [leg.get("dist", 0.0), roundi(leg.get("pct", 0.0) * 100.0)])
	_check(head.get("pct", 0.0) > leg.get("pct", 1.0), "naeher am Epizentrum = mehr Schaden")
	_check(not arm.is_empty() and not arm.traversed and arm.pct == 0.0, "nicht durchquerte Arme = 0 %")
	var expect := 0.0
	var ok_scale := true
	for e: Dictionary in k.last_pierce:
		expect += e.damage
		if not e.primary and absf(e.damage - prim.get("damage", 0.0) * e.pct) > 0.01:
			ok_scale = false
	_check(ok_scale, "Nebenschaden = Primaer-Schaden x Anteil")
	_check(absf((hp0 - giant.hp) - expect) < 0.5,
			"Riese verliert genau die Summe (%.0f HP)" % (hp0 - giant.hp))
	_check(by.size() == TrainingGiant.PARTS.size(), "alle %d Koerperteile ausgewertet" % by.size())
	g.release_hard_lock()
	await _place(Vector3(0, 1.2, -10.0), 0.0, 0.0)
	await _frames(30)


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
	var rigid_seen := false
	var prev := g.velocity
	var approach_sum := 0.0
	var approach_n := 0
	var l_start := -1.0
	var len_drift := 0.0
	for i in n:
		await physics_frame
		if l_start < 0.0:
			l_start = h.rope_length
		len_drift = maxf(len_drift, absf(h.rope_length - l_start))
		turbo_seen = turbo_seen or g.is_turbo()
		rigid_seen = rigid_seen or g.is_rope_rigid()
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
		"max_slack": max_slack, "max_jolt": max_jolt, "turbo_seen": turbo_seen, "rigid_seen": rigid_seen, "len_drift": len_drift,
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
