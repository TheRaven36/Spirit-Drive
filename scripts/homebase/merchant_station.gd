class_name MerchantStation
extends InteractionStation
## Haendler: Verbrauchsgueter fuer Guardian und Spirit gegen Gold.

const TABS := {"guardian": "Guardian", "spirit": "Spirit"}


func fill(w: StationWindow) -> void:
	var p := progress()
	for tab_id: String in TABS:
		var tab := w.add_tab(TABS[tab_id])
		for id: String in GuardianProgress.GOODS:
			var good: Dictionary = GuardianProgress.GOODS[id]
			if good.tab != tab_id:
				continue
			w.add_row(tab, "%s   x%d   (%d Gold)" % [good.name, p.consumables.get(id, 0), good.price],
					[["Kaufen", _buy.bind(id), p.can_afford({"gold": good.price})]])
	w.set_info("Gold %d" % p.gold())


func _buy(id: String) -> void:
	progress().buy_good(id)
	window.refresh()
