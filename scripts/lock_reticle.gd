class_name LockReticle
extends Control
## Hard-Lock-Rahmen: vier Eckklammern exakt um den Lock-Punkt (Hitbox), ohne Text.
## Farbe zeigt den Reichweiten-Status: aktiv/farbig = in Grapple-Reichweite,
## grau = ausserhalb (Lock bleibt bestehen, Seil erst wieder in Reichweite).

const COL_IN_RANGE := Color(1.0, 0.55, 0.2, 0.95)
const COL_OUT_OF_RANGE := Color(0.62, 0.62, 0.62, 0.55)
const MIN_RADIUS := 18.0
const MAX_RADIUS := 150.0
const LINE_WIDTH := 2.5

## Bildschirm-Mitte des Rahmens (Viewport-Koordinaten).
var center := Vector2.ZERO
## Halbe Kantenlaenge des Rahmens in Pixeln.
var radius := 30.0
var in_range := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func current_color() -> Color:
	return COL_IN_RANGE if in_range else COL_OUT_OF_RANGE


func show_at(screen_center: Vector2, screen_radius: float, target_in_range: bool) -> void:
	center = screen_center
	radius = clampf(screen_radius, MIN_RADIUS, MAX_RADIUS)
	in_range = target_in_range
	visible = true
	queue_redraw()


func _draw() -> void:
	var col := current_color()
	var r := radius
	var arm := maxf(r * 0.38, 7.0)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := center + Vector2(sx * r, sy * r)
			draw_line(corner, corner - Vector2(sx * arm, 0.0), col, LINE_WIDTH, true)
			draw_line(corner, corner - Vector2(0.0, sy * arm), col, LINE_WIDTH, true)
	# Mittelpunkt = exakter Lock-Punkt
	draw_circle(center, 2.0, col)
