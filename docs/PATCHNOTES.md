# Patchnotes – Spirit Drive

Neueste Einträge immer oben.

## Unreleased (Robin-Branch)

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
