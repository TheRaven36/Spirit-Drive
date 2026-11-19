class_name WorldSectorData
extends Resource
## Ein Sektor (Knoten) des Kleeblatt-Weltgeruests: Region, Whitebox-Szene, optionales Lager.
## Die Verbindungen stehen als SectorLink in WorldMapData.links (kein festes Array pro Sektor).

## Lage im Kleeblatt. HARDCORE_* gehoeren zur spaeteren Kontrast-Map (Feuer/Vulkan vs. Eis/Blizzard).
enum Region {
	HEADQUARTERS, STEM, CENTER,
	LOOP_NATURE, LOOP_SWAMP, LOOP_MOUNTAIN, LOOP_DESERT,
	HARDCORE_FIRE, HARDCORE_ICE,
}
enum CampKind { NONE, HEADQUARTERS, CENTER_CAMP, OUTPOST }
## Ausbaustufen eines Lagers. UNDISCOVERED -> (entdeckt) LOCKED oder AVAILABLE_FOR_BUILD
## -> (gebaut) TIER_1 -> (ausgebaut) UPGRADED. Schnellreise-Ziel ab TIER_1.
enum CampUnlockState { UNDISCOVERED, LOCKED, AVAILABLE_FOR_BUILD, TIER_1, UPGRADED }

@export var id: StringName
@export var display_name := ""
@export var region := Region.STEM
@export_file("*.tscn") var scene_path := ""
## Abseitige Sackgassen-Nische (Schlaf-/Rohstoff-Spot), nicht Teil des Rundlaufs.
@export var dead_end := false
## Freie Platzhalter-Metadaten fuer spaetere Systeme (z. B. "hidden_adds", "flying_grapple_minions").
@export var tags: PackedStringArray = []

@export_group("Camp")
@export var camp := CampKind.NONE
@export var camp_start_state := CampUnlockState.UNDISCOVERED
## Platzhalter: Liefer-/Haendler-Quest, die das Bauen erst freigibt (leer = nach Entdeckung baubar).
@export var camp_unlock_quest: StringName
@export var camp_build_cost := {}
@export var camp_upgrade_cost := {}
