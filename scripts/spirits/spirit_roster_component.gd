class_name SpiritRosterComponent
extends Node
## 3er-Kampf-Roster eines Guardians (Komponente, als Kind an den Spieler haengen).
##
## Aus den 9 Basis-Spirits werden genau 3 ausgewaehlt (`spirits`). Im Kampf gibt es
## zwei unabhaengige Zustaende:
##   - active_field_spirit_index (0..2): Spirit, der draussen in der Arena kaempft.
##   - weapon_socket_spirit_index (0..2): Spirit, der in die Waffe gesockelt ist
##     (Klingen-Glow/-Trail-Farbe + Elementar-Tag beim Momentum-Slash).
##     SOCKET_NONE (-1) = leere Waffe / reiner Stahl (kein Saeulen-Faktor, dafuer
##     Momentum-Bonus bei High-Speed, siehe KnifeCombat).
##   Der dritte (bzw. jeder nicht benutzte) Spirit ist die Reserve.
##
## Steuerung (InputActions, registriert ueber GuardianInput):
##   field_spirit_1/2/3 (Tasten 1/2/3) ......... Spirit aufs Feld schicken
##   cycle_weapon_spirit_prev / _next (Q / E) .. Slot 1 -> 2 -> 3 -> leer -> Slot 1
##
## Coop-ready: keine Singletons/Autoloads. Jeder Spieler hat seine eigene Komponente,
## die Verbraucher (Messer, HUD, Avatar) verbinden sich ueber die Signale.
## `input_enabled = false` schaltet die Tastatur-Steuerung ab (z. B. fuer einen
## zweiten Spieler mit eigenem Eingabe-Routing, der set_field_spirit() direkt aufruft).

signal field_spirit_changed(spirit_data: SpiritData)
signal weapon_spirit_changed(spirit_data: SpiritData)
signal roster_changed(spirits: Array[SpiritData])

const ROSTER_SIZE := 3
## Saeulen-Vorteil: Angreifer-Saeule -> Saeule, die sie schlaegt.
const PILLAR_BEATS := {
	SpiritData.Pillar.NATURE: SpiritData.Pillar.ORDER,
	SpiritData.Pillar.ORDER: SpiritData.Pillar.CYCLE,
	SpiritData.Pillar.CYCLE: SpiritData.Pillar.NATURE,
}
const ADVANTAGE_MULT := 1.5
const DISADVANTAGE_MULT := 0.75
const NEUTRAL_MULT := 1.0
## Waffen-Sockel leer (reiner Stahl).
const SOCKET_NONE := -1
const FIELD_ACTIONS: Array[StringName] = [&"field_spirit_1", &"field_spirit_2", &"field_spirit_3"]

## Die 3 gewaehlten Spirits (Reihenfolge = Slot 1..3 / Tasten 1..3).
@export var spirits: Array[SpiritData] = []
@export var input_enabled := true

var active_field_spirit_index := 0
var weapon_socket_spirit_index := 0


func _ready() -> void:
	GuardianInput.ensure_actions()
	if spirits.size() != ROSTER_SIZE:
		push_warning("SpiritRoster: erwartet %d Spirits, hat %d" % [ROSTER_SIZE, spirits.size()])


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not event.is_pressed() or event.is_echo():
		return
	for i in FIELD_ACTIONS.size():
		if event.is_action_pressed(FIELD_ACTIONS[i]):
			set_field_spirit(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"cycle_weapon_spirit_next"):
		cycle_weapon_spirit(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"cycle_weapon_spirit_prev"):
		cycle_weapon_spirit(-1)
		get_viewport().set_input_as_handled()


# --- Abfragen -------------------------------------------------------------
func get_spirit(index: int) -> SpiritData:
	return spirits[index] if index >= 0 and index < spirits.size() else null


func field_spirit() -> SpiritData:
	return get_spirit(active_field_spirit_index)


func weapon_spirit() -> SpiritData:
	return get_spirit(weapon_socket_spirit_index)


## Index-Liste der Spirits, die weder draussen noch in der Waffe sind.
func reserve_indices() -> Array[int]:
	var out: Array[int] = []
	for i in spirits.size():
		if i != active_field_spirit_index and i != weapon_socket_spirit_index:
			out.append(i)
	return out


# --- Aenderungen ----------------------------------------------------------
## Neues 3er-Roster setzen (z. B. aus einem Auswahl-Menue). Indizes werden zurueckgesetzt.
func set_roster(new_spirits: Array[SpiritData]) -> bool:
	if not is_valid_roster(new_spirits):
		return false
	spirits = new_spirits.duplicate()
	active_field_spirit_index = 0
	weapon_socket_spirit_index = 0
	roster_changed.emit(spirits)
	field_spirit_changed.emit(field_spirit())
	weapon_spirit_changed.emit(weapon_spirit())
	return true


## Genau ROSTER_SIZE verschiedene Spirits – sonst frei kombinierbar (alle Saeulen/Elemente).
static func is_valid_roster(list: Array[SpiritData]) -> bool:
	if list.size() != ROSTER_SIZE or list.has(null):
		return false
	for s in list:
		if list.count(s) > 1:
			return false
	return true


## Spirit `index` aufs Feld schicken. false = ungueltig oder schon draussen.
func set_field_spirit(index: int) -> bool:
	if get_spirit(index) == null or index == active_field_spirit_index:
		return false
	active_field_spirit_index = index
	field_spirit_changed.emit(field_spirit())
	return true


## index = Slot 0..2 oder SOCKET_NONE (Spirit aus der Waffe entladen).
func set_weapon_spirit(index: int) -> bool:
	if (index != SOCKET_NONE and get_spirit(index) == null) or index == weapon_socket_spirit_index:
		return false
	weapon_socket_spirit_index = index
	weapon_spirit_changed.emit(weapon_spirit())
	return true


## Gesockeltes Element zyklisch wechseln (+1 = E, -1 = Q). Der Zyklus hat einen Platz mehr
## als das Roster: Position spirits.size() = leere Waffe.
func cycle_weapon_spirit(step: int) -> bool:
	if spirits.is_empty():
		return false
	var n := spirits.size()
	var cur := n if weapon_socket_spirit_index == SOCKET_NONE else weapon_socket_spirit_index
	var next := posmod(cur + step, n + 1)
	return set_weapon_spirit(SOCKET_NONE if next == n else next)


# --- Schere-Stein-Papier --------------------------------------------------
## Schadens-Multiplikator Saeule gegen Saeule: NATURE > ORDER > CYCLE > NATURE.
## Vorteil 1.5x, Nachteil 0.75x, gleiche Saeule 1.0x.
static func pillar_multiplier(attacker: SpiritData.Pillar, defender: SpiritData.Pillar) -> float:
	if PILLAR_BEATS.get(attacker, -1) == defender:
		return ADVANTAGE_MULT
	if PILLAR_BEATS.get(defender, -1) == attacker:
		return DISADVANTAGE_MULT
	return NEUTRAL_MULT


## Ziel traegt noch Ruestung (is_armored()): Elementar-Faktoren prallen ab.
static func is_armored(target: Object) -> bool:
	return target != null and target.has_method("is_armored") and target.is_armored()


## Saeulen-Faktor eines Angreifers gegen `target` – nur ohne Ruestung und wenn das Ziel
## eine Saeule hat (get_spirit_pillar), sonst 1.0. Gilt fuer Waffe und Feld-Spirit.
static func pillar_factor_against(attacker: SpiritData.Pillar, target: Object) -> float:
	if target == null or is_armored(target) or not target.has_method("get_spirit_pillar"):
		return NEUTRAL_MULT
	return pillar_multiplier(attacker, target.get_spirit_pillar())


## Multiplikator des gesockelten Waffen-Spirits gegen ein Ziel mit Saeule `defender`.
func weapon_multiplier_against(defender: SpiritData.Pillar) -> float:
	var s := weapon_spirit()
	return s.weapon_damage_multiplier * pillar_multiplier(s.pillar, defender) if s else 1.0
