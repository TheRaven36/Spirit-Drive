class_name GuardianProgress
extends Node
## Besitz und Fortschritt EINES Guardians (Komponente, Coop-ready): Materialien (Gold, spaeter
## Monster-Materialien), Rucksack, Lagertruhe, Ausruestung, Verbrauchsgueter, Schmiede-Upgrades.
## Die Homebase-Stationen lesen/aendern nur diese Daten; Upgrades wirken sofort auf den Guardian.

signal changed

## Gegenstaende: id -> {name, slot}. slot "" = Beute/Material ohne Ausruestungs-Platz.
const ITEMS := {
	"jagdmesser": {"name": "Jagdmesser", "slot": "weapon"},
	"schwere_klinge": {"name": "Schwere Klinge", "slot": "weapon"},
	"leder_set": {"name": "Leder-Set", "slot": "armor"},
	"titan_set": {"name": "Titan-Set", "slot": "armor"},
	"standard_haken": {"name": "Standard-Haken", "slot": "hook"},
	"leicht_haken": {"name": "Leicht-Haken", "slot": "hook"},
	"riesen_splitter": {"name": "Riesen-Splitter (Beute)", "slot": ""},
}
const SLOTS := ["weapon", "armor", "hook"]

## Schmiede: id -> {category, name, cost {material: menge}}. Wirkung in _apply_upgrade().
const UPGRADES := {
	"hook_range": {"category": "hook", "name": "Seil-Reichweite +5 %", "cost": {"gold": 100}},
	"hook_speed": {"category": "hook", "name": "Winden-Tempo +5 %", "cost": {"gold": 100}},
	"armor_break": {"category": "weapon", "name": "Armor-Break +10 %", "cost": {"gold": 150}},
	"vitality": {"category": "armor", "name": "Lebenspunkte +10 % (Set)", "cost": {"gold": 150}},
}
const HOOK_UPGRADE := 1.05
const ARMOR_BREAK_UPGRADE := 1.1
const VITALITY_UPGRADE := 1.1

## Haendler: id -> {tab, name, price}.
const GOODS := {
	"heal_potion": {"tab": "guardian", "name": "Heiltrank", "price": 50},
	"gas_booster": {"tab": "guardian", "name": "Gas-Kartusche (Boost)", "price": 80},
	"elemental_gel": {"tab": "spirit", "name": "Elementar-Gel", "price": 60},
	"spirit_injection": {"tab": "spirit", "name": "Spirit-Injektion", "price": 120},
}

@export var start_gold := 500

var materials := {}
var backpack: Array[String] = ["schwere_klinge", "riesen_splitter"]
var stash: Array[String] = ["titan_set", "leicht_haken"]
var equipped := {"weapon": "jagdmesser", "armor": "leder_set", "hook": "standard_haken"}
var consumables := {}
var upgrade_levels := {}

@onready var _guardian := get_parent() as GuardianController


func _ready() -> void:
	materials["gold"] = start_gold


func gold() -> int:
	return materials.get("gold", 0)


func item_name(id: String) -> String:
	return ITEMS[id].name if ITEMS.has(id) else id


# --- Lagertruhe ------------------------------------------------------------
## Gegenstand zwischen Rucksack und Truhe verschieben (Beute ablegen / holen).
func move_item(id: String, to_stash: bool) -> bool:
	var from := backpack if to_stash else stash
	var to := stash if to_stash else backpack
	if not from.has(id):
		return false
	from.erase(id)
	to.append(id)
	changed.emit()
	return true


## Ausruesten aus Rucksack oder Truhe; das bisherige Teil landet in derselben Liste.
func equip(id: String) -> bool:
	var slot: String = ITEMS.get(id, {}).get("slot", "")
	var source := backpack if backpack.has(id) else stash
	if slot == "" or not source.has(id):
		return false
	source.erase(id)
	source.append(equipped[slot])
	equipped[slot] = id
	changed.emit()
	return true


# --- Schmiede / Haendler ---------------------------------------------------
func can_afford(cost: Dictionary) -> bool:
	for m: String in cost:
		if materials.get(m, 0) < cost[m]:
			return false
	return true


## Kosten bezahlen, falls bezahlbar (z. B. Lager-Bau ueber den WorldMapManager).
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	_pay(cost)
	changed.emit()
	return true


func _pay(cost: Dictionary) -> void:
	for m: String in cost:
		materials[m] -= cost[m]


func buy_upgrade(id: String) -> bool:
	var cost: Dictionary = UPGRADES[id].cost
	if not can_afford(cost):
		return false
	_pay(cost)
	upgrade_levels[id] = upgrade_levels.get(id, 0) + 1
	_apply_upgrade(id)
	changed.emit()
	return true


func _apply_upgrade(id: String) -> void:
	if _guardian == null:
		return
	match id:
		"hook_range":
			_guardian.grapple_range *= HOOK_UPGRADE
		"hook_speed":
			_guardian.reel_speed *= HOOK_UPGRADE
		"armor_break":
			_guardian.knife.armor_break_multiplier *= ARMOR_BREAK_UPGRADE
		"vitality":
			var h := _guardian.health
			if h:
				var extra := h.max_hp * (VITALITY_UPGRADE - 1.0)
				h.max_hp += extra
				h.heal(extra)  # neue Lebenspunkte gleich gefuellt


func buy_good(id: String) -> bool:
	var cost := {"gold": GOODS[id].price}
	if not can_afford(cost):
		return false
	_pay(cost)
	consumables[id] = consumables.get(id, 0) + 1
	changed.emit()
	return true
