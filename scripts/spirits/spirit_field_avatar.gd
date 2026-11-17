class_name SpiritFieldAvatar
extends Node3D
## Greybox-Platzhalter fuer den aktiven Feld-Spirit: leuchtende Kugel in der
## theme_color, die dem Guardian schwebend folgt. Hoert nur auf das Signal
## field_spirit_changed des zugewiesenen Rosters (keine globale Abhaengigkeit).
## Spaeter ersetzt durch echte Spirit-Modelle + KI.

@export var roster_path: NodePath
@export var follow_offset := Vector3(1.4, 1.1, 1.2)
@export var follow_sharpness := 8.0
@export var radius := 0.35

var spirit: SpiritData = null
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _owner3d: Node3D
var _t := 0.0


func _ready() -> void:
	top_level = true
	_owner3d = get_parent() as Node3D
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 0.5  # dezent, kein Ueberstrahlen (Glow ist an)
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var roster := get_node_or_null(roster_path) as SpiritRosterComponent
	if roster:
		roster.field_spirit_changed.connect(set_spirit)
		set_spirit(roster.field_spirit())
	if _owner3d:
		global_position = _target_pos()


func set_spirit(s: SpiritData) -> void:
	spirit = s
	visible = s != null
	if s:
		_mat.albedo_color = s.theme_color
		_mat.emission = s.theme_color
		scale = Vector3.ONE * 1.6  # kurzer "Beschwoerungs"-Puls


func _target_pos() -> Vector3:
	var yaw := _owner3d.global_basis
	if _owner3d is GuardianController:
		yaw = Basis(Vector3.UP, (_owner3d as GuardianController)._yaw)
	return _owner3d.get_global_transform_interpolated().origin + yaw * follow_offset + Vector3.UP * sin(_t * 2.5) * 0.15


func _process(delta: float) -> void:
	if _owner3d == null:
		return
	_t += delta
	var k := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_target_pos(), k)
	scale = scale.lerp(Vector3.ONE, k)
