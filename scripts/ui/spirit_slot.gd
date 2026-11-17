class_name SpiritSlot
extends Control
## Quadratischer Roster-Slot in der theme_color des Spirits (ohne Text).
##   Feld-Spirit (draussen) ... deutlicher aeusserer Rahmen + Glow
##   Waffen-Spirit ............ heller innerer Kern + kleines Klingen-Symbol
##   Reserve .................. gedimmt

const COL_BG := Color(0.0, 0.0, 0.0, 0.5)
const COL_EMPTY := Color(1, 1, 1, 0.15)
const COL_BLADE := Color(1, 1, 1, 0.95)

var spirit: SpiritData = null:
	set(v):
		spirit = v
		queue_redraw()
var is_field := false:
	set(v):
		if v and not is_field:
			_pulse = 1.0
		is_field = v
		queue_redraw()
var is_weapon := false:
	set(v):
		if v and not is_weapon:
			_pulse = maxf(_pulse, 0.6)
		is_weapon = v
		queue_redraw()

var _pulse := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 3.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if spirit == null:
		draw_rect(r, COL_EMPTY, false, 1.0)
		return
	var col := spirit.theme_color
	var reserve := not is_field and not is_weapon
	draw_rect(r, COL_BG)
	draw_rect(r.grow(-2.0), Color(col, 0.35 if reserve else 0.75))

	if is_field:
		# Glow: mehrere nach aussen auslaufende Rahmen
		for i in 4:
			var g := 2.0 + i * 2.0 + _pulse * 4.0
			draw_rect(r.grow(g), Color(col.lightened(0.3), 0.45 / (i + 1)), false, 2.0)
		draw_rect(r.grow(1.0), col.lightened(0.45), false, 3.0)

	if is_weapon:
		var core := r.size * 0.36
		var core_r := Rect2((r.size - core) * 0.5, core)
		draw_rect(core_r.grow(1.5), Color(1, 1, 1, 0.9))
		draw_rect(core_r, col.lightened(0.2))
		_draw_blade(Vector2(size.x - 2.0, 2.0), size.x * 0.32)


## Kleine Klinge oben rechts (Spitze nach oben rechts).
func _draw_blade(tip: Vector2, length: float) -> void:
	var d := Vector2(-1, 1).normalized()
	var n := Vector2(d.y, -d.x)
	var base := tip + d * length
	var w := length * 0.16
	draw_colored_polygon(PackedVector2Array([tip, base + n * w, base - n * w]), COL_BLADE)
	draw_line(base - n * w * 1.8, base + n * w * 1.8, COL_BLADE, 2.0)
