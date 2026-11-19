class_name SectorLink
extends Resource
## Eine Verbindung im Kleeblatt-Graph zwischen zwei Sektoren (Kante des WorldMapData-Graphen).
## Standard: beidseitig begehbar. one_way = nur von from_sector nach to_sector (z. B. Drop/Abkuerzung).
## monster_only = Ausweich-/Fluchtweg fuer Bosse/Monster; der Spieler bekommt dafuer keinen Uebergang.

## Bauform des Uebergangs (bestimmt die Szene, die der WorldMapManager einsetzt).
enum TransitionType { ORGANIC_TUNNEL, ROCK_PASS, SLOPED_SHORTCUT }
## Sperre bis Story-/Monster-Fortschritt (Startzustand; Laufzeit-Zustand haelt der WorldMapManager).
enum GateBlockType { NONE, ROCK_BLOCK, BURNABLE_GROWTH, CLASH_TREE }

@export var from_sector: StringName
@export var to_sector: StringName
@export var transition := TransitionType.ORGANIC_TUNNEL
@export var block := GateBlockType.NONE
@export var one_way := false
@export var monster_only := false


func connects(a: StringName, b: StringName) -> bool:
	return (from_sector == a and to_sector == b) or (from_sector == b and to_sector == a)


func other(id: StringName) -> StringName:
	return to_sector if id == from_sector else from_sector


## Darf ein Spieler (is_monster = false) bzw. ein Monster von `from` aus diese Kante nehmen?
func allows(from: StringName, is_monster: bool) -> bool:
	if from != from_sector and from != to_sector:
		return false
	if monster_only and not is_monster:
		return false
	return not one_way or from == from_sector
