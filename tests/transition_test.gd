extends SceneTree
## Headless-Test fuer die Uebergaenge (Phase 3G):
##   1. Bidirektionale Passierbarkeit: jede Spieler-Verbindung (beide Sektoren geladen) wird per
##      Kapsel-Sweep in beide Richtungen abgefahren; Umkehr nach dem Entladen laedt die Herkunft neu;
##      ungebaute Lager haben keine unsichtbaren Waende mehr.
##   2. RockPass-Varianten (Canyon, Klamm, Serpentine, Steil) unterscheiden sich spuerbar und sind
##      ueber die Karte verteilt.
##   3. LongTrailTransition: Ziel dockt frueh als Grob-Stufe, Details erst in der Naeherungszone,
##      Herkunft wird spaeter entladen, kein Speicher-Leck.
## Aufruf: godot --headless --path . --script res://tests/transition_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

const A := SeamlessLoadingGate.End.A
const B := SeamlessLoadingGate.End.B
const TT := SectorLink.TransitionType
const PV := SectorLink.PassVariant
const LOAD_TIMEOUT_FRAMES := 900
## Freie Flaeche fuer die Test-Aufbauten (weit weg von der Hoehle).
const FIXTURE_POS := Vector3(0, 0, -4000)
## Kapsel wie der Guardian; Wegpunkte so hoch ueber dem Boden, dass sie ihn nicht streift.
const CAPSULE := Vector2(0.4, 1.8)
const WALK_LIFT := 1.3
const STEP := 3.0
const INSIDE := 12.0
## Sichtlinien-Strahl muss so nah an der Landmarken-Spitze auftreffen.
const LANDMARK_HIT_RADIUS := 10.0
## Blickpunkte auf dem ersten Wegdrittel (Steinmaennchen duerfen einzelne verdecken), Augenhoehe ueber Boden.
const SIGHT_FRACTIONS := [0.02, 0.1, 0.2, 0.3]
const EYE_HEIGHT := 1.7
## Parkplatz des Guardians zwischen den Aufbauten (Hoehlenboden, weit weg von FIXTURE_POS).
const PARK_POS := Vector3(0, 1.2, 0)

var _fails := 0
var map: WorldMapData
var world: Node
var g: GuardianController
var wm: WorldMapManager
var areas: Node3D
var capsule := CapsuleShape3D.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	capsule.radius = CAPSULE.x
	capsule.height = CAPSULE.y
	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	g = world.get_node("Guardian")
	g.get_node("SpiritEntity").process_mode = Node.PROCESS_MODE_DISABLED
	wm = world.get_node("WorldMap")
	map = wm.map
	areas = world.get_node("Areas")
	await _frames(10)

	await _test_unbuilt_camps()
	await _test_all_links()
	await _test_pass_variants()
	_test_assignment()
	await _test_long_trail()

	print("TRANSITION TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


# --- 1. Bidirektional ---------------------------------------------------------
## Ungebaute Lager (unsichtbar) duerfen keine Collision behalten – das war die "Einbahn-Wand".
func _test_unbuilt_camps() -> void:
	print("Ungebaute Lager ohne unsichtbare Waende")
	for s in map.sectors:
		if s.camp == WorldSectorData.CampKind.NONE or wm.is_camp_built(s.id):
			continue
		var sector := _instance(s.scene_path)
		await _frames(1)
		wm.apply_camp_state(sector, false)
		await _frames(3)
		var c := sector.global_position + Vector3.UP * WALK_LIFT
		var blocked := 0
		for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			blocked += _sweep_blocked([c + d * 25.0, c - d * 25.0]).size()
		_check(blocked == 0, "%s: Lagerplatz in alle 4 Richtungen frei" % s.id)
		sector.queue_free()
		await _frames(2)


## Jede Spieler-Verbindung: beide Seiten laden, Weg hin und zurueck abfahren, Umkehr, Rueckweg.
func _test_all_links() -> void:
	print("Alle Verbindungen in beide Richtungen")
	var checked := 0
	for link in map.links:
		if link.monster_only:
			continue
		checked += 1
		await _test_link(link)
	_check(checked >= 30, "%d Spieler-Verbindungen geprueft" % checked)


func _test_link(link: SectorLink) -> void:
	var label := "%s -> %s [%s]" % [link.from_sector, link.to_sector, TT.keys()[link.transition]]
	var x := _instance(map.sector(link.from_sector).scene_path)
	await _frames(1)
	var gate := wm.make_gate(link, link.from_sector, x)
	areas.add_child(gate)
	gate.unlock_gate()
	await _frames(3)
	await _put_at(gate, 6.0)
	var y := await _wait_area(gate, B)
	if y == null:
		_check(false, "%s: Ziel geladen" % label)
		_cleanup([gate, x])
		await _frames(2)
		return
	await _frames(3)
	var route := _route(gate, x, y)
	var fwd := _sweep_blocked(route)
	route.reverse()
	var back := _sweep_blocked(route)
	_check(fwd.is_empty() and (back.is_empty() or link.one_way), "%s: hin %s / zurueck %s frei" % [
			label, str(fwd), "(Einbahn)" if link.one_way else str(back)])
	_check(gate.is_barrier_open(A) and gate.is_barrier_open(B), "%s: beide Barrieren offen" % label)
	if not link.one_way:
		await _test_turn_back(gate, label)
	_cleanup([gate, gate.area(A), gate.area(B)])
	await _frames(3)


## Nach der Biegung umdrehen: Herkunft wird neu geladen, Barriere oeffnet, Ziel wird entladen.
func _test_turn_back(gate: SeamlessLoadingGate, label: String) -> void:
	await _put_at(gate, gate.length * (gate.unload_fraction + 0.1))
	await _frames(2)
	var unloaded := gate.area(A) == null and not gate.is_barrier_open(A)
	await _put_at(gate, gate.length * 0.1)
	var back := await _wait_area(gate, A)
	await _frames(3)
	_check(unloaded and back != null and gate.is_barrier_open(A) and gate.area(B) == null,
			"%s: Umkehr laedt Herkunft neu, Ziel entladen" % label)
	if back is WhiteboxSector:
		_check((back as WhiteboxSector).has_detail(), "%s: neu geladene Herkunft mit Details" % label)


## Wegpunkte: im Sektor X -> Exit -> Boden entlang der Kurve -> Exit -> im Sektor Y.
func _route(gate: SeamlessLoadingGate, x: Node3D, y: Node3D) -> Array[Vector3]:
	var pts: Array[Vector3] = [_inside(x, gate.sector_b)]
	var off := 0.0
	while off <= gate.length:
		var f := gate.curve.sample_baked_with_rotation(off)
		pts.append(gate.to_global(f.origin - f.basis.y * (gate.cross_section.y * 0.5 - WALK_LIFT)))
		off += STEP
	pts.append(_inside(y, gate.sector_a))
	return pts


func _inside(sector: Node3D, exit_to: StringName) -> Vector3:
	var m := sector.get_node("Exits/" + str(exit_to)) as Node3D
	return m.global_position - m.global_basis.z * INSIDE + Vector3.UP * WALK_LIFT


## Indizes der Teilstrecken, auf denen die Kapsel haengen bleibt (leer = frei).
func _sweep_blocked(pts: Array[Vector3]) -> Array[int]:
	var out: Array[int] = []
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.exclude = [g.get_rid()]
	var space := g.get_world_3d().direct_space_state
	for i in pts.size() - 1:
		q.transform = Transform3D(Basis(), pts[i])
		q.motion = pts[i + 1] - pts[i]
		if space.cast_motion(q)[0] < 1.0:
			out.append(i)
	return out


# --- 2. RockPass-Varianten ------------------------------------------------------
func _test_pass_variants() -> void:
	print("RockPass-Varianten")
	var stats := {}
	for v in PV.values():
		var gate := (load(wm.ROCK_PASS_SCENES[v]) as PackedScene).instantiate() as RockPassTransition
		gate.position = FIXTURE_POS
		areas.add_child(gate)
		stats[v] = _pass_stats(gate)
		var end := gate.curve.sample_baked(gate.length)
		var exit := gate.get_node("ExitAnchor") as Node3D
		_check(exit.position.is_equal_approx(end - Vector3(0, gate.cross_section.y * 0.5, 0))
				and (gate.get_node("EntryAnchor") as Node3D).position.y == -gate.cross_section.y * 0.5,
				"%s: Anker am Boden der Kurven-Enden" % PV.keys()[v])
		gate.free()
	print("    Breite / Wand / Seitenausschlag / Hoehe / Bogen-Abstand / Anker-Hoehe / Ueberhang")
	for v in stats:
		print("    %-10s %s" % [PV.keys()[v], str(stats[v])])
	for key in ["width", "wall", "sway", "climb", "spacing", "anchor"]:
		var vals: Array = stats.values().map(func(s: Dictionary) -> float: return s[key])
		_check(vals.max() >= vals.min() * 1.5 + 1.0, "%s variiert spuerbar (%.1f .. %.1f)" % [key, vals.min(), vals.max()])
	var distinct := true
	for a in stats:
		for b in stats:
			if a < b and _differences(stats[a], stats[b]) < 3:
				distinct = false
	_check(distinct, "je zwei Varianten unterscheiden sich in mind. 3 Werten")
	_check(stats.values().any(func(s: Dictionary) -> bool: return s.overhangs)
			and stats.values().any(func(s: Dictionary) -> bool: return not s.overhangs), "Boegen und Ueberhaenge gemischt")


func _pass_stats(gate: RockPassTransition) -> Dictionary:
	var xs: Array[float] = []
	var ys: Array[float] = []
	for p in gate.curve.get_baked_points():
		xs.append(absf(p.x))
		ys.append(p.y)
	return {
		"width": gate.cross_section.x, "wall": gate.cross_section.y, "sway": xs.max(),
		"climb": ys.max() - ys.min() + 1.0, "spacing": gate.arch_spacing,
		"anchor": gate.arch_height * gate.cross_section.y, "overhangs": gate.overhangs,
	}


func _differences(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	for key in a:
		if key == "overhangs":
			n += int(a[key] != b[key])
		elif absf(a[key] - b[key]) > 0.2 * maxf(absf(a[key]), absf(b[key])):
			n += 1
	return n


func _test_assignment() -> void:
	print("Zuweisung auf der Karte")
	var uses := {}
	var regions := {}
	for l in map.links:
		if l.transition != TT.ROCK_PASS or l.monster_only:
			continue
		uses[l.pass_variant] = uses.get(l.pass_variant, 0) + 1
		var r: int = map.sector(l.from_sector).region
		if not regions.has(r):
			regions[r] = {}
		regions[r][l.pass_variant] = true
		if wm.scene_for(l) != wm.ROCK_PASS_SCENES[l.pass_variant]:
			_check(false, "%s -> %s: falsche Pass-Szene" % [l.from_sector, l.to_sector])
	_check(uses.size() == PV.size() and uses.values().all(func(n: int) -> bool: return n >= 2),
			"alle 4 Varianten mehrfach vergeben %s" % str(uses))
	var mixed := regions.values().filter(func(vs: Dictionary) -> bool: return vs.size() >= 2).size()
	_check(mixed >= 4, "%d Regionen mischen mehrere Pass-Varianten" % mixed)
	var trails := map.links.filter(func(l: SectorLink) -> bool: return l.transition == TT.LONG_TRAIL)
	var trail_regions := {}
	for l in trails:
		trail_regions[map.sector(l.to_sector).region] = true
	_check(trails.size() >= 3 and trail_regions.size() >= 3, "%d lange Wege in %d Regionen" % [
			trails.size(), trail_regions.size()])
	_check(wm.scene_for(trails[0]) == "res://scenes/transitions/long_trail_transition.tscn", "LONG_TRAIL -> eigene Szene")


# --- 3. Langer Weg --------------------------------------------------------------
func _test_long_trail() -> void:
	print("LongTrailTransition: Grob frueh, Details spaet")
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var link := map.link_between(&"center_south", &"desert_rocks")
	_check(link.transition == TT.LONG_TRAIL, "Suedterrasse -> Felswueste ist ein langer Weg")
	var x := _instance(map.sector(link.from_sector).scene_path)
	await _frames(1)
	var trail := wm.make_gate(link, link.from_sector, x) as LongTrailTransition
	areas.add_child(trail)
	await _frames(3)
	_check(trail.length > 300.0, "Weg %.0f m lang" % trail.length)
	await _put_at(trail, 6.0)
	var y := await _wait_area(trail, B) as WhiteboxSector
	await _frames(3)
	_check(y != null and trail.progress_of(g.global_position) < trail.length * 0.1, "Ziel dockt schon am Weganfang an")
	if y == null:
		return
	_check(not y.has_detail() and y.get_node_or_null("Detail") == null and y.get_node_or_null("Geometry") != null,
			"Ziel nur als Grob-Stufe (Boden, Waende, Landmarken)")
	var views := 0
	for f in SIGHT_FRACTIONS:
		var p := trail.to_global(trail.curve.sample_baked(trail.length * f))
		views += int(_landmark_visible(y, p + Vector3.UP * (EYE_HEIGHT - trail.cross_section.y * 0.5)))
	_check(views >= 1, "Landmarke im ersten Wegdrittel sichtbar (%d/%d Blickpunkte frei)" % [views, SIGHT_FRACTIONS.size()])
	await _put_at(trail, trail.length * 0.4)
	_check(trail.area(A) != null, "Herkunft bei 40 % noch geladen (offener Blick zurueck)")
	await _put_at(trail, trail.length * 0.55)
	await _frames(2)
	_check(trail.area(A) == null and not is_instance_valid(x), "Herkunft ab 50 % entladen")
	await _put_at(trail, trail.length * 0.75)
	_check(not y.has_detail(), "bei 75 % noch keine Details")
	await _put_at(trail, trail.length * 0.85)
	var detail := y.get_node_or_null("Detail") as StaticBody3D
	_check(y.has_detail() and detail != null and detail.get_child_count() > 0, "Naeherungszone: Details gebaut")
	_check(detail != null and _detail_collides(detail), "Detail-Anker mit Collision")
	_check(trail.is_barrier_open(B) and not trail.is_barrier_open(A), "Gate-Ablauf: Ziel offen, Herkunft zu")
	_place(_inside(y, link.from_sector))
	await _frames(4)
	_check(trail.travel_from == -1, "im Ziel angekommen")
	_cleanup([trail, y])
	await _frames(4)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_check(orphans <= orphans_before, "kein Speicher-Leck (verwaiste Nodes %d -> %d)" % [orphans_before, orphans])


## Strahl von from zur Spitze der hoechsten Saeule trifft zuerst diese Saeule.
func _landmark_visible(sector: WhiteboxSector, from: Vector3) -> bool:
	var body := sector.get_node("Geometry") as StaticBody3D
	var top := Vector3.ZERO
	var best := -1.0
	for c: CollisionShape3D in body.get_children():
		var s := (c.shape as BoxShape3D).size
		if s.y > best and s.y > WhiteboxSector.WALL_HEIGHT + 1.0:
			best = s.y
			top = c.global_position + Vector3.UP * (s.y * 0.5 - 1.0)
	var hit := _cast(from, top)
	return best > 0.0 and not hit.is_empty() and hit.collider == body \
			and (hit.position as Vector3).distance_to(top) < LANDMARK_HIT_RADIUS


func _detail_collides(detail: StaticBody3D) -> bool:
	var c := detail.get_child(0) as CollisionShape3D
	var hit := _cast(c.global_position + Vector3.UP * 200.0, c.global_position)
	return not c.disabled and not hit.is_empty() and hit.collider == detail


# --- Helfer ---------------------------------------------------------------
func _instance(path: String) -> Node3D:
	_place(PARK_POS)
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.position = FIXTURE_POS
	areas.add_child(node)
	return node


func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()


func _put_at(gate: SeamlessLoadingGate, offset: float) -> void:
	_place(gate.to_global(gate.curve.sample_baked(offset)))
	await _frames(2)


func _place(pos: Vector3) -> void:
	g.global_position = pos
	g.velocity = Vector3.ZERO
	g.reset_physics_interpolation()


func _wait_area(gate: SeamlessLoadingGate, end: int) -> Node3D:
	for i in LOAD_TIMEOUT_FRAMES:
		if gate.area(end) != null:
			return gate.area(end)
		await process_frame
	return null


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [g.get_rid()])
	return g.get_world_3d().direct_space_state.intersect_ray(q)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	print(("  [OK]   " if ok else "  [FAIL] ") + label)
	if not ok:
		_fails += 1
