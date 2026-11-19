class_name RockPassTransition
extends SeamlessLoadingGate
## Offener Felspass zwischen zwei Sektoren (Loading Gate: siehe SeamlessLoadingGate).
## Gewundene, leicht ansteigende Schlucht, oben offen. Boden + Felswaende als Segmente entlang der
## Kurve, quer gespannte Felsboegen als Grapple-Anker – ein StaticBody3D + ein MultiMesh.
## Anker: EntryAnchor = Anfang am Boden, ExitAnchor = Ende am Boden (180 Grad gedreht).

const POINTS := [
	Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(14, 3, 40), Vector3(-12, 6, 75),
	Vector3(8, 3, 105), Vector3(0, 0, 130), Vector3(0, 0, 140),
]
## Segment-Abstand; Segmente sind laenger (OVERLAP), damit in Kurven keine Luecken entstehen.
const SEGMENT := 6.0
const OVERLAP := 1.5
const WALL_THICKNESS := 3.0
## Felsboegen quer ueber der Schlucht (Anteil der Laenge).
const ARCHES := [0.3, 0.55, 0.8]
const ARCH_THICKNESS := Vector2(3.0, 2.0)
const COL_ROCK := Color(0.62, 0.55, 0.47)
const COL_ARCH := Color(1.2, 1.1, 1.0)


func _curve_points() -> Array:
	return POINTS


func _build_geometry() -> void:
	var boxes: Array[Dictionary] = []
	var half := cross_section * 0.5
	var full_width := cross_section.x + 2 * WALL_THICKNESS
	var off := 0.0
	while off <= length:
		var f := curve.sample_baked_with_rotation(off)
		var seg := SEGMENT * OVERLAP
		boxes.append(_segment(f, Vector3(0, -half.y - 0.5, 0), Vector3(full_width, 1, seg), Color.WHITE))
		for side in [-1.0, 1.0]:
			boxes.append(_segment(f, Vector3(side * (half.x + WALL_THICKNESS * 0.5), 0, 0),
					Vector3(WALL_THICKNESS, cross_section.y, seg), Color.WHITE))
		off += SEGMENT
	for a: float in ARCHES:
		var f := curve.sample_baked_with_rotation(length * a)
		boxes.append(_segment(f, Vector3(0, half.y - ARCH_THICKNESS.y, 0),
				Vector3(full_width, ARCH_THICKNESS.y, ARCH_THICKNESS.x), COL_ARCH))
	WhiteboxSector.add_box_cluster(self, "Rocks", boxes, COL_ROCK)


## Box im Kurven-Rahmen f mit lokalem Versatz.
func _segment(f: Transform3D, local: Vector3, box_size: Vector3, tint: Color) -> Dictionary:
	return {"xf": Transform3D(f.basis, f * local), "size": box_size, "color": tint}
