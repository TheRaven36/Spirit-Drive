class_name EquipmentStash
extends InteractionStation
## Lagertruhe: Beute zwischen Rucksack und Truhe verschieben, Ausruestung (Waffe, Ruestung,
## Haken) aus Rucksack oder Truhe anlegen. Daten: GuardianProgress des Guardians.


func fill(w: StationWindow) -> void:
	var p := progress()
	var bag := w.add_tab("Rucksack")
	for id in p.backpack:
		w.add_row(bag, p.item_name(id), [["In Truhe", _move.bind(id, true), true],
				["Anlegen", _equip.bind(id), _equippable(id)]])
	var chest := w.add_tab("Truhe")
	for id in p.stash:
		w.add_row(chest, p.item_name(id), [["In Rucksack", _move.bind(id, false), true],
				["Anlegen", _equip.bind(id), _equippable(id)]])
	var gear := w.add_tab("Ausruestung")
	for slot: String in GuardianProgress.SLOTS:
		w.add_row(gear, "%s:  %s" % [slot.capitalize(), p.item_name(p.equipped[slot])])
	w.set_info("Rucksack %d  ·  Truhe %d" % [p.backpack.size(), p.stash.size()])


func _equippable(id: String) -> bool:
	return GuardianProgress.ITEMS.get(id, {}).get("slot", "") != ""


func _move(id: String, to_stash: bool) -> void:
	progress().move_item(id, to_stash)
	window.refresh()


func _equip(id: String) -> void:
	progress().equip(id)
	window.refresh()
