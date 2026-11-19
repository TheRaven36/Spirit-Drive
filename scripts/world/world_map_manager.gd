class_name WorldMapManager
extends Node
## Laufzeit-Seite des Kleeblatt-Weltgeruests (ein Knoten in world.tscn, kein Singleton -> coop-tauglich:
## alle Guardians teilen sich den Welt-Zustand dieses Knotens).
##
## Streaming-Kette: Laedt ein SeamlessLoadingGate einen Sektor, setzt der Manager fuer jede weitere
##   Spieler-Verbindung dieses Sektors den passenden Uebergang an dessen Exit-Marker. Uebergaenge,
##   deren beide Seiten weder geladen sind noch laden, werden entfernt -> nur das aktive Areal
##   (+ seine Uebergaenge) liegt im Speicher. monster_only-Links bekommen keinen Uebergang.
## Sperren: Laufzeit-Zustand je Link (Start = SectorLink.block); unlock_link() oeffnet auch das Gate.
## Lager: CampUnlockState je Sektor; Schnellreise nur aus einer SafeZone zu Lagern ab TIER_1.

signal sector_loaded(id: StringName, node: Node3D)
signal sector_unloaded(id: StringName)
signal link_unlocked(link: SectorLink)
signal camp_state_changed(id: StringName, state: WorldSectorData.CampUnlockState)
signal fast_travel_finished(id: StringName)

const TRANSITION_SCENES := {
	SectorLink.TransitionType.ORGANIC_TUNNEL: "res://scenes/organic_transition_tunnel.tscn",
	SectorLink.TransitionType.SLOPED_SHORTCUT: "res://scenes/transitions/sloped_cave_shortcut.tscn",
	SectorLink.TransitionType.LONG_TRAIL: "res://scenes/transitions/long_trail_transition.tscn",
}
const ROCK_PASS_SCENES := {
	SectorLink.PassVariant.CANYON: "res://scenes/transitions/rock_pass_canyon.tscn",
	SectorLink.PassVariant.GORGE: "res://scenes/transitions/rock_pass_gorge.tscn",
	SectorLink.PassVariant.SERPENTINE: "res://scenes/transitions/rock_pass_serpentine.tscn",
	SectorLink.PassVariant.STEEP: "res://scenes/transitions/rock_pass_steep.tscn",
}
const CAMP := WorldSectorData.CampUnlockState
## Hoehe ueber dem Spawn-Marker bei der Schnellreise-Ankunft (Kapsel-Mitte).
const SPAWN_LIFT := 1.0

@export var map: WorldMapData
## Platzhalter fuer die spaetere Hardcore-Kontrast-Map (Feuer/Vulkan vs. Eis/Blizzard), noch deaktiviert.
@export var hardcore_map: WorldMapData
@export var areas_path: NodePath
@export var guardian_path: NodePath

var _areas: Node3D
var _guardian: Node3D
var _blocks := {}   # SectorLink -> GateBlockType (Laufzeit)
var _camps := {}    # Sektor-ID -> CampUnlockState
var _loaded := {}   # Sektor-ID -> Node3D
var _gates := {}    # SectorLink -> SeamlessLoadingGate
var _travel_target: StringName
var _travel_guardian: Node3D


func _ready() -> void:
	_areas = get_node(areas_path) as Node3D
	_guardian = get_node_or_null(guardian_path) as Node3D
	for l in map.links:
		_blocks[l] = l.block
	for s in map.sectors:
		_camps[s.id] = s.camp_start_state
	# Bereits in der Welt platzierte Uebergaenge (z. B. Hoehlen-Tunnel) uebernehmen.
	for c in _areas.get_children():
		if c is SeamlessLoadingGate:
			_register_gate(c, map.link_between(c.sector_a, c.sector_b))
	for c in _gates.values():
		for e in [SeamlessLoadingGate.End.A, SeamlessLoadingGate.End.B]:
			if c.area(e) != null:
				_on_sector_loaded(c.sector_at(e), c.area(e))


func loaded_sectors() -> Array:
	return _loaded.keys()


func sector_node(id: StringName) -> Node3D:
	var n: Node3D = _loaded.get(id)
	return n if is_instance_valid(n) else null


func gate_for(link: SectorLink) -> SeamlessLoadingGate:
	var g: SeamlessLoadingGate = _gates.get(link)
	return g if is_instance_valid(g) else null


# --- Streaming-Kette ---------------------------------------------------------
func _register_gate(gate: SeamlessLoadingGate, link: SectorLink) -> void:
	if link == null:
		push_warning("WorldMap: kein Link fuer Uebergang %s" % gate.name)
		return
	_gates[link] = gate
	gate.area_loaded.connect(func(end: int, node: Node3D) -> void: _on_sector_loaded(gate.sector_at(end), node))
	gate.area_unloaded.connect(func(end: int) -> void: _on_sector_unloaded(gate.sector_at(end)))


func _on_sector_loaded(id: StringName, node: Node3D) -> void:
	_loaded[id] = node
	if _camps.get(id) == CAMP.UNDISCOVERED:
		discover_camp(id)
	_apply_camp(id)
	for l in map.links_of(id):
		if not l.monster_only and gate_for(l) == null:
			_spawn_gate(l, id)
	sector_loaded.emit(id, node)


func _on_sector_unloaded(id: StringName) -> void:
	_loaded.erase(id)
	for l: SectorLink in _gates.keys():
		var g := gate_for(l)
		if g == null or not _gate_alive(g):
			if g != null:
				g.queue_free()
			_gates.erase(l)
	sector_unloaded.emit(id)


func _gate_alive(g: SeamlessLoadingGate) -> bool:
	for e in [SeamlessLoadingGate.End.A, SeamlessLoadingGate.End.B]:
		if g.area(e) != null or g.is_loading(e):
			return true
	return false


## Uebergang am Exit-Marker "Exits/<Nachbar>" des geladenen Sektors from_id einsetzen (Seite A = from_id).
func _spawn_gate(link: SectorLink, from_id: StringName) -> void:
	var gate := make_gate(link, from_id, sector_node(from_id))
	if gate == null:
		return
	_areas.add_child(gate)
	_register_gate(gate, link)


## Konfiguriertes, am Exit-Marker von from_node ausgerichtetes Gate (noch nicht im Baum).
func make_gate(link: SectorLink, from_id: StringName, from_node: Node3D) -> SeamlessLoadingGate:
	var to_id := link.other(from_id)
	var marker := from_node.get_node_or_null("Exits/" + str(to_id)) as Node3D
	if marker == null:
		push_warning("WorldMap: Sektor %s hat keinen Exit-Marker zu %s" % [from_id, to_id])
		return null
	var gate := (load(scene_for(link)) as PackedScene).instantiate() as SeamlessLoadingGate
	gate.name = "Gate_%s_%s" % [from_id, to_id]
	gate.sector_a = from_id
	gate.sector_b = to_id
	gate.scene_a = map.sector(from_id).scene_path
	gate.scene_b = map.sector(to_id).scene_path
	gate.block_type = _blocks[link]
	gate.one_way_from = -1 if not link.one_way else \
			(SeamlessLoadingGate.End.A if link.from_sector == from_id else SeamlessLoadingGate.End.B)
	gate.area_a_path = NodePath("../" + str(from_node.name))
	if _guardian != null:
		gate.guardian_path = NodePath("../" + str(_areas.get_path_to(_guardian)))
	var anchor := gate.get_node("EntryAnchor") as Node3D
	gate.transform = _areas.global_transform.affine_inverse() * marker.global_transform \
			* anchor.transform.affine_inverse()
	return gate


func scene_for(link: SectorLink) -> String:
	if link.transition == SectorLink.TransitionType.ROCK_PASS:
		return ROCK_PASS_SCENES[link.pass_variant]
	return TRANSITION_SCENES[link.transition]


# --- Sperren -----------------------------------------------------------------
func block_of(link: SectorLink) -> SectorLink.GateBlockType:
	return _blocks.get(link, SectorLink.GateBlockType.NONE)


## Story-/Monster-Fortschritt: Sperre aufheben (Daten + ggf. geladenes Gate).
func unlock_link(link: SectorLink) -> void:
	if block_of(link) == SectorLink.GateBlockType.NONE:
		return
	_blocks[link] = SectorLink.GateBlockType.NONE
	var g := gate_for(link)
	if g != null:
		g.unlock_gate()
	link_unlocked.emit(link)


# --- Lager (CampUnlockState) -------------------------------------------------
func camp_state(id: StringName) -> WorldSectorData.CampUnlockState:
	return _camps.get(id, CAMP.UNDISCOVERED)


func _set_camp(id: StringName, state: WorldSectorData.CampUnlockState) -> void:
	_camps[id] = state
	_apply_camp(id)
	camp_state_changed.emit(id, state)


## Erstes Betreten: ohne Freischalt-Quest direkt baubar, sonst LOCKED bis complete_camp_quest().
func discover_camp(id: StringName) -> void:
	var s := map.sector(id)
	if s == null or s.camp == WorldSectorData.CampKind.NONE or camp_state(id) != CAMP.UNDISCOVERED:
		return
	_set_camp(id, CAMP.LOCKED if s.camp_unlock_quest != &"" else CAMP.AVAILABLE_FOR_BUILD)


## Platzhalter-Andockpunkt fuer Liefer-/Haendler-Quests.
func complete_camp_quest(id: StringName) -> void:
	if camp_state(id) == CAMP.LOCKED:
		_set_camp(id, CAMP.AVAILABLE_FOR_BUILD)


func build_camp(id: StringName, progress: GuardianProgress) -> bool:
	return _advance_camp(id, CAMP.AVAILABLE_FOR_BUILD, CAMP.TIER_1, map.sector(id).camp_build_cost, progress)


func upgrade_camp(id: StringName, progress: GuardianProgress) -> bool:
	return _advance_camp(id, CAMP.TIER_1, CAMP.UPGRADED, map.sector(id).camp_upgrade_cost, progress)


func _advance_camp(id: StringName, from: int, to: int, cost: Dictionary, progress: GuardianProgress) -> bool:
	if camp_state(id) != from or not progress.spend(cost):
		return false
	_set_camp(id, to)
	return true


func is_camp_built(id: StringName) -> bool:
	return camp_state(id) >= CAMP.TIER_1


## Camp-Prefab im geladenen Sektor erst ab TIER_1 sichtbar/aktiv (inkl. SafeZone und Collision).
func _apply_camp(id: StringName) -> void:
	var node := sector_node(id)
	if node != null:
		apply_camp_state(node, is_camp_built(id))


func apply_camp_state(sector: Node3D, built: bool) -> void:
	var camp := sector.get_node_or_null("Camp") as Node3D
	if camp == null:
		return
	camp.visible = built
	camp.process_mode = Node.PROCESS_MODE_INHERIT if built else Node.PROCESS_MODE_DISABLED
	# process_mode/visible schalten CSG-Collision nicht ab -> sonst unsichtbare Waende (Einbahn-Gefuehl).
	for csg: CSGShape3D in camp.find_children("*", "CSGShape3D", true, false):
		if csg.is_root_shape():
			csg.use_collision = built


# --- Schnellreise ------------------------------------------------------------
func is_in_safe_zone(body: Node3D) -> bool:
	for z in get_tree().get_nodes_in_group("safe_zone"):
		if z is Area3D and (z as Area3D).is_inside_tree() and (z as Area3D).overlaps_body(body):
			return true
	return false


func can_fast_travel(guardian: Node3D, camp_id: StringName) -> bool:
	return _travel_target == &"" and is_camp_built(camp_id) and is_in_safe_zone(guardian)


## Startet das asynchrone Laden des Ziel-Lagers; Ankunft per fast_travel_finished.
func fast_travel(guardian: Node3D, camp_id: StringName) -> bool:
	if not can_fast_travel(guardian, camp_id):
		return false
	_travel_target = camp_id
	_travel_guardian = guardian
	ResourceLoader.load_threaded_request(map.sector(camp_id).scene_path)
	return true


func is_fast_travelling() -> bool:
	return _travel_target != &""


func _process(_delta: float) -> void:
	if _travel_target == &"":
		return
	var path := map.sector(_travel_target).scene_path
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var id := _travel_target
	_travel_target = &""
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("WorldMap: %s konnte nicht geladen werden" % path)
		return
	_arrive(id, (ResourceLoader.load_threaded_get(path) as PackedScene).instantiate() as Node3D)


## Alte Areale + Uebergaenge sofort aus dem Baum nehmen, Ziel im Ursprung aufbauen, Guardian an Spawn.
func _arrive(id: StringName, node: Node3D) -> void:
	for n: Node in _loaded.values() + _gates.values():
		if is_instance_valid(n):
			_areas.remove_child(n)
			n.queue_free()
	_loaded.clear()
	_gates.clear()
	_areas.add_child(node)
	_on_sector_loaded(id, node)
	var g := _travel_guardian
	if g is GuardianController:
		for h: GrappleHook in (g as GuardianController).hooks:
			h.release()
		(g as GuardianController).velocity = Vector3.ZERO
	var spawn := node.get_node_or_null("Spawn") as Node3D
	g.global_position = (spawn.global_position if spawn != null else node.global_position) + Vector3.UP * SPAWN_LIFT
	g.reset_physics_interpolation()
	fast_travel_finished.emit(id)
