# Patchnotes – Spirit Drive

Neueste Einträge immer oben.

## Unreleased

### 2026-11-17 – Phase 2D: 5-s-Damage-Numbers, leere Waffe, Säulen-Nachteil, Höhlen-Arena
**Damage Numbers (5,0 s)**
- 0–0,1 s Overshoot-Pop (0,3 → 1,3 → 1,0 × Zielgröße), bis 3,5 s voll sichtbar mit langsamer Drift nach oben,
  3,5–5,0 s lineares Ausfaden, danach entfernt.

**Leere Waffe / Reiner Stahl**
- Q/E-Zyklus hat einen 4. Zustand: Slot 1 → 2 → 3 → leer → Slot 1 (`weapon_socket_spirit_index = -1`,
  `SpiritRosterComponent.SOCKET_NONE`). HUD zeigt dann keinen Waffen-Kern, Klinge + Trail silber.
- Leere Waffe ignoriert Säulen (immer 1,0×) und gibt +15 % (`steel_momentum_bonus`) auf High-Speed-Treffer
  (Schlag-Tempo ≥ `steel_bonus_min_speed` 20 m/s). Treffer-Info: `steel_bonus`.

**Säulen-Multiplikator**
- Jetzt mit Nachteil: Vorteil 1,5×, **Nachteil 0,75×** (vorher 1,0×), gleiche Säule 1,0× – für gesockelte Waffe
  und Feld-Spirit. Die Riesen haben jetzt Säulen, der Faktor greift also im Spiel.

**Geschlossene Greybox-Höhle**
- Decke auf 3 × höchster Turm (`max_pillar_height` 45,5 m → Decke 136,4 m), Wände rundum am Bodenrand (±150 m),
  alles mit Collision. Wände/Decke werfen keine Schatten (sonst läge die Höhle im Sonnen-Schatten).
- 6 Stalagmiten, 8 Stalaktiten (25–60 m, Decken-Anker), 3 Mega-Säulen Boden → Decke. Zylinder als eigenes
  MultiMesh (+2 Draw Calls gesamt), Collision im gemeinsamen StaticBody3D.
- Drei Riesen: Standard 1,0× NATURE (bisherige Position), Großer Riese 1,4× ORDER, Titan 2,0× CYCLE (27,6 m,
  6000 HP). `TrainingGiant.size_scale` skaliert Teile, Shapes und Lock-Punkte direkt; Gesicht zur Mitte.

**Tests**
- Spirit-System: NONE im Zyklus (E/Q, Signal, HUD, Trail), Stahl-Bonus (1,15× ab 20 m/s, Säule egal, Rohschaden
  Stahl = Feuer × 1,15), Nachteil 0,75×, Damage-Number-Lebensdauer (α = 1 bis 3,5 s, 0,5 bei 4,25 s, weg nach 5 s).
- Smoke: Höhle (Decke per Raycast auf 3 × Turmhöhe, 4 Wände, Mega-Säulen, Stalaktit/Stalagmit, 3 Riesen inkl.
  Titan-Hitbox/-Lock-Punkte); Mausrad-Test zählt nur noch die Punkte des gewählten Riesen.

### 2026-11-17 – Phase 2C: Spirit-Leine, Dual-Unlock, Damage-Numbers, Anflug-Schub
**Spirit-Leine (kein Gummiband mehr)**
- Teleport zum Guardian entfernt. Nur noch Notfall: > 150 m Abstand (`emergency_teleport_distance`) oder
  unter die Map gefallen.
- Fokus-Ziel gilt nur, solange der Lock in Grapple-Reichweite ist (Rahmen farbig). Rahmen grau → Spirit bricht
  ab und läuft physisch (Sprint 32 m/s, an Wänden entlang) zum Guardian zurück; wieder in Reichweite → greift an.

**Hard-Lock lösen: Doppelklick ODER 0,5 s halten**
- Neu `lock_double_click` (0,3 s): zweiter Klick auf eine bestehende Auswahl löst sie. Auswählen + sofortiger
  Snap-Klick löst nicht (nur Klicks auf eine schon bestehende Auswahl zählen). `lock_clear_hold` 0,45 → 0,5 s.
- Beide Wege rufen den Feld-Spirit in `FOLLOW_PROTECT` zurück.

**Floating Damage Numbers (`DamageNumberManager`, `scenes/ui/damage_number.tscn`)**
- Jeder Treffer (Messer, Piercing-Nebentreffer, Feld-Spirit) zeigt die Zahl an der Trefferstelle der Hitbox
  (`info.hit_position` bzw. neuer Parameter `hit_position` an `SpiritEntity.hit_landed`).
- `t = Schaden / 400`: Größe 1,0× → 2,0×, Farbe Weiß → Gelb → Orange → Karmesin `(1, 0.1, 0.1)`, schwarze Outline.
- Pop 0,3 → 1,3 × Zielgröße (0,08 s) → 1,0×, Drift nach oben mit kleinem Zufalls-Versatz, Ausblenden nach 0,8 s.

**Anflug-Schub (LMB auf den Hard-Lock)**
- `attack_reel_boost_accel` = 21 m/s² zusätzlich entlang der Zielrichtung, additiv zu Schwerkraft, Momentum und
  Seil (kein Velocity-Override). Kalibriert über v² = v0² + 2·a·d: 50 m mit 100 m/s → ~110 m/s.
- Gemessen (Tempo-Deckel im Test angehoben, Messung 4 m vor dem Ziel): flach 100 → 108; bergauf 100 → 108,
  Sturzflug 106 → 114 – der Schwerkraft-Anteil bleibt gleich. Im normalen Spiel deckelt `terminal_speed` (75 m/s).

**Tests**
- Smoke: Doppelklick- und Halten-Unlock, Anflug-Schub (flach/bergauf/Sturzflug, Schwerkraft-Differenz).
- Spirit-Entity: Leine (kein Teleport, max. Schritt pro Frame, Rückkehr in Reichweite), Rückruf per
  Halten und per Doppelklick, Trefferposition auf der Hitbox.
- Spirit-System: Damage-Number-Skala/-Farbe (20 / 200 / 400), Pop-Overshoot, Drift, Entfernen, Zahl am Treffer.

### 2026-11-17 – Phase 2B: Feld-Spirit als Kampf-Monster + Hard-Lock-Befehl
**SpiritEntity (`scenes/spirits/spirit_entity.tscn`, ersetzt den schwebenden Platzhalter)**
- Greybox-Kapsel (3,0 m / r 0,8 m) mit Visor vorne, gefärbt in der `theme_color` des Feld-Spirits mit leichtem
  Glow. Spawnt 4,5 m neben dem Guardian; Taste 1/2/3 tauscht Daten + Farbe an Ort und Stelle (Scale-Pop).
- Eigener Kollisions-Layer 2: Guardian-Raycasts, Seile und Messer ignorieren den Spirit.
- Ist der Guardian > 60 m entfernt (Respawn, extremer Flug), wird der Spirit neben ihn versetzt.

**KI (`FOLLOW_PROTECT`, `CHASE`, `ATTACK`)**
- `FOLLOW_PROTECT`: folgt am Boden mit 4–6 m Abstand (weit weg: Aufhol-Tempo 32 m/s). Bodyguard: Gegner näher
  als 8 m am Guardian wird angegriffen, losgelassen ab 11 m, danach zurück zum Guardian.
- `CHASE`/`ATTACK`: Hard-Lock des Guardians = Fokus-Ziel (neues Signal `GuardianController.hard_lock_changed`),
  Mausrad-Wechsel zieht den Spirit mit. In Reichweite alle 1,8 s ein Lunge (Vorpreschen + Strecken der Kapsel),
  Treffer über die `Area3D`-Hitbox: 40 × Säulen-Multiplikator, Signal `hit_landed(target, damage, effect_tag)`
  + `[SPIRIT]`-Log.
- Lock-Taste halten (0,45 s, wie bisher) löst den Lock → Spirit kehrt in `FOLLOW_PROTECT` zurück.

**Tests**
- Neu: `tests/spirit_entity_test.gd` (Spawn/Farbe, Live-Wechsel 1 → 2, Follow-Abstand, Bodyguard,
  Hard-Lock → CHASE/ATTACK + Schaden + Takt, Ziel-Wechsel, Säulen-Faktor, Halten = Rückruf).
- Smoke- und Spirit-System-Test legen die Spirit-KI still, damit sie die Dummy-Messwerte nicht verfälscht.

### 2026-11-17 – Phase 2A: 9 Spirits, 3er-Roster & Minimal-HUD
**Spirit-Daten**
- Neue Resource `SpiritData` (`scripts/spirits/spirit_data.gd`): Name, Säule (`NATURE/ORDER/CYCLE`),
  Element (9), Evolutionsstufe (`CORE` … `GOD`, Standard `CORE`), `theme_color`, `weapon_damage_multiplier`
  (1,0), `special_effect_tag`.
- 9 Basis-Spirits unter `res://data/spirits/` (Zugriff über `SpiritLibrary`):
  Nature: Feuer (rot, `burn`), Wasser (cyan, `slow`), Erde (ocker, `stagger`) ·
  Order: Licht (gold, `blind`), Schatten (dunkelviolett, `crit_dive`), Schwerkraft (magenta, `pull_down`) ·
  Cycle: Leben (smaragd, `lifesteal`), Zeit (hellblau-silber, `echo_hit`), Tod (giftgrün-grau, `armor_decay`).

**3er-Roster (`SpiritRosterComponent`, Kind „SpiritRoster“ am Guardian)**
- Genau 3 Spirits aus den 9 (`set_roster()`), Start-Roster in der Test-Arena: Feuer, Licht, Leben.
- **1 / 2 / 3** schickt den Spirit aufs Feld (`field_spirit_changed`), Greybox-Avatar (leuchtende Kugel)
  folgt dem Guardian in der Spirit-Farbe.
- **Q / E** (Controller LB / RB) wechselt den Waffen-Sockel zyklisch (`weapon_spirit_changed`): Klinge glüht
  in der Spirit-Farbe, kurzer Slash-Trail in derselben Farbe, jeder Treffer trägt `element` + `effect_tag`.
- Schere-Stein-Papier: `pillar_multiplier()` NATURE > ORDER > CYCLE > NATURE = 1,5×, sonst 1,0×. Greift im
  Messer-Schaden automatisch bei Zielen mit `get_spirit_pillar()` (Dummies/Riese haben noch keine Säule).
- Coop-ready: keine Singletons; jede Komponente hängt an ihrem Guardian, Verbraucher binden sich per Signal.

**Minimal-HUD (`scenes/ui/minimal_hud.tscn`)**
- Oben links: HP-Balken (neue `HealthComponent` am Guardian) + Haken-Indikatoren L/R: abgefeuert = ausgegraut,
  danach Füllstand von unten bis bereit (kurzer Aufblitz), Combat-Seil = oranger Rand.
- Unten links: 3 Spirit-Slots in `theme_color` – Feld-Spirit mit Glow-Rahmen, Waffen-Spirit mit hellem Kern
  + Klingen-Symbol, Reserve gedimmt. Kein Text.
- **+ / Num+** blendet ein halbtransparentes Steuerungs-Overlay ein/aus (Tasten live aus der InputMap).
- Debug-HUD entschlackt: Hilfetext und Haken-Text entfernt (→ Overlay/Indikatoren), Debug-Werte oben rechts.

**Grapple**
- Hüft-Werfer haben einen kurzen Nachlade-Cooldown (`hook_cooldown` 0,3 s) nach dem Einholen; die andere Hüfte
  bleibt frei. Neue Signale `GuardianController.hook_fired / hook_released` (bzw. `GrappleHook.fired / released`).

**Tests**
- Neu: `tests/spirit_system_test.gd` (Ressourcen, Säulen-Matrix, 1/2/3 + Q/E per echtem Tastendruck inkl.
  Signale, Waffen-Element im Treffer, HUD-Slots/Haken/HP/Overlay).
- Smoke-Test: Doppel-Tap-Gameplay-Check wartet jetzt den Werfer-Cooldown ab.

### 2026-11-16 – Gegner-Anflug: Carving statt Rail-Snap, Doppelklick = doppelte Kraft
Ersetzt den unveröffentlichten Rail-Lock (kein sofortiges Umlenken beim Anheften, kein Einrasten auf eine Linie).
- **Carving:** Am Gegner dreht eine Lenk-Drehrate (`carve_turn_rate` 3,5 rad/s pro Seil, `Vector3.rotated`) die
  vorhandene Geschwindigkeit zum Ziel. Der Betrag bleibt exakt erhalten, die Flugkurve biegt sich stetig ein
  (Zentripetal-Beschleunigung = Rate × Tempo, Wenderadius = Tempo / Rate).
- **Schwerkraft am Gegner** wirkt nur noch entlang der Zielrichtung, wenn das Ziel unten liegt: Sturzflüge
  beschleunigen weiter, Durchsacken unter die Anflugbahn entfällt.
- **Ein Seil:** einfache Lenk- und Zugkraft, weiter Bogen, A/D bleibt aktiv.
- **Zwei Seile am selben Gegner** (LMB-Doppelklick + halten, RMB-Doppel-Tap oder RMB + LMB): doppelte Lenkrate
  und doppelte Zugkraft (beide Winden mit Combat-Stärke) → etwa halber Wenderadius. HUD zeigt `DOPPEL`.
- **LMB-Doppelklick:** Ein kurzer Klick (< `double_tap_window`) schlägt nicht sofort, das Seil zieht weiter; ein
  zweiter Klick im Fenster hängt das zweite Combat-Seil an dasselbe Ziel. Ohne zweiten Klick folgt der Schlag am
  Fensterende (max. 0,2 s später). Halten + Loslassen schlägt wie bisher sofort.
- Der Dash-Kick (`combat_pull_impulse`) kommt nur vom ersten Combat-Seil; ein Combat-Seil verdrängt nie ein anderes
  Combat-Seil. RMB auf einen Gegner-Körper ohne eigenen Lock-Punkt (Riese) merkt sich den Gegner als Seil-Ziel.
- Smoke-Test (22 m/s tangential an einem Dummy vorbei): ein Seil Radius 5,2 m / Zug 142 m/s², zwei Seile
  3,3 m / 258 m/s², Tempo 100 % erhalten, kein Durchsacken, beide treffen. Free-Flow-Sturzflug: 157 statt 210
  Schaden (zielt direkter auf den Lock-Punkt).

### 2026-11-16 – Code entschlackt (CLAUDE.md-Prinzip)
Kein Gameplay-Unterschied: Smoke-Test liefert dieselben Messwerte wie vorher.
- **Movement:** Seil-Zähler über `Array.any/filter`, Hüften-/Winden-/Kamera-Logik je einmal statt doppelt,
  `Vector3.slide` für Wall-Run und Seil-Steuerung, Seil-Rendering in kurze Funktionen geteilt.
  `GrappleHook`: ungenutzte Felder (`normal`, `attach_height`, `total_length`) entfernt.
- **Combat/Targeting:** Ziel-Suche über einen gemeinsamen Filter (`_lockables_within`), doppelte Aim-Start-/
  Lock-Punkt-Berechnungen entfernt, ungenutzter `toggle_hard_lock` gestrichen. Messer: ein `swing_radius()`
  für Kugel und Piercing-Bahn, `_pierce_entry` für die Debug-Liste. HUD-Treffertext vereinfacht.
- **Testarena:** Riese baut Körperteile/Lock-Punkte über `_add_part`/`_add_lock_point`, Flash-/Anzeige-Zeiten
  bei Dummy und Riese als Konstanten, Arena-Kollision ohne Zwischenvariablen.

### 2026-11-16 – CLAUDE.md
- `CLAUDE.md` im Hauptverzeichnis: kurze Projektstruktur + verbindliches Code-Prinzip (minimal, klar, Engine-Funktionen nutzen).

## v0.9 – Release 2026-11-16

### 2026-11-16 – Dual-Hooks: echte Kraft-Vektorsumme v0.9
**Neues Seil-Modell (Kraft statt Geschwindigkeits-Regelung)**
- Jede Winde zieht mit eigener Kraft entlang ihrer **Hüfte → Anker**-Richtung:
  `F_i = d_i · F_pull · (1 − v_i / v_max)`. `F_total = F_links + F_rechts` wird als Beschleunigung angewendet.
- `F_pull` = `reel_force` (200 m/s²) × Basis 0,4 / Combat 1,0, Turbo (W) zusätzlich × 2,5. Die Kraft läuft aus,
  je näher die Einzugsgeschwindigkeit an der Linien-Geschwindigkeit der Winde liegt (wie ein Motor) – das hält
  Basis- und Turbo-Tempo wie bisher (9,6 / 24 m/s) und verhindert Endlos-Beschleunigung.
- **Gleicher Anker/gleiche Richtung = 2× Beschleunigung** (Basis 160 statt 80 m/s², Turbo 400 statt 200 m/s²).
  Gegen die Schwerkraft merkt man das deutlich: zwei Seile heben schneller als eins.
- **Gegenüberliegende Anker:** Querkräfte heben sich auf, gemeinsame Anteile addieren sich (links/rechts oben →
  gerade nach oben, 2·F·cos 45°).
- Seillängen sind harte Constraints, iterativ gelöst (`rope_solver_iterations`), damit zwei Seile nicht
  gegeneinander arbeiten. Das Seil nimmt nur die nach außen gerichtete Radial-Geschwindigkeit weg.
- **S (starr)** mit einem oder zwei Seilen: Zugkraft 0, beide Längen eingefroren, Schwung bleibt erhalten.
- Doppel-Tap darf jetzt **denselben Punkt/Pfeiler** treffen (`dual_min_separation` = 0, vorher 2,5 m Pflichtabstand).
- Die Seile hängen physikalisch an den Hüft-Werfern (`HIP_SIDE` 0,38 m, `HIP_UP` −0,15 m) – dieselben Punkte wie
  die sichtbaren Seile.

**High-Speed-Schutz**
- `move_and_slide` fegt die Kollisionsform kontinuierlich (kein Tunneln durch Geometrie mit Volumen), dazu bleibt
  die Linien-Geschwindigkeit der Winde die Obergrenze fürs Einziehen (auch bei 2× Turbo) und `terminal_speed`
  (75 m/s) deckelt das Gesamttempo.

**Tests**
- Smoke-Test: 137 Checks (neu: 2× Kraft/Beschleunigung am selben Anker in Basis und Turbo, links/rechts-Auslöschung
  und gerader Aufstieg, schräge Anker = exakte Vektorsumme, S mit zwei Seilen, Doppel-Tap auf denselben Pfeiler,
  2× Turbo gegen einen Pfeiler ohne Tunneln).

### 2026-11-16 – Starres Seil auf S, Piercing-Schaden mit Distanz-Abfall v0.8
**S am Seil = starres Seil (ersetzt die Bremse)**
- S friert die Seillänge ein: kein Einholen, kein Nachlassen, keine Schwung-Dämpfung mehr (`reel_brake_mult` und
  `brake_damping` entfernt). Man pendelt verlustfrei auf festem Radius um den Pivot.
- Das Seil nimmt nur die nach außen gerichtete Radial-Geschwindigkeit weg – der tangentiale Schwung bleibt komplett.
  Innerhalb des Radius hängt es (wie ein echtes Seil) locker, bis es wieder spannt.
- HUD zeigt `STARR` statt `BREMSE`. W (Turbo) hat weiterhin Vorrang vor S.

**Piercing-Schlag: Multi-Hit mit dynamischem Distanz-Abfall**
- Bei Gegnern mit mehreren Körperteilen (mehrere `CollisionShape3D`, z. B. Riese) wird die komplette Flugbahn seit
  Schlag-Start ausgewertet.
- **Epizentrum** = Einschlagpunkt des Primär-Treffers (Lock-Punkt bzw. nächster Punkt des getroffenen Teils).
  Das Primär-Teil bekommt **100 %**.
- Durchquerte Nebenteile: `Anteil = 0,5 × (1 − d / 4,5 m)` mit d = Abstand Epizentrum → Teil-Oberfläche.
  Beispiel Sturz auf die Brust: Torso 100 % · Kopf 30 % (1,8 m) · Beine je 10 % (3,6 m) · Arme 0 % (nicht durchquert).
- Nicht durchquerte Teile und Teile außerhalb des Radius bekommen 0 %. Alle Nebenteile zusammen höchstens
  1× Primär-Schaden (`pierce_secondary_budget`) – kein Vervielfachen am Boss.
- Tuning am Messer: `pierce_secondary_max`, `pierce_radius`, `pierce_falloff_exp`, `pierce_path_step`.
- **Debug** (`debug_hits`, standardmäßig an): Konsolen-Tabelle `[PIERCE]` mit Epizentrum, Teil, Prozent, Schaden und
  Distanz sowie farbige Marker in der Welt (weiß = Epizentrum, rot = Primär, orange→gelb = Nebenteile, 2 s sichtbar).

**Tests**
- Smoke-Test: 124 Checks (neu: Luft-Pendel mit S – Länge exakt, Radius fest, Energie bleibt erhalten; Vergleich ohne S;
  Piercing-Sturz am Riesen mit Prozentwerten je Körperteil und HP-Summe).

### 2026-11-16 – Freie Kamera + Kamera-Snap, Auto-Clear, High-Speed-Hit-Window, Boss-Skalierung v0.7
**Freie Kamera statt Dauer-Lock**
- Der permanente Kamera-Lock ist raus – die Kamera bleibt beim Laufen und Schwingen komplett frei, auch mit
  gewähltem Ziel.
- **Mausrad-Klick / R3 = Kamera-Snap-Impuls:** ohne Auswahl wird das Ziel unterm Fadenkreuz gewählt; jeder Klick
  richtet die Kamera in 0,22 s (`snap_duration`) weich auf das gewählte Ziel/den Trefferpunkt, danach ist sie
  sofort wieder frei. Maus/Stick bewegen bricht den Snap ab (Spieler hat Vorrang).
- **Gedrückt halten (0,45 s, `lock_clear_hold`) löst die Auswahl.**
- **Mausrad** schaltet bei Gegnern mit mehreren Trefferpunkten (Riese) nur durch dessen Punkte (Kopf, Brust,
  Knie …); bei einfachen Zielen durch die anderen Ziele in der Nähe. Danach Klick = Snap auf den neuen Punkt.

**Auto-Clear nach Distanz**
- Die Auswahl bleibt bestehen, solange man in der Nähe ist (außerhalb der Grapple-Reichweite grau, kein Seil).
- Weiter als **3× Grapple-Reichweite (210 m, `lock_expire_range_mult`)** → Auswahl und Rahmen werden gelöscht.

**High-Speed-Hit-Window**
- Lock-Schlag-Reichweite wächst mit dem Tempo: 4 m im Stand, +0,03 m pro m/s, max. +2,5 m (≈ 6,1 m bei 70 m/s).
- Der Lock-Treffer prüft die ganze Flugstrecke seit dem letzten Physik-Frame – bei 60+ m/s rauscht man nicht
  mehr zwischen zwei Frames ohne Treffer am Ziel vorbei.
- Kugel-Radius (+ max. 1 m) und Active-Phase (+ max. 0,08 s) wachsen ebenfalls mit dem Tempo.
- Auto-Grab-Fang-Kegel wird mit dem Tempo breiter (+0,06° pro m/s, max. +5°).

**Schadens-Skalierung (Adds vs. Boss)**
- Rohschaden läuft durch einen weichen Deckel `cap · tanh(roh / cap)`: normale Treffer bleiben praktisch gleich,
  Top-Treffer nähern sich dem Deckel.
- Standard-Ziele: Deckel 285 (`hit_soft_cap`) → **Top-Sturzflug ≈ 95 % eines 300-HP-Dummys**, mittlerer Sturz ≈ 183.
- Bosse liefern `get_hit_cap()`: Riese max. **15 % der Max-HP pro Treffer** (`max_hit_fraction`) → Top-Sturz 450 von
  3000, mind. 7 perfekte Treffer, kein One-Hit-Kill.
- Treffer-Info enthält jetzt `raw_damage` und `hit_cap`.

**Tests**
- Smoke-Test: 111 Checks (neu: freie Kamera mit Auswahl beim Schwingen, Snap + Abbruch, Halten löst, Auto-Clear
  über 3× Reichweite, High-Speed-Vorbeiflug trifft, Dummy-/Boss-Schadensdeckel).

### 2026-11-15 – Dual-Mode-Targeting: Free-Flow Auto-Grab + echter Hard-Lock v0.6
**Free-Flow Auto-Grab (ohne Hard-Lock)**
- **LMB halten** greift automatisch den Gegner unter/nahe dem Fadenkreuz in Grapple-Reichweite und zieht heran,
  **LMB loslassen** = Momentum-Slash im Anflug. Kein Lock nötig.
- Großzügige Erkennung: Gegner exakt unterm Fadenkreuz → sonst nächster sichtbarer Trefferpunkt auf dem
  anvisierten Körper (z. B. Riese) → sonst Fang-Kegel 9° / min. 3,5 m (`auto_grab_cone_deg`, `auto_grab_radius`).
- Wird LMB gehalten und ein Ziel kommt erst später ins Fadenkreuz (oder zurück in Reichweite), greift das Seil sofort.
- Näher als 4,5 m (`auto_grab_min_dist`) schlägt LMB direkt zu, statt ein Seil zu schießen.
- Fadenkreuz wird orange, sobald LMB einen Gegner greifen würde.

**Hard-Lock = echter Kamera-Lock**
- Mit Hard-Lock übernimmt die Kamera: Yaw/Pitch folgen dem Lock-Punkt weich (`lock_camera_speed`), Maus und
  rechter Stick drehen nicht frei. Schulter-Versatz und Spring-Arm sind eingerechnet – der Lock-Punkt liegt
  exakt unterm Fadenkreuz.
- **Lock bleibt außerhalb der Reichweite bestehen** (kein Abbruch mehr bei 1,3× Reichweite). Er fällt nur weg,
  wenn das Ziel verschwindet/besiegt ist oder man ihn per Klick löst.
- Einrasten und Durchschalten bis 120 m (`lock_acquire_range`), auch über die Grapple-Reichweite hinaus.
- Mausrad-Wechsel mit **fester Reihenfolge**: Die mitdrehende Kamera wirft die Sortierung nicht mehr um
  (kein Hin-und-her zwischen zwei Punkten).

**Hitbox-Ausrichtung**
- Dummy-Lock-Punkt = Mitte der Kollisions-Kapsel (vorher Mesh-Origin + 0,4 m Versatz).
- Riesen-Lock-Punkte hängen jetzt unter der `CollisionShape3D` ihres Körperteils (`Shape_Torso`, `Shape_Kopf` …)
  und folgen damit der Hitbox. Ziele ohne eigenen Lock-Punkt nutzen die Mitte ihrer Kollisions-Shapes.
- `LockPoint`: neue Felder `radius` (Rahmengröße) und `center_on_shape`.

**Reticle-UI**
- Lock-Anzeige ohne Text/Namen: neuer `LockReticle` mit vier Eckklammern, exakt auf den Lock-Punkt projiziert,
  Größe passt sich Ziel-Radius und Distanz an.
- **Farbig** = in Grapple-Reichweite, **grau** = außerhalb (Lock bleibt, Seil erst wieder in Reichweite).

**Kampf**
- Der Schlag nutzt das stärkste Anflug-Momentum der letzten 0,12 s (`momentum_memory`) – ein Aufprall kurz vor
  dem Schlag-Start verschluckt den Speed-/Plunge-Bonus nicht mehr.
- Es gibt immer nur ein Combat-Seil; LMB loslassen löst es zuverlässig.

**Tests**
- Smoke-Test: 94 Checks (neu: Hitbox-Ausrichtung, Auto-Grab + Slash ohne Lock, Greifen beim Halten,
  Kamera-Lock + Reticle-Position, Mausrad-Wechsel mit Kamera, Lock außer Reichweite grau + Wiedergreifen).

### 2026-11-15 – Winde per W/S, Hard-Lock mit Mausrad, LMB-Angriffs-Loop v0.5
**Winde**
- **Base-Pull 0,4** (`reel_base_mult`): 0,4 × 24 m/s ≈ 9,6 m/s – straff, hält die Distanz, zieht nicht aggressiv.
- **W am Seil = Turbo-Einzug** (2,5× Basis, `reel_turbo_mult`). Shift ist wieder reiner Sprint.
- **S am Seil = Bremse**: Winde läuft nur noch mit 0,05 (≈ 1,2 m/s, `reel_brake_mult`), zusätzlich wird der
  eigene Schwung gedämpft (`brake_damping`) – man hängt fast regungslos an der Leine.
- **A / D** bleiben seitliches Ausweichen/Schwingen quer zum Seil.

**Hard-Lock & Ziel-Wechsel**
- **Mausrad-Klick / R3** rastet das Ziel im Lock-Kegel ein, erneut drücken löst. Der Lock hält, auch wenn das
  Fadenkreuz wegschaut (bis 1,3× Grapple-Reichweite, `lock_keep_range_mult`).
- **Mausrad hoch/runter** (Controller: D-Pad links/rechts) schaltet durch alle sichtbaren Ziele und
  Trefferpunkte, sortiert nach Nähe zum Fadenkreuz. Verdeckte Punkte (z. B. Nacken von vorne) sind nicht wählbar.
- HUD zeigt nur bei aktivem Hard-Lock eine Klammer mit Punktnamen.
- Tab-Lock und der automatische Sturzangriff entfallen.

**LMB-Angriffs-Loop**
- Mit Hard-Lock: **LMB halten** schießt das Combat-Seil zum Lock-Punkt und zieht heran (Winde 1,0 × 24 m/s,
  W-Turbo/S-Bremse wirken auch hier). **LMB loslassen** löst das Seil und führt den Schlag im Anflug aus.
- Ohne Hard-Lock: LMB = normaler Slash wie bisher.
- Schaden nutzt das **Momentum beim Schlag-Start** (nicht erst nach einem Aufprall) – Speed-Faktor und
  exponentieller Plunge-Bonus wie definiert. Treffer werden dem Lock-Punkt zugeordnet (`damage_mult` pro Punkt
  als Haken für Schwachstellen/Rüstung).

**Test-Arena**
- **Trainings-Riese** (~14 m, 3000 HP) bei (0, 0, -95) mit 7 Lock-Punkten: Kopf, Nacken, Brust, Schultern, Knie.
- Neue Klasse `LockPoint` (Marker3D) für beliebige anvisierbare Trefferpunkte an Gegnern.
- Smoke-Test: 65 Checks.

### 2026-11-15 – Grapple- & Kampf-Fundament v0.4 (straffes Seil, Turbo-Pull, Momentum-Schaden)
**Entfernt**
- **Slingshot und Tactical Nest** komplett entfernt – kein Auto-Schleudern, kein automatisches Fixieren mehr.
- Rebound-Kick am Anker und das Einholen per Leertaste entfallen (Seil arbeitet jetzt physikalisch ehrlich).

**Neu / Geändert**
- **Straffes Seil mit Winde (RMB / LT):** Das Seil lässt nie nach, reißt aber auch nicht weg. Eine Winde holt
  gleichmäßig ein – **Basis = 0,5× von 24 m/s = 12 m/s** (`reel_speed`, `reel_base_mult`). Am Ende hängt man
  ruhig am Anker (`hang_length`). Mehrere Seile werden gemeinsam gelöst und kämpfen nicht gegeneinander.
- **Turbo-Pull (Shift am Seil):** **2,75× der Basis ≈ 33 m/s** (`reel_turbo_mult`), wirkt auf beide Hüft-Haken.
- **Dual-Hooks:** RMB nutzt die nächste freie Hüfte (abwechselnd L/R); Doppel-Tap setzt den zweiten Haken –
  zwei ganz normale straffe Seile, keine Sondermodi.
- **WASD am Seil:** tangentiale Steuerung von Flugbahn/Pendel (`rope_steer_accel`), arbeitet nie gegen das Seil.
- **Target-Lock auf Tab / R3:** Tab feuert den Combat-Grapple auf den Gegner im Lock-Kegel (Anflug über das Ziel →
  Sturzangriff → Abprall). Tab erneut = abbrechen. RMB rastet nicht mehr auf Gegner ein.
- **Momentum-Schaden (Messer):** `min_damage` im Stand (5), Speed-Faktor überproportional
  (`1 + (v/20)^1.5`), **Plunge-Bonus** exponentiell bei steilem Sturz von oben (×2 je 10 m/s Fallspeed über
  15 m/s, × Steilheit, ×1,25 im Turbo). Beispiel: Stand 5 · 40 m/s flach 19 · 40 m/s Sturz 217.
  Treffer-Info (`speed_mult`, `plunge_mult`, `is_plunge`) als Basis für spätere Schwachstellen/Rüstung.
- Dummies: 300 HP, zeigen den letzten Treffer an. HUD: Trefferzeile mit Speed-/Plunge-Faktor, TURBO/DIVE.
- Smoke-Test: 49 Checks.

### 2026-11-15 – Dash entfernt, kontextsensitive Shift-Taste
**Entfernt**
- **Dash** restlos aus Code, Input-Map (Q / Strg / Xbox B) und HUD entfernt. Q, Strg und B sind frei.

**Neu / Geändert**
- **Shift kontextsensitiv:**
  - Am Boden: Sprint. Sprint-Speed **17 → 24 m/s**, Boden-Beschleunigung 80 → 110 („richtiges Rennen“).
  - In der Luft mit aktivem Seil: **Turbo-Einzug** – 1,5× der neuen, sanften Basis.
- **Sanfter Basis-Einzug:** Zug-Beschleunigung und -Höchstgeschwindigkeit des Grapples laufen jetzt mit
  0,5× (`reel_base_mult`), Turbo = 1,5× davon (`reel_turbo_mult`). Gilt auch fürs Einholen am hängenden Seil
  (Space sanft, Shift Turbo).
- **Zielführung im Einzug** (`pull_homing`): seitliches Driften wird gedämpft, damit man trotz sanfterem Zug
  nicht unter dem Ziel durchrauscht und es umkreist.
- **Ankunft beim Vorbeifliegen** (`pull_arrive_window`): Rebound bzw. Sturzangriff lösen auch aus, wenn man den
  nächsten Punkt zum Ziel passiert hat (nicht mehr nur innerhalb von 3,5 m).
- Fix: Nach dem Abwickeln eines Seil-Knicks löste der Rebound zu früh aus (Nähe-Wert wird bei Pivot-Wechsel
  zurückgesetzt).
- HUD zeigt `TURBO` neben dem State. Smoke-Test: 46 Checks.

### 2026-11-15 – Dual-Hip-Grapple v0.3 (Slingshot & Tactical Nest)
**Neu**
- **Dual-Hip-Grapple auf RMB / LT:** zwei Werfer an linker und rechter Hüfte.
  - Klick/Halten feuert den nächsten Hüfthaken (wechselt automatisch L ↔ R). Auf Gegner weiterhin
    Anflug + Sturzangriff, auf Geometrie Zug + Rebound.
  - **Doppel-Tap:** Nach dem Loslassen hängt das Seil 0,2 s locker (keine Kraft = sofortiges
    Abspring-Gefühl). Ein zweiter Klick in diesem Fenster spannt den ersten Haken wieder und setzt den
    zweiten an der neuen Zielfläche (mind. 2,5 m entfernt).
  - **Slingshot:** Beide Seile ziehen sich zusammen, Spannung lädt in 0,8 s auf (Seile verfärben sich).
    Loslassen oder Sprung schleudert in Blickrichtung (mind. leicht nach oben), 26–62 m/s je nach Ladung.
  - **Tactical Nest:** Sind beide Anker nah (≤ 9 m) oder beide an der Decke, wird der Spieler an einem
    stabilen Hängepunkt fixiert (keine Schwerkraft). Loslassen = fallen lassen, Sprung = Absprung in
    Blickrichtung.
- **Nest-Halle** in der Test-Arena (zwei Wände + Decke) zum Ausprobieren.
- Seile kommen sichtbar aus der Hüfte; Farbe zeigt den Zustand (gespannt / Slingshot-Ladung / Nest).

**Entfernt / Geändert**
- Q/E-Momentum-Swing (inkl. LB/RB) komplett entfernt. **Q ist wieder Dash** (zusätzlich Strg / Xbox B).
- Lock-Marker im HUD entfernt. Auto-Aim (2,5 m / 5°-Kegel) arbeitet unsichtbar weiter, das Fadenkreuz
  färbt sich nur dezent. HUD zeigt L/R-Haken und Slingshot-Ladung bzw. NEST.
- Input-Action `hook_combat` → `grapple`; `hook_left`/`hook_right` entfallen.
- Smoke-Test: 42 Checks (u. a. Hüft-Wechsel, Doppel-Tap-Fenster, Slingshot, Nest).

### 2026-11-15 – Fix: Pull-Abbruch durch lokale .uid-Datei
- `tests/movement_smoke_test.gd.uid` aus dem Repo genommen (wird lokal von Godot erzeugt, jetzt gitignored).
- `start_game.bat` loest kuenftig Konflikte mit lokal erzeugten `.uid`-Dateien selbst
  (`tools/fix_uid_conflicts.bat`) und bricht nur noch bei echten lokalen Aenderungen ab.

### 2026-11-15 – Kamera, neues Kampf-Layout, Seil-System v0.2
**Neu**
- **Kamera-Wechsel (P / Xbox View):** nahtlose Überblendung Third-Person ↔ First-Person
  (Kamera im Kopf, Körper wirft nur noch Schatten, eigenes Viewmodel-Messer).
  Fadenkreuz, Grapple-Raycast und Speed-FOV funktionieren in beiden Modi (FP mit eigenem FOV-Bereich).
- **Neues Tasten-Layout (Tastatur + Xbox):**
  LMB/X Messer · RMB/LT Combat-Grapple + Target-Lock · Q/LB + E/RB Momentum-Swing ·
  Shift/L3 Sprint · Space/A Sprung/Höhe · Strg/B Dash · P/View Kamera · R/Menu Reset ·
  rechter Stick Kamera.
- **Auto-Aim (Kegel):** Gegner rasten im Radius von mind. 2,5 m um das Fadenkreuz ein (wächst mit der
  Distanz über einen 5°-Kegel). Für Geometrie: exakter Strahl, sonst Strahlenkegel um das Fadenkreuz.
  Lock-Marker im HUD springt auf den eingerasteten Punkt.
- **Combat-Grapple (RMB halten):** zieht mit voller Wucht heran. Auf Gegner: Anflug über das Ziel →
  Sturzangriff von oben (3× Messerschaden) → Abprall nach oben, Seil bleibt dran.
- **Momentum-Swing (Q/E halten):** Haken links/rechts automatisch schräg vorne-oben, Bogen nach vorne,
  Höhen-Regler hält die Höhe; Q↔E-Wechsel übernimmt die Zielhöhe. Space = einholen / Höhe gewinnen.
- **Seil-Bending:** Seile wickeln sich um Kanten (Knickpunkt = temporärer physikalischer Anker) und
  wickeln sich beim Zurückschwingen wieder ab. Kein Durchschneiden von Wänden mehr.
- **Reißfeste Seile:** lösen sich nie von selbst, nur beim Loslassen der Taste. Am Ankerpunkt:
  Rebound im Bogen drüber hinaus statt Abkoppeln.
- **Jagdmesser (`scripts/knife_combat.gd`):** 3er-Combo (Windup/Active/Recovery), Treffer per
  Kugel-Abfrage in Blickrichtung, Schaden skaliert mit Tempo, blockiert das Movement nicht.
- **Trainings-Dummies** in der Arena (Boden, Plattformen, schwebend) + **Swing-Allee** (Säulenreihen).
- Alle Seil-Segmente werden über **ein** MultiMesh gerendert.

**Geändert**
- Dash von Q/RMB auf **Strg / Xbox B** verlegt (Q/E/RMB sind jetzt Seile).
- State `GRAPPLE` → `HOOKED` (ein oder mehrere Seile aktiv).
- Smoke-Test auf 38 Checks erweitert (Kamera, Messer, Auto-Aim, Dive, Rebound, Bending, Swing).

### 2026-11-15 – Movement-Prototyp v0.1
**Neu**
- Projektstruktur: `scenes/`, `scripts/`, `assets/`, `docs/`, `tests/`.
- Guardian-Controller (`scripts/guardian_controller.gd`, `CharacterBody3D`):
  - Laufen / Sprinten mit Momentum-Erhalt (Speed aus Dash/Grapple wird am Boden nur sanft abgebaut).
  - Air-Control (Quake-artig), variable Sprunghöhe, Coyote-Time, Jump-Buffer.
  - Dash mit 2 Charges (Boden/Luft), Dash-Jump, Gas-Stoß während des Grapples.
  - Grapple-Hook: Seil-Constraint mit Swing, automatisches Einholen, Space = Gas-Boost, Lenkung per WASD.
  - Wall-Run inkl. Wall-Jump.
  - Third-Person-Kamera mit SpringArm, speed-abhängiger FOV.
- Test-Arena (`scenes/test_arena.tscn`): Türme, Wall-Run-Wände, Schwebeplattformen, Blöcke –
  alles über **ein** MultiMesh + **einen** StaticBody gebaut.
- Debug-HUD: Crosshair (grün = Grapple-Ziel in Reichweite), Speed, State, Dash-Charges, FPS.
- Headless-Smoke-Test `tests/movement_smoke_test.gd`.
- Physics-Interpolation aktiviert (gegen Mikroruckler).

**Steuerung**
WASD Laufen · Shift Sprint · Space Sprung / am Seil Gas · Q / Strg / RMB Dash ·
LMB halten Grapple · R Reset · Esc Maus freigeben
