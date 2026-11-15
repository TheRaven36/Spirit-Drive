extends SceneTree
## Headless-Smoke-Test fuer den Guardian (Movement, Kamera, Seile, Messer).
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
	await _test_aim_assist()
	await _test_combat_dive()
	await _test_combat_grapple_point()
	await _test_rope_bending()
	await _test_momentum_swing()
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
	_check(hs > g.sprint_speed * 0.9, "Sprint erreicht Zielspeed (%.1f)" % hs)
	await _tap("dash")
	_check(g.state == GuardianController.State.DASH, "Dash (Strg) startet")
	await _frames(20)
	_check(g.state == GuardianController.State.NORMAL, "Dash endet")
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
	var cam_h := g.camera.global_position.y - g.global_position.y
	_check(absf(cam_h - g.fp_height) < 0.1, "First-Person: Augenhoehe (%.2f)" % cam_h)
	_check(not g.knife_tp.visible and g.knife_fp.visible, "First-Person: Viewmodel-Messer sichtbar")
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
	_check(d.hp < hp_before, "Slash trifft Dummy (%.0f -> %.0f)" % [hp_before, d.hp])
	_check(not g.any_hook_active(), "LMB loest keinen Grapple aus")
	await _tap("attack")
	await _frames(4)
	_check(g.knife.combo_index == 1, "Combo zaehlt hoch (%d)" % g.knife.combo_index)
	await _frames(30)


func _test_aim_assist() -> void:
	print("Auto-Aim")
	var d := _dummy_near(Vector3(0, 1, -40))
	# Kamera 2 m neben dem Dummy vorbei zielen lassen
	await _place(Vector3(2.0, 1.2, -10.0), 0.0, -0.02)
	await _frames(3)
	_check(g.aim_kind == GuardianController.AimKind.ENEMY and g.aim_target == d,
			"Dummy rastet trotz Versatz ein (Kegel/Radius)")
	# Knapp neben einen Turm zielen: exakter Strahl verfehlt, Kegel trifft
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
	g._yaw += 0.01  # ~0.5 m ueber die Kante hinaus
	await _process_frames(1)
	await _frames(2)
	_check(missed and g.aim_kind == GuardianController.AimKind.POINT and g.aim_assisted,
			"Turmkante knapp verfehlt -> Assist rastet ein")


func _test_combat_dive() -> void:
	print("Combat-Grapple auf Gegner (RMB)")
	var d := _dummy_near(Vector3(0, 18, -60))
	await _place(Vector3(0, 1.2, -30), 0.0, 0.0)
	_aim_at(d.get_lock_point())
	await _process_frames(2)
	await _frames(3)
	_check(g.aim_target == d, "Ziel im Lock")
	var hits := d.hits_taken
	Input.action_press("hook_combat")
	var dived := false
	for i in 120:
		await physics_frame
		if g.hook_combat.phase == GrappleHook.Phase.DIVE:
			dived = true
		if d.hits_taken > hits:
			break
	_check(dived, "Sturzangriff von oben ausgeloest")
	_check(d.hits_taken > hits, "Sturzangriff trifft (HP %.0f)" % d.hp)
	await _frames(120)
	_check(g.hook_combat.active, "Seil bleibt nach dem Treffer dran")
	Input.action_release("hook_combat")
	await _frames(2)
	_check(not g.hook_combat.active, "Loslassen loest das Seil")
	await _frames(90)


func _test_combat_grapple_point() -> void:
	print("Combat-Grapple auf Geometrie")
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, t.size.y * 0.25, 0))
	await _process_frames(2)
	await _frames(3)
	_check(g.aim_kind == GuardianController.AimKind.POINT, "Turm anvisiert")
	var start := g.global_position.distance_to(g.aim_point)
	Input.action_press("hook_combat")
	var rebounded := false
	var min_d := INF
	for i in 240:  # 4 Sekunden halten
		await physics_frame
		min_d = minf(min_d, g.global_position.distance_to(g.hook_combat.anchor_world()))
		if g.hook_combat.phase == GrappleHook.Phase.TETHER:
			rebounded = true
	_check(min_d < start - 10.0, "zieht mit Wucht heran (%.1f -> %.1f)" % [start, min_d])
	_check(rebounded, "Rebound am Ankerpunkt (Bogen drueber hinaus)")
	_check(g.hook_combat.active, "reissfest: nach 4 s noch eingehakt")
	Input.action_release("hook_combat")
	await _frames(2)
	_check(not g.hook_combat.active and g.velocity.length() > 3.0,
			"Release behaelt Momentum (%.1f)" % g.velocity.length())
	await _frames(120)


func _test_rope_bending() -> void:
	print("Seil-Bending")
	await _place(Vector3(0, 1.2, 0), 0.0, 0.0)
	var t := _closest_tower()
	_aim_at(t.pos + Vector3(0, t.size.y * 0.3, 0))
	await _process_frames(2)
	await _frames(3)
	Input.action_press("hook_combat")
	await _frames(2)
	# Hindernis zwischen Spieler und Anker schieben
	var mid := g.global_position.lerp(g.hook_combat.anchor_world(), 0.4)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = mid
	await _frames(2)
	_check(g.hook_combat.has_bends(), "Seil knickt am Hindernis (%d Knick)" % g.hook_combat.bends.size())
	var ex: Array[RID] = [g.get_rid()]
	var pivot := g.hook_combat.pivot()
	var q := PhysicsRayQueryParameters3D.create(g.global_position, pivot, 1, ex)
	var hit := g.get_world_3d().direct_space_state.intersect_ray(q)
	_check(hit.is_empty() or (hit.position as Vector3).distance_to(pivot) < 0.5,
			"freie Linie Spieler -> Pivot (kein Durchschneiden)")
	Input.action_release("hook_combat")
	wall.queue_free()
	await _frames(90)


func _test_momentum_swing() -> void:
	print("Momentum-Swing (Q/E)")
	await _place(Vector3(-100, 10, -10), 0.0, 0.1)
	g.velocity = Vector3(0, 0, -14)
	Input.action_press("hook_left")
	await _frames(2)
	_check(g.hook_left.active, "Q wirft linken Haken")
	var a := g.hook_left.anchor_world()
	_check(a.x < -100.0 and a.z < -10.0, "Anker links vorne (%.0f, %.0f, %.0f)" % [a.x, a.y, a.z])
	var min_y := INF
	for i in 60:
		await physics_frame
		min_y = minf(min_y, g.global_position.y)
	_check(min_y > 8.5, "Hoehe bleibt beim Schwingen (min y %.1f)" % min_y)
	Input.action_release("hook_left")
	Input.action_press("hook_right")
	await _frames(2)
	_check(g.hook_right.active and not g.hook_left.active, "E wirft rechten Haken")
	var b := g.hook_right.anchor_world()
	_check(b.x > -100.0, "Anker rechts (x %.0f)" % b.x)
	var z0 := g.global_position.z
	await _frames(60)
	_check(g.global_position.z < z0 - 8.0, "Schwung nach vorne (dz %.1f)" % (g.global_position.z - z0))
	_check(g.hook_right.active, "Haken bleibt bis zum Loslassen")
	Input.action_release("hook_right")
	await _frames(120)


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
	var cam := g.global_position + Vector3.UP * g.tp_height
	var v := p - cam
	g._yaw = atan2(-v.x, -v.z)
	g._pitch = atan2(v.y, Vector2(v.x, v.z).length())


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
			"attack", "hook_combat", "hook_left", "hook_right", "dash"]:
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
