class_name GuardianInput
extends RefCounted
## Registriert die Input-Actions zur Laufzeit, falls sie in der InputMap fehlen.
## Actions, die im Editor (Projekteinstellungen > Eingabe) angelegt wurden,
## werden nicht angefasst – dort gesetzte Bindings haben also Vorrang.

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"dash": [KEY_Q, KEY_CTRL],
	"grapple": [],
	"reset": [KEY_R],
}

const MOUSE := {
	"grapple": [MOUSE_BUTTON_LEFT],
	"dash": [MOUSE_BUTTON_RIGHT],
}


static func ensure_actions() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for button: MouseButton in MOUSE.get(action, []):
			var mb := InputEventMouseButton.new()
			mb.button_index = button
			InputMap.action_add_event(action, mb)
