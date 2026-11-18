class_name DamageNumber
extends Label
## Eine Schadenszahl: haengt an einer 3D-Position (jeden Frame projiziert).
##   0.0 - 0.1 s  Overshoot-Pop (0.3 -> 1.3 -> 1.0 x Zielgroesse)
##   0.1 - 2.5 s  voll sichtbar, driftet langsam nach oben (lesbar nach dem Vorbeiflug)
##   2.5 - 3.0 s  schnelles lineares Ausfaden, danach queue_free()
## Die freie Position (kein Ueberlappen mit anderen Zahlen) waehlt der DamageNumberManager.

const POP_FROM := 0.3
const POP_OVERSHOOT := 1.3
const POP_TIME := 0.05
const SETTLE_TIME := 0.05
const FADE_START := 2.5
const LIFETIME := 3.0
const RISE := 1.0          # m nach oben ueber die Lebenszeit

var world_pos := Vector3.ZERO
var target_scale := 1.0
var _cam: Camera3D
var _age := 0.0


func setup(damage: float, pos: Vector3, s: float, col: Color, cam: Camera3D) -> void:
	text = str(roundi(damage))
	world_pos = pos
	target_scale = s
	_cam = cam
	add_theme_color_override("font_color", col)


func _ready() -> void:
	reset_size()
	pivot_offset = size * 0.5
	scale = Vector2.ONE * POP_FROM * target_scale
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * POP_OVERSHOOT * target_scale, POP_TIME)
	tw.tween_property(self, "scale", Vector2.ONE * target_scale, SETTLE_TIME)
	tw.tween_interval(FADE_START - POP_TIME - SETTLE_TIME)
	tw.tween_property(self, "modulate:a", 0.0, LIFETIME - FADE_START)  # linear
	tw.tween_callback(queue_free)
	_follow()


func _process(delta: float) -> void:
	_age += delta
	_follow()


## Aktuelle 3D-Anzeigeposition (Anker + Drift nach oben).
func display_pos() -> Vector3:
	return world_pos + Vector3.UP * RISE * minf(_age / LIFETIME, 1.0)


## Halbe Bildschirm-Groesse in Endgroesse (fuer die Ueberlappungs-Pruefung).
func half_extent() -> Vector2:
	return size * target_scale * 0.5


func _follow() -> void:
	if not is_instance_valid(_cam):
		return
	var p := display_pos()
	visible = not _cam.is_position_behind(p)
	position = _cam.unproject_position(p) - pivot_offset
