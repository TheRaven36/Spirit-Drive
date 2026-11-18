# CLAUDE.md – Spirit Drive

Godot 4.7 (Forward+, Jolt Physics, Physics-Interpolation aktiv), GDScript.
High-Speed-Action mit Grapple-Movement und Spirit-System.
Ablauf, Branches, Release und Checks: [docs/WORKFLOW.md](docs/WORKFLOW.md) – gilt verbindlich.

## Projektstruktur
```
scenes/world.tscn           Hauptszene (F5): Guardian, HUDs, Licht + Areas (Hoehle, Tunnel)
scenes/test_arena.tscn      Hoehlen-Arena (Areal, wird vom Tunnel ent-/geladen)
scenes/homebase_outpost.tscn  Homebase-Prefab: SafeZone + 4 Stationen
scenes/organic_transition_tunnel.tscn  3D-Grapple-Tunnel mit asynchronem Loading Gate
scenes/props/               Einzelne Props/Gegner-Szenen (training_dummy.tscn)
scenes/spirits/spirit_entity.tscn  Feld-Spirit (Greybox-Kapsel, Hitbox)
scenes/ui/minimal_hud.tscn  Minimal-HUD (HP, Haken, Spirit-Slots, Steuerungs-Overlay auf +)
scenes/ui/damage_number.tscn  Eine Floating Damage Number (Label + Pop-Tween)
scenes/areas/               Streamfaehige Areale (keine Megaszene)
scripts/
  guardian_controller.gd    Spieler: Movement, Wall-Run, Seilphysik, Kamera
  guardian_input.gd         Input-Actions zur Laufzeit (Tastatur/Maus + Xbox)
  grapple_hook.gd           Ein Seil: Anker, Ziel, Knickpunkte (Bending)
  knife_combat.gd           Jagdmesser: Combo, Treffer, Momentum-Schaden
  lock_point.gd             Anvisierbarer Trefferpunkt an Gegnern
  lock_reticle.gd           Hard-Lock-Rahmen (HUD)
  debug_hud.gd              Fadenkreuz + Debug-Werte (oben rechts)
  health_component.gd       Lebenspunkte (Komponente, Signal health_changed)
  guardian_progress.gd      Besitz/Fortschritt (Material, Rucksack, Truhe, Ausruestung, Upgrades)
  organic_transition_tunnel.gd  Tunnel: CSG-Roehre, Anker, Barrieren, load_threaded_request
  homebase/                 HomebaseOutpost, InteractionStation (F/ESC) + StationWindow,
                            SpiritAltar, EquipmentStash, ForgeStation, MerchantStation
  spirits/                  SpiritData (Resource), SpiritLibrary, SpiritRosterComponent (3er-Roster,
                            Feld 1/2/3, Waffen-Sockel Q/E, Saeulen-Vorteil), SpiritEntity (Feld-Spirit-KI)
  ui/                       MinimalHUD + Widgets (HookIndicator, SpiritSlot),
                            DamageNumberManager (Treffer -> Zahl an der Trefferstelle)
  test_arena.gd             Geschlossene Greybox-Hoehle (MultiMesh je Form, ein StaticBody3D),
                            Stalagmiten/Stalaktiten/Mega-Saeulen, 3 Elementar-Riesen
                            (Feuer 1.0x, Wasser 1.4x, Erde 2.0x)
  training_dummy.gd         Trainings-Ziel
  training_giant.gd         Test-Gegner mit LockPoints, size_scale, Element (Saeule + Glow), Ruestung
data/spirits/               Die 9 Basis-Spirits (.tres)
assets/shaders|models|textures
tests/movement_smoke_test.gd  Headless-Smoke-Test (Exit-Code 0 = ok)
tests/spirit_system_test.gd   Spirit-System + Minimal-HUD (Exit-Code 0 = ok)
tests/spirit_entity_test.gd   Feld-Spirit-KI: Follow, Bodyguard, Hard-Lock-Befehl (Exit-Code 0 = ok)
tests/homebase_test.gd        Homebase: Stationen, Interaktion, Altar-Kombinationen, SafeZone
tests/tunnel_test.gd          Tunnel: Geometrie, asynchrones Laden/Entladen in beide Richtungen
tools/, start_game.bat      Windows-Start + UID-Konflikt-Fix
docs/WORKFLOW.md, docs/PATCHNOTES.md
```

## Code-Prinzip: minimal und klar (strikt)
- **Kein Over-Engineering.** Nur bauen, was das aktuelle Feature braucht. Keine Vorrats-Features,
  keine "fuer spaeter"-Hooks, keine Konfigurationsschichten ohne konkreten Bedarf.
- **Keine unnoetigen Abstraktionen.** Keine Manager-, Factory-, Basis- oder Wrapper-Klassen,
  keine Interfaces/Vererbungsketten fuer einen einzigen Anwendungsfall. Eine neue Klasse nur,
  wenn sie eigenen Zustand mit klarer Verantwortung kapselt (z. B. `GrappleHook`).
- **Engine zuerst.** Bestehende Godot-Funktionen und -Nodes nutzen statt nachzubauen
  (Raycasts/Shape-Queries, `move_and_slide`, Signale, Gruppen, `Tween`, `MultiMeshInstance3D`,
  `Vector3`-Methoden wie `slide`, `project`, `lerp`, `move_toward` …).
- **Bestehenden Code wiederverwenden.** Vor neuem Code pruefen, ob es die Funktion im Projekt
  schon gibt; vorhandene Konventionen (`take_hit(damage, dir, source)`, Gruppen `lock_target`,
  `damageable`) einhalten.
- **Kurze, lesbare Funktionen.** Eine Funktion = eine Aufgabe, Richtwert unter ~30 Zeilen.
  Sprechende Namen, flache Verschachtelung (Early Return), statische Typen (`:=`, `-> void`).
- **Tuning-Werte als `@export` oder `const`** oben im Skript, keine Magic Numbers im Code.
- **Kommentare kurz, auf Deutsch**, erklaeren das *Warum*. Doc-Kommentar (`##`) oben in jedem Skript.
- **Kleine Diffs.** Nur aendern, was die Aufgabe verlangt; kein ungefragtes Refactoring.
- Performance-Regeln aus `docs/WORKFLOW.md` beachten (MultiMesh, ein StaticBody3D pro Cluster,
  Bewegung in `_physics_process`, Visuals in `_process`).

## Vor jedem Commit
1. `godot --headless --path . --import` und erzeugte `.uid`-Dateien mitcommitten.
2. Alle Suites in `tests/` muessen Exit-Code 0 liefern:
   `godot --headless --path . --script res://tests/<suite>.gd` fuer movement_smoke_test,
   spirit_system_test, spirit_entity_test, homebase_test, tunnel_test.
3. Eintrag in `docs/PATCHNOTES.md` (neueste oben).
4. Nur auf `Robin-Branch` committen und pushen; `main` nur nach Robins Freigabe.
