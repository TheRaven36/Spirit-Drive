class_name LongTrailTransition
extends SeamlessLoadingGate
## Langer, offener Weg (~350 m, flach geschwungen, niedrige Randsteine) zwischen zwei Sektoren.
## Grob frueh, Details spaet:
##   1. Eintritt: Ziel-Sektor wird wie ueblich asynchron geladen und dockt sofort an – aber nur als
##      Grob-Stufe (WhiteboxSector: Boden, Waende, Landmarken). Auf dem offenen Weg sieht man ihn von weitem.
##   2. Naeherungszone (DETAIL_FRACTION der Laenge): Detail-Stufe wird gebaut (build_detail()).
##   3. Die Herkunft wird erst nach unload_fraction (Szene: 0.5) entladen – man blickt laenger zurueck.
## Steinmaennchen (hohe Saeulen) ausserhalb der Randsteine dienen als Grapple-Anker unterwegs.

## Ab diesem Anteil des Wegs (vom Ziel aus gesehen: die letzten 20 %) baut das Ziel seine Details.
const DETAIL_FRACTION := 0.8
const POINTS := [
	Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(18, 3, 90), Vector3(-18, 6, 180),
	Vector3(18, 3, 270), Vector3(0, 0, 340), Vector3(0, 0, 350),
]
const SEGMENT := 8.0
const OVERLAP := 1.3
const RAIL_SIZE := Vector2(1.5, 1.2)
const CAIRN_SPACING := 60.0
const CAIRN_SIZE := Vector3(3, 18, 3)
const COL_TRAIL := Color(0.58, 0.54, 0.46)
const COL_CAIRN := Color(1.2, 1.15, 1.05)


func _curve_points() -> Array:
	return POINTS


func _build_geometry() -> void:
	var boxes: Array[Dictionary] = []
	var floor_y := -cross_section.y * 0.5
	var off := 0.0
	while off <= length:
		var f := curve.sample_baked_with_rotation(off)
		boxes.append(_segment(f, Vector3(0, floor_y - 0.5, 0), Vector3(cross_section.x, 1, SEGMENT * OVERLAP)))
		for side in [-1.0, 1.0]:
			boxes.append(_segment(f, Vector3(side * (cross_section.x - RAIL_SIZE.x) * 0.5, floor_y + RAIL_SIZE.y * 0.5, 0),
					Vector3(RAIL_SIZE.x, RAIL_SIZE.y, SEGMENT * OVERLAP)))
		off += SEGMENT
	var side := 1.0
	var cairn := CAIRN_SPACING
	while cairn < length - CAIRN_SPACING * 0.5:
		var f := curve.sample_baked_with_rotation(cairn)
		var x := side * (cross_section.x * 0.5 + CAIRN_SIZE.x)
		var box := _segment(f, Vector3(x, floor_y + CAIRN_SIZE.y * 0.5, 0), CAIRN_SIZE)
		box.color = COL_CAIRN
		boxes.append(box)
		side = -side
		cairn += CAIRN_SPACING
	WhiteboxSector.add_box_cluster(self, "Trail", boxes, COL_TRAIL)


func _segment(f: Transform3D, local: Vector3, box_size: Vector3) -> Dictionary:
	return {"xf": Transform3D(f.basis, f * local), "size": box_size, "color": Color.WHITE}


## Weit entfernt angedockte Sektoren zuerst nur grob aufbauen.
func _prepare_area(node: Node3D, end: int) -> void:
	if node is WhiteboxSector and not _in_detail_zone(end):
		(node as WhiteboxSector).build_detail_on_ready = false


func _physics_process(delta: float) -> void:
	super(delta)
	for e in [End.A, End.B]:
		var sector := area(e) as WhiteboxSector
		if sector != null and not sector.has_detail() and _in_detail_zone(e):
			sector.build_detail()


## Guardian ist nah genug an Seite end (oder gar nicht auf dem Weg -> volle Details).
func _in_detail_zone(end: int) -> bool:
	if not is_instance_valid(_guardian):
		return true
	var p := progress_of(_guardian.global_position)
	if p < 0.0:
		return true
	var to_end := p if end == End.A else length - p
	return to_end <= length * (1.0 - DETAIL_FRACTION)
