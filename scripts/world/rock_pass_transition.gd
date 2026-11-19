class_name RockPassTransition
extends SeamlessLoadingGate
## Offener Felspass zwischen zwei Sektoren (Loading Gate: siehe SeamlessLoadingGate).
## Schlucht entlang der Kurve, oben offen: Boden + Felswaende als Segmente, Felsboegen bzw. einseitige
## Ueberhaenge als Grapple-Anker – ein StaticBody3D + ein MultiMesh.
## Varianten sind Szenen mit eigenen Werten (scenes/transitions/rock_pass_*.tscn): Verlauf (points),
##   Breite/Wandhoehe (cross_section), Bogen-Abstand und -Hoehe, Ueberhaenge. SectorLink.pass_variant waehlt.
## Anker: EntryAnchor = Anfang am Boden, ExitAnchor = Ende am Boden (180 Grad gedreht).

## Segment-Abstand; Segmente sind laenger (OVERLAP), damit in Kurven keine Luecken entstehen.
const SEGMENT := 6.0
const OVERLAP := 1.5
const ARCH_THICKNESS := Vector2(3.0, 2.0)
const COL_ROCK := Color(0.62, 0.55, 0.47)
const COL_ARCH := Color(1.2, 1.1, 1.0)

## Mittellinie (lokal; Start Richtung +Z, Ende Richtung +Z). Das Ende bestimmt den ExitAnchor.
@export var points := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 10), Vector3(0, 0, 130), Vector3(0, 0, 140)])
@export var wall_thickness := 3.0
## Abstand der Felsboegen entlang des Passes (m).
@export var arch_spacing := 40.0
## Hoehe der Boegen/Ueberhaenge als Anteil der Wandhoehe (Grapple-Anker-Hoehe).
@export var arch_height := 0.9
## true = abwechselnd einseitige Ueberhaenge (halbe Breite) statt durchgehender Boegen.
@export var overhangs := false


func _curve_points() -> Array:
	return Array(points)


func _build_geometry() -> void:
	var boxes: Array[Dictionary] = []
	var half := cross_section * 0.5
	var full_width := cross_section.x + 2 * wall_thickness
	var off := 0.0
	while off <= length:
		var f := curve.sample_baked_with_rotation(off)
		var seg := SEGMENT * OVERLAP
		boxes.append(_segment(f, Vector3(0, -half.y - 0.5, 0), Vector3(full_width, 1, seg), Color.WHITE))
		for side in [-1.0, 1.0]:
			boxes.append(_segment(f, Vector3(side * (half.x + wall_thickness * 0.5), 0, 0),
					Vector3(wall_thickness, cross_section.y, seg), Color.WHITE))
		off += SEGMENT
	boxes.append_array(_arch_boxes())
	WhiteboxSector.add_box_cluster(self, "Rocks", boxes, COL_ROCK)


## Offsets der Boegen (m ab Seite A), gleichmaessig mit arch_spacing, nicht direkt an den Enden.
func arch_offsets() -> Array[float]:
	var out: Array[float] = []
	var off := arch_spacing
	while off < length - arch_spacing * 0.5:
		out.append(off)
		off += arch_spacing
	return out


func _arch_boxes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var full_width := cross_section.x + 2 * wall_thickness
	var y := (arch_height - 0.5) * cross_section.y
	var side := 1.0
	for off in arch_offsets():
		var f := curve.sample_baked_with_rotation(off)
		var width := full_width * 0.5 if overhangs else full_width
		var x := side * (full_width - width) * 0.5
		out.append(_segment(f, Vector3(x, y, 0), Vector3(width, ARCH_THICKNESS.y, ARCH_THICKNESS.x), COL_ARCH))
		side = -side
	return out


## Box im Kurven-Rahmen f mit lokalem Versatz.
func _segment(f: Transform3D, local: Vector3, box_size: Vector3, tint: Color) -> Dictionary:
	return {"xf": Transform3D(f.basis, f * local), "size": box_size, "color": tint}
