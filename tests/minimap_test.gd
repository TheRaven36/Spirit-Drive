extends SceneTree
## Headless-Test fuer die Minimap: Kartenpositionen (Kleeblatt-Layout), gezoomte Ansicht = aktueller
## Sektor + Nachbarn, Spieler-Punkt (auch anteilig im Uebergang), Vollkarte per toggle_map.
## Aufruf: godot --headless --path . --script res://tests/minimap_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

const R := WorldSectorData.Region
const LOAD_TIMEOUT_FRAMES := 900

var _fails := 0
var world: Node
var g: GuardianController
var wm: WorldMapManager
var mini: MiniMap
var full: MiniMap


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	g = world.get_node("Guardian")
	g.get_node("SpiritEntity").process_mode = Node.PROCESS_MODE_DISABLED
	wm = world.get_node("WorldMap")
	mini = world.get_node("Map/MiniMap")
	full = world.get_node("Map/FullMap")
	await _frames(10)

	_test_layout()
	_test_zoomed_view()
	await _test_player_in_tunnel()
	await _test_toggle_full_map()

	print("MINIMAP TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


func _test_layout() -> void:
	print("Kartenpositionen")
	var seen := {}
	for s in wm.map.sectors:
		seen[s.map_position] = true
	_check(seen.size() == wm.map.sectors.size(), "jeder Sektor hat eine eigene Kartenposition")
	var c := wm.map.sector(&"center_crossing").map_position
	var quad := {
		R.LOOP_NATURE: Vector2(-1, -1), R.LOOP_MOUNTAIN: Vector2(1, -1),
		R.LOOP_SWAMP: Vector2(1, 1), R.LOOP_DESERT: Vector2(1, 1),
	}
	for region: int in quad:
		var mid := Vector2.ZERO
		var secs := wm.map.in_region(region)
		for s in secs:
			mid += s.map_position / secs.size()
		var d := (mid - c).sign()
		_check(d == quad[region], "%s liegt als Blatt %s vom Zentrum" % [R.keys()[region], str(quad[region])])
	_check(wm.map.sector(&"hq").map_position.y > c.y + 5.0, "HQ unten am Staengel")


func _test_zoomed_view() -> void:
	print("Gezoomte Minimap (Start in der Hoehle)")
	_check(mini.visible and not full.visible, "Minimap sichtbar, Vollkarte zu")
	_check(mini.current_sector() == &"cathedral_cave", "aktueller Sektor: Kathedralen-Hoehle")
	_check(Array(mini.focus_sectors()) == [&"cathedral_cave", &"hq"], "Fokus: Hoehle + HQ")
	var view := mini.target_view()
	_check(view.has_point(_pos(&"hq")) and not view.has_point(_pos(&"center_crossing")),
			"Ausschnitt zeigt Nachbarn, nicht das Zentrum")
	var all := full.target_view()
	_check(wm.map.sectors.all(func(s: WorldSectorData) -> bool: return all.has_point(s.map_position)),
			"Vollkarte enthaelt alle %d Sektoren" % wm.map.sectors.size())


func _test_player_in_tunnel() -> void:
	print("Spieler-Punkt")
	_check(mini.player_map_position() == _pos(&"cathedral_cave"), "im Sektor auf dessen Kartenposition")
	var tunnel := world.get_node("Areas/Tunnel") as SeamlessLoadingGate
	_place(tunnel.to_global(tunnel.curve.sample_baked(tunnel.length * 0.25)))
	await _frames(2)
	var expect := _pos(&"cathedral_cave").lerp(_pos(&"hq"), 0.25)
	_check(mini.player_map_position().distance_to(expect) < 0.05, "im Tunnel anteilig auf der Linie (25 %)")
	_place(tunnel.to_global(tunnel.curve.sample_baked(tunnel.length * 0.5)))
	for i in LOAD_TIMEOUT_FRAMES:
		if tunnel.area(SeamlessLoadingGate.End.B) != null:
			break
		await process_frame
	var hq := tunnel.area(SeamlessLoadingGate.End.B)
	_place(hq.get_node("Spawn").global_position + Vector3.UP)
	await _frames(4)
	_check(mini.current_sector() == &"hq" and Array(mini.focus_sectors()) == [&"hq", &"cathedral_cave", &"stem_1"],
			"im HQ: Fokus HQ + erreichbare Nachbarn, ohne Einbahn-Ankunft (%s)" % str(mini.focus_sectors()))
	mini.queue_redraw()
	full.queue_redraw()
	await _frames(3)


func _test_toggle_full_map() -> void:
	print("Vollkarte")
	var ev := InputEventAction.new()
	ev.action = "toggle_map"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_check(full.visible and not mini.visible, "toggle_map oeffnet die Vollkarte (Ecken-Minimap aus)")
	Input.parse_input_event(ev)
	await _frames(3)
	_check(not full.visible and mini.visible, "toggle_map schliesst sie wieder")


# --- Helfer ---------------------------------------------------------------
func _pos(id: StringName) -> Vector2:
	return wm.map.sector(id).map_position


func _place(pos: Vector3) -> void:
	g.global_position = pos
	g.velocity = Vector3.ZERO
	g.reset_physics_interpolation()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	print(("  [OK]   " if ok else "  [FAIL] ") + label)
	if not ok:
		_fails += 1
