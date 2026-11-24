#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/falling"
cd "$GAMEDIR"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

$ESUDO chmod +x "$GAMEDIR/falling.aarch64"

# control.txt exports SDL2-generated mappings which don't line up with SDL3's
# joystick enums
unset SDL_GAMECONTROLLERCONFIG
unset SDL_GAMECONTROLLERCONFIG_FILE

type pm_platform_helper >/dev/null 2>&1 && pm_platform_helper "$GAMEDIR/falling.aarch64"
unset SDL_GAMECONTROLLERCONFIG SDL_GAMECONTROLLERCONFIG_FILE

# export FALLING_PRESENT=composite

"$GAMEDIR/falling.aarch64"

type pm_finish >/dev/null 2>&1 && pm_finish
exit 0
