class_name SpiritAltar
extends InteractionStation
## Spirit-Altar: 3er-Roster frei aus allen 9 Spirits zusammenstellen (jede Kombination
## erlaubt, nur keine Duplikate). "Uebernehmen" setzt das Roster des Guardians.

var selection: Array[SpiritData] = []


func _on_open() -> void:
	selection.assign(guardian.spirit_roster.spirits)


func fill(w: StationWindow) -> void:
	var tab := w.add_tab("Spirits")
	for s in SpiritLibrary.load_all():
		var picked := selection.has(s)
		var can_pick := picked or selection.size() < SpiritRosterComponent.ROSTER_SIZE
		w.add_row(tab, "%s   %s" % [s.spirit_name, s.pillar_name()],
				[["Abwaehlen" if picked else "Waehlen", toggle_spirit.bind(s), can_pick]], s.theme_color)
	var names := selection.map(func(s: SpiritData) -> String: return s.spirit_name)
	w.add_row(tab, "Roster: " + " / ".join(PackedStringArray(names)),
			[["Uebernehmen", apply_selection, SpiritRosterComponent.is_valid_roster(selection)]])
	w.set_info("Waehle 3 verschiedene Spirits – jede Saeulen-Kombination ist erlaubt.")


func toggle_spirit(s: SpiritData) -> void:
	if selection.has(s):
		selection.erase(s)
	elif selection.size() < SpiritRosterComponent.ROSTER_SIZE:
		selection.append(s)
	window.refresh()


## Auswahl ins Roster des Guardians uebernehmen. false = keine 3 verschiedenen Spirits.
func apply_selection() -> bool:
	var ok := guardian.spirit_roster.set_roster(selection.duplicate())
	window.refresh()
	return ok
