class_name DamageNumberManager
extends CanvasLayer
## Floating Damage Numbers ("Dopamin-Pop"): bei jedem Treffer (Messer inkl. Piercing, Feld-Spirit)
## eine Zahl an der 3D-Trefferstelle, projiziert auf den Bildschirm dieses Spielers.
## Groesse 1x -> 2x und Farbe Weiss -> Gelb/Orange -> Karmesin ueber 0..REF_DAMAGE.
## Coop: pro Spieler-Viewport eine Instanz, gebunden ueber guardian_path / spirit_path.

const NUMBER_SCENE := preload("res://scenes/ui/damage_number.tscn")
## Referenz-Schaden: ab hier volle Groesse und volles Rot.
const REF_DAMAGE := 400.0
const MAX_SCALE := 2.0
const COL_MAX := Color(1.0, 0.1, 0.1)

## Weiss -> Gelb -> Orange -> Karmesin.
static var _gradient := _make_gradient()

@export var guardian_path: NodePath
@export var spirit_path: NodePath


func _ready() -> void:
	var g := get_node_or_null(guardian_path) as GuardianController
	if g:
		g.knife.hit_landed.connect(_on_knife_hit)
	var sp := get_node_or_null(spirit_path) as SpiritEntity
	if sp:
		sp.hit_landed.connect(_on_spirit_hit)


static func _make_gradient() -> Gradient:
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.35, 0.65, 1.0])
	gr.colors = PackedColorArray([Color.WHITE, Color(1.0, 0.9, 0.2), Color(1.0, 0.5, 0.1), COL_MAX])
	return gr


## Normalisierter Schaden t = damage / REF_DAMAGE (0..1).
static func damage_t(damage: float) -> float:
	return clampf(damage / REF_DAMAGE, 0.0, 1.0)


static func scale_for(damage: float) -> float:
	return lerpf(1.0, MAX_SCALE, damage_t(damage))


static func color_for(damage: float) -> Color:
	return _gradient.sample(damage_t(damage))


func spawn(damage: float, world_pos: Vector3) -> DamageNumber:
	var cam := get_viewport().get_camera_3d()
	if cam == null or damage <= 0.0:
		return null
	var n := NUMBER_SCENE.instantiate() as DamageNumber
	n.setup(damage, world_pos, scale_for(damage), color_for(damage), cam)
	add_child(n)
	return n


func _on_knife_hit(target: Node, damage: float, info: Dictionary) -> void:
	spawn(damage, info.get("hit_position", GuardianController.hitbox_center(target as Node3D)))


func _on_spirit_hit(_target: Node, damage: float, _tag: String, hit_position: Vector3) -> void:
	spawn(damage, hit_position)
