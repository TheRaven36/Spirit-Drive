class_name MiniMap
extends Control
## Karte des Kleeblatt-Graphen (Sektoren = Punkte, Spieler-Verbindungen = Linien) aus WorldMapData.
##   full_view = false: Ausschnitt um den aktuellen Sektor + seine Nachbarn (Minimap unten rechts).
##   full_view = true:  ganze Karte mit allen Namen (Overlay, Taste M / D-Pad hoch).
## Spieler-Punkt: im Sektor auf dessen Kartenposition, im Uebergang anteilig auf der Verbindungslinie.
## Rot = gesperrter Uebergang, Pfeil = Einbahnstrasse, Quadrat = Lager (gefuellt = gebaut).
## Monster-Pfade erscheinen nicht. Bindet sich an EINEN Guardian (Coop: eine Instanz pro Spieler).

@export var world_map_path: NodePath
@export var guardian_path: NodePath
@export var full_view := false

## Rand um den Kartenausschnitt (Karten-Einheiten) und Innenabstand (Pixel).
const VIEW_MARGIN := 1.2
const PADDING := 14.0
## Kartenausschnitt folgt dem Spieler weich (Anteil pro Sekunde).
const VIEW_FOLLOW := 4.0
const NODE_RADIUS := 6.0
const CAMP_SIZE := 7.0
const PLAYER_RADIUS := 5.0
const FONT_SIZE := 11
const ARROW_SIZE := 7.0
const COL_BG := Color(0.05, 0.06, 0.08, 0.78)
const COL_LINK := Color(0.85, 0.85, 0.9, 0.7)
const COL_BLOCKED := Color(1.0, 0.3, 0.25, 0.9)
const COL_TEXT := Color(1, 1, 1, 0.9)
const COL_PLAYER := Color(1.0, 0.85, 0.2)
const COL_CURRENT := Color(1, 1, 1)
## Ausserhalb des Fokus (gezoomte Ansicht) abgedunkelt.
const DIM := 0.3
const REGION_COLORS := {
	WorldSectorData.Region.HEADQUARTERS: Color(0.35, 0.75, 1.0),
	WorldSectorData.Region.STEM: Color(0.75, 0.65, 0.5),
	WorldSectorData.Region.CENTER: Color(0.9, 0.9, 0.95),
	WorldSectorData.Region.LOOP_NATURE: Color(0.4, 0.85, 0.4),
	WorldSectorData.Region.LOOP_SWAMP: Color(0.55, 0.6, 0.35),
	WorldSectorData.Region.LOOP_MOUNTAIN: Color(0.65, 0.7, 0.85),
	WorldSectorData.Region.LOOP_DESERT: Color(0.95, 0.8, 0.45),
}

var _wm: WorldMapManager
var _guardian: Node3D
var _view := Rect2()


func _ready() -> void:
	GuardianInput.ensure_actions()
	_wm = get_node_or_null(world_map_path) as WorldMapManager
	_guardian = get_node_or_null(guardian_path) as Node3D
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _ready_to_draw():
		_view = target_view()


func _unhandled_input(event: InputEvent) -> void:
	if full_view and event.is_action_pressed("toggle_map"):
		visible = not visible
		# Die Ecken-Minimap waere unter der Vollkarte nur doppelt.
		for m in get_parent().get_children():
			if m is MiniMap and m != self:
				m.visible = not visible


func _ready_to_draw() -> bool:
	return _wm != null and _wm.map != null and is_instance_valid(_guardian)


func _process(delta: float) -> void:
	if not visible or not _ready_to_draw():
		return
	var target := target_view()
	var k := minf(1.0, VIEW_FOLLOW * delta)
	_view = Rect2(_view.position.lerp(target.position, k), _view.size.lerp(target.size, k))
	queue_redraw()


# --- Abfragen (auch fuer Tests) ------------------------------------------------
func current_sector() -> StringName:
	return _wm.current_sector(_guardian)


## Aktueller Sektor + alle von hier erreichbaren Nachbarn (Einbahn-Ankuenfte zaehlen nicht,
## sonst zoomt die Minimap am HQ bis zum Zentrum heraus).
func focus_sectors() -> Array[StringName]:
	var cur := current_sector()
	var out: Array[StringName] = [cur]
	out.append_array(_wm.map.neighbors(cur))
	return out


## Kartenausschnitt (Karten-Einheiten): alles bzw. Fokus-Sektoren, plus Rand.
func target_view() -> Rect2:
	var ids: Array = focus_sectors() if not full_view else _wm.map.sectors.map(
			func(s: WorldSectorData) -> StringName: return s.id)
	var r := Rect2(_pos(ids[0]), Vector2.ZERO)
	for id: StringName in ids:
		r = r.expand(_pos(id))
	return r.grow(VIEW_MARGIN)


## Spieler auf der Karte: im Uebergang anteilig zwischen beiden Sektoren.
func player_map_position() -> Vector2:
	for g in _wm.gates():
		var p := g.progress_of(_guardian.global_position)
		if p >= 0.0:
			return _pos(g.sector_a).lerp(_pos(g.sector_b), p / g.length)
	return _pos(current_sector())


func _pos(id: StringName) -> Vector2:
	var s := _wm.map.sector(id)
	return s.map_position if s != null else Vector2.ZERO


# --- Zeichnen ----------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if not _ready_to_draw() or _view.size == Vector2.ZERO:
		return
	var focus := focus_sectors()
	for l in _wm.map.links:
		if not l.monster_only:
			_draw_link(l, focus)
	for s in _wm.map.sectors:
		_draw_sector(s, focus)
	draw_circle(_to_screen(player_map_position()), PLAYER_RADIUS, COL_PLAYER)


## Karten-Einheiten -> Pixel: Ausschnitt seitentreu einpassen und zentrieren.
func _to_screen(p: Vector2) -> Vector2:
	var inner := size - Vector2.ONE * PADDING * 2.0
	var scale_px := minf(inner.x / _view.size.x, inner.y / _view.size.y)
	var offset := (size - _view.size * scale_px) * 0.5
	return offset + (p - _view.position) * scale_px


func _alpha(id: StringName, focus: Array[StringName]) -> float:
	return 1.0 if full_view or focus.has(id) else DIM


func _draw_link(l: SectorLink, focus: Array[StringName]) -> void:
	var a := _to_screen(_pos(l.from_sector))
	var b := _to_screen(_pos(l.to_sector))
	var col := COL_BLOCKED if _wm.block_of(l) != SectorLink.GateBlockType.NONE else COL_LINK
	col.a *= minf(_alpha(l.from_sector, focus), _alpha(l.to_sector, focus))
	draw_line(a, b, col, 2.0, true)
	if l.one_way:
		var dir := (b - a).normalized()
		var tip := (a + b) * 0.5 + dir * ARROW_SIZE * 0.5
		var side := dir.orthogonal() * ARROW_SIZE * 0.5
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * ARROW_SIZE + side,
				tip - dir * ARROW_SIZE - side]), col)


func _draw_sector(s: WorldSectorData, focus: Array[StringName]) -> void:
	var p := _to_screen(s.map_position)
	var col: Color = REGION_COLORS.get(s.region, COL_LINK)
	col.a = _alpha(s.id, focus)
	var r := NODE_RADIUS * (0.7 if s.dead_end else 1.0)
	draw_circle(p, r, col)
	if s.id == focus[0]:
		draw_arc(p, r + 3.0, 0.0, TAU, 24, COL_CURRENT, 2.0, true)
	if s.camp != WorldSectorData.CampKind.NONE:
		var box := Rect2(p + Vector2(r, -r - CAMP_SIZE), Vector2.ONE * CAMP_SIZE)
		var built := _wm.is_camp_built(s.id)
		draw_rect(box, col, built, -1.0 if built else 1.5)
	if full_view or focus.has(s.id):
		var font := ThemeDB.fallback_font
		var text_col := COL_TEXT
		text_col.a *= col.a
		draw_string(font, p + Vector2(-60, r + FONT_SIZE + 2), s.display_name,
				HORIZONTAL_ALIGNMENT_CENTER, 120, FONT_SIZE, text_col)
