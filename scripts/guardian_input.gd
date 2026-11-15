class_name GuardianInput
extends RefCounted
## Registriert die Input-Actions zur Laufzeit (Tastatur/Maus + Xbox-Controller).
## Actions, die im Editor (Projekteinstellungen > Eingabe) angelegt wurden,
## werden nicht angefasst – dort gesetzte Bindings haben also Vorrang.
##
## Layout:
##   LMB / X ............ attack        (Jagdmesser-Slash)
##   RMB / LT ........... grapple       (straffes Seil, halten; Doppel-Tap = 2. Haken)
##   W / S am Seil ...... Winde: W = Turbo-Einzug, S = starres Seil (A/D = seitlich)
##   Mausrad-Klick / R3 . hard_lock     (Ziel waehlen + Kamera-Snap-Impuls, halten = loesen)
##   Mausrad / D-Pad L-R  lock_next / lock_prev (Trefferpunkt-/Ziel-Wechsel)
##   LMB halten ......... Combat-Seil zum Ziel (Hard-Lock oder Gegner unterm
##                        Fadenkreuz = Auto-Grab) + heranziehen, loslassen = Schlag
##   Shift / L3 ......... sprint
##   Space / A .......... jump
##   P / View ........... toggle_camera (First-/Third-Person)
##   R / Menu ........... reset

const DEADZONE := 0.2

## Jeder Eintrag: [typ, code, (achsen-richtung)]
const BINDINGS := {
	"move_forward": [["key", KEY_W], ["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [["key", KEY_S], ["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [["key", KEY_A], ["axis", JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [["key", KEY_D], ["axis", JOY_AXIS_LEFT_X, 1.0]],
	"look_left": [["axis", JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [["axis", JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [["axis", JOY_AXIS_RIGHT_Y, 1.0]],
	"jump": [["key", KEY_SPACE], ["joy", JOY_BUTTON_A]],
	"sprint": [["key", KEY_SHIFT], ["joy", JOY_BUTTON_LEFT_STICK]],
	"attack": [["mouse", MOUSE_BUTTON_LEFT], ["joy", JOY_BUTTON_X]],
	"grapple": [["mouse", MOUSE_BUTTON_RIGHT], ["axis", JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"hard_lock": [["mouse", MOUSE_BUTTON_MIDDLE], ["joy", JOY_BUTTON_RIGHT_STICK]],
	"lock_next": [["mouse", MOUSE_BUTTON_WHEEL_DOWN], ["joy", JOY_BUTTON_DPAD_RIGHT]],
	"lock_prev": [["mouse", MOUSE_BUTTON_WHEEL_UP], ["joy", JOY_BUTTON_DPAD_LEFT]],
	"toggle_camera": [["key", KEY_P], ["joy", JOY_BUTTON_BACK]],
	"reset": [["key", KEY_R], ["joy", JOY_BUTTON_START]],
}


static func ensure_actions() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for b: Array in BINDINGS[action]:
			InputMap.action_add_event(action, _make_event(b))


static func _make_event(b: Array) -> InputEvent:
	match b[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = b[1]
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = b[1]
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.button_index = b[1]
			return j
		_:
			var a := InputEventJoypadMotion.new()
			a.axis = b[1]
			a.axis_value = b[2]
			return a
