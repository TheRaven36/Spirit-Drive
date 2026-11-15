# Patchnotes – Spirit Drive

Neueste Einträge immer oben.

## Unreleased (Robin-Branch)

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
