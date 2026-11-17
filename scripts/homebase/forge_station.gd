class_name ForgeStation
extends InteractionStation
## Schmied: Upgrades in drei Kategorien (Grappling Hook, Waffe, Ruestung/Set-Effekte).
## Kosten als Material-Dictionary (heute Gold, spaeter Monster-Materialien).

const TABS := {"hook": "Grappling Hook", "weapon": "Waffe", "armor": "Ruestung / Set"}


func fill(w: StationWindow) -> void:
	var p := progress()
	for cat: String in TABS:
		var tab := w.add_tab(TABS[cat])
		for id: String in GuardianProgress.UPGRADES:
			var u: Dictionary = GuardianProgress.UPGRADES[id]
			if u.category != cat:
				continue
			w.add_row(tab, "%s   Stufe %d   (%d Gold)" % [u.name, p.upgrade_levels.get(id, 0), u.cost.gold],
					[["Schmieden", _forge.bind(id), p.can_afford(u.cost)]])
	var g := guardian
	w.set_info("Gold %d  ·  Reichweite %.1f m  ·  Winde %.1f m/s  ·  Armor-Break x%.2f  ·  HP %d" % [
			p.gold(), g.grapple_range, g.reel_speed, g.knife.armor_break_multiplier,
			g.health.max_hp if g.health else 0])


func _forge(id: String) -> void:
	progress().buy_upgrade(id)
	window.refresh()
