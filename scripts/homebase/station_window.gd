class_name StationWindow
extends CanvasLayer
## Gemeinsames UI-Fenster der Homebase-Stationen: Titel, Tabs mit Zeilen (Text + Buttons),
## Info-Zeile. Die offene Station fuellt es ueber fill(); nach jeder Aktion refresh().

const ROW_FONT := 15
const INFO_COLOR := Color(1, 1, 1, 0.7)
const HINT := "[F] / [ESC] Schliessen"
const PANEL_COLOR := Color(0.05, 0.06, 0.08, 0.9)
const PADDING := 18

var station: InteractionStation = null

var _title: Label
var _tabs: TabContainer
var _info: Label


func _ready() -> void:
	layer = 5
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 380)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(6)
	style.set_content_margin_all(PADDING)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = _label("", 20, Color.WHITE)
	box.add_child(_title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_info = _label("", 14, INFO_COLOR)
	box.add_child(_info)
	box.add_child(_label(HINT, 12, INFO_COLOR))


func is_open() -> bool:
	return visible and station != null


func open(s: InteractionStation) -> void:
	station = s
	visible = true
	refresh()


func close() -> void:
	visible = false
	station = null


## Inhalt neu aufbauen (aktiver Tab bleibt).
func refresh() -> void:
	if station == null:
		return
	var current := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_title.text = station.title
	_info.text = ""
	station.fill(self)
	if current >= 0 and current < _tabs.get_tab_count():
		_tabs.current_tab = current


func add_tab(tab_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	_tabs.add_child(v)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, tab_name)  # Knotennamen erlauben kein "/"
	return v


## Eine Zeile: Text + Buttons. actions = [[text, callable, enabled], ...]
func add_row(tab: VBoxContainer, text: String, actions := [], color := Color.WHITE) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(text, ROW_FONT, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	for a: Array in actions:
		var b := Button.new()
		b.text = a[0]
		b.disabled = not a[2]
		b.pressed.connect(a[1])
		row.add_child(b)
	tab.add_child(row)
	return row


func set_info(text: String) -> void:
	_info.text = text


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
