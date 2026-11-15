extends CanvasLayer
## Debug-HUD.
## - Fadenkreuz in der Bildmitte (beide Kamera-Modi): gruen = Grapple-Punkt,
##   orange = Gegner im Lock.
## - Lock-Marker rastet auf den per Auto-Aim gefundenen Punkt/Gegner ein.
## - Seil-Status (Q / E / RMB), Speed, State, Dash, Kamera-Modus, FPS.

@export var guardian_path: NodePath

const STATE_NAMES := ["NORMAL", "DASH", "HOOKED", "WALLRUN"]
const COL_POINT := Color(0.3, 1.0, 0.5)
const COL_ENEMY := Color(1.0, 0.55, 0.2)
const COL_IDLE := Color(1, 1, 1, 0.6)

var _guardian: GuardianController
var _crosshair: Label
var _lock: Label
var _info: Label
var _hooks: Label


func _ready() -> void:
	_guardian = get_node_or_null(guardian_path) as GuardianController

	_crosshair = _make_label("+", 28)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH

	_lock = _make_label("[   ]", 26)
	_lock.size = Vector2(80, 40)

	_info = _make_label("", 16)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info.position = Vector2(16, 12)

	_hooks = _make_label("", 20)
	_hooks.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hooks.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hooks.position.y -= 90

	var help := _make_label(
			"WASD Laufen | Shift Sprint | Space Sprung / am Seil Hoehe | Strg Dash | P Kamera\n"
			+ "LMB Messer | RMB halten Combat-Grapple + Lock | Q / E halten Swing links / rechts | R Reset", 14)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position += Vector2(16, -56)


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if _guardian == null:
		return
	var g := _guardian
	var col := COL_IDLE
	if g.aim_kind == GuardianController.AimKind.POINT:
		col = COL_POINT
	elif g.aim_kind == GuardianController.AimKind.ENEMY:
		col = COL_ENEMY
	_crosshair.modulate = col

	# Lock-Marker auf den eingerasteten Punkt projizieren
	var show_lock := g.aim_kind != GuardianController.AimKind.NONE \
			and (g.aim_assisted or g.aim_kind == GuardianController.AimKind.ENEMY) \
			and not g.camera.is_position_behind(g.aim_point)
	_lock.visible = show_lock
	if show_lock:
		_lock.modulate = col
		_lock.position = g.camera.unproject_position(g.aim_point) - _lock.size * 0.5

	_hooks.text = "%s Q    %s RMB    %s E" % [
		_dot(g.hook_left.active), _dot(g.hook_combat.active), _dot(g.hook_right.active)]

	var v := g.velocity
	var horiz := Vector2(v.x, v.z).length()
	_info.text = "Speed  %5.1f m/s  (horiz %5.1f)\nState  %s\nDash   %d/%d\nCam    %s\nFPS    %d" % [
		v.length(), horiz, STATE_NAMES[g.state],
		g.dash_charges, g.dash_charges_max,
		"First-Person" if g.first_person else "Third-Person",
		Engine.get_frames_per_second(),
	]


func _dot(on: bool) -> String:
	return "●" if on else "○"
