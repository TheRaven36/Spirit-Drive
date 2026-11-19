class_name SlopedCaveShortcut
extends SeamlessLoadingGate
## Kurze, steil abfallende Hoehlen-Abkuerzung (Drop) – meist Einbahnstrasse (one_way_from = A).
## Elliptische CSG-Roehre (aussen minus innen) entlang der Kurve, Innenflaeche mit Collision.
## Anker: EntryAnchor = oberes Ende am Boden, ExitAnchor = unteres Ende am Boden (180 Grad gedreht).

const POINTS := [
	Vector3(0, 0, 0), Vector3(0, 0, 8), Vector3(0, -8, 28), Vector3(0, -20, 48),
	Vector3(0, -26, 62), Vector3(0, -26, 72),
]
const RING_SEGMENTS := 24
const INNER_EXTENSION := 2.0
const PATH_INTERVAL := 2.0
const COL_CAVE := Color(0.4, 0.38, 0.42)


func _curve_points() -> Array:
	return POINTS


func _build_geometry() -> void:
	var tube := CSGCombiner3D.new()
	tube.name = "Tube"
	tube.use_collision = true
	add_child(tube)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_CAVE
	var half := cross_section * 0.5
	_add_ring(tube, "Outer", half + Vector2(WALL, WALL), curve, CSGShape3D.OPERATION_UNION, mat)
	_add_ring(tube, "Inner", half, make_curve(POINTS, INNER_EXTENSION), CSGShape3D.OPERATION_SUBTRACTION, mat)


func _add_ring(tube: CSGCombiner3D, ring_name: String, radius: Vector2, c: Curve3D,
		op: CSGShape3D.Operation, mat: Material) -> void:
	var path := Path3D.new()
	path.name = "Path" + ring_name
	path.curve = c
	add_child(path)
	var poly := CSGPolygon3D.new()
	poly.name = ring_name
	poly.operation = op
	poly.mode = CSGPolygon3D.MODE_PATH
	poly.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH
	poly.path_local = true
	poly.path_interval = PATH_INTERVAL
	poly.material = mat
	var pts := PackedVector2Array()
	for i in RING_SEGMENTS:
		var a := TAU * i / RING_SEGMENTS
		pts.append(Vector2(cos(a) * radius.x, sin(a) * radius.y))
	poly.polygon = pts
	tube.add_child(poly)
	poly.path_node = poly.get_path_to(path)
