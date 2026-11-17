class_name TrainingGiant
extends StaticBody3D
## Grosser Test-Gegner (~14 m x size_scale) mit mehreren Lock-Punkten (LockPoint) fuer
## Hard-Lock und Mausrad-Ziel-Wechsel. Baut Koerper, Kollision und Punkte selbst –
## size_scale skaliert Teile, Shapes und Punkte direkt (kein skalierter Physik-Body).
## Steht mit dem Gesicht in +Z. Hat eine Saeule (get_spirit_pillar) fuer Element-Faktoren.
## Ruestung (armor_integrity): Treffer gehen zuerst in die Ruestung. Solange sie steht, prallen
## Elementar-Faktoren ab (nur reiner Stahl bricht sie mit Bonus), danach "Armor-Broken".

signal defeated
signal armor_broken

const FLASH_TIME := 0.15
const DMG_SHOW_TIME := 1.5
const LABEL_HEIGHT := 15.0

@export var max_hp := 3000.0
@export var respawn_time := 4.0
## Boss-Skalierung: ein Treffer nimmt hoechstens ~diesen Anteil der Max-HP
## (weicher Deckel, siehe KnifeCombat.scale_for_target) – kein One-Hit-Kill.
@export var max_hit_fraction := 0.15
## Groessen-Faktor (1.0 = Standard-Riese, 2.0 = Titan).
@export var size_scale := 1.0
@export var pillar: SpiritData.Pillar = SpiritData.Pillar.NATURE
@export var display_name := "RIESE"
@export var max_armor := 500.0

var hp := 3000.0
var hits_taken := 0
var last_damage := 0.0
var last_point := ""
var armor_integrity := 0.0

var _mat: StandardMaterial3D
var _label: Label3D
var _meshes: Array[MeshInstance3D] = []
var _shapes := {}
var _flash := 0.0
var _dmg_show := 0.0
var _down_t := 0.0

## [name, art, groesse, position]
const PARTS := [
	["BeinL", "box", Vector3(1.6, 6.0, 1.6), Vector3(-1.4, 3.0, 0.0)],
	["BeinR", "box", Vector3(1.6, 6.0, 1.6), Vector3(1.4, 3.0, 0.0)],
	["Torso", "box", Vector3(4.5, 5.0, 2.5), Vector3(0.0, 8.5, 0.0)],
	["ArmL", "box", Vector3(1.2, 5.5, 1.2), Vector3(-3.0, 8.2, 0.0)],
	["ArmR", "box", Vector3(1.2, 5.5, 1.2), Vector3(3.0, 8.2, 0.0)],
	["Kopf", "sphere", Vector3(1.4, 0, 0), Vector3(0.0, 12.4, 0.0)],
]

## [label, position, damage_mult, koerperteil, rahmen-radius] – Punkte sitzen knapp vor der
## Oberflaeche und haengen unter der CollisionShape3D ihres Koerperteils (folgen der Hitbox).
const POINTS := [
	["Kopf", Vector3(0.0, 12.6, 1.45), 1.0, "Kopf", 1.2],
	["Nacken", Vector3(0.0, 11.3, -1.4), 1.0, "Kopf", 0.9],
	["Brust", Vector3(0.0, 9.5, 1.3), 1.0, "Torso", 1.6],
	["Schulter L", Vector3(-3.0, 10.6, 0.65), 1.0, "ArmL", 0.9],
	["Schulter R", Vector3(3.0, 10.6, 0.65), 1.0, "ArmR", 0.9],
	["Knie L", Vector3(-1.4, 3.0, 0.85), 1.0, "BeinL", 0.9],
	["Knie R", Vector3(1.4, 3.0, 0.85), 1.0, "BeinR", 0.9],
]


func _ready() -> void:
	hp = max_hp
	armor_integrity = max_armor
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.75, 0.35, 0.35)
	_mat.emission_enabled = true
	var s := size_scale
	for p: Array in PARTS:
		_add_part(p[0], p[1] == "box", p[2] * s, p[3] * s)
	for p: Array in POINTS:
		_add_lock_point(p[0], p[1] * s, p[2], p[3], p[4] * s)
	_label = Label3D.new()
	_label.position = Vector3(0, LABEL_HEIGHT * s, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 64
	_label.outline_size = 14
	add_child(_label)
	_update_label()


## Koerperteil = Mesh + gleich grosse CollisionShape3D (Box: size, Kugel: size.x = Radius).
func _add_part(part_name: String, is_box: bool, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	if is_box:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
	else:
		var sm := SphereMesh.new()
		sm.radius = size.x
		sm.height = size.x * 2.0
		mi.mesh = sm
		var ss := SphereShape3D.new()
		ss.radius = size.x
		cs.shape = ss
	mi.name = part_name
	mi.position = pos
	mi.material_override = _mat
	cs.name = "Shape_" + part_name
	cs.position = pos
	add_child(mi)
	add_child(cs)
	_meshes.append(mi)
	_shapes[part_name] = cs


## Lock-Punkt haengt unter der Shape seines Koerperteils (folgt der Hitbox).
func _add_lock_point(label: String, pos: Vector3, mult: float, part_name: String, radius: float) -> void:
	var part: CollisionShape3D = _shapes[part_name]
	var lp := LockPoint.new()
	lp.name = "LP_" + label.replace(" ", "")
	lp.label = label
	lp.damage_mult = mult
	lp.radius = radius
	lp.position = pos - part.position
	part.add_child(lp)


func is_armored() -> bool:
	return armor_integrity > 0.0


func get_spirit_pillar() -> SpiritData.Pillar:
	return pillar


## Gesamthoehe = Scheitel des Kopfes (letzter PARTS-Eintrag: Mitte + Radius).
func height() -> float:
	var head: Array = PARTS[-1]
	return ((head[3] as Vector3).y + (head[2] as Vector3).x) * size_scale


func get_hit_cap() -> float:
	return max_hp * max_hit_fraction


func is_lockable() -> bool:
	return _down_t <= 0.0


func take_hit(damage: float, _dir: Vector3, source: Node) -> void:
	if _down_t > 0.0:
		return
	hits_taken += 1
	var absorbed := minf(damage, armor_integrity)
	armor_integrity -= absorbed
	if absorbed > 0.0 and armor_integrity <= 0.0:
		armor_broken.emit()
	hp -= damage - absorbed
	last_damage = damage
	last_point = ""
	if source is GuardianController:
		last_point = (source as GuardianController).knife.last_hit.get("point", "")
	_flash = FLASH_TIME
	_dmg_show = DMG_SHOW_TIME
	if hp <= 0.0:
		_down_t = respawn_time
		_set_visible(false)
		defeated.emit()
	_update_label()


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_mat.emission = Color.WHITE * (_flash / FLASH_TIME) * 2.0
	if _dmg_show > 0.0:
		_dmg_show -= delta
		if _dmg_show <= 0.0:
			_update_label()
	if _down_t > 0.0:
		_down_t -= delta
		if _down_t <= 0.0:
			hp = max_hp
			armor_integrity = max_armor
			_set_visible(true)
			_update_label()


func _set_visible(on: bool) -> void:
	for m in _meshes:
		m.visible = on


func _update_label() -> void:
	var t := "%s  %d" % [display_name, maxf(hp, 0.0)] if _down_t <= 0.0 else display_name + "  ..."
	if is_armored() and _down_t <= 0.0:
		t += "\nRUESTUNG %d" % armor_integrity
	if _dmg_show > 0.0:
		t += "\n-%d %s" % [last_damage, last_point]
	_label.text = t
