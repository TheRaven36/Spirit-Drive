extends Node3D
## Test-Arena: geschlossene Greybox-Hoehle.
##
## Innen das bisherige Layout (Tuerme, Waende, Allee, Plattformen). Drumherum:
##   - Hoehlenwaende + Decke auf CEILING_MULT x hoechster Turm (max_pillar_height),
##     Boden 300 x 300 aus test_arena.tscn -> kein Herausfallen mehr. Einziger Ausgang:
##     Tor in der +Z-Wand (DOOR_*) zum OrganicTransitionTunnel (Richtung Homebase).
##   - Stalagmiten (Boden), Stalaktiten (Decke, Anker fuer Decken-Schwuenge) und
##     durchgehende Mega-Saeulen Boden -> Decke (vertikale Katapult-Pfade).
##   - Drei Riesen fuer den Massstab: 1.0x NATURE, 1.4x ORDER, 2.0x CYCLE (Titan).
##
## Performance-Gesetz: je Form EIN MultiMeshInstance3D (Bloecke, Hoehlenhuelle, Zylinder =
## 3 Draw Calls), alle teilen sich EINEN StaticBody3D mit mehreren Collision-Shapes.
## Die Huelle wirft keine Schatten (sonst laege die ganze Hoehle im Sonnen-Schatten).
## Seed ist fix -> Layout ist reproduzierbar.

const GRID_SHADER := preload("res://assets/shaders/proto_grid.gdshader")
const DUMMY_SCENE := preload("res://scenes/props/training_dummy.tscn")
## Halbe Kantenlaenge des Bodens (300 x 300 in test_arena.tscn).
const CAVE_HALF := 150.0
const SHELL_THICKNESS := 2.0
const CEILING_MULT := 3.0
const COL_SHELL := Color(0.55, 0.57, 0.62)
const COL_ROCK := Color(0.8, 0.74, 0.66)
## Tor in der +Z-Wand (Mitte x = 0, ab Boden) – passt zur Tunnel-Roehre (Radius 5).
const DOOR_WIDTH := 10.0
const DOOR_HEIGHT := 10.0

## Riesen: [name, position, groesse, saeule, anzeigename]
const GIANTS := [
	["TrainingGiant", Vector3(0, 0, -95), 1.0, SpiritData.Pillar.NATURE, "RIESE"],
	["GiantLarge", Vector3(100, 0, -80), 1.4, SpiritData.Pillar.ORDER, "GROSSER RIESE"],
	["TitanColossus", Vector3(90, 0, 60), 2.0, SpiritData.Pillar.CYCLE, "TITAN"],
]
## Durchgehende Mega-Saeulen Boden -> Decke: [x, z, radius]
const MEGA_PILLARS := [[40.0, 115.0, 6.0], [-125.0, 40.0, 5.0], [125.0, -15.0, 5.5]]
## Stalagmiten (aus dem Boden): [x, z, radius, hoehe]
const STALAGMITES := [
	[95.0, 105.0, 3.0, 18.0], [-40.0, 130.0, 2.5, 30.0], [-132.0, -20.0, 4.0, 24.0],
	[132.0, 40.0, 2.0, 12.0], [60.0, -125.0, 3.5, 35.0], [-50.0, -135.0, 3.0, 16.0],
]
## Stalaktiten (aus der Decke): [x, z, radius, laenge]
const STALACTITES := [
	[60.0, 40.0, 3.0, 40.0], [-40.0, 60.0, 2.5, 55.0], [80.0, -40.0, 4.0, 30.0],
	[-70.0, -60.0, 3.0, 45.0], [20.0, -120.0, 3.5, 60.0], [-110.0, 110.0, 3.0, 35.0],
	[110.0, 110.0, 2.5, 50.0], [-20.0, 95.0, 2.0, 25.0],
]

## Trainings-Dummies (Boden, Plattform-Hoehe, frei schwebend).
const DUMMY_SPOTS := [
	Vector3(7, 1, -20), Vector3(-7, 1, -24), Vector3(0, 1, -40),
	Vector3(-100, 14, -70), Vector3(0, 18, -60), Vector3(25, 12, 15),
]

@export var layout_seed := 1337

## Hoehe des hoechsten Turms und daraus die Hoehlendecke (Unterkante).
var max_pillar_height := 0.0
var ceiling_height := 0.0

var _boxes: Array[Dictionary] = []      # {pos: Vector3, size: Vector3, color: Color}
var _shell: Array[Dictionary] = []      # Hoehlenwaende + Decke (Boxen ohne Schatten)
var _cylinders: Array[Dictionary] = []  # size = (Durchmesser, Hoehe, Durchmesser)


func _ready() -> void:
	_build_layout()
	_build_cave()
	var body := StaticBody3D.new()
	body.name = "BlocksCollision"
	add_child(body)
	_spawn_instances("BlocksMultiMesh", _boxes, BoxMesh.new(), true, body)
	_spawn_instances("CaveShell", _shell, BoxMesh.new(), false, body)
	_spawn_instances("CaveColumns", _cylinders, _unit_cylinder(), true, body)
	_spawn_dummies()
	_spawn_giants()


func _add_box(pos: Vector3, size: Vector3, color := Color.WHITE) -> void:
	_boxes.append({"pos": pos, "size": size, "color": color})


func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed

	# Ring aus hohen Tuermen – Grapple-Anker zum Schwingen.
	for i in 14:
		var a := TAU * float(i) / 14.0
		var r := rng.randf_range(38.0, 70.0)
		var h := rng.randf_range(22.0, 48.0)
		var w := rng.randf_range(4.0, 7.0)
		max_pillar_height = maxf(max_pillar_height, h)
		_add_box(Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(w, h, w),
				Color(0.85, 0.9, 1.0))

	# Lange Waende fuer Wall-Runs (parallel, mit Luecke zum Durchspringen).
	for i in 3:
		var x := 16.0 + i * 9.0
		_add_box(Vector3(x, 4.0, -30.0), Vector3(1.0, 8.0, 34.0), Color(1.0, 0.85, 0.7))

	# Saeulen-Allee: zwei Reihen fuer Grapple-Ketten und Slingshots.
	for i in 8:
		var z := -25.0 - i * 16.0
		for x in [-88.0, -112.0]:
			_add_box(Vector3(x, 14.0, z), Vector3(3.0, 28.0, 3.0), Color(0.8, 0.85, 1.0))

	# Enge Halle mit Decke: Doppel-Haken in engen Raeumen testen.
	var hall := Color(1.0, 0.9, 0.75)
	_add_box(Vector3(-64.5, 4.5, 100.0), Vector3(1.0, 9.0, 20.0), hall)
	_add_box(Vector3(-55.5, 4.5, 100.0), Vector3(1.0, 9.0, 20.0), hall)
	_add_box(Vector3(-60.0, 9.5, 100.0), Vector3(10.0, 1.0, 20.0), hall)

	# Schwebende Plattformen hoch oben.
	for i in 8:
		var a := rng.randf() * TAU
		var r := rng.randf_range(10.0, 45.0)
		_add_box(Vector3(cos(a) * r, rng.randf_range(14.0, 28.0), sin(a) * r),
				Vector3(rng.randf_range(4.0, 8.0), 1.0, rng.randf_range(4.0, 8.0)),
				Color(0.7, 1.0, 0.8))

	# Verstreute kleine Bloecke / Rampen-Ersatz.
	for i in 30:
		var p := Vector3(rng.randf_range(-35.0, 35.0), 0.0, rng.randf_range(5.0, 40.0))
		var s := Vector3(rng.randf_range(1.5, 5.0), rng.randf_range(1.0, 4.0), rng.randf_range(1.5, 5.0))
		p.y = s.y * 0.5
		_add_box(p, s, Color(0.95, 0.95, 0.95))


## Geschlossene Huelle, Stalagmiten, Stalaktiten und Mega-Saeulen.
func _build_cave() -> void:
	ceiling_height = CEILING_MULT * max_pillar_height
	var h := ceiling_height
	var t := SHELL_THICKNESS
	var span := 2.0 * (CAVE_HALF + t)
	var off := CAVE_HALF + t * 0.5
	_shell.append({"pos": Vector3(0, h + t * 0.5, 0), "size": Vector3(span, t, span), "color": COL_SHELL})
	for side in [-1.0, 1.0]:
		_shell.append({"pos": Vector3(off * side, h * 0.5, 0), "size": Vector3(t, h, span), "color": COL_SHELL})
	_shell.append({"pos": Vector3(0, h * 0.5, -off), "size": Vector3(span, h, t), "color": COL_SHELL})
	_add_door_wall(off, h, t, span)
	for m: Array in MEGA_PILLARS:
		_add_cylinder(Vector3(m[0], h * 0.5, m[1]), m[2], h)
	for s: Array in STALAGMITES:
		_add_cylinder(Vector3(s[0], s[3] * 0.5, s[1]), s[2], s[3])
	for s: Array in STALACTITES:
		_add_cylinder(Vector3(s[0], h - s[3] * 0.5, s[1]), s[2], s[3])


## +Z-Wand in drei Teilen um das Tunnel-Tor (links, rechts, Sturz darueber).
func _add_door_wall(off: float, h: float, t: float, span: float) -> void:
	var side_w := (span - DOOR_WIDTH) * 0.5
	var side_x := (DOOR_WIDTH + side_w) * 0.5
	for sx in [-1.0, 1.0]:
		_shell.append({"pos": Vector3(side_x * sx, h * 0.5, off), "size": Vector3(side_w, h, t), "color": COL_SHELL})
	var top_h := h - DOOR_HEIGHT
	_shell.append({"pos": Vector3(0, DOOR_HEIGHT + top_h * 0.5, off),
			"size": Vector3(DOOR_WIDTH, top_h, t), "color": COL_SHELL})


func _add_cylinder(pos: Vector3, radius: float, height: float) -> void:
	_cylinders.append({"pos": pos, "size": Vector3(radius * 2.0, height, radius * 2.0), "color": COL_ROCK})


func _unit_cylinder() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 0.5
	c.height = 1.0
	return c


## Ein MultiMesh (1 Draw Call) fuer alle Eintraege + passende Collision-Shapes im gemeinsamen Body.
func _spawn_instances(node_name: String, items: Array[Dictionary], mesh: PrimitiveMesh,
		shadows: bool, body: StaticBody3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.set_shader_parameter("use_instance_tint", true)
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var b: Dictionary = items[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(b.size), b.pos))
		mm.set_instance_color(i, b.color)
		var col := CollisionShape3D.new()
		col.shape = _shape_for(mesh, b.size)
		col.position = b.pos
		body.add_child(col)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _shape_for(mesh: PrimitiveMesh, size: Vector3) -> Shape3D:
	if mesh is CylinderMesh:
		var c := CylinderShape3D.new()
		c.radius = size.x * 0.5
		c.height = size.y
		return c
	var b := BoxShape3D.new()
	b.size = size
	return b


func _spawn_dummies() -> void:
	for p: Vector3 in DUMMY_SPOTS:
		var d := DUMMY_SCENE.instantiate() as Node3D
		d.position = p
		add_child(d)


## Riesen in drei Groessen, Gesicht zur Arena-Mitte. HP wachsen mit der Groesse.
func _spawn_giants() -> void:
	for g: Array in GIANTS:
		var giant := TrainingGiant.new()
		giant.name = g[0]
		giant.position = g[1]
		giant.size_scale = g[2]
		giant.pillar = g[3]
		giant.display_name = g[4]
		giant.max_hp *= g[2]
		var to_center := -(g[1] as Vector3)
		if to_center.length() > 0.1:
			giant.rotation.y = atan2(to_center.x, to_center.z)
		add_child(giant)
