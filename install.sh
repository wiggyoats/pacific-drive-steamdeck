#!/usr/bin/env bash
# Pacific Drive on Steam Deck: faster settings + a UE4SS mod that stops the car's dash screens re-rendering every frame
#
#   ./install.sh [--framegen] [--scale PERCENT] [--no-settings] [--game-dir DIR]   install (or update)
#      --framegen: 60 fps with lsfg-vk frame generation (needs lsfg-vk set up, see the README): the game is capped
#                  at 30 and every frame is doubled, so it can render sharper (100% scale, Epic textures)
#      --scale: render scale, 50 to 100 (default 67, or 100 with --framegen)
#      --no-settings: only install the mod, leave the graphics settings alone
#   ./install.sh --uninstall [--game-dir DIR]                         remove it and restore the backup
#
# Run it in Desktop Mode with the game closed. It installs, into the game's PenDriverPro/Binaries/Win64 folder:
#   - UE4SS v3.0.1 (Unreal mod loader, downloaded from its official GitHub release)
#   - PDThrottle (the Lua mod from this repo)
# and sets the graphics settings in GameUserSettings.ini: Low preset, cheaper car mirrors, no headlight shadows,
# render scale 67%. You then add a launch option in Steam, see the README.
set -euo pipefail

APPID=1458140
REPO_RAW=${REPO_RAW:-'https://raw.githubusercontent.com/wiggyoats/pacific-drive-steamdeck/main'}
UE4SS_URL=${UE4SS_URL:-'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip'}
UE4SS_SHA='4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec'

# Every file and folder we add to Win64 (removed again by --uninstall)
OURS=(dwmapi.dll UE4SS.dll UE4SS-settings.ini UE4SS.log Mods/PDThrottle)

say() { printf '\e[1m[pacific-drive-deck]\e[0m %s\n' "$*"; }
die() { printf '[pacific-drive-deck] error: %s\n' "$*" >&2; exit 1; }

SCALE=""; SETTINGS=1; GAME_DIR=""; UNINSTALL=0; FRAMEGEN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --scale) SCALE=$2; shift ;;
        --no-settings) SETTINGS=0 ;;
        --framegen) FRAMEGEN=1 ;;
        --game-dir) GAME_DIR=$2; shift ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done
[ -n "$SCALE" ] || { [ $FRAMEGEN = 1 ] && SCALE=100 || SCALE=67; }
[[ "$SCALE" =~ ^[0-9]+$ ]] && [ "$SCALE" -ge 50 ] && [ "$SCALE" -le 100 ] || die "--scale must be 50 to 100"

STEAM="$HOME/.local/share/Steam"
[ -d "$STEAM/steamapps" ] || STEAM="$HOME/.steam/steam"
LIBS=("$STEAM" $(grep -o '"path"[[:space:]]*"[^"]*"' "$STEAM/steamapps/libraryfolders.vdf" 2>/dev/null | cut -d'"' -f4))

# --- find the game and its Proton prefix (any Steam library, internal or SD card) ---
if [ -z "$GAME_DIR" ]; then
    for lib in "${LIBS[@]}"; do
        d="$lib/steamapps/common/Pacific Drive"
        [ -f "$d/PenDriverPro/Binaries/Win64/PenDriverPro-Win64-Shipping.exe" ] && { GAME_DIR="$d"; break; }
    done
fi
[ -n "$GAME_DIR" ] || die "game not found, pass --game-dir \"/path/to/Pacific Drive\""
WIN64="$GAME_DIR/PenDriverPro/Binaries/Win64"
[ -f "$WIN64/PenDriverPro-Win64-Shipping.exe" ] || die "no PenDriverPro-Win64-Shipping.exe in $WIN64"
PFX=""
for lib in "${LIBS[@]}"; do
    [ -d "$lib/steamapps/compatdata/$APPID/pfx" ] && { PFX="$lib/steamapps/compatdata/$APPID/pfx"; break; }
done
CONFIG="$PFX/drive_c/users/steamuser/AppData/Local/PenDriverPro/Saved/Config/WindowsNoEditor"
BACKUP="$HOME/pacific-drive-deck-backup"
LSFG_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/lsfg-vk/conf.toml"
say "game: $GAME_DIR"

pgrep -f PenDriverPro-Win64-Shipping.exe >/dev/null && die "close the game first"

# lsfg-vk profile for --framegen (picked by LSFG_PROCESS=pacific-drive in the launch options). lsfg_profile add|remove
lsfg_profile() {
    python3 - "$LSFG_CONF" "$1" <<'PY'
import re, sys
p, mode = sys.argv[1], sys.argv[2]
t = open(p).read()
t = re.sub(r"\n*# BEGIN pacific-drive-steamdeck\n.*?# END pacific-drive-steamdeck\n", "\n", t, flags=re.S)
if mode == "add":
    t = t.rstrip("\n") + "\n\n" + "\n".join([
        "# BEGIN pacific-drive-steamdeck",
        "[[game]]",
        "# Pacific Drive: 2x frame generation on a 30 fps base",
        'exe = "pacific-drive"',
        "multiplier = 2",
        "flow_scale = 0.5",
        "performance_mode = true",
        "hdr_mode = false",
        'experimental_present_mode = "fifo"',
        "# END pacific-drive-steamdeck"]) + "\n"
open(p, "w").write(t)
PY
}

# --- uninstall ---
if [ $UNINSTALL = 1 ]; then
    for f in "${OURS[@]}"; do rm -rf "${WIN64:?}/$f"; done
    if [ -f "$BACKUP/mods.txt" ]; then
        cp "$BACKUP/mods.txt" "$WIN64/Mods/mods.txt"
    elif [ -d "$WIN64/Mods" ]; then
        rm -f "$WIN64/Mods/mods.txt"; rmdir "$WIN64/Mods" 2>/dev/null || true
    fi
    if [ -d "$BACKUP/Win64" ]; then
        cp -a "$BACKUP/Win64/." "$WIN64/"
        say "restored the files that were there before from $BACKUP/Win64"
    fi
    if [ -f "$BACKUP/GameUserSettings.ini" ] && [ -n "$PFX" ]; then
        cp "$BACKUP/GameUserSettings.ini" "$CONFIG/GameUserSettings.ini"
        [ -f "$BACKUP/Engine.ini" ] && cp "$BACKUP/Engine.ini" "$CONFIG/Engine.ini"
        say "restored your graphics settings"
    fi
    if [ -f "$LSFG_CONF" ] && grep -q '^# BEGIN pacific-drive-steamdeck' "$LSFG_CONF"; then
        lsfg_profile remove
        say "removed the pacific-drive profile from $LSFG_CONF"
    fi
    say "done. Remove the WINEDLLOVERRIDES part of the launch options in Steam too."
    exit 0
fi

# --- backup (only once, so re-running the installer never overwrites the original backup) ---
if [ ! -d "$BACKUP" ]; then
    mkdir -p "$BACKUP/Win64"
    for f in dwmapi.dll UE4SS.dll UE4SS-settings.ini; do [ -e "$WIN64/$f" ] && cp -a "$WIN64/$f" "$BACKUP/Win64/"; done
    [ -f "$WIN64/Mods/mods.txt" ] && cp "$WIN64/Mods/mods.txt" "$BACKUP/mods.txt"
    [ -n "$PFX" ] && [ -f "$CONFIG/GameUserSettings.ini" ] && cp "$CONFIG/GameUserSettings.ini" "$BACKUP/GameUserSettings.ini"
    say "backed up the files we replace to $BACKUP"
fi
# Engine.ini and the lsfg-vk config are only changed by --framegen (added later, so older backups lack them)
[ -n "$PFX" ] && [ -f "$CONFIG/Engine.ini" ] && [ ! -f "$BACKUP/Engine.ini" ] && cp "$CONFIG/Engine.ini" "$BACKUP/Engine.ini"
if [ $FRAMEGEN = 1 ]; then
    [ -f "$LSFG_CONF" ] || die "lsfg-vk is not set up ($LSFG_CONF is missing), see the README's frame generation section"
    [ -f "$BACKUP/lsfg-conf.toml" ] || cp "$LSFG_CONF" "$BACKUP/lsfg-conf.toml"
fi

# --- downloads ---
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
say "downloading UE4SS v3.0.1"
curl -fL --retry 3 -o "$TMP/ue4ss.zip" "$UE4SS_URL"
echo "$UE4SS_SHA  $TMP/ue4ss.zip" | sha256sum -c --status || die "UE4SS_v3.0.1.zip: checksum mismatch"
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$TMP/ue4ss.zip" "$TMP/ue4ss"

# The mod: from a clone of this repo if the script runs from one, otherwise from GitHub
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$HERE/PDThrottle/Scripts/main.lua" ]; then
    MOD="$HERE/PDThrottle"
else
    MOD="$TMP/PDThrottle"; mkdir -p "$MOD/Scripts"
    curl -fsL --retry 3 -o "$MOD/Scripts/main.lua" "$REPO_RAW/PDThrottle/Scripts/main.lua"
    curl -fsL --retry 3 -o "$MOD/config.txt" "$REPO_RAW/PDThrottle/config.txt"
fi

# --- install ---
cp "$TMP/ue4ss/dwmapi.dll" "$TMP/ue4ss/UE4SS.dll" "$WIN64/"
# UE4SS settings: no debug console windows (they open separate windows under Proton), and none of UE4SS's optional
# hooks: PDThrottle doesn't need them, the Blueprint call hooks add overhead to every Blueprint function call, and with
# the other four on the game crashed every time at the first "kick the logs" scene of a new game (camera shake)
sed -e 's/^ConsoleEnabled = .*/ConsoleEnabled = 0/' -e 's/^GuiConsoleEnabled = .*/GuiConsoleEnabled = 0/' \
    -E -e 's/^(HookProcessInternal|HookProcessLocalScriptFunction|HookInitGameState|HookCallFunctionByNameWithArguments|HookBeginPlay|HookLocalPlayerExec)( *)= .*/\1\2= 0/' \
    "$TMP/ue4ss/UE4SS-settings.ini" > "$WIN64/UE4SS-settings.ini"
mkdir -p "$WIN64/Mods"
rm -rf "$WIN64/Mods/PDThrottle"
cp -a "$MOD" "$WIN64/Mods/PDThrottle"
if [ -f "$WIN64/Mods/mods.txt" ]; then
    # keep any other UE4SS mods the player has; add ours before UE4SS's keybinds line
    if ! grep -q '^PDThrottle' "$WIN64/Mods/mods.txt"; then
        python3 - "$WIN64/Mods/mods.txt" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8-sig", newline="").read()
nl = "\r\n" if "\r\n" in t else "\n"
k = t.find("; Built-in keybinds")
t = t[:k] + "PDThrottle : 1" + nl + nl + t[k:] if k >= 0 else t.rstrip("\r\n") + nl + "PDThrottle : 1" + nl
open(p, "w", encoding="utf-8-sig", newline="").write(t)
PY
    fi
else
    printf 'PDThrottle : 1\n\n; Built-in keybinds, do not move up!\nKeybinds : 0\n' > "$WIN64/Mods/mods.txt"
fi
say "installed UE4SS and PDThrottle"

# --- graphics settings ---
if [ $SETTINGS = 1 ]; then
    if [ -z "$PFX" ] || [ ! -f "$CONFIG/GameUserSettings.ini" ]; then
        say "skipped the graphics settings: start the game once (to the main menu), then run this again"
    else
        python3 - "$CONFIG/GameUserSettings.ini" "$SCALE" "$FRAMEGEN" <<'PY'
import re, sys
p, scale, framegen = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
t = open(p, newline="").read()
crlf = "\r\n" in t  # the game writes Windows line endings; keep them
t = t.replace("\r\n", "\n")
H = "[/Script/PenDriverPro.DrivingGameUserSettings]\n"
def setk(t, k, v):
    if re.search(r"(?m)^" + re.escape(k) + "=", t):
        return re.sub(r"(?m)^" + re.escape(k) + "=.*$", lambda m: k + "=" + v, t)
    if k.startswith("sg."):
        if "[ScalabilityGroups]\n" not in t: t = t.rstrip("\n") + "\n\n[ScalabilityGroups]\n"
        return t.replace("[ScalabilityGroups]\n", "[ScalabilityGroups]\n" + k + "=" + v + "\n", 1)
    if H not in t: t = H + "\n" + t
    return t.replace(H, H + k + "=" + v + "\n", 1)
# Low preset: on the Deck, Epic 12 fps, High 12, Medium 25, Low 25 (before the mirror settings)
for g in "ViewDistance AntiAliasing Shadow PostProcess Texture Effects Foliage Shading".split():
    t = setk(t, "sg." + g + "Quality", "0")
# Low turns anti-aliasing off, which looks very jagged at 67%; TAA costs ~1 fps (FSR 4 Lite via OptiScaler cost ~13)
t = setk(t, "sg.AntiAliasingQuality", "2")
# With frame generation the game only has to hold 30, which leaves room for these (still 60 shown on the Deck);
# Medium shadows did not fit (the 30 fps base broke constantly)
if framegen:
    for g, v in [("Texture", "3"), ("PostProcess", "1"), ("Effects", "1")]:
        t = setk(t, "sg." + g + "Quality", v)
t = setk(t, "sg.ResolutionQuality", "%d.000000" % int(scale))
# The car's mirrors render the scene again; these took Low from 25 to 34 fps
for k, v in [("MirrorResolutionScale", "0.500000"), ("bMirrorGrassRendering", "False"), ("bMirrorFogRendering", "False"),
             ("MirrorShadowQuality", "0"), ("MirrorDrawDistance", "8000"), ("bEnableHeadlightShadowCasters", "False")]:
    t = setk(t, k, v)
open(p, "w", newline="").write(t.replace("\n", "\r\n") if crlf else t)
PY
        say "set Low preset with TAA, cheaper mirrors, no headlight shadows, render scale $SCALE%"
        # Light sharpening against TAA softness (frame generation preset only). The game rewrites Engine.ini on exit
        # and may drop our marker comments, so stray Sharpen lines are removed too
        python3 - "$CONFIG/Engine.ini" "$FRAMEGEN" <<'PY'
import re, sys
p, framegen = sys.argv[1], sys.argv[2] == "1"
try:
    t = open(p, newline="").read()
except FileNotFoundError:
    t = ""
crlf = "\r\n" in t
t = re.sub(r"\n*; BEGIN pacific-drive-steamdeck\n.*?; END pacific-drive-steamdeck\n", "\n", t.replace("\r\n", "\n"), flags=re.S)
t = re.sub(r"(?m)^r\.Tonemapper\.Sharpen=.*\n", "", t)
if framegen:
    t = t.rstrip("\n") + "\n\n; BEGIN pacific-drive-steamdeck\n[SystemSettings]\nr.Tonemapper.Sharpen=0.3\n; END pacific-drive-steamdeck\n"
open(p, "w", newline="").write(t.replace("\n", "\r\n") if crlf else t)
PY
        [ $FRAMEGEN = 1 ] && say "frame generation preset: Epic textures, Medium effects and post-processing, light sharpening"
    fi
fi
if [ $FRAMEGEN = 1 ]; then
    lsfg_profile add
    say "added the pacific-drive profile (2x) to $LSFG_CONF"
fi

if [ $FRAMEGEN = 1 ]; then cat <<EOF

Done. Now in Steam: right click Pacific Drive > Properties > Launch Options:

    ENABLE_GAMESCOPE_WSI=0 DXVK_HDR=0 LSFG_PROCESS=pacific-drive VKD3D_FRAME_RATE=30 WINEDLLOVERRIDES="dwmapi=n,b" %command%

VKD3D_FRAME_RATE=30 caps the game at 30 and lsfg-vk doubles it to 60. Don't also use the Decky plugin's ~/lsfg
launch option or Decky Framegen for this game, and leave Steam's frame limit off.

To undo everything: bash install.sh --uninstall
EOF
exit 0
fi

cat <<EOF

Done. Now in Steam: right click Pacific Drive > Properties > Launch Options:

    WINEDLLOVERRIDES="dwmapi=n,b" %command%

If you use Decky Framegen, put it in front of the fgmod part instead:

    WINEDLLOVERRIDES="dwmapi=n,b" ~/fgmod/fgmod %command%

To undo everything: bash install.sh --uninstall
EOF
