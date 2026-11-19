class_name WorldMapData
extends Resource
## Datengetriebener Welt-Graph (Kleeblatt): Sektoren als Knoten, SectorLinks als Kanten.
## Keine feste Groesse: Sektoren/Links im Inspector ergaenzen oder entfernen genuegt.
## Reine Abfragen ohne Laufzeit-Zustand (Sperren/Lager haelt der WorldMapManager).

@export var map_id: StringName
@export var display_name := ""
## Platzhalter-Maps (z. B. spaetere Hardcore-Kontrast-Map) bleiben deaktiviert, bis sie ausgebaut sind.
@export var enabled := true
@export var start_sector: StringName
@export var sectors: Array[WorldSectorData] = []
@export var links: Array[SectorLink] = []


func sector(id: StringName) -> WorldSectorData:
	for s in sectors:
		if s.id == id:
			return s
	return null


func in_region(region: WorldSectorData.Region) -> Array[WorldSectorData]:
	var out: Array[WorldSectorData] = []
	for s in sectors:
		if s.region == region:
			out.append(s)
	return out


func links_of(id: StringName) -> Array[SectorLink]:
	var out: Array[SectorLink] = []
	for l in links:
		if l.from_sector == id or l.to_sector == id:
			out.append(l)
	return out


func link_between(a: StringName, b: StringName) -> SectorLink:
	for l in links:
		if l.connects(a, b):
			return l
	return null


## Nachbarn, die von id aus betretbar sind (Einbahnstrassen + monster_only beachtet).
func neighbors(id: StringName, is_monster := false) -> Array[StringName]:
	var out: Array[StringName] = []
	for l in links_of(id):
		if l.allows(id, is_monster):
			out.append(l.other(id))
	return out


## Kuerzester Weg (Breitensuche) als Sektor-Liste inkl. Start/Ziel; leer = unerreichbar.
func find_path(from: StringName, to: StringName, is_monster := false) -> Array[StringName]:
	var came := {from: from}
	var queue: Array[StringName] = [from]
	while not queue.is_empty():
		var cur: StringName = queue.pop_front()
		if cur == to:
			return _unwind(came, to)
		for n in neighbors(cur, is_monster):
			if not came.has(n):
				came[n] = cur
				queue.append(n)
	return []


func _unwind(came: Dictionary, to: StringName) -> Array[StringName]:
	var path: Array[StringName] = [to]
	while came[path[0]] != path[0]:
		path.push_front(came[path[0]])
	return path
