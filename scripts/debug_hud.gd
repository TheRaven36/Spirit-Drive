extends CanvasLayer
## Debug-HUD (clean): nur Fadenkreuz + Infotext.
## Der Auto-Aim arbeitet unsichtbar im Hintergrund – Seil und Trefferpunkt
## sieht der Spieler direkt in der Welt. Das Fadenkreuz faerbt sich nur dezent.

@export var guardian_path: NodePath

const STATE_NAMES := ["NORMAL", "HOOKED", "WALLRUN"]
const COL_POINT := Color(0.3, 1.0, 0.5, 0.9)
const COL_ENEMY := Color(1.0, 0.55, 0.2, 0.9)
const COL_IDLE := Color(1, 1, 1, 0.5)

var _guardian: GuardianController
var _crosshair: Label
var _info: Label
var _hooks: Label


func _ready() -> void:
	_guardian = get_node_or_null(guardian_path) as GuardianController

	_crosshair = _make_label("+", 28)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH

	_info = _make_label("", 16)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info.position = Vector2(16, 12)

	_hooks = _make_label("", 18)
	_hooks.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hooks.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hooks.position.y -= 90

	var help := _make_label(
			"WASD Laufen | Shift Sprint (am Seil: Turbo-Einzug) | Space Sprung / am Seil einholen | P Kamera\n"
			+ "LMB Messer | RMB halten Grapple | RMB Doppel-Tap = 2. Haken (Slingshot / Nest) | R Reset", 14)
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

	var mode := ""
	match g.dual_mode:
		GuardianController.DualMode.SLINGSHOT:
			mode = "   SLINGSHOT %d%%" % int(g.slingshot_charge * 100.0)
		GuardianController.DualMode.NEST:
			mode = "   NEST"
	_hooks.text = "%s L   %s R%s" % [_dot(g.hook_left.active), _dot(g.hook_right.active), mode]

	var v := g.velocity
	var horiz := Vector2(v.x, v.z).length()
	_info.text = "Speed  %5.1f m/s  (horiz %5.1f)\nState  %s%s\nCam    %s\nFPS    %d" % [
		v.length(), horiz, STATE_NAMES[g.state], "  TURBO" if g.is_turbo() else "",
		"First-Person" if g.first_person else "Third-Person",
		Engine.get_frames_per_second(),
	]


func _dot(on: bool) -> String:
	return "●" if on else "○"
