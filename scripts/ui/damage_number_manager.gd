class_name DamageNumberManager
extends CanvasLayer
## Floating Damage Numbers ("Dopamin-Pop"): bei jedem Treffer (Messer inkl. Piercing, Feld-Spirit)
## eine Zahl an der 3D-Trefferstelle, projiziert auf den Bildschirm dieses Spielers.
## Groesse 1x -> 2x und Farbe Weiss -> Gelb/Orange -> Karmesin ueber 0..REF_DAMAGE.
## Anti-Overlap: ueberdeckt die neue Zahl auf dem Bildschirm eine lebende Zahl (Multi-Hit an Kopf/
## Torso/Schulter, mehrere Ziele), rueckt sie auf einer Spirale (zufaelliger Startwinkel) nach aussen,
## bis ihr Text-Rechteck frei ist. Gerechnet wird in Pixeln mit der echten Textgroesse (Krits sind
## doppelt so gross), der Versatz wird in die gleiche Tiefe zurueckprojiziert -> die Zahl haengt
## weiter im Raum.
## Coop: pro Spieler-Viewport eine Instanz, gebunden ueber guardian_path / spirit_path.

const NUMBER_SCENE := preload("res://scenes/ui/damage_number.tscn")
## Referenz-Schaden: ab hier volle Groesse und volles Rot.
const REF_DAMAGE := 400.0
const MAX_SCALE := 2.0
const COL_MAX := Color(1.0, 0.1, 0.1)
## Luft zwischen zwei Zahlen (px).
const MARGIN_PX := 4.0
const SPREAD_TRIES := 48
## Goldener Winkel: Spiral-Kandidaten verteilen sich gleichmaessig ohne Haeufung.
const GOLDEN_ANGLE := 2.39996

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
	add_child(n)  # _ready misst die Textgroesse
	n.world_pos = free_position(n, cam)
	return n


## Naechste freie Anker-Position fuer `n` (unveraendert, wenn frei). Kandidaten liegen auf einer
## Spirale um den Treffpunkt auf dem Bildschirm, Radius waechst mit sqrt(k) -> gleichmaessige Dichte.
func free_position(n: DamageNumber, cam: Camera3D) -> Vector3:
	var pos := n.world_pos
	if cam.is_position_behind(pos):
		return pos
	var depth := -(cam.global_transform.affine_inverse() * pos).z
	var screen := cam.unproject_position(pos)
	var half := n.half_extent()
	var start := randf() * TAU
	for k in SPREAD_TRIES:
		var a := start + k * GOLDEN_ANGLE
		var p := screen + Vector2(cos(a), sin(a)) * half.length() * sqrt(float(k))
		if is_free(p, half, n, cam):
			return pos if k == 0 else cam.project_position(p, depth)
	return pos


## Text-Rechteck (Mitte p, halbe Groesse half) ueberdeckt keine andere lebende Zahl.
func is_free(p: Vector2, half: Vector2, self_n: DamageNumber, cam: Camera3D) -> bool:
	for c in get_children():
		var o := c as DamageNumber
		if o == null or o == self_n or o.is_queued_for_deletion():
			continue
		var d := (cam.unproject_position(o.display_pos()) - p).abs()
		var need := half + o.half_extent() + Vector2.ONE * MARGIN_PX
		if d.x < need.x and d.y < need.y:
			return false
	return true


func _on_knife_hit(target: Node, damage: float, info: Dictionary) -> void:
	spawn(damage, info.get("hit_position", GuardianController.hitbox_center(target as Node3D)))


func _on_spirit_hit(_target: Node, damage: float, _tag: String, hit_position: Vector3) -> void:
	spawn(damage, hit_position)
