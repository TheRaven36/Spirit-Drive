class_name HomebaseOutpost
extends Node3D
## Homebase-Vorposten (26 x 26 x 10 m, Tor auf -Z): wiederverwendbares Camp-Prefab.
## SafeZone (Gruppe "safe_zone"): Feld-Spirits bleiben hier in FOLLOW_PROTECT.
## Vier Stationen: Spirit-Altar (Mitte), Lagertruhe, Schmied, Haendler – alle InteractionStation.


func stations() -> Array[InteractionStation]:
	var out: Array[InteractionStation] = []
	for c in get_children():
		if c is InteractionStation:
			out.append(c)
	return out
