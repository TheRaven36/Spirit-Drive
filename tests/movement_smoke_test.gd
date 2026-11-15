extends SceneTree
## Headless-Smoke-Test fuer den Guardian-Controller.
## Aufruf: godot --headless --path . --script res://tests/movement_smoke_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena: Node = load("res://scenes/test_arena.tscn").instantiate()
	root.add_child(arena)
	var g: GuardianController = arena.get_node("Guardian")
	await _frames(30)
	_check(g.is_on_floor(), "Guardian steht nach Spawn auf dem Boden")

	# Sprint nach vorne
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	var hs := Vector2(g.velocity.x, g.velocity.z).length()
	_check(hs > g.sprint_speed * 0.9, "Sprint erreicht Zielspeed (%.1f)" % hs)

	# Dash
	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	_check(g.state == GuardianController.State.DASH, "Dash startet")
	hs = Vector2(g.velocity.x, g.velocity.z).length()
	_check(hs >= g.dash_speed * 0.95, "Dash-Speed (%.1f)" % hs)
	await _frames(20)
	_check(g.state == GuardianController.State.NORMAL, "Dash endet")
	Input.action_release("move_forward")
	Input.action_release("sprint")

	# Sprung
	await _frames(60)
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	_check(g.velocity.y > 5.0 and not g.is_on_floor(), "Sprung hebt ab")
	await _frames(90)

	# Grapple: Spieler zu einem Turm drehen und anvisieren
	g._respawn()
	await _frames(10)
	var target := _find_tower(arena)
	var flat := target - g.global_position
	g._yaw = atan2(-flat.x, -flat.z)
	g._pitch = 0.25
	await _frames(5)
	var tries := 0
	while not g.aim_valid and tries < 40:
		g._pitch += 0.03
		tries += 1
		await _frames(2)
	_check(g.aim_valid, "Grapple-Ziel anvisiert")
	var start_dist := g.global_position.distance_to(g.aim_point)
	Input.action_press("grapple")
	await _frames(2)
	_check(g.state == GuardianController.State.GRAPPLE, "Grapple haengt ein")
	await _frames(45)
	var anchor: Vector3 = g._anchor
	var now_dist := g.global_position.distance_to(anchor)
	_check(now_dist < start_dist - 3.0, "Grapple zieht heran (%.1f -> %.1f)" % [start_dist, now_dist])
	Input.action_release("grapple")
	await _frames(2)
	_check(g.state == GuardianController.State.NORMAL, "Grapple loest beim Loslassen")
	_check(g.velocity.length() > 5.0, "Momentum bleibt nach Release (%.1f)" % g.velocity.length())

	# Wall-Run: neben der ersten Wand (x=16) in der Luft entlang laufen
	await _frames(60)
	g.global_position = Vector3(14.9, 4.0, -18.0)
	g.reset_physics_interpolation()
	g._yaw = 0.0
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
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	_check(g.state == GuardianController.State.NORMAL and g.velocity.x < -5.0,
			"Wall-Jump stoesst von der Wand ab (vx=%.1f)" % g.velocity.x)
	Input.action_release("move_forward")
	Input.action_release("move_right")

	print("SMOKE TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


func _find_tower(arena: Node) -> Vector3:
	var boxes: Array = arena._boxes
	var best := Vector3.ZERO
	var best_d := INF
	for b: Dictionary in boxes:
		if b.size.y > 20.0:
			var d: float = (b.pos as Vector3).length()
			if d < best_d:
				best_d = d
				best = b.pos
	return best


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	print(("  [OK]   " if ok else "  [FAIL] ") + label)
	if not ok:
		_fails += 1
