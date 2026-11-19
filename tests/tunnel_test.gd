extends SceneTree
## Headless-Test fuer den OrganicTransitionTunnel (Phase 3A): 3D-S-Kurve mit Collision,
## Felsvorspruenge, Barrieren, asynchrones Laden/Entladen Hoehle -> Hauptquartier und zurueck.
## Phase 3E: Das HQ ist ein Whitebox-Sektor mit dem Homebase-Prefab als "Camp"; angedockt wird
## ueber den Exit-Marker "Exits/cathedral_cave".
## Aufruf: godot --headless --path . --script res://tests/tunnel_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

const A := OrganicTransitionTunnel.End.A
const B := OrganicTransitionTunnel.End.B
const LOAD_TIMEOUT_FRAMES := 600

var _fails := 0
var world: Node
var g: GuardianController
var tunnel: OrganicTransitionTunnel


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	g = world.get_node("Guardian")
	g.get_node("SpiritEntity").process_mode = Node.PROCESS_MODE_DISABLED
	tunnel = world.get_node("Areas/Tunnel")
	await _frames(10)

	_test_geometry()
	await _test_to_homebase()
	await _test_back_to_arena()

	print("TUNNEL TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


func _test_geometry() -> void:
	print("Tunnel-Geometrie")
	var curve: Curve3D = tunnel.get_node("PathOuter").curve
	var pts := curve.get_baked_points()
	var ys: Array[float] = []
	var xs: Array[float] = []
	for p in pts:
		ys.append(p.y)
		xs.append(p.x)
	_check(tunnel.length > 170.0 and tunnel.length < 195.0, "Laenge %.1f m" % tunnel.length)
	_check(xs.max() > 14.0 and xs.min() < -14.0, "S-Kurve links/rechts (x %.1f .. %.1f m)" % [xs.min(), xs.max()])
	_check(ys.max() > 30.0, "steil hoch und wieder runter (Scheitel %.1f m)" % ys.max())
	_check(2.0 * OrganicTransitionTunnel.RADIUS_X >= 22.0 and 2.0 * OrganicTransitionTunnel.RADIUS_Y >= 18.0,
			"Querschnitt %.0f m breit x %.0f m hoch" % [2.0 * OrganicTransitionTunnel.RADIUS_X,
				2.0 * OrganicTransitionTunnel.RADIUS_Y])
	# Wand-Abstand an vielen Stellen: seitlich RADIUS_X, oben/unten RADIUS_Y (keine Faltung, keine Loecher)
	var walls := 0
	var rays := 0
	var off := 6.0
	while off < tunnel.length - 6.0:
		var xf := curve.sample_baked_with_rotation(off)
		var o := tunnel.to_global(xf.origin)
		for d: Array in [[xf.basis.x, 12.0], [-xf.basis.x, 12.0], [xf.basis.y, 9.0], [-xf.basis.y, 9.0]]:
			rays += 1
			var hit := _cast(o, o + tunnel.global_basis * (d[0] as Vector3) * 40.0)
			# Treffer auf einen Felsvorsprung (steht von der Wand ab) zaehlt ebenfalls als dicht.
			if not hit.is_empty() and (absf((hit.position as Vector3).distance_to(o) - d[1]) < 0.6
					or hit.collider == tunnel.get_node("Ledges")):
				walls += 1
		off += 6.0
	_check(walls == rays, "Innenwand ueberall dicht: %d/%d Strahlen auf 12 m / 9 m" % [walls, rays])
	var cap := _cast(Vector3(0, 15, 140), Vector3(0, 15, 160))
	_check(not cap.is_empty() and absf(cap.position.z - 149.5) < 0.6, "End-Platte schliesst ueber dem Tor ab")
	_check(tunnel.get_node("Ledges").get_child_count() == OrganicTransitionTunnel.LEDGES.size(),
			"%d Felsvorspruenge als Anker" % OrganicTransitionTunnel.LEDGES.size())
	_check(tunnel.is_barrier_open(A) and not tunnel.is_barrier_open(B), "Start: Barriere Hoehle offen, Homebase zu")
	var door := _cast(Vector3(0, 5, 140), Vector3(0, 5, 160))
	_check(door.is_empty(), "Hoehlentor -> Tunnel frei begehbar")


func _test_to_homebase() -> void:
	print("Hoehle -> Homebase")
	var arena := tunnel.area(A)
	_check(arena != null and arena.name == "TestArena" and tunnel.area(B) == null, "Start: nur die Hoehle geladen")
	await _put_at(6.0)
	_check(tunnel.travel_from == A and (tunnel.is_loading(B) or tunnel.area(B) != null),
			"Eintritt: Homebase wird asynchron geladen")
	_check(is_instance_valid(arena), "Hoehle bleibt bis zur Biegung geladen")
	await _put_at(tunnel.length * 0.4)
	await _frames(2)
	_check(not is_instance_valid(arena) and tunnel.area(A) == null, "nach der ersten Biegung: Hoehle entladen")
	_check(not tunnel.is_barrier_open(A), "Barriere zur (leeren) Hoehlen-Seite geschlossen")
	var base := await _wait_loaded(B)
	_check(base is WhiteboxSector and base.get_node("Camp") is HomebaseOutpost,
			"Hauptquartier mit Homebase geladen (THREAD_LOAD_LOADED)")
	var docked: Transform3D = tunnel.get_node("ExitAnchor").global_transform \
			* (base.get_node("Exits/cathedral_cave") as Node3D).transform.affine_inverse() if base != null else Transform3D()
	_check(base != null and base.global_transform.is_equal_approx(docked), "Exit-Marker liegt am ExitAnchor")
	_check(tunnel.is_barrier_open(B), "Ausgangs-Barriere oeffnet")
	# Durch den Ausgang in die Homebase
	g.global_position = base.global_position + Vector3(0, 1.2, 0)
	g.reset_physics_interpolation()
	await _frames(5)
	_check(tunnel.travel_from == -1 and g.is_on_floor(), "in der Homebase angekommen")


func _test_back_to_arena() -> void:
	print("Homebase -> Hoehle (Rueckweg)")
	var base := tunnel.area(B)
	await _put_at(tunnel.length - 6.0)
	_check(tunnel.travel_from == B and (tunnel.is_loading(A) or tunnel.area(A) != null),
			"Rueckweg-Trigger: Hoehle wird asynchron geladen")
	await _put_at(tunnel.length * 0.5)
	await _frames(2)
	_check(not is_instance_valid(base) and not tunnel.is_barrier_open(B), "Homebase entladen, Barriere zu")
	var arena := await _wait_loaded(A)
	_check(arena != null and arena.global_position.is_equal_approx(Vector3.ZERO)
			and arena.get_node_or_null("TrainingGiant") != null, "Hoehle neu aufgebaut am EntryAnchor")
	_check(tunnel.is_barrier_open(A), "Barriere zur Hoehle offen")
	await _frames(3)
	var floor_hit := _cast(Vector3(0, 10, 0), Vector3(0, -5, 0))
	_check(not floor_hit.is_empty(), "Hoehlenboden wieder mit Collision")


# --- Helfer ---------------------------------------------------------------
## Guardian an Kurven-Offset (m ab Seite A) in die Roehre setzen.
func _put_at(offset: float) -> void:
	var curve: Curve3D = tunnel.get_node("PathOuter").curve
	g.global_position = tunnel.to_global(curve.sample_baked(offset))
	g.velocity = Vector3.ZERO
	g.reset_physics_interpolation()
	await _frames(2)


func _wait_loaded(end: int) -> Node3D:
	for i in LOAD_TIMEOUT_FRAMES:
		if tunnel.area(end) != null:
			return tunnel.area(end)
		await process_frame
	return null


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [g.get_rid()])
	return g.get_world_3d().direct_space_state.intersect_ray(q)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	print(("  [OK]   " if ok else "  [FAIL] ") + label)
	if not ok:
		_fails += 1
