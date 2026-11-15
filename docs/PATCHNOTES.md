# Patchnotes – Spirit Drive

Neueste Einträge immer oben.

## Unreleased (Robin-Branch)

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
