class_name SpiritLibrary
extends RefCounted
## Zugriff auf die 9 Basis-Spirits (res://data/spirits/*.tres).
## Feste Pfadliste statt Ordner-Scan -> funktioniert auch im exportierten Build.

const DIR := "res://data/spirits/"
const PATHS := {
	SpiritData.Element.FIRE: DIR + "fire.tres",
	SpiritData.Element.WATER: DIR + "water.tres",
	SpiritData.Element.EARTH: DIR + "earth.tres",
	SpiritData.Element.LIGHT: DIR + "light.tres",
	SpiritData.Element.SHADOW: DIR + "shadow.tres",
	SpiritData.Element.GRAVITY: DIR + "gravity.tres",
	SpiritData.Element.LIFE: DIR + "life.tres",
	SpiritData.Element.TIME: DIR + "time.tres",
	SpiritData.Element.DEATH: DIR + "death.tres",
}


static func get_spirit(element: SpiritData.Element) -> SpiritData:
	return load(PATHS[element]) as SpiritData


## Alle 9 Spirits in Element-Reihenfolge.
static func load_all() -> Array[SpiritData]:
	var out: Array[SpiritData] = []
	for e: int in SpiritData.Element.values():
		out.append(get_spirit(e))
	return out
