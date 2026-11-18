class_name OrganicTransitionTunnel
extends Node3D
## Organischer 3D-Grapple-Tunnel zwischen zwei Arealen (Seite A = EntryAnchor, B = ExitAnchor).
##
## Geometrie: S-Kurve (links/rechts UND steil hoch/runter, ~183 m), die die Sichtlinie bricht.
##   Elliptischer Querschnitt 24 m breit x 18 m hoch (Schwing-Raum). Roehre = CSGPolygon3D
##   entlang Path3D (aussen) minus etwas laengere Innen-Roehre; an beiden Enden schliesst eine
##   Platte mit Tor (DOOR_SIZE, passt zu Hoehlen- und Homebase-Tor) ab. Innenflaeche mit
##   Collision (Grapple-Anker ueberall). Felsvorspruenge an den Kurven-Scheiteln (links, rechts,
##   Decke) als zusaetzliche Anker (ein MultiMesh, ein Body).
##   Kurve so weit, dass sich die breite Roehre in den Biegungen nicht selbst schneidet.
##
## Loading Gate (Fortschritt = naechster Kurven-Offset des Guardians):
##   1. Guardian betritt die Roehre an Seite X -> Ziel-Szene der anderen Seite wird per
##      ResourceLoader.load_threaded_request im Hintergrund geladen.
##   2. Nach der ersten grossen Biegung (BEND_FRACTION der Laenge, ausser Sicht) wird das Areal
##      an Seite X entladen (queue_free) und Barriere X schliesst (dahinter ist nichts mehr).
##   3. Sobald THREAD_LOAD_LOADED: Szene am Anker der Zielseite andocken, Barriere oeffnet.
##   Rueckweg funktioniert symmetrisch (Seite B -> A, Areal A wird neu geladen).

signal area_loaded(end: int, area: Node3D)
signal area_unloaded(end: int)

enum End { A, B }

## Innen-Halbachsen der Ellipse: 24 m breit, 18 m hoch. Boden der Enden = Areal-Boden.
const RADIUS_X := 12.0
const RADIUS_Y := 9.0
const WALL := 1.0
## Tor in den End-Platten (Breite, Hoehe; ab Roehren-Boden).
const DOOR_SIZE := Vector2(10, 10)
## Innen-Roehre ragt an beiden Enden so weit hinaus -> keine End-Kappen.
const INNER_EXTENSION := 2.0
const RING_SEGMENTS := 24
const PATH_INTERVAL := 2.0
## Kurven-Stuetzpunkte (lokal; Start bei A Richtung +Z, Ende bei B Richtung +Z). Das Ende
## (z = 140) bestimmt End-Platte B und den ExitAnchor in organic_transition_tunnel.tscn (z = 140 + 13).
const POINTS := [
	Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(18, 12, 40), Vector3(0, 36, 70),
	Vector3(-18, 12, 100), Vector3(0, 0, 130), Vector3(0, 0, 140),
]
## Areal wird entladen, sobald der Guardian diesen Anteil der Laenge von seiner Seite zurueckgelegt hat.
const BEND_FRACTION := 0.35
## Erst so tief in der Roehre zaehlt der Guardian als "drin" (m ab Ende).
const ENTER_MARGIN := 3.0
## Felsvorspruenge: [Anteil der Laenge, Seite] – Seite: Richtung im Querschnitt (x = links/rechts, y = Decke).
const LEDGES := [
	[0.2, Vector2(-1, 0)], [0.33, Vector2(0, 1)], [0.45, Vector2(1, 0)],
	[0.55, Vector2(0, 1)], [0.67, Vector2(-1, 0)], [0.8, Vector2(1, 0)],
]
const LEDGE_SIZE := Vector3(3.0, 1.5, 3.0)
const COL_LEDGE := Color(0.8, 0.72, 0.6)
const COL_BARRIER := Color(0.3, 0.85, 1.0, 0.35)

@export var scene_a := "res://scenes/test_arena.tscn"
@export var scene_b := "res://scenes/homebase_outpost.tscn"
## Bereits geladene Areale beim Start (leer = nicht geladen).
@export var area_a_path: NodePath
@export var area_b_path: NodePath
@export var guardian_path: NodePath

var length := 0.0
## Seite, von der der Guardian gerade durch die Roehre reist (-1 = nicht in der Roehre).
var travel_from := -1

var _areas: Array[Node3D] = [null, null]
var _loading: Array[bool] = [false, false]
var _barriers: Array[StaticBody3D] = []
var _guardian: Node3D

@onready var _path_outer: Path3D = $PathOuter
@onready var _path_inner: Path3D = $PathInner
@onready var _anchors: Array[Marker3D] = [$EntryAnchor, $ExitAnchor]


func _ready() -> void:
	_path_outer.curve = _make_curve(0.0)
	_path_inner.curve = _make_curve(INNER_EXTENSION)
	length = _path_outer.curve.get_baked_length()
	_guardian = get_node_or_null(guardian_path) as Node3D
	_areas[End.A] = get_node_or_null(area_a_path) as Node3D
	_areas[End.B] = get_node_or_null(area_b_path) as Node3D
	_build_ledges()
	for e in [End.A, End.B]:
		_barriers.append(_make_barrier(e))
		set_barrier_open(e, _areas[e] != null)


## Glatte Kurve durch POINTS (Bezier-Griffe nach Catmull-Rom). ext verlaengert beide Enden.
func _make_curve(ext: float) -> Curve3D:
	var pts: Array = POINTS.duplicate()
	pts[0] = (pts[0] as Vector3) - Vector3(0, 0, ext)
	pts[-1] = (pts[-1] as Vector3) + Vector3(0, 0, ext)
	var c := Curve3D.new()
	for i in pts.size():
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]) / 6.0
		c.add_point(pts[i], -t, t)
	return c


# --- Anker & Barrieren -------------------------------------------------------
func _build_ledges() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = LEDGE_SIZE
	mm.mesh = box
	mm.instance_count = LEDGES.size()
	var body := StaticBody3D.new()
	body.name = "Ledges"
	add_child(body)
	for i in LEDGES.size():
		var xf := _ledge_transform(LEDGES[i][0], LEDGES[i][1])
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, COL_LEDGE)
		var shape := BoxShape3D.new()
		shape.size = LEDGE_SIZE
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = xf
		body.add_child(col)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LedgesMesh"
	mmi.multimesh = mm
	add_child(mmi)


## Vorsprung sitzt an der Innenwand: Querschnitts-Richtung side, halb in der Wand.
func _ledge_transform(fraction: float, side: Vector2) -> Transform3D:
	var frame := _path_outer.curve.sample_baked_with_rotation(length * fraction)
	var dir := (frame.basis.x * side.x + frame.basis.y * side.y).normalized()
	var r := RADIUS_X if absf(side.x) > absf(side.y) else RADIUS_Y
	return Transform3D(frame.basis, frame.origin + dir * (r - LEDGE_SIZE.y * 0.25))


## Energie-Barriere direkt hinter dem Tor der End-Platte (Tor-gross, Boden = Roehren-Boden).
func _make_barrier(end: int) -> StaticBody3D:
	var off := 1.0 if end == End.A else length - 1.0
	var frame := _path_outer.curve.sample_baked_with_rotation(off)
	var body := StaticBody3D.new()
	body.name = "Barrier" + ("A" if end == End.A else "B")
	var door_center := frame.basis.y * (DOOR_SIZE.y * 0.5 - RADIUS_Y)
	body.transform = Transform3D(frame.basis, frame.origin + door_center)
	var size := Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.4)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y, 0.2)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL_BARRIER
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)
	return body


func set_barrier_open(end: int, open: bool) -> void:
	var b := _barriers[end]
	b.visible = not open
	(b.get_child(0) as CollisionShape3D).set_deferred("disabled", open)


func is_barrier_open(end: int) -> bool:
	return not _barriers[end].visible


func area(end: int) -> Node3D:
	return _areas[end] if is_instance_valid(_areas[end]) else null


func is_loading(end: int) -> bool:
	return _loading[end]


# --- Loading Gate ------------------------------------------------------------
## Kurven-Offset des Punkts (m ab Seite A), -1 = nicht in der Roehre.
func progress_of(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	var curve := _path_outer.curve
	var off := curve.get_closest_offset(local)
	var inside := local.distance_to(curve.sample_baked(off)) <= maxf(RADIUS_X, RADIUS_Y) + WALL \
			and off > ENTER_MARGIN and off < length - ENTER_MARGIN
	return off if inside else -1.0


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_guardian):
		return
	var p := progress_of(_guardian.global_position)
	if p < 0.0:
		travel_from = -1
		return
	if travel_from == -1:
		travel_from = End.A if p < length * 0.5 else End.B
		_request(_other(travel_from))
	var travelled := p if travel_from == End.A else length - p
	if travelled >= length * BEND_FRACTION and area(travel_from) != null:
		_unload(travel_from)


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
		push_error("Tunnel: %s konnte nicht geladen werden" % _scene(end))
		return
	var packed := ResourceLoader.load_threaded_get(_scene(end)) as PackedScene
	var node := packed.instantiate() as Node3D
	# Lage vor add_child setzen -> Physik-Bodies entstehen direkt am Anker.
	node.transform = (get_parent() as Node3D).global_transform.affine_inverse() * _anchors[end].global_transform
	get_parent().add_child(node)
	_areas[end] = node
	set_barrier_open(end, true)
	area_loaded.emit(end, node)


func _unload(end: int) -> void:
	_areas[end].queue_free()
	_areas[end] = null
	set_barrier_open(end, false)
	area_unloaded.emit(end)


func _scene(end: int) -> String:
	return scene_a if end == End.A else scene_b


func _other(end: int) -> int:
	return End.B if end == End.A else End.A
