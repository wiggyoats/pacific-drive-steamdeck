# Pacific Drive on Steam Deck: from 12 to 44 fps

> **Work in progress: not fully tested yet.** The numbers below come from automated benchmarks of one scene on one Steam Deck.
> Nobody has played a full session with this setup yet; that is next. Back up your saves, and please open an issue if
> something looks or behaves wrong.

Pacific Drive runs badly on the Steam Deck, even though it doesn't look like a demanding game. This sets it up to run at
**~44 fps** in a heavy scene, from 12 fps at the settings the Deck picks by default, with one install script and a small
[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) mod.

Measured on a Steam Deck LCD (Proton 11, sitting in the car in the Deep Zone forest at night, in rain, frame rate uncapped,
30 s per run, 1280x800):

| Setup | Average fps |
|---|---:|
| Epic (what a fresh install picks on the Deck) | 12.3 |
| Low preset | 24.6 |
| Low + cheaper mirror settings | 34.0 |
| Low + cheaper mirrors, 67% render scale | 35.9 |
| **This setup**: Low + cheaper mirrors, 67% render scale, PDThrottle mod | **44.4** (1% low 24) |
| Low + cheaper mirrors, 100% render scale, PDThrottle mod | 33.8 |

**Anti-aliasing.** The Low preset switches anti-aliasing off, which looks very jagged at 67%, so the installer turns TAA back on
(`sg.AntiAliasingQuality=2`). Measured with the mod at 67%: no AA 45.5 fps, TAA 44.4, FSR 4 Lite (OptiScaler, Quality) 31.6,
FSR 4 Lite Balanced 30.8. FSR 4 Lite has a fixed cost at output resolution that the Deck can't afford, so TAA is the better deal.

Runs of the same setup vary by about ±2 fps (weather and camera direction change between runs). Lighter places (daytime, the
garage) run faster. The 1% lows are still in the mid 20s, so a 30 fps cap is the safe choice for now.

## Why the game runs badly, and what this does

- **The car's mirrors render the whole scene a second time.** The game has settings for them (`GameUserSettings.ini`); lowering
  their resolution and turning off grass, fog and shadows in them gives the biggest single gain: 25 to 34 fps at Low.
- **Most of the rest is on the CPU, not the GPU.** Below ~35 fps nothing graphical helped: shadows off, fog off, no grass, short
  draw distance, 30% render scale, DX11 instead of DX12, FSR 4 through OptiScaler, `Engine.ini` tweaks like
  `r.FinishCurrentFrame=0`. Profiling the game thread showed it spends almost half its time running the game's Blueprint
  scripts (`tools/` has the profiler). Wine/Proton overhead is under 3%.
- **The car's two in-dash screens re-render their UI into textures every frame.** `BP_InteractCameraComponent` draws widgets
  into render targets on every tick, which costs CPU, render thread and GPU no matter the resolution. The **PDThrottle** mod
  makes it tick 10 times a second instead; the screens look the same. That is the 36 to 44 fps step. It helps most when the
  render scale is lowered; at 100% the GPU is the limit and it adds only ~2 fps.
- Throttling other Blueprints (time of day, foliage detection, ~900 breakable props, the car computer) gained nothing
  measurable, so the mod only touches the dash screens. The game's manager objects can't be slowed down safely (their tick
  can only be switched on or off, and their logic uses the frame time), so they are left alone.

## Install

You need: the game from Steam, started once (to the main menu) so its settings file exists.

1. Switch to **Desktop Mode** (Steam button > Power > Switch to Desktop).
2. Open Konsole and run:

   ```bash
   curl -fLO https://raw.githubusercontent.com/wiggyoats/pacific-drive-steamdeck/main/install.sh
   bash install.sh
   ```

   For a sharper image at fewer fps: `bash install.sh --scale 100` (50 to 100). To only install the mod and keep your own
   graphics settings: `bash install.sh --no-settings`.
3. In Steam, right click the game > Properties > **Launch Options**:

   ```
   WINEDLLOVERRIDES="dwmapi=n,b" %command%
   ```

   With [Decky Framegen](https://github.com/xXJSONDeruloXx/Decky-Framegen), put it in front of the fgmod part:

   ```
   WINEDLLOVERRIDES="dwmapi=n,b" ~/fgmod/fgmod %command%
   ```

4. Back in Game Mode, cap the frame rate at 30 in the performance overlay (the `...` button).

The settings are the game's own, so you can change any of them in its menu afterwards (Graphics > Advanced has the mirror
options). The script backs up what it changes to `~/pacific-drive-deck-backup`.

**Uninstall:** `bash install.sh --uninstall`, then remove the `WINEDLLOVERRIDES` part from the launch options.

**Windows / other PCs:** extract [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) into
`Pacific Drive/PenDriverPro/Binaries/Win64`, copy the `PDThrottle` folder into its `Mods` folder and add `PDThrottle : 1` to
`Mods/mods.txt`. Not tested on a desktop PC, where the dash screens cost much less.

## How the mod works

`PDThrottle/Scripts/main.lua` reads `PDThrottle/config.txt` (Blueprint class path, then seconds between ticks). The Blueprint
classes only exist once a map is loaded, so a few seconds after the player spawns it sets the tick interval of every existing
instance once, and registers for new ones. It never scans periodically: UE4SS's `FindAllOf` walks every object in the game
and stalls it for ~100 ms each time.

If a game update renames the dash screen class, the mod simply stops finding it and changes nothing.

## Tools

For other modders, `tools/` has what found the dash screens:

- `pdprof.c`: a profiler DLL loaded as a `dwmapi.dll` proxy. It hooks `UObject::ProcessInternal` and
  `ProcessLocalScriptFunction` (every Blueprint function call) and writes per-function call counts and inclusive/exclusive
  time on the game thread to `pd_prof.txt` every 10 s. The function addresses are for the current Steam build
  (exe sha1 `21a0e88d2c7ea3ddf05b8088a6bfa47eaeaaa0cf`); UE4SS's log prints them for other builds. Build with
  `zig cc -target x86_64-windows-gnu -shared -O2 -o dwmapi.dll pdprof.c` (it replaces UE4SS's `dwmapi.dll` while profiling).
- `bpreport.py`: diffs two `pd_prof.txt` snapshots into a table of the most expensive Blueprint functions and classes.

## Credits

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT) by the UE4SS team, downloaded by the install script from its release.
- Pacific Drive is by Ironwood Studios. This repo contains no game files.
