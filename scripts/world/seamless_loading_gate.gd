class_name SeamlessLoadingGate
extends Node3D
## Asynchrones Loading Gate zwischen zwei Sektoren (Seite A = EntryAnchor, B = ExitAnchor).
## Gemeinsame Basis aller Uebergaenge (OrganicTransitionTunnel, RockPassTransition, SlopedCaveShortcut);
## diese liefern nur die Geometrie: _curve_points() = Mittellinie des Durchgangs, _build_geometry().
##
## Ablauf (Fortschritt = naechster Kurven-Offset des Guardians):
##   1. Guardian betritt den Durchgang an Seite X -> Ziel-Szene der anderen Seite wird per
##      ResourceLoader.load_threaded_request im Hintergrund geladen.
##   2. Ab BEND_FRACTION der Laenge (ausser Sicht) wird das Areal an Seite X entladen (queue_free),
##      Barriere X schliesst (dahinter ist nichts mehr).
##   3. Sobald THREAD_LOAD_LOADED: Szene an der Zielseite andocken, Barriere oeffnet.
##   Rueckweg symmetrisch. Immer nur das aktive Areal bleibt im Speicher.
##
## Andocken: Hat das Areal einen Marker "Exits/<Sektor der Gegenseite>" (Exits liegt im Ursprung),
##   landet dieser Marker genau auf dem Anker – Marker-+Z zeigt aus dem Sektor in den Uebergang.
##   Ohne Marker landet der Areal-Ursprung auf dem Anker.
## Sperre (block_type != NONE): Ein Hindernis fuellt die Mitte des Durchgangs, das Gate laedt nichts.
##   unlock_gate() raeumt es weg (Fels/Gestruepp verschwinden, der Clash-Baum stuerzt um).
## Einbahnstrasse (one_way_from): nur wer von dieser Seite kommt, loest Laden/Entladen aus.

signal area_loaded(end: int, area: Node3D)
signal area_unloaded(end: int)
signal gate_unlocked

enum End { A, B }

## Areal wird entladen, sobald der Guardian diesen Anteil der Laenge von seiner Seite zurueckgelegt hat.
const BEND_FRACTION := 0.35
## Erst so tief im Durchgang zaehlt der Guardian als "drin" (m ab Ende).
const ENTER_MARGIN := 3.0
const WALL := 1.0
const COL_BARRIER := Color(0.3, 0.85, 1.0, 0.35)
const BLOCK_DEPTH := 4.0
const BLOCK_COLORS := {
	SectorLink.GateBlockType.ROCK_BLOCK: Color(0.45, 0.42, 0.4),
	SectorLink.GateBlockType.BURNABLE_GROWTH: Color(0.25, 0.42, 0.12),
	SectorLink.GateBlockType.CLASH_TREE: Color(0.42, 0.28, 0.16),
}
const TREE_RADIUS := 1.5
const TREE_FALL_TIME := 1.2

@export var scene_a := ""
@export var scene_b := ""
## Sektor-IDs der beiden Seiten (fuer Exit-Marker und WorldMapManager; leer = ohne Marker andocken).
@export var sector_a: StringName
@export var sector_b: StringName
## Bereits geladene Areale beim Start (leer = nicht geladen).
@export var area_a_path: NodePath
@export var area_b_path: NodePath
@export var guardian_path: NodePath
## Innerer Querschnitt (Breite, Hoehe). Die Kurve laeuft mittig, der Boden liegt Hoehe/2 darunter.
@export var cross_section := Vector2(24, 18)
## Energie-Barriere an den Enden (Breite, Hoehe ab Boden).
@export var door_size := Vector2(10, 10)
@export var block_type := SectorLink.GateBlockType.NONE
## -1 = beide Richtungen, sonst nur von dieser Seite (End.A / End.B).
@export var one_way_from := -1

var curve: Curve3D
var length := 0.0
## Seite, von der der Guardian gerade durch den Durchgang reist (-1 = nicht drin).
var travel_from := -1

var _areas: Array[Node3D] = [null, null]
var _loading: Array[bool] = [false, false]
var _barriers: Array[StaticBody3D] = []
var _blocker: StaticBody3D
var _guardian: Node3D

@onready var _anchors: Array[Marker3D] = [$EntryAnchor, $ExitAnchor]


func _ready() -> void:
	curve = make_curve(_curve_points(), 0.0)
	length = curve.get_baked_length()
	_guardian = get_node_or_null(guardian_path) as Node3D
	_areas[End.A] = get_node_or_null(area_a_path) as Node3D
	_areas[End.B] = get_node_or_null(area_b_path) as Node3D
	_build_geometry()
	for e in [End.A, End.B]:
		_barriers.append(_make_barrier(e))
		set_barrier_open(e, _areas[e] != null)
	_make_blocker()


## Mittellinie des Durchgangs (lokal; Start bei A Richtung +Z, Ende bei B Richtung +Z).
func _curve_points() -> Array:
	return [Vector3.ZERO, Vector3(0, 0, 10)]


## Waende/Anker des Durchgangs – von den Uebergaengen ueberschrieben.
func _build_geometry() -> void:
	pass


## Glatte Kurve durch pts (Bezier-Griffe nach Catmull-Rom). ext verlaengert beide Enden.
static func make_curve(points: Array, ext: float) -> Curve3D:
	var pts := points.duplicate()
	pts[0] = (pts[0] as Vector3) - Vector3(0, 0, ext)
	pts[-1] = (pts[-1] as Vector3) + Vector3(0, 0, ext)
	var c := Curve3D.new()
	for i in pts.size():
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]) / 6.0
		c.add_point(pts[i], -t, t)
	return c


# --- Barrieren ---------------------------------------------------------------
## Energie-Barriere direkt hinter dem Ende (Tor-gross, Boden = Durchgangs-Boden).
func _make_barrier(end: int) -> StaticBody3D:
	var off := 1.0 if end == End.A else length - 1.0
	var frame := curve.sample_baked_with_rotation(off)
	var body := StaticBody3D.new()
	body.name = "Barrier" + ("A" if end == End.A else "B")
	var door_center := frame.basis.y * (door_size.y - cross_section.y) * 0.5
	body.transform = Transform3D(frame.basis, frame.origin + door_center)
	var size := Vector3(door_size.x, door_size.y, 0.4)
	body.add_child(_box_shape(size))
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL_BARRIER
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y, 0.2)
	body.add_child(_mesh_instance(mesh, mat))
	add_child(body)
	return body


func set_barrier_open(end: int, open: bool) -> void:
	var b := _barriers[end]
	b.visible = not open
	(b.get_child(0) as CollisionShape3D).set_deferred("disabled", open)


func is_barrier_open(end: int) -> bool:
	return not _barriers[end].visible


# --- Sperre (GateBlockType) --------------------------------------------------
## Hindernis in der Mitte, fuellt den ganzen Querschnitt (Collision). Clash-Baum: stehender Stamm
## am Rand + unsichtbare Sperre (Abbruchkante); umgestuerzt liegt er quer als Weg.
func _make_blocker() -> void:
	if block_type == SectorLink.GateBlockType.NONE:
		return
	_blocker = StaticBody3D.new()
	_blocker.name = "Blocker"
	_blocker.transform = curve.sample_baked_with_rotation(length * 0.5)
	_blocker.add_child(_box_shape(Vector3(cross_section.x, cross_section.y, BLOCK_DEPTH)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLOCK_COLORS[block_type]
	if block_type == SectorLink.GateBlockType.CLASH_TREE:
		_blocker.add_child(_make_tree(mat))
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(cross_section.x, cross_section.y, BLOCK_DEPTH)
		_blocker.add_child(_mesh_instance(mesh, mat))
	add_child(_blocker)


## Stamm-Pivot am Fuss (Boden, rechter Rand) -> Umstuerzen = Drehung um die Laengsachse.
func _make_tree(mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Tree"
	pivot.position = Vector3(cross_section.x * 0.4, -cross_section.y * 0.5, 0)
	var mesh := CylinderMesh.new()
	mesh.top_radius = TREE_RADIUS * 0.7
	mesh.bottom_radius = TREE_RADIUS
	mesh.height = cross_section.x * 0.9
	var trunk := _mesh_instance(mesh, mat)
	trunk.position.y = mesh.height * 0.5
	pivot.add_child(trunk)
	return pivot


func is_blocked() -> bool:
	return block_type != SectorLink.GateBlockType.NONE


## Gibt den Durchgang frei (Story-/Monster-Fortschritt): Collision weg, Hindernis weg bzw. Baum faellt.
func unlock_gate() -> void:
	if not is_blocked():
		return
	var was := block_type
	block_type = SectorLink.GateBlockType.NONE
	(_blocker.get_child(0) as CollisionShape3D).set_deferred("disabled", true)
	if was == SectorLink.GateBlockType.CLASH_TREE:
		create_tween().tween_property(_blocker.get_node("Tree"), "rotation:z", PI * 0.5, TREE_FALL_TIME)
	else:
		_blocker.queue_free()
		_blocker = null
	gate_unlocked.emit()


# --- Loading Gate ------------------------------------------------------------
## Geladenes Areal der Seite (null, wenn entladen – auch schon im Frame des queue_free).
func area(end: int) -> Node3D:
	var a := _areas[end]
	return a if is_instance_valid(a) and not a.is_queued_for_deletion() else null


func is_loading(end: int) -> bool:
	return _loading[end]


func sector_at(end: int) -> StringName:
	return sector_a if end == End.A else sector_b


## Kurven-Offset des Punkts (m ab Seite A), -1 = nicht im Durchgang.
func progress_of(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	var off := curve.get_closest_offset(local)
	var inside := local.distance_to(curve.sample_baked(off)) <= maxf(cross_section.x, cross_section.y) * 0.5 + WALL \
			and off > ENTER_MARGIN and off < length - ENTER_MARGIN
	return off if inside else -1.0


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_guardian) or is_blocked():
		return
	var p := progress_of(_guardian.global_position)
	if p < 0.0:
		travel_from = -1
		return
	if travel_from == -1:
		travel_from = End.A if p < length * 0.5 else End.B
		if _may_travel():
			_request(_other(travel_from))
	if not _may_travel():
		return
	var travelled := p if travel_from == End.A else length - p
	if travelled >= length * BEND_FRACTION and area(travel_from) != null:
		_unload(travel_from)


func _may_travel() -> bool:
	return one_way_from == -1 or one_way_from == travel_from


func _process(_delta: float) -> void:
	for e in [End.A, End.B]:
		if _loading[e]:
			_poll(e)


func _request(end: int) -> void:
	if area(end) != null or _loading[end]:
		return
	ResourceLoader.load_threaded_request(_scene(end))
	_loading[end] = true


func _poll(end: int) -> void:
	var status := ResourceLoader.load_threaded_get_status(_scene(end))
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_loading[end] = false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("LoadingGate: %s konnte nicht geladen werden" % _scene(end))
		return
	var packed := ResourceLoader.load_threaded_get(_scene(end)) as PackedScene
	var node := packed.instantiate() as Node3D
	# Lage vor add_child setzen -> Physik-Bodies entstehen direkt am Anker.
	node.transform = (get_parent() as Node3D).global_transform.affine_inverse() \
			* _anchors[end].global_transform * _dock_offset(node, end)
	get_parent().add_child(node)
	_areas[end] = node
	set_barrier_open(end, true)
	area_loaded.emit(end, node)


## Marker "Exits/<Gegenseite>" des Areals auf den Anker legen (siehe Doc oben).
func _dock_offset(node: Node3D, end: int) -> Transform3D:
	var other := sector_at(_other(end))
	if other == &"":
		return Transform3D.IDENTITY
	var marker := node.get_node_or_null("Exits/" + str(other)) as Node3D
	return marker.transform.affine_inverse() if marker != null else Transform3D.IDENTITY


func _unload(end: int) -> void:
	_areas[end].queue_free()
	_areas[end] = null
	set_barrier_open(end, false)
	area_unloaded.emit(end)


func _scene(end: int) -> String:
	return scene_a if end == End.A else scene_b


func _other(end: int) -> int:
	return End.B if end == End.A else End.A


# --- Helfer ------------------------------------------------------------------
func _box_shape(size: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	return col


func _mesh_instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
