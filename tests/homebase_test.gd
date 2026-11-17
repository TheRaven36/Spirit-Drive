extends SceneTree
## Headless-Test fuer die Homebase (Phase 3A): 4 Stationen, gemeinsame Interaktion (F / ESC,
## Bewegung pausiert), freie 9-Spirit-Kombination ohne Duplikate, Truhe, Schmied, Haendler,
## SafeZone (Spirit bleibt in FOLLOW_PROTECT).
## Aufruf: godot --headless --path . --script res://tests/homebase_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

## Freier Platz ausserhalb der Hoehle fuer die Test-Homebase.
const BASE_POS := Vector3(400, 0, 0)

var _fails := 0
var world: Node
var g: GuardianController
var base: HomebaseOutpost
var win: StationWindow


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	g = world.get_node("Guardian")
	base = load("res://scenes/homebase_outpost.tscn").instantiate()
	base.position = BASE_POS
	world.get_node("Areas").add_child(base)
	win = base.get_node("StationWindow")
	await _frames(10)

	_test_layout()
	await _test_interaction()
	await _test_altar()
	await _test_stash()
	await _test_forge()
	await _test_merchant()
	await _test_safe_zone()

	print("HOMEBASE TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


func _test_layout() -> void:
	print("Aufbau")
	var st := base.stations()
	var kinds := st.map(func(s: InteractionStation) -> String: return s.get_script().get_global_name())
	_check(st.size() == 4 and kinds.has("SpiritAltar") and kinds.has("EquipmentStash")
			and kinds.has("ForgeStation") and kinds.has("MerchantStation"), "4 Stationen: %s" % [kinds])
	var zone: Area3D = base.get_node("SafeZone")
	var size: Vector3 = (zone.get_node("Shape") as CollisionShape3D).shape.size
	_check(zone.is_in_group("safe_zone") and size == Vector3(26, 10, 26), "SafeZone 26 x 26 x 10 m")
	var down := _cast(BASE_POS + Vector3(5, 5, 5), BASE_POS + Vector3(5, -5, 5))
	var up := _cast(BASE_POS + Vector3(5, 5, 5), BASE_POS + Vector3(5, 15, 5))
	_check(not down.is_empty() and absf(down.position.y - BASE_POS.y) < 0.05
			and not up.is_empty() and absf(up.position.y - BASE_POS.y - 10.0) < 0.05, "Boden + Decke (10 m) mit Collision")
	var door := _cast(BASE_POS + Vector3(0, 5, 0), BASE_POS + Vector3(0, 5, -30))
	_check(door.is_empty(), "Tor auf -Z offen")
	_check(base.get_node("SpiritAltar").position.length() < 3.0, "Altar in der Mitte")


func _test_interaction() -> void:
	print("Interaktion (F / ESC)")
	var forge: InteractionStation = base.get_node("Forge")
	await _stand_at(forge)
	_check(forge.guardian == g and forge._prompt.visible, "Trigger: Hinweis [F] Interagieren")
	await _key(KEY_F)
	_check(forge.is_open() and win.visible and g.controls_locked, "F oeffnet das Fenster, Steuerung gesperrt")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Maus frei")
	Input.action_press("move_forward")
	Input.action_press("jump")
	await _frames(20)
	Input.action_release("move_forward")
	Input.action_release("jump")
	_check(Vector2(g.velocity.x, g.velocity.z).length() < 0.1 and g.is_on_floor(), "Bewegung pausiert")
	await _key(KEY_F)
	_check(not win.visible and not g.controls_locked, "F schliesst")
	await _key(KEY_F)
	await _key(KEY_ESCAPE)
	_check(not win.visible and not g.controls_locked and forge._prompt.visible, "ESC schliesst")


func _test_altar() -> void:
	print("Spirit-Altar")
	var altar: SpiritAltar = base.get_node("SpiritAltar")
	var roster := g.spirit_roster
	await _stand_at(altar)
	altar.open()
	_check(win._tabs.get_tab_count() == 1 and win._tabs.get_child(0).get_child_count() == 10,
			"9 Spirits + Uebernehmen-Zeile")
	var all := SpiritLibrary.load_all()
	var combos := 0
	var ok := 0
	for a in 9:
		for b in range(a + 1, 9):
			for c in range(b + 1, 9):
				combos += 1
				altar.selection.assign([all[a], all[b], all[c]])
				if altar.apply_selection() and roster.spirits == altar.selection:
					ok += 1
	_check(combos == 84 and ok == 84, "alle %d 3er-Kombinationen frei waehlbar (%d ok)" % [combos, ok])
	altar.selection.assign([all[0], all[0], all[4]])
	_check(not altar.apply_selection() and not roster.spirits.has(all[0]), "Duplikate abgelehnt")
	altar.selection.clear()
	for i in 4:
		altar.toggle_spirit(all[i])
	_check(altar.selection.size() == 3, "mehr als 3 nicht waehlbar")
	altar.selection.assign([all[0], all[3], all[6]])  # Feuer, Licht, Leben (Standard)
	altar.apply_selection()
	altar.close()


func _test_stash() -> void:
	print("Lagertruhe")
	var stash: EquipmentStash = base.get_node("EquipmentStash")
	var p := g.progress
	await _stand_at(stash)
	stash.open()
	_check(win._tabs.get_tab_count() == 3, "Tabs Rucksack / Truhe / Ausruestung")
	_check(p.move_item("riesen_splitter", true) and p.stash.has("riesen_splitter")
			and not p.backpack.has("riesen_splitter"), "Beute in die Truhe legen")
	_check(p.equip("titan_set") and p.equipped.armor == "titan_set" and p.stash.has("leder_set"),
			"Ausruestung aus der Truhe anlegen (altes Teil zurueck in die Truhe)")
	_check(not p.equip("riesen_splitter"), "Beute ist nicht anlegbar")
	stash.close()


func _test_forge() -> void:
	print("Schmied")
	var forge: ForgeStation = base.get_node("Forge")
	var p := g.progress
	await _stand_at(forge)
	forge.open()
	_check(win._tabs.get_tab_count() == 3 and win._tabs.get_tab_title(0) == "Grappling Hook"
			and win._tabs.get_tab_title(1) == "Waffe" and win._tabs.get_tab_title(2) == "Ruestung / Set",
			"Kategorien Grappling Hook / Waffe / Ruestung")
	var gold0 := p.gold()
	var range0 := g.grapple_range
	var ab0 := g.knife.armor_break_multiplier
	var hp0 := g.health.max_hp
	_check(p.buy_upgrade("hook_range") and is_equal_approx(g.grapple_range, range0 * 1.05)
			and p.gold() == gold0 - 100, "+5 %% Grapple-Range (%.1f m)" % g.grapple_range)
	_check(p.buy_upgrade("armor_break") and is_equal_approx(g.knife.armor_break_multiplier, ab0 * 1.1),
			"+10 %% Armor-Break (x%.2f)" % g.knife.armor_break_multiplier)
	_check(p.buy_upgrade("vitality") and is_equal_approx(g.health.max_hp, hp0 * 1.1), "Set: +10 %% HP")
	p.materials.gold = 0
	_check(not p.buy_upgrade("hook_speed"), "ohne Material kein Upgrade")
	forge.close()
	p.materials.gold = 500


func _test_merchant() -> void:
	print("Haendler")
	var m: MerchantStation = base.get_node("Merchant")
	var p := g.progress
	await _stand_at(m)
	m.open()
	_check(win._tabs.get_tab_count() == 2 and win._tabs.get_tab_title(0) == "Guardian"
			and win._tabs.get_tab_title(1) == "Spirit", "Tabs Guardian / Spirit")
	_check(p.buy_good("heal_potion") and p.buy_good("elemental_gel") and p.consumables.heal_potion == 1
			and p.consumables.elemental_gel == 1 and p.gold() == 500 - 110, "Heiltrank + Elementar-Gel gekauft")
	m.close()


func _test_safe_zone() -> void:
	print("SafeZone")
	var sp: SpiritEntity = g.get_node("SpiritEntity")
	var foe := (load("res://scenes/props/training_dummy.tscn") as PackedScene).instantiate() as Node3D
	foe.position = Vector3(4, 1, -4)
	base.add_child(foe)
	g.global_position = BASE_POS + Vector3(0, 1.2, -6)
	g.velocity = Vector3.ZERO
	g.reset_physics_interpolation()
	await _frames(10)
	_check(sp.guardian_in_safe_zone(), "Guardian in der SafeZone")
	g.hard_lock = foe
	await _frames(5)
	_check(sp.current_target() == null and sp.guard_target == null
			and sp.state == SpiritEntity.State.FOLLOW_PROTECT, "Spirit bleibt in FOLLOW_PROTECT (trotz Gegner + Lock)")
	g.release_hard_lock()
	foe.queue_free()


# --- Helfer ---------------------------------------------------------------
func _stand_at(s: InteractionStation) -> void:
	g.global_position = s.global_position + Vector3(0, 1.2, -2.2)
	g.velocity = Vector3.ZERO
	g.reset_physics_interpolation()
	await _frames(6)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [g.get_rid()])
	return g.get_world_3d().direct_space_state.intersect_ray(q)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	print(("  [OK]   " if ok else "  [FAIL] ") + label)
	if not ok:
		_fails += 1
