# Pacific Drive on Steam Deck: from 12 to 44 fps (60 with frame generation)

> Play-tested on my own Steam Deck LCD. Back up your saves first, and please open an issue if something looks or
> behaves wrong on yours.

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

**60 fps with frame generation (optional, `--framegen`).** With [lsfg-vk](https://github.com/PancakeTAS/lsfg-vk) the game is
capped at 30 and every frame is doubled, so it shows 60. Holding 30 leaves room to make it sharper, so this preset renders at
100% with Epic textures, Medium effects and post-processing and light sharpening. Input lag is that of a 30 fps game.
Same scene, 30 s each, "drops" = moments the real frame rate fell below 30:

| Setup (all with PDThrottle, TAA, 2x frame generation) | Shown fps | Drops below 30 |
|---|---:|---:|
| 67%, Low, sharpen 0.8 | 60.0 | 7 |
| 100%, Low, sharpen 0.3 | 59.8 | 15 |
| **`--framegen`**: 100%, Epic textures, Medium effects + post-processing, sharpen 0.3 | **59.9** | **12** |
| the same + Medium shadows | 53.3 | 230 |

The remaining drops are the game's own CPU spikes and happen at every setting; shadows are the one thing that doesn't fit.

Runs of the same setup vary by about ±2 fps (weather and camera direction change between runs). Lighter places (daytime, the
garage) run faster. The 1% lows are still in the mid 20s, so without frame generation expect some unevenness (see step 4 of the install).

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
   graphics settings: `bash install.sh --no-settings`. For 60 fps with frame generation: `bash install.sh --framegen` (set up
   lsfg-vk first, see below); it prints the launch options to use instead of step 3, and skip step 4.
3. In Steam, right click the game > Properties > **Launch Options**:

   ```
   WINEDLLOVERRIDES="dwmapi=n,b" %command%
   ```

   With [Decky Framegen](https://github.com/xXJSONDeruloXx/Decky-Framegen), put it in front of the fgmod part:

   ```
   WINEDLLOVERRIDES="dwmapi=n,b" ~/fgmod/fgmod %command%
   ```

4. Back in Game Mode, leave the frame rate uncapped. Don't cap at 30 with PDThrottle in: it makes the dash screens do all
   their drawing in one frame, 10 times a second, and a 30 cap turns that into a regular judder (frames of about 53, 20 and
   27 ms in a repeating pattern). If you want a steady 30 without frame generation, use the settings without the mod:
   remove the launch options from step 3, then cap at 30 in the performance overlay (the `...` button).

The settings are the game's own, so you can change any of them in its menu afterwards (Graphics > Advanced has the mirror
options). The script backs up what it changes to `~/pacific-drive-deck-backup`.

**Frame generation setup (`--framegen`):** buy and install
[Lossless Scaling](https://store.steampowered.com/app/993090/Lossless_Scaling/) from Steam (lsfg-vk uses its
`Lossless.dll`), then install lsfg-vk, for example with the Decky plugin
[decky-lsfg-vk](https://github.com/xXJSONDeruloXx/decky-lsfg-vk), and open the plugin once so it writes
`~/.config/lsfg-vk/conf.toml`. The installer adds a `pacific-drive` profile to that file (2x, flow scale 0.5, performance
mode), and the launch options it prints select that profile and cap the game at 30:

```
ENABLE_GAMESCOPE_WSI=0 DXVK_HDR=0 LSFG_PROCESS=pacific-drive VKD3D_FRAME_RATE=30 WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

Don't add the plugin's own `~/lsfg %command%` launch option or Decky Framegen on top, and leave the Steam frame limit off.

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

The installer switches off all of UE4SS's optional hooks (`[Hooks]` in `UE4SS-settings.ini`). With UE4SS's default
hooks on, a new game crashed every time at the first scene where you kick logs out of the way (inside the game's camera
shake code), even with PDThrottle disabled; with them off it plays through. If you installed before 2026-11-03, run the
installer again to get this fix.

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
- [lsfg-vk](https://github.com/PancakeTAS/lsfg-vk) by PancakeTAS, which runs Lossless Scaling's frame generation on Linux
  (optional, installed separately).
- Pacific Drive is by Ironwood Studios. This repo contains no game files.
