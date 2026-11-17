extends SceneTree
## Headless-Test fuer das Spirit-System (Phase 2A):
## 9 Spirit-Ressourcen, 3er-Roster (Feld 1/2/3, Waffen-Sockel Q/E) inkl. Signale,
## Saeulen-Multiplikatoren, Waffen-Spirit im Messer und Minimal-HUD.
## Aufruf: godot --headless --path . --script res://tests/spirit_system_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

var _fails := 0
var arena: Node
var g: GuardianController
var roster: SpiritRosterComponent
var hud: MinimalHUD

var _field_events: Array[SpiritData] = []
var _weapon_events: Array[SpiritData] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_resources()
	_test_pillar_matrix()

	arena = load("res://scenes/test_arena.tscn").instantiate()
	root.add_child(arena)
	g = arena.get_node("Guardian")
	roster = g.get_node("SpiritRoster")
	hud = arena.get_node("MinimalHUD")
	# Feld-Spirit-KI aus (Bodyguard wuerde den Messer-Test-Dummy treffen); Daten-Bindung bleibt.
	g.get_node("SpiritEntity").set_physics_process(false)
	roster.field_spirit_changed.connect(func(s: SpiritData) -> void: _field_events.append(s))
	roster.weapon_spirit_changed.connect(func(s: SpiritData) -> void: _weapon_events.append(s))
	await _frames(20)

	await _test_input_map()
	await _test_field_switching()
	await _test_weapon_socket()
	await _test_weapon_damage()
	await _test_set_roster()
	await _test_hud_slots()
	await _test_hud_hooks()
	await _test_hud_health()
	await _test_controls_overlay()

	print("SPIRIT TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


# --- Ressourcen -----------------------------------------------------------
func _test_resources() -> void:
	print("9 Spirit-Ressourcen")
	var all := SpiritLibrary.load_all()
	_check(all.size() == 9 and not all.has(null), "alle 9 .tres laden (%d)" % all.size())
	var elements := {}
	var colors := {}
	var per_pillar := {}
	var ok_fields := true
	for s in all:
		if s == null:
			continue
		elements[s.element] = true
		colors[s.theme_color.to_html()] = true
		per_pillar[s.pillar] = per_pillar.get(s.pillar, 0) + 1
		ok_fields = ok_fields and s.is_consistent() and s.spirit_name != "" \
				and s.special_effect_tag != "" and s.weapon_damage_multiplier == 1.0 \
				and s.evolution_stage == SpiritData.EvolutionStage.CORE
	_check(elements.size() == 9, "jedes Element genau einmal")
	_check(colors.size() == 9, "9 eindeutige Signalfarben")
	_check(per_pillar.get(SpiritData.Pillar.NATURE, 0) == 3 and per_pillar.get(SpiritData.Pillar.ORDER, 0) == 3
			and per_pillar.get(SpiritData.Pillar.CYCLE, 0) == 3, "je 3 Spirits pro Saeule")
	_check(ok_fields, "Saeule passt zum Element, Name/Tag gesetzt, Stufe CORE, Multiplikator 1.0")
	var tags := {
		SpiritData.Element.FIRE: "burn", SpiritData.Element.WATER: "slow",
		SpiritData.Element.EARTH: "stagger", SpiritData.Element.LIGHT: "blind",
		SpiritData.Element.SHADOW: "crit_dive", SpiritData.Element.GRAVITY: "pull_down",
		SpiritData.Element.LIFE: "lifesteal", SpiritData.Element.TIME: "echo_hit",
		SpiritData.Element.DEATH: "armor_decay",
	}
	var tags_ok := true
	for e: int in tags:
		tags_ok = tags_ok and SpiritLibrary.get_spirit(e).special_effect_tag == tags[e]
	_check(tags_ok, "Effekt-Tags je Element korrekt")


func _test_pillar_matrix() -> void:
	print("Saeulen-Multiplikator (NATURE > ORDER > CYCLE > NATURE)")
	var N := SpiritData.Pillar.NATURE
	var O := SpiritData.Pillar.ORDER
	var C := SpiritData.Pillar.CYCLE
	var m := SpiritRosterComponent.pillar_multiplier
	_check(m.call(N, O) == 1.5, "NATURE vs ORDER = 1.5x")
	_check(m.call(O, C) == 1.5, "ORDER vs CYCLE = 1.5x")
	_check(m.call(C, N) == 1.5, "CYCLE vs NATURE = 1.5x")
	_check(m.call(O, N) == 1.0 and m.call(C, O) == 1.0 and m.call(N, C) == 1.0, "Rueckrichtung = 1.0x")
	_check(m.call(N, N) == 1.0 and m.call(O, O) == 1.0 and m.call(C, C) == 1.0, "gleiche Saeule = 1.0x")


# --- Roster ---------------------------------------------------------------
func _test_input_map() -> void:
	print("Input-Map")
	var ok := true
	for a in ["field_spirit_1", "field_spirit_2", "field_spirit_3", "cycle_weapon_spirit_prev",
			"cycle_weapon_spirit_next", "toggle_controls_overlay"]:
		ok = ok and InputMap.has_action(a)
	_check(ok, "Spirit-Actions registriert")
	_check(_key_matches("cycle_weapon_spirit_prev", KEY_Q) and _key_matches("cycle_weapon_spirit_next", KEY_E),
			"Q = prev, E = next")
	_check(_key_matches("field_spirit_1", KEY_1) and _key_matches("field_spirit_3", KEY_3), "1 / 3 belegt")


func _test_field_switching() -> void:
	print("Feld-Spirit (1 / 2 / 3)")
	_check(roster.spirits.size() == 3 and roster.active_field_spirit_index == 0
			and roster.weapon_socket_spirit_index == 0, "Start: 3 Spirits, Feld = Waffe = Slot 1")
	var entity: SpiritEntity = g.get_node("SpiritEntity")
	_field_events.clear()
	await _key(KEY_2)
	_check(roster.active_field_spirit_index == 1, "Taste 2 -> Slot 2 aufs Feld")
	_check(_field_events.size() == 1 and _field_events[0] == roster.spirits[1],
			"Signal field_spirit_changed mit Slot-2-Daten")
	_check(entity.spirit == roster.spirits[1], "Feld-Spirit folgt dem Signal")
	await _key(KEY_2)
	_check(_field_events.size() == 1, "gleiche Taste erneut = kein doppeltes Signal")
	await _key(KEY_3)
	_check(roster.active_field_spirit_index == 2 and _field_events.size() == 2
			and _field_events[1] == roster.spirits[2], "Taste 3 -> Slot 3")
	await _key(KEY_1)
	_check(roster.active_field_spirit_index == 0 and _field_events[-1] == roster.spirits[0], "Taste 1 -> Slot 1")
	_check(roster.weapon_socket_spirit_index == 0 and _weapon_events.is_empty(),
			"Feld-Wechsel aendert den Waffen-Sockel nicht")


func _test_weapon_socket() -> void:
	print("Waffen-Sockel (Q / E)")
	_weapon_events.clear()
	await _key(KEY_E)
	_check(roster.weapon_socket_spirit_index == 1 and _weapon_events.size() == 1
			and _weapon_events[0] == roster.spirits[1], "E -> naechster Spirit + Signal")
	_check(g.knife.weapon_spirit == roster.spirits[1] and g.knife.trail_color == roster.spirits[1].theme_color,
			"Messer: Element + Trail-Farbe uebernommen")
	await _key(KEY_E)
	await _key(KEY_E)
	_check(roster.weapon_socket_spirit_index == 0 and _weapon_events.size() == 3, "E wickelt um (3 -> 1)")
	await _key(KEY_Q)
	_check(roster.weapon_socket_spirit_index == 2 and _weapon_events[-1] == roster.spirits[2],
			"Q rueckwaerts (1 -> 3)")
	await _key(KEY_Q)
	_check(roster.weapon_socket_spirit_index == 1, "Q -> Slot 2")
	_check(roster.active_field_spirit_index == 0, "Sockel-Wechsel aendert den Feld-Spirit nicht")
	roster.set_weapon_spirit(0)
	await _frames(1)


func _test_weapon_damage() -> void:
	print("Waffen-Spirit im Schaden")
	var fire: SpiritData = roster.spirits[0]
	_check(fire.pillar == SpiritData.Pillar.NATURE and g.knife.weapon_spirit == fire, "Feuer gesockelt")
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar p := 0\nfunc get_spirit_pillar() -> int:\n\treturn p\n"
	scr.reload()
	var foe: Node = scr.new()
	foe.p = SpiritData.Pillar.ORDER
	_check(is_equal_approx(g.knife.element_multiplier(foe), 1.5), "Feuer vs ORDER-Ziel = 1.5x")
	foe.p = SpiritData.Pillar.CYCLE
	_check(is_equal_approx(g.knife.element_multiplier(foe), 1.0), "Feuer vs CYCLE-Ziel = 1.0x")
	foe.p = SpiritData.Pillar.ORDER
	roster.set_weapon_spirit(2)  # Leben (CYCLE) vs ORDER -> neutral
	_check(is_equal_approx(roster.weapon_multiplier_against(SpiritData.Pillar.NATURE), 1.5)
			and is_equal_approx(g.knife.element_multiplier(foe), 1.0), "Leben: 1.5x nur gegen NATURE")
	foe.free()
	roster.set_weapon_spirit(0)
	# Echter Treffer am Dummy (ohne Saeule): Tag am Treffer, Schaden unveraendert.
	var d: TrainingDummy = null
	for c in arena.get_children():
		if c is TrainingDummy and (c as Node3D).global_position.distance_to(Vector3(7, 1, -20)) < 1.0:
			d = c
	g._release_all_hooks()
	g.global_position = Vector3(7, 1.2, -17.8)
	g.velocity = Vector3.ZERO
	g._yaw = 0.0
	g._pitch = -0.1
	g._vel_history.clear()
	g.reset_physics_interpolation()
	await _frames(4)
	var hp0 := d.hp
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(15)
	var h := g.knife.last_hit
	_check(hp0 - d.hp > 0.0 and h.get("effect_tag", "") == "burn" and h.get("element", "") == "FIRE",
			"Treffer traegt Element + Tag (burn)")
	_check(absf((hp0 - d.hp) - g.knife.min_damage) < 0.6 and is_equal_approx(h.get("element_mult", 0.0), 1.0),
			"neutrales Ziel = Basis-Schaden (%.1f)" % (hp0 - d.hp))
	await _frames(30)


func _test_set_roster() -> void:
	print("Roster-Auswahl")
	var old := roster.spirits.duplicate()
	var bad: Array[SpiritData] = [SpiritLibrary.get_spirit(SpiritData.Element.WATER)]
	_check(not roster.set_roster(bad), "falsche Groesse wird abgelehnt")
	var pick: Array[SpiritData] = [
		SpiritLibrary.get_spirit(SpiritData.Element.WATER),
		SpiritLibrary.get_spirit(SpiritData.Element.GRAVITY),
		SpiritLibrary.get_spirit(SpiritData.Element.TIME),
	]
	_field_events.clear()
	_weapon_events.clear()
	_check(roster.set_roster(pick) and roster.spirits[1].element == SpiritData.Element.GRAVITY
			and _field_events.size() == 1 and _weapon_events.size() == 1, "neues 3er-Roster + Signale")
	_check(roster.reserve_indices() == [1, 2], "Reserve = nicht benutzte Slots")
	var restore: Array[SpiritData] = []
	restore.assign(old)
	roster.set_roster(restore)
	await _frames(1)


# --- HUD ------------------------------------------------------------------
func _test_hud_slots() -> void:
	print("HUD: Spirit-Slots")
	roster.set_field_spirit(1)
	roster.set_weapon_spirit(2)
	await _process_frames(1)
	var ok_col := true
	for i in 3:
		ok_col = ok_col and hud.slots[i].spirit == roster.spirits[i]
	_check(ok_col, "3 Slots zeigen die Roster-Spirits (theme_color)")
	_check(not hud.slots[0].is_field and hud.slots[1].is_field and not hud.slots[2].is_field,
			"Feld-Highlight nur auf Slot 2")
	_check(not hud.slots[0].is_weapon and not hud.slots[1].is_weapon and hud.slots[2].is_weapon,
			"Waffen-Kern nur auf Slot 3")
	await _key(KEY_1)
	await _key(KEY_Q)
	_check(hud.slots[0].is_field and hud.slots[1].is_weapon, "HUD folgt Tasten-Wechseln")
	roster.set_weapon_spirit(0)


func _test_hud_hooks() -> void:
	print("HUD: Haken-Indikatoren")
	var L := hud.hook_left_ind
	var R := hud.hook_right_ind
	await _process_frames(1)
	_check(L.is_ready() and R.is_ready() and L.ratio == 1.0, "Start: beide Haken bereit")
	var fired: Array = []
	g.hook_fired.connect(func(h: GrappleHook) -> void: fired.append(h), CONNECT_ONE_SHOT)
	g.hook_left.attach(g.global_position + Vector3(0, 10, -5), null, g.global_position)
	await _process_frames(1)
	_check(fired.size() == 1 and fired[0] == g.hook_left, "Signal hook_fired (links)")
	_check(L.active and L.ratio == 0.0 and not L.is_ready() and R.is_ready(), "abgefeuert = links ausgegraut")
	g.hook_left.release()
	await _frames(int(g.hook_cooldown * 30.0))
	await _process_frames(1)
	_check(not L.active and L.ratio > 0.1 and L.ratio < 0.95, "Cooldown fuellt sich auf (%.2f)" % L.ratio)
	_check(g._take_free_hip() == g.hook_right, "Werfer im Cooldown wird uebersprungen")
	await _frames(int(g.hook_cooldown * 60.0) + 2)
	await _process_frames(1)
	_check(L.is_ready() and L.ratio == 1.0, "nach Cooldown wieder bereit")


func _test_hud_health() -> void:
	print("HUD: HP-Balken")
	var hp: HealthComponent = g.get_node("Health")
	_check(hud.hp_bar.visible and hud.hp_bar.value == hp.max_hp, "voll beim Start")
	hp.take_damage(25.0)
	_check(is_equal_approx(hud.hp_bar.value, hp.max_hp - 25.0), "Schaden senkt den Balken")
	hp.reset()
	_check(hud.hp_bar.value == hp.max_hp, "Reset fuellt auf")


func _test_controls_overlay() -> void:
	print("HUD: Steuerungs-Overlay (+)")
	_check(not hud.controls_overlay.visible, "standardmaessig unsichtbar")
	await _key(KEY_PLUS, true)
	_check(hud.controls_overlay.visible, "+ blendet ein")
	_check(hud._controls_grid.get_child_count() == MinimalHUD.CONTROLS.size() * 2, "Belegung gelistet")
	await _key(KEY_PLUS, true)
	_check(not hud.controls_overlay.visible, "+ erneut blendet aus")
	await _key(KEY_KP_ADD)
	_check(hud.controls_overlay.visible, "Num+ funktioniert auch")
	await _key(KEY_KP_ADD)
	_check(MinimalHUD.key_text(&"cycle_weapon_spirit_next") == "E", "Tastennamen aus der InputMap")


# --- Helfer ---------------------------------------------------------------
func _key_matches(action: String, key: Key) -> bool:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	return InputMap.event_is_action(ev, action, true)


## Echter Tastendruck durch die Engine (Input -> _unhandled_input).
func _key(key: Key, label_only := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		if not label_only:
			ev.physical_keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _process_frames(1)
	await _frames(1)


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
