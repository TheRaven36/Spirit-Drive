# Workflow – Spirit Drive

## Branches
| Branch | Zweck |
|---|---|
| `main` | Stabiler, jederzeit spielbarer Release-Stand. Kein direktes Entwickeln/Committen. |
| `Robin-Branch` | Aktiver Entwicklungs- und Test-Branch. **Alle** Features und Experimente landen hier. |

## Entwickeln & Testen (`Robin-Branch`)
1. Feature/Fix im `Robin-Branch` umsetzen.
2. Checks laufen lassen (siehe unten).
3. Eintrag in `docs/PATCHNOTES.md` unter **Unreleased** ergänzen (neueste Einträge oben).
4. Committen und `git push origin Robin-Branch` – Robin zieht den Stand lokal und spielt an.

## Release (nur nach ausdrücklicher Freigabe durch Robin)
1. Alle finalen Änderungen sind im `Robin-Branch` committed und gepusht.
2. `git fetch origin` → `git merge origin/main` in den `Robin-Branch` (kein Rebase, kein Force-Push).
3. `docs/PATCHNOTES.md` prüfen: Unreleased-Block wird zur neuen Version.
4. Checks laufen lassen.
5. Falls Build-Hook aktiv: `GAME_BUMP=1 git commit --allow-empty -m "Release: Build hochzaehlen"`
6. `git push origin Robin-Branch`, danach `git push origin Robin-Branch:main` (nur Fast-Forward, nie `--force`).

## Regel: Godot-UIDs
Godot 4.4+ legt zu jedem Skript/Shader eine `.uid`-Datei an. Vor jedem Commit
`godot --headless --path . --import` laufen lassen und die erzeugten `.uid`-Dateien
**mit** dem neuen Skript committen – sonst erzeugt Robins Editor sie lokal und der
nächste `git pull` bricht ab. `tests/*.uid` sind ausgenommen (gitignored).
`start_game.bat` repariert diesen Konflikt notfalls automatisch (`tools/fix_uid_conflicts.bat`).

## Checks
```bash
# Projekt importieren + Skripte parsen
godot --headless --path . --import
# Movement-Smoke-Test (Exit-Code 0 = ok)
godot --headless --path . --script res://tests/movement_smoke_test.gd
# Spirit-System + Minimal-HUD (Exit-Code 0 = ok)
godot --headless --path . --script res://tests/spirit_system_test.gd
# Feld-Spirit-KI (Exit-Code 0 = ok)
godot --headless --path . --script res://tests/spirit_entity_test.gd
```

## Lokal starten (Windows)
- Der lokale Klon steht auf `Robin-Branch`. Im Klon nichts von Hand ändern.
- `start_game.bat` holt per `git pull --ff-only` den aktuellen Stand und öffnet das Projekt in Godot.
  Beim ersten Start fragt es einmal nach dem Pfad zur Godot-EXE und merkt ihn sich in
  `godot_path.local` (nicht im Repo).
- Einmal pro Klon: `git config core.hooksPath hooks` (sobald ein `hooks/`-Ordner existiert).

## Projektstruktur
```
scenes/          Szenen (.tscn); scenes/areas/ = streamfähige Areale
scenes/ui/       HUD-Szenen (minimal_hud.tscn)
scripts/         GDScript-Logik (Guardian, Injects, Mobs …)
scripts/spirits/ Spirit-Daten, Roster-Komponente, Feld-Avatar
scripts/ui/      HUD-Skripte und -Widgets
data/spirits/    Die 9 Basis-Spirits (.tres)
assets/          shaders/, models/, textures/ …
tests/           Headless-Tests
docs/            WORKFLOW.md, PATCHNOTES.md
```

## Performance-Regeln
- Umgebung, Props, Mob-Schwärme: **MultiMeshInstance3D** statt vieler Einzel-Meshes (Draw Calls minimal).
- Statische Kollision eines Clusters: ein `StaticBody3D` mit mehreren Shapes statt vieler Bodies.
- Welt modular in streamfähigen Arealen (`scenes/areas/`), keine monolithische Megaszene.
- Physics-Interpolation ist aktiv: Bewegung in `_physics_process`, Kamera/Visuals in `_process`
  über `get_global_transform_interpolated()`.
