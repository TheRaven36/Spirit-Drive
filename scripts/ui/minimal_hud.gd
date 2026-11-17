class_name MinimalHUD
extends CanvasLayer
## Minimal-HUD: so viel wie noetig, so wenig wie moeglich – keine Erklaertexte.
##   Oben links ... HP-Balken, darunter Haken-Indikatoren L / R (Cooldown-Fill)
##   Unten links .. 3 Spirit-Slots (Feld = Glow-Rahmen, Waffe = Kern + Klinge)
##   "+" .......... halbtransparentes Steuerungs-Overlay ein/aus (Standard: aus)
##
## Bindet sich nur ueber NodePaths/Signale an EINEN Guardian -> fuer Coop einfach
## pro Spieler eine Instanz (eigener Viewport/Split-Screen) mit eigenem Pfad.

@export var guardian_path: NodePath
## Leer = Guardian/SpiritRoster bzw. Guardian/Health.
@export var roster_path: NodePath
@export var health_path: NodePath

## Steuerungs-Overlay: [Beschreibung, Actions ...] – Tasten kommen live aus der InputMap.
const CONTROLS := [
	["Laufen", "move_forward", "move_left", "move_back", "move_right"],
	["Sprint", "sprint"], ["Sprung", "jump"],
	["Seil (Doppel-Tap = 2. Haken)", "grapple"],
	["Angriff / Gegner greifen (Doppelklick = 2 Seile)", "attack"],
	["Ziel waehlen", "hard_lock"], ["Trefferpunkt wechseln", "lock_next", "lock_prev"],
	["Spirit aufs Feld", "field_spirit_1", "field_spirit_2", "field_spirit_3"],
	["Waffen-Spirit wechseln", "cycle_weapon_spirit_prev", "cycle_weapon_spirit_next"],
	["Kamera", "toggle_camera"], ["Reset", "reset"], ["Station benutzen", "interact"],
	["Steuerung ein/aus", "toggle_controls_overlay"],
]

@onready var hp_bar: ProgressBar = %HPBar
@onready var hook_left_ind: HookIndicator = %HookLeft
@onready var hook_right_ind: HookIndicator = %HookRight
@onready var slots: Array[SpiritSlot] = [%Slot1, %Slot2, %Slot3]
@onready var controls_overlay: Control = %ControlsOverlay
@onready var _controls_grid: GridContainer = %ControlsGrid

var guardian: GuardianController
var roster: SpiritRosterComponent
var health: HealthComponent


func _ready() -> void:
	GuardianInput.ensure_actions()
	controls_overlay.visible = false
	guardian = get_node_or_null(guardian_path) as GuardianController
	roster = _resolve(roster_path, "SpiritRoster") as SpiritRosterComponent
	health = _resolve(health_path, "Health") as HealthComponent
	if health:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.hp, health.max_hp)
	hp_bar.visible = health != null
	if roster:
		roster.field_spirit_changed.connect(_on_spirit_state_changed.unbind(1))
		roster.weapon_spirit_changed.connect(_on_spirit_state_changed.unbind(1))
		roster.roster_changed.connect(_on_spirit_state_changed.unbind(1))
	refresh_spirits()
	if guardian:
		guardian.hook_fired.connect(_on_hook_event)
		guardian.hook_released.connect(_on_hook_event)
	_build_controls()


func _resolve(path: NodePath, child_name: String) -> Node:
	if not path.is_empty():
		return get_node_or_null(path)
	return guardian.get_node_or_null(child_name) if guardian else null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_controls_overlay") and not event.is_echo():
		toggle_controls_overlay()
		get_viewport().set_input_as_handled()


func toggle_controls_overlay() -> void:
	controls_overlay.visible = not controls_overlay.visible


func _process(_delta: float) -> void:
	if guardian:
		_sync_hook(hook_left_ind, guardian.hook_left)
		_sync_hook(hook_right_ind, guardian.hook_right)


# --- Bindings -------------------------------------------------------------
func _on_health_changed(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp


func _on_hook_event(hook: GrappleHook) -> void:
	_sync_hook(hook_left_ind if hook.kind == GrappleHook.Kind.HIP_LEFT else hook_right_ind, hook)


func _sync_hook(ind: HookIndicator, hook: GrappleHook) -> void:
	ind.active = hook.active
	ind.combat = hook.combat
	ind.ratio = hook.ready_ratio()


func _on_spirit_state_changed() -> void:
	refresh_spirits()


func refresh_spirits() -> void:
	for i in slots.size():
		var s := slots[i]
		s.spirit = roster.get_spirit(i) if roster else null
		s.is_field = roster != null and i == roster.active_field_spirit_index
		s.is_weapon = roster != null and i == roster.weapon_socket_spirit_index


# --- Steuerungs-Overlay ---------------------------------------------------
func _build_controls() -> void:
	for c in _controls_grid.get_children():
		c.queue_free()
	for row: Array in CONTROLS:
		var keys: PackedStringArray = []
		for i in range(1, row.size()):
			keys.append(key_text(row[i]))
		_controls_grid.add_child(_label(" / ".join(keys), Color(1, 1, 1, 1)))
		_controls_grid.add_child(_label(row[0], Color(1, 1, 1, 0.7)))


## Kurznamen fuer lange Engine-Bezeichnungen.
const SHORT_NAMES := {
	"Left Mouse Button": "LMB", "Right Mouse Button": "RMB", "Middle Mouse Button": "MMB",
	"Mouse Wheel Up": "Rad ↑", "Mouse Wheel Down": "Rad ↓", "Plus": "+", "Kp Add": "Num+",
}


## Lesbare Tastennamen aller Tastatur/Maus-Belegungen einer Action ("+ / Num+").
static func key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "-"
	var names: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			var t: String = ev.as_text().replace(" (Physical)", "").replace(" - Physical", "")
			names.append(SHORT_NAMES.get(t, t))
	return " / ".join(names) if not names.is_empty() else "-"


func _label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	return l
