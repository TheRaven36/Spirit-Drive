extends SceneTree
## Headless-Test fuer den Feld-Spirit (SpiritEntity, Phase 2B):
## Spawn + Farbe, Live-Wechsel (1 -> 2), FOLLOW_PROTECT, Bodyguard, Hard-Lock-Befehl
## (CHASE/ATTACK + Schaden, Ziel-Wechsel), Leine an die Grapple-Reichweite (physischer
## Rueckweg, kein Teleport), Rueckruf per Halten (0.5 s) und per Doppelklick.
## Aufruf: godot --headless --path . --script res://tests/spirit_entity_test.gd
## Exit-Code 0 = alles ok, 1 = Fehler.

## Freie Flaeche ohne Dummy im guard_radius (naechster Dummy > 10 m).
const OPEN_SPOT := Vector3(-10, 1.2, -8)
const NEAR_FOCUS := Vector3(3, 1.2, -30)
## ~78 m vom Fokus-Dummy: ausserhalb der Grapple-Reichweite (70 m), Lock bleibt aber bestehen.
const LEASH_SPOT := Vector3(60, 1.2, -90)

var _fails := 0
var arena: Node
var g: GuardianController
var sp: SpiritEntity
var roster: SpiritRosterComponent


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	arena = load("res://scenes/test_arena.tscn").instantiate()
	root.add_child(arena)
	g = arena.get_node("Guardian")
	sp = g.get_node("SpiritEntity")
	roster = g.spirit_roster
	await _frames(20)

	await _test_spawn()
	await _test_switch()
	await _test_follow()
	await _test_bodyguard()
	await _test_hard_lock_attack()
	await _test_leash()
	await _test_hold_recall()
	await _test_double_click_recall()

	print("SPIRIT ENTITY TEST: %s" % ("OK" if _fails == 0 else "%d FEHLER" % _fails))
	quit(1 if _fails > 0 else 0)


func _test_spawn() -> void:
	print("Spawn")
	var d := _flat(sp.global_position, g.global_position)
	_check(sp.spirit == roster.field_spirit() and sp.visible, "Feld-Spirit aus dem Roster des Guardians")
	_check(d >= sp.follow_min and d <= sp.follow_max, "spawnt neben dem Guardian (%.1f m)" % d)
	_check(_mat().albedo_color == roster.field_spirit().theme_color and _mat().emission_enabled,
			"Farbe = theme_color mit Glow")
	_check(sp.collision_layer == 2, "eigener Kollisions-Layer (Guardian-Raycasts ignorieren ihn)")


func _test_switch() -> void:
	print("Live-Wechsel (1 -> 2)")
	var pos := sp.global_position
	await _key(KEY_2)
	_check(sp.spirit == roster.spirits[1], "Taste 2: neue Spirit-Daten")
	_check(_mat().albedo_color == roster.spirits[1].theme_color, "Taste 2: neue Farbe")
	_check(sp.get_node("Visual").scale.x > 1.05, "Scale-Pop beim Wechsel")
	_check(_flat(sp.global_position, pos) < 1.0, "bleibt an seiner Position")
	await _frames(30)
	_check(is_equal_approx(sp.get_node("Visual").scale.x, 1.0), "Pop federt zurueck")
	await _key(KEY_1)


func _test_follow() -> void:
	print("FOLLOW_PROTECT")
	await _place(OPEN_SPOT)
	await _frames(150)
	var d := _flat(sp.global_position, g.global_position)
	_check(sp.state == SpiritEntity.State.FOLLOW_PROTECT and sp.current_target() == null,
			"ohne Lock / ohne Gegner: FOLLOW_PROTECT")
	_check(d >= sp.follow_min - 0.3 and d <= sp.follow_max + 0.3, "folgt und haelt Abstand (%.1f m)" % d)
	_check(sp.is_on_floor(), "laeuft am Boden")
	# Guardian versetzt sich 20 m weiter -> Spirit laeuft hinterher
	await _place(OPEN_SPOT + Vector3(0, 0, 20))
	await _frames(120)
	d = _flat(sp.global_position, g.global_position)
	_check(d <= sp.follow_max + 0.3, "laeuft dem Guardian nach (%.1f m)" % d)


func _test_bodyguard() -> void:
	print("Bodyguard")
	var dummy := _dummy_near(Vector3(-7, 1, -24))
	await _place(Vector3(-7, 1.2, -19))  # 5 m vor dem Dummy, kein Lock
	var hp0 := dummy.hp
	await _frames(180)
	_check(sp.guard_target == dummy, "Gegner < guard_radius -> Spirit greift an")
	_check(dummy.hp < hp0, "Bodyguard-Treffer (%.0f Schaden)" % (hp0 - dummy.hp))
	await _place(OPEN_SPOT)
	await _frames(150)
	_check(sp.current_target() == null and sp.state == SpiritEntity.State.FOLLOW_PROTECT
			and _flat(sp.global_position, g.global_position) <= sp.follow_max + 0.3,
			"Guardian weg vom Gegner -> zurueck in FOLLOW_PROTECT")


func _test_hard_lock_attack() -> void:
	print("Hard-Lock-Befehl")
	var dummy := _dummy_near(Vector3(0, 1, -40))
	await _place(NEAR_FOCUS)
	await _frames(60)
	var hp0 := dummy.hp
	g.hard_lock = dummy
	await _frames(2)
	_check(sp.combat_target == dummy and sp.state == SpiritEntity.State.CHASE, "Lock -> combat_target, CHASE")
	var seen_attack := false
	var hits: Array = []
	sp.hit_landed.connect(func(t: Node, dmg: float, tag: String, pos: Vector3) -> void:
		hits.append([t, dmg, tag, pos]))
	for i in 180:  # 3 s Gameplay
		await physics_frame
		seen_attack = seen_attack or sp.state == SpiritEntity.State.ATTACK
	_check(seen_attack, "erreicht das Ziel -> ATTACK")
	_check(dummy.hp < hp0 and not hits.is_empty() and hits[0][0] == dummy,
			"Lunge trifft (%.0f Schaden in 3 s)" % (hp0 - dummy.hp))
	_check(not hits.is_empty() and is_equal_approx(hits[0][1], sp.base_damage)
			and hits[0][2] == sp.spirit.special_effect_tag, "Basisschaden x1.0 (Dummy ohne Saeule) + Effekt-Tag")
	_check(not hits.is_empty() and KnifeCombat.part_distance(dummy.get_node("Shape"), hits[0][3]) < 0.05,
			"Trefferposition liegt auf der Hitbox des Ziels")
	_check(hits.size() >= 2 and hits.size() <= 3, "Angriffs-Takt ~%.1f s (%d Treffer)" % [sp.attack_interval, hits.size()])
	# Mausrad-Wechsel: Spirit zieht mit
	var other := _dummy_near(Vector3(7, 1, -20))
	g.hard_lock = other
	await _frames(2)
	_check(sp.combat_target == other and sp.state == SpiritEntity.State.CHASE, "Ziel-Wechsel -> Spirit zieht mit")
	# Saeulen-Vorteil am Treffer
	_check(_pillar_damage(SpiritData.Pillar.ORDER) == sp.base_damage * 1.5
			and _pillar_damage(SpiritData.Pillar.CYCLE) == sp.base_damage, "Feuer: 1.5x gegen ORDER, 1.0x gegen CYCLE")


func _test_leash() -> void:
	print("Leine: Grapple-Reichweite")
	var dummy := _dummy_near(Vector3(0, 1, -40))
	await _place(NEAR_FOCUS)
	g.hard_lock = dummy
	await _frames(120)
	_check(sp.current_target() == dummy and sp.state != SpiritEntity.State.FOLLOW_PROTECT,
			"Ziel in Reichweite: Spirit kaempft")
	var p0 := sp.global_position
	await _place(LEASH_SPOT)
	_check(g.hard_lock == dummy and not g.hard_lock_in_range(), "Guardian ausser Reichweite, Lock bleibt (grau)")
	_check(sp.state == SpiritEntity.State.FOLLOW_PROTECT and sp.combat_target == dummy,
			"Spirit bricht ab -> Rueckweg (FOLLOW_PROTECT), Befehl bleibt gespeichert")
	_check(sp.global_position.distance_to(p0) < 1.0, "kein Teleport zum Guardian")
	var d0 := _flat(sp.global_position, g.global_position)
	var max_step := 0.0
	var prev := sp.global_position
	for i in 120:  # 2 s Rueckweg
		await physics_frame
		max_step = maxf(max_step, sp.global_position.distance_to(prev))
		prev = sp.global_position
	var d1 := _flat(sp.global_position, g.global_position)
	_check(d1 < d0 - 30.0, "laeuft physisch zurueck (%.0f m -> %.0f m in 2 s)" % [d0, d1])
	_check(max_step <= sp.catchup_speed / 60.0 * 1.2,
			"keine Spruenge: max. %.2f m pro Frame (Sprint %.0f m/s)" % [max_step, sp.catchup_speed])
	await _place(NEAR_FOCUS)
	_check(sp.current_target() == dummy and sp.state != SpiritEntity.State.FOLLOW_PROTECT,
			"zurueck in Reichweite: Spirit greift wieder an")


func _test_hold_recall() -> void:
	print("Lock-Taste 0.5 s halten = Rueckruf")
	_check(g.is_hard_locked() and sp.combat_target != null, "Lock aktiv")
	_action(true)
	await _frames(32)  # ~0.5 s halten
	_action(false)
	await _frames(2)
	_check(not g.is_hard_locked(), "Hard-Lock geloest")
	_check(sp.combat_target == null and sp.state == SpiritEntity.State.FOLLOW_PROTECT,
			"combat_target geloescht, FOLLOW_PROTECT")
	await _place(OPEN_SPOT)
	# Physischer Rueckweg (ggf. an Waenden entlang) – bis zu 8 s Zeit.
	for i in 480:
		await physics_frame
		if i > 60 and _flat(sp.global_position, g.global_position) <= sp.follow_max + 0.3 \
				and sp.velocity.length() < 1.0:
			break
	_check(sp.state == SpiritEntity.State.FOLLOW_PROTECT
			and _flat(sp.global_position, g.global_position) <= sp.follow_max + 0.3,
			"Spirit kehrt zum Guardian zurueck (%.1f m)" % _flat(sp.global_position, g.global_position))


func _test_double_click_recall() -> void:
	print("Lock-Taste Doppelklick = Rueckruf")
	var dummy := _dummy_near(Vector3(0, 1, -40))
	await _place(NEAR_FOCUS)
	g.hard_lock = dummy
	await _frames(30)
	_check(sp.current_target() == dummy, "Lock aktiv, Spirit greift an")
	for i in 2:  # zwei kurze Klicks innerhalb von 0.3 s
		_action(true)
		await _frames(3)
		_action(false)
		await _frames(3)
	_check(not g.is_hard_locked(), "Doppelklick loest den Hard-Lock")
	_check(sp.combat_target == null and sp.state == SpiritEntity.State.FOLLOW_PROTECT,
			"combat_target geloescht, FOLLOW_PROTECT")


# --- Helfer ---------------------------------------------------------------
func _mat() -> StandardMaterial3D:
	return (sp.get_node("Visual/Body") as MeshInstance3D).material_override


## Schaden eines Spirit-Treffers gegen ein Ziel mit Saeule `pillar`.
func _pillar_damage(pillar: SpiritData.Pillar) -> float:
	var scr := GDScript.new()
	scr.source_code = ("extends Node\nvar p := %d\nvar dmg := 0.0\n" % pillar) \
			+ "func get_spirit_pillar() -> int:\n\treturn p\n" \
			+ "func take_hit(d: float, _dir: Vector3, _s: Node) -> void:\n\tdmg = d\n"
	scr.reload()
	var foe: Node = scr.new()
	sp._deal_hit(foe, Vector3.ZERO)
	var d: float = foe.dmg
	foe.free()
	return d


func _place(pos: Vector3) -> void:
	g.global_position = pos
	g.velocity = Vector3.ZERO
	g._yaw = 0.0
	g.reset_physics_interpolation()
	await _frames(2)


func _dummy_near(p: Vector3) -> TrainingDummy:
	for c in arena.get_children():
		if c is TrainingDummy and (c as Node3D).global_position.distance_to(p) < 1.0:
			return c
	return null


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _action(pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = "hard_lock"
	ev.pressed = pressed
	Input.parse_input_event(ev)


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
