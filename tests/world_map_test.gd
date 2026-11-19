extends SceneTree
## Headless-Test fuer das Kleeblatt-Weltgeruest (Phase 3E):
##   1. Datengetriebener Graph: HQ, Staengel, Zentrum, 4 Schleifen mit Dead-End-Nischen,
##      monster_only, Einbahnstrassen, keine Sektor-Obergrenze, Hardcore-Platzhalter, Whitebox-Szenen.
##   2. Sperren: ROCK_BLOCK / BURNABLE_GROWTH / CLASH_TREE blockieren Durchgang + Laden, unlock_gate() oeffnet.
##   3. Lager (CampUnlockState) + Schnellreise nur aus einer SafeZone.
##   4. Streaming-Kette ueber den WorldMapManager (immer nur das aktive Areal geladen).
## Aufruf: godot --headless --path . --script res://tests/world_map_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

const A := SeamlessLoadingGate.End.A
const B := SeamlessLoadingGate.End.B
const R := WorldSectorData.Region
const CAMP := WorldSectorData.CampUnlockState
const BLOCK := SectorLink.GateBlockType
const LOAD_TIMEOUT_FRAMES := 900
## Freie Flaeche fuer die einzelnen Sperr-Test-Gates (weit weg von der Hoehle).
const BLOCK_TEST_ORIGIN := Vector3(3000, 0, 0)

var _fails := 0
var map: WorldMapData
var world: Node
var g: GuardianController
var wm: WorldMapManager


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	map = load("res://data/world/kleeblatt_world.tres")
	_test_graph_structure()
	_test_loops()
	_test_monster_and_one_way()
	_test_no_sector_limit()
	_test_hardcore_placeholder()
	_test_sector_scenes()

	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	g = world.get_node("Guardian")
	g.get_node("SpiritEntity").process_mode = Node.PROCESS_MODE_DISABLED
	wm = world.get_node("WorldMap")
	await _frames(10)

	await _test_gate_blocks()
	_test_camp_states()
	await _test_chain_to_hq()
	await _test_fast_travel()
	await _test_chain_from_center()

	print("WORLD MAP TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


# --- 1. Graph -------------------------------------------------------------
func _test_graph_structure() -> void:
	print("Kleeblatt-Graph")
	var ids := {}
	for s in map.sectors:
		ids[s.id] = true
	_check(ids.size() == map.sectors.size() and map.sectors.size() >= 15,
			"%d eindeutige Sektoren (Richtwert 15-20+, ohne Obergrenze)" % map.sectors.size())
	_check(map.links.all(func(l: SectorLink) -> bool: return ids.has(l.from_sector) and ids.has(l.to_sector)),
			"alle %d Links verbinden existierende Sektoren" % map.links.size())
	_check(map.sector(map.start_sector).region == R.HEADQUARTERS
			and map.sector(map.start_sector).camp == WorldSectorData.CampKind.HEADQUARTERS, "Start = Hauptquartier")
	_check(map.in_region(R.STEM).size() >= 3 and map.in_region(R.CENTER).size() >= 3,
			"Staengel %d / Zentrum %d Sektoren" % [map.in_region(R.STEM).size(), map.in_region(R.CENTER).size()])
	var stem_path := map.find_path(&"hq", &"center_crossing")
	var via_stem := stem_path.slice(1, -1).all(func(id: StringName) -> bool: return map.sector(id).region == R.STEM)
	_check(stem_path.size() >= 5 and via_stem, "HQ -> Zentrum ueber %d Staengel-Sektoren" % (stem_path.size() - 2))
	var kinds := {}
	for id in stem_path.slice(0, -1):
		kinds[map.link_between(id, stem_path[stem_path.find(id) + 1]).transition] = true
	_check(kinds.size() >= 2, "Staengel mit abwechselnden Uebergangs-Typen (%d)" % kinds.size())
	var unreachable := map.sectors.filter(func(s: WorldSectorData) -> bool:
			return map.find_path(&"hq", s.id).is_empty() or map.find_path(s.id, &"hq").is_empty())
	_check(unreachable.is_empty(), "jeder Sektor vom HQ erreichbar und zurueck (kein Softlock)")
	_check(map.sector(&"cathedral_cave").scene_path == "res://scenes/test_arena.tscn",
			"Kathedralen-Hoehle (test_arena) als Nische am HQ angebunden")


func _test_loops() -> void:
	print("4 Kleeblatt-Schleifen")
	var center_ids := map.in_region(R.CENTER).map(func(s: WorldSectorData) -> StringName: return s.id)
	for region in [R.LOOP_NATURE, R.LOOP_SWAMP, R.LOOP_MOUNTAIN, R.LOOP_DESERT]:
		var secs := map.in_region(region)
		var route := secs.filter(func(s: WorldSectorData) -> bool: return not s.dead_end)
		var niches := secs.filter(func(s: WorldSectorData) -> bool: return s.dead_end)
		var to_center := map.links.filter(func(l: SectorLink) -> bool: return not l.monster_only \
				and _is_loop_center_link(l, region, center_ids))
		var niche_ok := niches.all(func(s: WorldSectorData) -> bool: return map.neighbors(s.id).size() == 1)
		var name: String = R.keys()[region]
		_check(route.size() >= 3 and niches.size() >= 1 and niche_ok,
				"%s: %d Rundlauf-Sektoren + %d Dead-End-Nischen" % [name, route.size(), niches.size()])
		# Rundlauf: zwei verschiedene Anbindungen ans Zentrum (rein + raus).
		_check(to_center.size() >= 2, "%s: Schleife beginnt und endet im Zentrum (%d Anbindungen)" % [name, to_center.size()])
	_check(map.sector(&"nature_flatland").tags.has("flying_grapple_minions")
			and map.sector(&"nature_deep_forest").tags.has("hidden_adds"), "Natur: Metadaten Versteck-Adds + Flug-Minions")
	_check(map.sector(&"desert_monoliths").tags.has("monolith_anchors")
			and ["desert_rocks", "desert_sand", "desert_dunes"].all(func(id: String) -> bool:
				return map.sector(StringName(id)).region == R.LOOP_DESERT), "Wueste: Felsen -> Sand -> Duenen -> Monolithen")


func _is_loop_center_link(l: SectorLink, region: int, center_ids: Array) -> bool:
	var a := map.sector(l.from_sector)
	var b := map.sector(l.to_sector)
	return (a.region == region and center_ids.has(b.id)) or (b.region == region and center_ids.has(a.id))


func _test_monster_and_one_way() -> void:
	print("monster_only + Einbahnstrassen")
	var monster_links := map.links.filter(func(l: SectorLink) -> bool: return l.monster_only)
	_check(monster_links.size() >= 4, "%d exklusive Monster-Pfade" % monster_links.size())
	_check(not map.neighbors(&"nature_deep_forest").has(&"nature_lake")
			and map.neighbors(&"nature_deep_forest", true).has(&"nature_lake"), "Tiefer Wald -> See nur fuer Monster")
	var p_player := map.find_path(&"swamp_marsh", &"swamp_village")
	var p_monster := map.find_path(&"swamp_marsh", &"swamp_village", true)
	_check(p_monster.size() == 2 and p_player.size() > 2, "Sumpf: Monster flieht direkt (%d), Spieler laeuft (%d)" % [
			p_monster.size(), p_player.size()])
	var drop := map.link_between(&"mountain_summit", &"center_hollow")
	_check(drop.one_way and drop.transition == SectorLink.TransitionType.SLOPED_SHORTCUT,
			"Berg: Full-Circle-Drop als Einbahn-Shortcut")
	_check(map.neighbors(&"mountain_summit").has(&"center_hollow") and not map.neighbors(&"center_hollow").has(&"mountain_summit"),
			"Drop nur Gipfel -> Senke, nicht zurueck")
	_check(map.neighbors(&"center_crossing").has(&"hq") and not map.neighbors(&"hq").has(&"center_crossing"),
			"Abkuerzung Zentrum -> HQ als Einbahnstrasse")
	var blocks := {}
	for l in map.links:
		blocks[l.block] = true
	_check(blocks.has(BLOCK.ROCK_BLOCK) and blocks.has(BLOCK.BURNABLE_GROWTH) and blocks.has(BLOCK.CLASH_TREE),
			"Daten enthalten ROCK_BLOCK, BURNABLE_GROWTH und CLASH_TREE")


func _test_no_sector_limit() -> void:
	print("Keine Sektor-Obergrenze")
	var m := map.duplicate(true) as WorldMapData
	var before := m.sectors.size()
	for i in 5:
		var s := WorldSectorData.new()
		s.id = StringName("extra_%d" % i)
		s.region = R.LOOP_NATURE
		m.sectors.append(s)
		var l := SectorLink.new()
		l.from_sector = &"nature_lake" if i == 0 else StringName("extra_%d" % (i - 1))
		l.to_sector = s.id
		m.links.append(l)
	_check(m.sectors.size() == before + 5 and m.find_path(&"hq", &"extra_4").size() > 5,
			"5 Sektoren ergaenzt -> sofort im Graph erreichbar")
	m.sectors.remove_at(m.sectors.size() - 1)
	_check(m.sector(&"extra_4") == null and map.sector(&"extra_0") == null, "Entfernen ok, Original-Map unveraendert")


func _test_hardcore_placeholder() -> void:
	print("Hardcore-Kontrast-Map (Platzhalter)")
	var hc: WorldMapData = load("res://data/world/hardcore_contrast_map.tres")
	_check(hc != null and not hc.enabled and hc.map_id == &"hardcore_contrast", "Platzhalter-Map vorhanden, deaktiviert")
	_check(R.has("HARDCORE_FIRE") and R.has("HARDCORE_ICE"), "Regionen Feuer/Vulkan + Eis/Blizzard vorgemerkt")


func _test_sector_scenes() -> void:
	print("Whitebox-Szenen")
	var missing: Array[String] = []
	for s in map.sectors:
		if not ResourceLoader.exists(s.scene_path):
			missing.append(str(s.id))
			continue
		var node := (load(s.scene_path) as PackedScene).instantiate()
		for n in map.neighbors(s.id) + _incoming(s.id):
			if node.get_node_or_null("Exits/" + str(n)) == null:
				missing.append("%s/Exits/%s" % [s.id, n])
		if node is WhiteboxSector and node.get_node_or_null("Spawn") == null:
			missing.append("%s/Spawn" % s.id)
		if s.camp != WorldSectorData.CampKind.NONE and not (node.get_node_or_null("Camp") is HomebaseOutpost):
			missing.append("%s/Camp" % s.id)
		node.free()
	_check(missing.is_empty(), "alle Szenen mit Exit-Markern, Spawn und Camp %s" % str(missing))


## Nachbarn, die per Einbahnstrasse hereinkommen (brauchen ebenfalls einen Exit-Marker).
func _incoming(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for l in map.links_of(id):
		if not l.monster_only and l.one_way and l.to_sector == id:
			out.append(l.from_sector)
	return out


# --- 2. Sperren -----------------------------------------------------------
func _test_gate_blocks() -> void:
	print("Blockierte Uebergaenge")
	var cases := [
		[BLOCK.ROCK_BLOCK, "res://scenes/transitions/rock_pass_transition.tscn"],
		[BLOCK.BURNABLE_GROWTH, "res://scenes/organic_transition_tunnel.tscn"],
		[BLOCK.CLASH_TREE, "res://scenes/transitions/sloped_cave_shortcut.tscn"],
	]
	for i in cases.size():
		await _test_block(cases[i][0], cases[i][1], BLOCK_TEST_ORIGIN + Vector3(i * 600, 0, 0))
	var link := map.link_between(&"center_crossing", &"center_hollow")
	var fired := [false]
	wm.link_unlocked.connect(func(_l: SectorLink) -> void: fired[0] = true, CONNECT_ONE_SHOT)
	_check(wm.block_of(link) == BLOCK.ROCK_BLOCK, "Manager: Zentrum -> Senke startet mit ROCK_BLOCK")
	wm.unlock_link(link)
	_check(wm.block_of(link) == BLOCK.NONE and fired[0] and link.block == BLOCK.ROCK_BLOCK,
			"unlock_link: Laufzeit frei, Daten-Ressource unveraendert")


func _test_block(type: int, scene: String, origin: Vector3) -> void:
	var label: String = BLOCK.keys()[type]
	var gate := (load(scene) as PackedScene).instantiate() as SeamlessLoadingGate
	gate.position = origin
	gate.block_type = type
	gate.scene_b = "res://scenes/areas/world/stem_niche.tscn"
	gate.guardian_path = NodePath("../../Guardian")
	world.get_node("Areas").add_child(gate)
	await _frames(4)
	await _put_at(gate, 6.0)
	_check(gate.is_blocked() and gate.travel_from == -1 and not gate.is_loading(B), "%s: Loading Gate loest nicht aus" % label)
	_check(_blocked_mid(gate), "%s: Collision versperrt die Mitte" % label)
	gate.unlock_gate()
	await _frames(3)
	_check(not gate.is_blocked() and not _blocked_mid(gate), "%s: unlock_gate() gibt den Weg frei" % label)
	if type == BLOCK.CLASH_TREE:
		await create_timer(SeamlessLoadingGate.TREE_FALL_TIME + 0.2).timeout
		var tree := gate.get_node("Blocker/Tree") as Node3D
		_check(is_equal_approx(tree.rotation.z, PI * 0.5), "CLASH_TREE: Baum ist umgestuerzt (liegt quer)")
	else:
		_check(gate.get_node_or_null("Blocker") == null, "%s: Hindernis entfernt" % label)
	await _put_at(gate, 6.0)
	_check(gate.travel_from == A and (gate.is_loading(B) or gate.area(B) != null), "%s: danach laedt das Gate" % label)
	var area := await _wait_area(gate, B)
	_check(area != null, "%s: Ziel-Sektor angedockt" % label)
	if area != null:
		area.queue_free()
	gate.queue_free()
	await _frames(2)


## Strahl durch die Durchgangs-Mitte (auf halber Hoehe ueber dem Boden) entlang der Kurve.
func _blocked_mid(gate: SeamlessLoadingGate) -> bool:
	var lift := gate.cross_section.y * 0.25
	var f0 := gate.curve.sample_baked_with_rotation(gate.length * 0.5 - 8.0)
	var f1 := gate.curve.sample_baked_with_rotation(gate.length * 0.5 + 8.0)
	var hit := _cast(gate.to_global(f0.origin - f0.basis.y * lift), gate.to_global(f1.origin - f1.basis.y * lift))
	return not hit.is_empty()


# --- 3. Lager ---------------------------------------------------------------
func _test_camp_states() -> void:
	print("Lager-Zustaende (CampUnlockState)")
	var progress: GuardianProgress = g.get_node("Progress")
	_check(wm.camp_state(&"hq") == CAMP.TIER_1, "HQ startet als TIER_1")
	_check(wm.camp_state(&"center_crossing") == CAMP.UNDISCOVERED and not wm.build_camp(&"center_crossing", progress),
			"Zentrumslager unentdeckt, nicht baubar")
	wm.discover_camp(&"center_crossing")
	_check(wm.camp_state(&"center_crossing") == CAMP.AVAILABLE_FOR_BUILD, "entdeckt ohne Quest -> AVAILABLE_FOR_BUILD")
	wm.discover_camp(&"nature_flatland")
	_check(wm.camp_state(&"nature_flatland") == CAMP.LOCKED and not wm.build_camp(&"nature_flatland", progress),
			"Vorposten mit Liefer-Quest -> LOCKED, nicht baubar")
	wm.complete_camp_quest(&"nature_flatland")
	_check(wm.camp_state(&"nature_flatland") == CAMP.AVAILABLE_FOR_BUILD, "Quest erledigt -> AVAILABLE_FOR_BUILD")
	var gold := progress.gold()
	_check(wm.build_camp(&"center_crossing", progress) and wm.camp_state(&"center_crossing") == CAMP.TIER_1
			and progress.gold() == gold - 300, "Zentrumslager gebaut (300 Gold) -> TIER_1")
	_check(not wm.upgrade_camp(&"center_crossing", progress) and wm.camp_state(&"center_crossing") == CAMP.TIER_1,
			"Ausbau ohne genug Gold scheitert")
	progress.materials["gold"] = 1000
	_check(wm.upgrade_camp(&"center_crossing", progress) and wm.camp_state(&"center_crossing") == CAMP.UPGRADED,
			"Ausbau -> UPGRADED")


# --- 4. Streaming-Kette + Schnellreise ---------------------------------------
func _test_chain_to_hq() -> void:
	print("Kette Hoehle -> HQ")
	var tunnel := world.get_node("Areas/Tunnel") as SeamlessLoadingGate
	var hq := await _traverse(tunnel, A)
	_check(hq != null and wm.loaded_sectors() == [&"hq"], "nur das HQ geladen")
	_check(hq != null and (hq.get_node("Camp") as Node3D).visible, "HQ-Camp (TIER_1) sichtbar")
	var pass_gate := wm.gate_for(map.link_between(&"hq", &"stem_1"))
	_check(pass_gate is RockPassTransition and pass_gate.sector_a == &"hq", "Felspass HQ -> Staengel eingesetzt")
	_check(pass_gate != null and pass_gate.get_node("EntryAnchor").global_transform.is_equal_approx(
			hq.get_node("Exits/stem_1").global_transform), "Pass sitzt am Exit-Marker")
	var shortcut := wm.gate_for(map.link_between(&"center_crossing", &"hq"))
	_check(shortcut is SlopedCaveShortcut and shortcut.one_way_from == B, "Abkuerzung vom Zentrum: nur Richtung HQ")


func _test_fast_travel() -> void:
	print("Schnellreise")
	var hq := wm.sector_node(&"hq")
	_place(hq.get_node("Spawn").global_position + Vector3.UP)
	await _frames(4)
	_check(wm.is_in_safe_zone(g), "Guardian in der HQ-SafeZone")
	_check(not wm.can_fast_travel(g, &"swamp_ruins"), "kein Ziel: Lager noch nicht gebaut")
	_place(hq.global_position + Vector3(50, 1.2, 50))
	await _frames(4)
	_check(not wm.is_in_safe_zone(g) and not wm.fast_travel(g, &"center_crossing"), "ausserhalb der SafeZone gesperrt")
	_place(hq.get_node("Spawn").global_position + Vector3.UP)
	await _frames(4)
	_check(wm.fast_travel(g, &"center_crossing"), "aus der SafeZone zum Zentrumslager gestartet")
	for i in LOAD_TIMEOUT_FRAMES:
		if not wm.is_fast_travelling():
			break
		await process_frame
	await _frames(4)
	var cross := wm.sector_node(&"center_crossing")
	_check(cross != null and wm.loaded_sectors() == [&"center_crossing"] and not is_instance_valid(hq),
			"Szene gewechselt: nur das Zentrum geladen, HQ entladen")
	_check(cross != null and g.global_position.distance_to(cross.get_node("Spawn").global_position) < 3.0
			and wm.is_in_safe_zone(g), "Ankunft am Spawn im Zentrumslager")
	var player_links := map.links_of(&"center_crossing").filter(func(l: SectorLink) -> bool: return not l.monster_only)
	_check(player_links.all(func(l: SectorLink) -> bool: return wm.gate_for(l) != null),
			"alle %d Uebergaenge des Zentrums eingesetzt" % player_links.size())
	var hollow := wm.gate_for(map.link_between(&"center_crossing", &"center_hollow"))
	_check(hollow != null and not hollow.is_blocked(), "freigeschaltete Senke: Gate ohne Sperre")


func _test_chain_from_center() -> void:
	print("Kette Zentrum -> Sumpf-Dorf -> Ruinen")
	var village := await _traverse(wm.gate_for(map.link_between(&"swamp_village", &"center_crossing")), A)
	_check(village != null and wm.loaded_sectors() == [&"swamp_village"], "Dorf geladen, Zentrum entladen")
	_check(wm.gate_for(map.link_between(&"swamp_marsh", &"swamp_village")) == null, "Monster-Pfad ohne Spieler-Uebergang")
	_check(wm.gate_for(map.link_between(&"center_crossing", &"hq")) == null, "Uebergaenge des Zentrums freigegeben")
	var ruins := await _traverse(wm.gate_for(map.link_between(&"swamp_ruins", &"swamp_village")), A)
	_check(ruins != null and wm.loaded_sectors() == [&"swamp_ruins"], "Ruinen geladen, Dorf entladen")
	_check(wm.camp_state(&"swamp_ruins") == CAMP.LOCKED, "Vorposten beim Betreten entdeckt (LOCKED, Quest offen)")
	_place(ruins.get_node("Spawn").global_position + Vector3.UP)
	await _frames(4)
	var camp := ruins.get_node("Camp") as Node3D
	_check(not camp.visible and not wm.is_in_safe_zone(g), "ungebautes Lager: unsichtbar, keine SafeZone")
	var crypt := wm.gate_for(map.link_between(&"swamp_ruins", &"swamp_crypt"))
	_check(crypt != null and crypt.block_type == BLOCK.ROCK_BLOCK, "Krypta-Nische per ROCK_BLOCK versperrt")


## Guardian durch den Uebergang von Seite from tragen; liefert den angedockten Ziel-Sektor.
func _traverse(gate: SeamlessLoadingGate, from: int) -> Node3D:
	if gate == null:
		return null
	var to := B if from == A else A
	var start := 6.0 if from == A else gate.length - 6.0
	await _put_at(gate, start)
	await _put_at(gate, gate.length * 0.5)
	await _frames(2)
	var target := await _wait_area(gate, to)
	if target == null:
		return null
	var marker := target.get_node_or_null("Exits/" + str(gate.sector_at(from))) as Node3D
	_check(marker != null and marker.global_transform.is_equal_approx(
			gate.get_node("EntryAnchor" if to == A else "ExitAnchor").global_transform),
			"%s am Exit-Marker angedockt" % gate.sector_at(to))
	_place(marker.global_position - marker.global_basis.z * 12.0 + Vector3.UP * 1.2)
	await _frames(4)
	return target


# --- Helfer ---------------------------------------------------------------
func _put_at(gate: SeamlessLoadingGate, offset: float) -> void:
	_place(gate.to_global(gate.curve.sample_baked(offset)))
	await _frames(2)


func _place(pos: Vector3) -> void:
	g.global_position = pos
	g.velocity = Vector3.ZERO
	g.reset_physics_interpolation()


func _wait_area(gate: SeamlessLoadingGate, end: int) -> Node3D:
	for i in LOAD_TIMEOUT_FRAMES:
		if not is_instance_valid(gate):
			return null
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
