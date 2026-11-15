extends Node3D
## Test-Arena fuer Movement-Tests.
##
## Performance-Gesetz: Alle Bloecke werden ueber EIN MultiMeshInstance3D
## gerendert (1 Draw Call) und teilen sich EINEN StaticBody3D mit mehreren
## Collision-Shapes. Seed ist fix -> Layout ist reproduzierbar.

const GRID_SHADER := preload("res://assets/shaders/proto_grid.gdshader")

@export var layout_seed := 1337

var _boxes: Array[Dictionary] = []  # {pos: Vector3, size: Vector3, color: Color}


func _ready() -> void:
	_build_layout()
	_spawn_boxes()


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
		_add_box(Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(w, h, w),
				Color(0.85, 0.9, 1.0))

	# Lange Waende fuer Wall-Runs (parallel, mit Luecke zum Durchspringen).
	for i in 3:
		var x := 16.0 + i * 9.0
		_add_box(Vector3(x, 4.0, -30.0), Vector3(1.0, 8.0, 34.0), Color(1.0, 0.85, 0.7))

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


func _spawn_boxes() -> void:
	var mesh := BoxMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.set_shader_parameter("use_instance_tint", true)
	mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = _boxes.size()

	var body := StaticBody3D.new()
	body.name = "BlocksCollision"
	add_child(body)

	for i in _boxes.size():
		var b: Dictionary = _boxes[i]
		var xf := Transform3D(Basis.from_scale(b.size), b.pos)
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, b.color)

		var shape := BoxShape3D.new()
		shape.size = b.size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = b.pos
		body.add_child(col)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BlocksMultiMesh"
	mmi.multimesh = mm
	add_child(mmi)
