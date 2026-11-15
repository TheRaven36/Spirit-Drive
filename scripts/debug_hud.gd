extends CanvasLayer
## Minimales Debug-HUD: Crosshair (gruen = Grapple-Ziel in Reichweite),
## Speed, State, Dash-Charges, FPS und Steuerungshilfe.

@export var guardian_path: NodePath

const STATE_NAMES := ["NORMAL", "DASH", "GRAPPLE", "WALLRUN"]

var _guardian: GuardianController
var _crosshair: Label
var _info: Label


func _ready() -> void:
	_guardian = get_node_or_null(guardian_path) as GuardianController

	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 28)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_crosshair)

	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 4)
	add_child(_info)

	var help := Label.new()
	help.text = "WASD Laufen | Shift Sprint | Space Sprung (am Seil: Gas) | Q/Strg/RMB Dash\n" \
			+ "LMB halten Grapple | R Reset | Esc Maus frei"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 4)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position += Vector2(16, -56)
	add_child(help)


func _process(_delta: float) -> void:
	if _guardian == null:
		return
	_crosshair.modulate = Color(0.3, 1.0, 0.5) if _guardian.aim_valid else Color(1, 1, 1, 0.6)
	var v := _guardian.velocity
	var horiz := Vector2(v.x, v.z).length()
	_info.text = "Speed  %5.1f m/s  (horiz %5.1f)\nState  %s\nDash   %d/%d\nFPS    %d" % [
		v.length(), horiz, STATE_NAMES[_guardian.state],
		_guardian.dash_charges, _guardian.dash_charges_max,
		Engine.get_frames_per_second(),
	]
