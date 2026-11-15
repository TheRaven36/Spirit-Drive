# Patchnotes – Spirit Drive

Neueste Einträge immer oben.

## Unreleased (Robin-Branch)

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
