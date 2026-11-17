class_name HookIndicator
extends Control
## Kleines Haken-Symbol fuer einen Hueft-Werfer (ohne Text).
##   bereit ........ helles Symbol, voll gefuellt
##   abgefeuert .... ausgegraut, leer (Seil haengt)
##   Cooldown ...... ausgegraut, fuellt sich von unten wieder auf
##   Combat-Seil ... Akzent-Rand (orange)
## `ratio` (0..1) und `active`/`combat` setzt das MinimalHUD aus dem GrappleHook.

const COL_BG := Color(0.0, 0.0, 0.0, 0.45)
const COL_FILL := Color(1.0, 1.0, 1.0, 0.85)
const COL_GLYPH_READY := Color(0.08, 0.08, 0.1, 1.0)
const COL_GLYPH_OFF := Color(1.0, 1.0, 1.0, 0.35)
const COL_COMBAT := Color(1.0, 0.55, 0.2, 1.0)

## Spiegelt das Symbol (rechter Werfer zeigt nach rechts).
@export var mirrored := false

var ratio := 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if v >= 1.0 and ratio < 1.0:
			_flash = 1.0  # kurzer Aufblitz-Puls, sobald wieder bereit
		if v != ratio:
			ratio = v
			queue_redraw()
var active := false:
	set(v):
		if v != active:
			active = v
			queue_redraw()
var combat := false:
	set(v):
		if v != combat:
			combat = v
			queue_redraw()

var _flash := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(20, 20)
	mouse_filter = MOUSE_FILTER_IGNORE


func is_ready() -> bool:
	return ratio >= 1.0 and not active


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, COL_BG)
	if ratio > 0.0:
		var h := size.y * ratio
		var fill := COL_FILL if ratio >= 1.0 else Color(COL_FILL, 0.35)
		draw_rect(Rect2(0.0, size.y - h, size.x, h), fill)
	if _flash > 0.0:
		draw_rect(r.grow(2.0 * _flash), Color(1, 1, 1, 0.6 * _flash), false, 2.0)
	if combat and active:
		draw_rect(r, COL_COMBAT, false, 2.0)
	_draw_hook(COL_GLYPH_READY if is_ready() else COL_GLYPH_OFF)


## Stilisierter Haken: Schaft + Bogen.
func _draw_hook(col: Color) -> void:
	var s := size
	var sx := -1.0 if mirrored else 1.0
	var cx := s.x * 0.5
	var shaft_x := cx + sx * s.x * 0.12
	draw_line(Vector2(shaft_x, s.y * 0.18), Vector2(shaft_x, s.y * 0.62), col, 2.0, true)
	var c := Vector2(cx - sx * s.x * 0.06, s.y * 0.62)
	var rad := s.x * 0.18
	var a0 := 0.0 if not mirrored else PI
	draw_arc(c, rad, a0, a0 + PI * sx, 10, col, 2.0, true)
