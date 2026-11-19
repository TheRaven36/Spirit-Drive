class_name OrganicTransitionTunnel
extends SeamlessLoadingGate
## Organischer 3D-Grapple-Tunnel zwischen zwei Sektoren (Loading Gate: siehe SeamlessLoadingGate).
##
## Geometrie: S-Kurve (links/rechts UND steil hoch/runter, ~183 m), die die Sichtlinie bricht.
##   Elliptischer Querschnitt 24 m breit x 18 m hoch (Schwing-Raum). Roehre = CSGPolygon3D
##   entlang Path3D (aussen) minus etwas laengere Innen-Roehre; an beiden Enden schliesst eine
##   Platte mit Tor (DOOR_SIZE, passt zu Hoehlen- und Homebase-Tor) ab. Innenflaeche mit
##   Collision (Grapple-Anker ueberall). Felsvorspruenge an den Kurven-Scheiteln (links, rechts,
##   Decke) als zusaetzliche Anker (ein MultiMesh, ein Body).
##   Kurve so weit, dass sich die breite Roehre in den Biegungen nicht selbst schneidet.
## Anker: EntryAnchor = Tor A am Boden, ExitAnchor = Tor B am Boden (um 180 Grad gedreht,
##   +Z zeigt zurueck in die Roehre) – passend zu den Exit-Markern der Sektoren.

## Innen-Halbachsen der Ellipse: 24 m breit, 18 m hoch (= cross_section in der Szene).
const RADIUS_X := 12.0
const RADIUS_Y := 9.0
## Tor in den End-Platten (Breite, Hoehe; ab Roehren-Boden).
const DOOR_SIZE := Vector2(10, 10)
## Innen-Roehre ragt an beiden Enden so weit hinaus -> keine End-Kappen.
const INNER_EXTENSION := 2.0
## Kurven-Stuetzpunkte. Das Ende (z = 140) bestimmt End-Platte B und den ExitAnchor in
## organic_transition_tunnel.tscn.
const POINTS := [
	Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(18, 12, 40), Vector3(0, 36, 70),
	Vector3(-18, 12, 100), Vector3(0, 0, 130), Vector3(0, 0, 140),
]
## Felsvorspruenge: [Anteil der Laenge, Seite] – Seite: Richtung im Querschnitt (x = links/rechts, y = Decke).
const LEDGES := [
	[0.2, Vector2(-1, 0)], [0.33, Vector2(0, 1)], [0.45, Vector2(1, 0)],
	[0.55, Vector2(0, 1)], [0.67, Vector2(-1, 0)], [0.8, Vector2(1, 0)],
]
const LEDGE_SIZE := Vector3(3.0, 1.5, 3.0)
const COL_LEDGE := Color(0.8, 0.72, 0.6)

@onready var _path_outer: Path3D = $PathOuter
@onready var _path_inner: Path3D = $PathInner


func _curve_points() -> Array:
	return POINTS


func _build_geometry() -> void:
	_path_outer.curve = curve
	_path_inner.curve = make_curve(POINTS, INNER_EXTENSION)
	_build_ledges()


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
		var col := _box_shape(LEDGE_SIZE)
		col.transform = xf
		body.add_child(col)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LedgesMesh"
	mmi.multimesh = mm
	add_child(mmi)


## Vorsprung sitzt an der Innenwand: Querschnitts-Richtung side, halb in der Wand.
func _ledge_transform(fraction: float, side: Vector2) -> Transform3D:
	var frame := curve.sample_baked_with_rotation(length * fraction)
	var dir := (frame.basis.x * side.x + frame.basis.y * side.y).normalized()
	var r := RADIUS_X if absf(side.x) > absf(side.y) else RADIUS_Y
	return Transform3D(frame.basis, frame.origin + dir * (r - LEDGE_SIZE.y * 0.25))
