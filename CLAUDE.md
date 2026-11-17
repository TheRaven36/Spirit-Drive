# CLAUDE.md – Spirit Drive

Godot 4.7 (Forward+, Jolt Physics, Physics-Interpolation aktiv), GDScript.
High-Speed-Action mit Grapple-Movement und Spirit-System.
Ablauf, Branches, Release und Checks: [docs/WORKFLOW.md](docs/WORKFLOW.md) – gilt verbindlich.

## Projektstruktur
```
scenes/test_arena.tscn      Hauptszene (F5)
scenes/props/               Einzelne Props/Gegner-Szenen (training_dummy.tscn)
scenes/ui/minimal_hud.tscn  Minimal-HUD (HP, Haken, Spirit-Slots, Steuerungs-Overlay auf +)
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
  spirits/                  SpiritData (Resource), SpiritLibrary, SpiritRosterComponent (3er-Roster,
                            Feld 1/2/3, Waffen-Sockel Q/E, Saeulen-Vorteil), SpiritFieldAvatar
  ui/                       MinimalHUD + Widgets (HookIndicator, SpiritSlot)
  test_arena.gd             Arena-Aufbau (MultiMesh, ein StaticBody3D)
  training_dummy.gd         Trainings-Ziel
  training_giant.gd         Grosser Test-Gegner mit mehreren LockPoints
data/spirits/               Die 9 Basis-Spirits (.tres)
assets/shaders|models|textures
tests/movement_smoke_test.gd  Headless-Smoke-Test (Exit-Code 0 = ok)
tests/spirit_system_test.gd   Spirit-System + Minimal-HUD (Exit-Code 0 = ok)
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
2. `godot --headless --path . --script res://tests/movement_smoke_test.gd` und
   `... res://tests/spirit_system_test.gd` muessen Exit-Code 0 liefern.
3. Eintrag in `docs/PATCHNOTES.md` (neueste oben).
4. Nur auf `Robin-Branch` committen und pushen; `main` nur nach Robins Freigabe.
