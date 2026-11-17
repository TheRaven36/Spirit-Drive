class_name HealthComponent
extends Node
## Lebenspunkte als eigenstaendige Komponente (Guardian, spaeter Spirits/Mobs).
## Pro Besitzer eine Instanz -> Coop-ready, das HUD bindet sich per Signal.

signal health_changed(hp: float, max_hp: float)
signal damaged(amount: float)
signal died

@export var max_hp := 100.0

var hp := 0.0


func _ready() -> void:
	hp = max_hp


func ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func is_dead() -> bool:
	return hp <= 0.0


func take_damage(amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	hp = maxf(hp - amount, 0.0)
	damaged.emit(amount)
	health_changed.emit(hp, max_hp)
	if is_dead():
		died.emit()


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)


func reset() -> void:
	hp = max_hp
	health_changed.emit(hp, max_hp)
