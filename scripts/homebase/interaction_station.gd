class_name InteractionStation
extends Area3D
## Gemeinsame Interaktions-Logik aller Homebase-Stationen:
## Guardian im Trigger -> Hinweis "[F] Interagieren" -> F oeffnet das StationWindow
## (Maus frei, Bewegung pausiert) -> F oder ESC schliesst. Inhalt liefert fill().
## Coop: bedient den Guardian, der gerade im Trigger steht (kein Singleton).

const PROMPT := "[F] Interagieren"
const PROMPT_HEIGHT := 2.6

@export var title := "Station"
@export var window_path := NodePath("../StationWindow")

var guardian: GuardianController = null

var _prompt: Label3D
@onready var window: StationWindow = get_node(window_path)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.text = PROMPT
	_prompt.position = Vector3(0, PROMPT_HEIGHT, 0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 40
	_prompt.outline_size = 10
	_prompt.visible = false
	add_child(_prompt)


func _on_body_entered(body: Node3D) -> void:
	if body is GuardianController:
		guardian = body
		_prompt.visible = not is_open()


func _on_body_exited(body: Node3D) -> void:
	if body == guardian and not is_open():
		guardian = null
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if guardian == null:
		return
	if event.is_action_pressed("interact"):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return window.is_open() and window.station == self


func open() -> void:
	if guardian == null or window.is_open():
		return
	_on_open()
	window.open(self)
	guardian.set_controls_locked(true)
	_prompt.visible = false


func close() -> void:
	if not is_open():
		return
	window.close()
	guardian.set_controls_locked(false)
	_prompt.visible = overlaps_body(guardian)


## Unterklassen: Zustand beim Oeffnen vorbereiten.
func _on_open() -> void:
	pass


## Unterklassen: Tabs + Zeilen ins Fenster schreiben.
func fill(_w: StationWindow) -> void:
	pass


func progress() -> GuardianProgress:
	return guardian.progress if guardian else null
