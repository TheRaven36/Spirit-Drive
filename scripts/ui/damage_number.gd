class_name DamageNumber
extends Label
## Eine Schadenszahl: haengt an einer 3D-Position (jeden Frame projiziert), poppt mit
## Overshoot auf, driftet leicht nach oben (+ kleiner Zufalls-Versatz gegen Ueberlappen)
## und blendet nach LIFETIME aus.

const POP_FROM := 0.3
const POP_OVERSHOOT := 1.3
const POP_TIME := 0.08
const SETTLE_TIME := 0.1
const LIFETIME := 0.8
const RISE := 1.5          # m nach oben ueber die Lebenszeit
const JITTER := 0.5        # m horizontaler Zufalls-Versatz

var world_pos := Vector3.ZERO
var target_scale := 1.0
var _cam: Camera3D
var _offset := Vector3.ZERO
var _age := 0.0


func setup(damage: float, pos: Vector3, s: float, col: Color, cam: Camera3D) -> void:
	text = str(roundi(damage))
	world_pos = pos
	target_scale = s
	_cam = cam
	add_theme_color_override("font_color", col)
	_offset = Vector3(randf_range(-JITTER, JITTER), 0.0, randf_range(-JITTER, JITTER))


func _ready() -> void:
	reset_size()
	pivot_offset = size * 0.5
	scale = Vector2.ONE * POP_FROM * target_scale
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * POP_OVERSHOOT * target_scale, POP_TIME)
	tw.tween_property(self, "scale", Vector2.ONE * target_scale, SETTLE_TIME)
	tw.tween_property(self, "modulate:a", 0.0, LIFETIME - POP_TIME - SETTLE_TIME) \
			.set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	_follow()


func _process(delta: float) -> void:
	_age += delta
	_follow()


func _follow() -> void:
	if not is_instance_valid(_cam):
		return
	var p := world_pos + _offset + Vector3.UP * RISE * minf(_age / LIFETIME, 1.0)
	visible = not _cam.is_position_behind(p)
	position = _cam.unproject_position(p) - pivot_offset
