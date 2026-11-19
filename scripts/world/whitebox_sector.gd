class_name WhiteboxSector
extends Node3D
## Whitebox-Sektor des Kleeblatt-Weltgeruests: Boden, Randwaende mit Toren an den Exits und
## Saeulen/Monolithe als Grapple-Anker – alles ein StaticBody3D + ein MultiMesh (Performance-Regel).
## Feste Geometrie, nach seed reproduzierbar (kein Terrain-Backen zur Laufzeit).
##
## Szenen-Konvention (vom SeamlessLoadingGate / WorldMapManager gelesen):
##   Exits/<Nachbar-ID>  Marker3D am Rand, Boden-Hoehe, +Z zeigt aus dem Sektor in den Uebergang.
##   Spawn               Ankunftspunkt (Schnellreise).
##   Camp                optional: HomebaseOutpost-Instanz; sichtbar/aktiv erst ab CampUnlockState.TIER_1.

const WALL_HEIGHT := 8.0
const WALL_THICKNESS := 2.0
## Luecke in der Randwand um jeden Exit (breiter als jedes Uebergangs-Tor).
const GATE_GAP := 16.0
## Saeulen halten so viel Abstand zu Exits, Spawn und Camp.
const CLEAR_RADIUS := 24.0
## Mindestabstand der Saeulen untereinander (Platz zum Schwingen).
const PILLAR_SPACING := 14.0
const EDGE_MARGIN := 10.0
const MAX_TRIES := 400
const COL_PILLAR := Color(1.15, 1.15, 1.2)
const GRID_SHADER := preload("res://assets/shaders/proto_grid.gdshader")

@export var size := Vector2(160, 160)
@export var theme_color := Color(0.45, 0.47, 0.5)
@export var pillar_count := 8
## Hoehe (min, max) und Kantenlaenge der Saeulen/Monolithe.
@export var pillar_height := Vector2(14, 40)
@export var pillar_width := 4.0
@export var layout_seed := 1


func _ready() -> void:
	var boxes: Array[Dictionary] = [_box(Vector3(0, -0.5, 0),
			Vector3(size.x + 2 * WALL_THICKNESS, 1, size.y + 2 * WALL_THICKNESS), Color.WHITE)]
	boxes.append_array(_wall_boxes())
	boxes.append_array(_pillar_boxes())
	add_box_cluster(self, "Geometry", boxes, theme_color)


## Box-Beschreibung fuer add_box_cluster (xf ohne Skalierung).
static func _box(pos: Vector3, box_size: Vector3, tint: Color, basis := Basis()) -> Dictionary:
	return {"xf": Transform3D(basis, pos), "size": box_size, "color": tint}


## Viele Boxen als ein StaticBody3D (je eine Shape) + ein MultiMesh (Einheits-Box, skaliert).
## Auch von RockPassTransition genutzt.
static func add_box_cluster(parent: Node3D, cluster_name: String, boxes: Array[Dictionary],
		base_color: Color) -> StaticBody3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = boxes.size()
	var body := StaticBody3D.new()
	body.name = cluster_name
	parent.add_child(body)
	for i in boxes.size():
		var xf: Transform3D = boxes[i].xf
		var box_size: Vector3 = boxes[i].size
		mm.set_instance_transform(i, Transform3D(xf.basis * Basis.from_scale(box_size), xf.origin))
		mm.set_instance_color(i, boxes[i].color)
		var shape := BoxShape3D.new()
		shape.size = box_size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = xf
		body.add_child(col)
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.set_shader_parameter("base_color", base_color)
	mat.set_shader_parameter("cell_size", 4.0)
	mat.set_shader_parameter("use_instance_tint", true)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = cluster_name + "Mesh"
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return body


func exits() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var node := get_node_or_null("Exits")
	if node != null:
		for c in node.get_children():
			if c is Marker3D:
				out.append(c)
	return out


# --- Randwaende --------------------------------------------------------------
## Je Kante: Wandstuecke zwischen den Exit-Luecken.
func _wall_boxes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for normal: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]:
		var tangent := Vector3(absf(normal.z), 0, absf(normal.x))
		var half := (size.x if normal.x != 0 else size.y) * 0.5
		var edge_len := (size.y if normal.x != 0 else size.x) + 2 * WALL_THICKNESS
		var cuts: Array[float] = [-edge_len * 0.5]
		for gap in _gaps_on_edge(normal, half):
			cuts.append_array([gap - GATE_GAP * 0.5, gap + GATE_GAP * 0.5])
		cuts.append(edge_len * 0.5)
		for i in range(0, cuts.size(), 2):
			var seg := cuts[i + 1] - cuts[i]
			if seg <= 0.0:
				continue
			var center := normal * (half + WALL_THICKNESS * 0.5) + tangent * (cuts[i] + seg * 0.5) \
					+ Vector3.UP * WALL_HEIGHT * 0.5
			var thick := Vector3(WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS)
			out.append(_box(center, thick + tangent * (seg - WALL_THICKNESS), Color.WHITE))
	return out


## Positionen (entlang der Kante) der Exits, die auf dieser Kante liegen – sortiert.
func _gaps_on_edge(normal: Vector3, half: float) -> Array[float]:
	var tangent := Vector3(absf(normal.z), 0, absf(normal.x))
	var out: Array[float] = []
	for m in exits():
		if absf(m.position.dot(normal) - half) < 1.0:
			out.append(m.position.dot(tangent))
	out.sort()
	return out


# --- Saeulen / Monolithe -----------------------------------------------------
func _pillar_boxes() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var keep_clear := _keep_clear_points()
	var placed: Array[Vector3] = []
	var out: Array[Dictionary] = []
	var tries := 0
	while out.size() < pillar_count and tries < MAX_TRIES:
		tries += 1
		var p := Vector3(rng.randf_range(-0.5, 0.5) * (size.x - 2 * EDGE_MARGIN), 0,
				rng.randf_range(-0.5, 0.5) * (size.y - 2 * EDGE_MARGIN))
		if _near(p, keep_clear, CLEAR_RADIUS) or _near(p, placed, PILLAR_SPACING):
			continue
		var h := rng.randf_range(pillar_height.x, pillar_height.y)
		out.append(_box(p + Vector3.UP * h * 0.5, Vector3(pillar_width, h, pillar_width), COL_PILLAR))
		placed.append(p)
	return out


static func _near(p: Vector3, points: Array[Vector3], radius: float) -> bool:
	return points.any(func(c: Vector3) -> bool: return Vector2(c.x - p.x, c.z - p.z).length() < radius)


func _keep_clear_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for m in exits():
		out.append(m.position)
	for n in ["Spawn", "Camp"]:
		var node := get_node_or_null(n) as Node3D
		if node != null:
			out.append(node.position)
	return out
