# falling

A clone of [NS-SHAFT](https://www.nagi-p.com/v1/eng/nsshaft.html) written in Zig and SDL3.

## playing

[Play online](https://sadbeast.com/falling) or [download](https://sadbeast.com/falling/download.html) a static binary for your operating system.

If you have Nix installed, try `nix run github:coat/falling#`.

## building

### Requirements

1. Zig 0.15.2
2. emscripten (optional to build web version)
3. SDL3 provided by your system **or** all of SDL3's dependencies to build and statically include SDL3 in the binary.

Instead of installing above dependencies, just install Nix and either run `nix develop` or also install direnv and run `direnv allow` to make your dreams come true.

`zig build -Dtarget=ReleaseSmall` and the game will be in `zig-out/bin/falling`.

If you want to link against the system provided SDL (recommended for Linux), add the `-Dsystem_sdl` option to the above command to build a lil' binary.

### emscripten

Ensure sysroot has been built by running `source tools/sysroot.sh` from the project's root directory. This will be taken care of for you if using the provided Nix devShell.

Then run `zig build -Dtarget=wasm32-emscripten --sysroot "$EM_CACHE/sysroot" run` to open a browser with the game running.

## Acknowledgements

- [breakout game](https://github.com/castholm/zig-examples/tree/master/breakout) from zig-examples.

- Uses the [1-bit](https://kenney.nl/assets/tag:1-bit) collection of assets from Kenney.

- Uses [dustbyte](https://lospec.com/palette-list/dustbyte) 4-color palette.

- A [reverse engineered version](https://github.com/cdfmr/NS-SHAFT-NS-TOWER) of NS-SHAFT.

- [NAGI-P SOFT](https://www.nagi-p.com/v1/eng/) for making a great shareware game.
