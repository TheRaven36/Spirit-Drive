class_name SpiritData
extends Resource
## Datenblatt eines Spirits (reine Daten, keine Logik im Kampf).
##
## Die 9 Basis-Spirits liegen als .tres unter res://data/spirits/ (siehe SpiritLibrary).
## Drei Saeulen mit je drei Elementen:
##   NATURE: FIRE, WATER, EARTH
##   ORDER:  LIGHT, SHADOW, GRAVITY
##   CYCLE:  LIFE, TIME, DEATH
## Saeulen-Vorteil (Schere-Stein-Papier): NATURE > ORDER > CYCLE > NATURE,
## siehe SpiritRosterComponent.pillar_multiplier().

enum Pillar { NATURE, ORDER, CYCLE }
enum Element { FIRE, WATER, EARTH, LIGHT, SHADOW, GRAVITY, LIFE, TIME, DEATH }
enum EvolutionStage { CORE, ASPIRANT, KEEPER, TITAN, GOD }

## Element -> zugehoerige Saeule (zur Validierung der Ressourcen).
const ELEMENT_PILLAR := {
	Element.FIRE: Pillar.NATURE, Element.WATER: Pillar.NATURE, Element.EARTH: Pillar.NATURE,
	Element.LIGHT: Pillar.ORDER, Element.SHADOW: Pillar.ORDER, Element.GRAVITY: Pillar.ORDER,
	Element.LIFE: Pillar.CYCLE, Element.TIME: Pillar.CYCLE, Element.DEATH: Pillar.CYCLE,
}

@export var spirit_name := ""
@export var pillar: Pillar = Pillar.NATURE
@export var element: Element = Element.FIRE
@export var evolution_stage: EvolutionStage = EvolutionStage.CORE
## Eindeutige Signalfarbe: Greybox-Visual, Klingen-Glow/-Trail und HUD-Slot.
@export var theme_color := Color.WHITE
## Faktor auf den Messer-Schaden, solange der Spirit in der Waffe gesockelt ist.
@export var weapon_damage_multiplier := 1.0
## Elementar-Effekt beim Treffer, z. B. "burn", "slow", "stagger" ...
@export var special_effect_tag := ""


func pillar_name() -> String:
	return Pillar.keys()[pillar]


func element_name() -> String:
	return Element.keys()[element]


## true, wenn Element und Saeule zusammenpassen.
func is_consistent() -> bool:
	return ELEMENT_PILLAR.get(element, -1) == pillar
