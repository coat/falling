{
  callPackage,
  copyDesktopItems,
  makeDesktopItem,
  lib,
  stdenv,
  autoPatchelfHook,
  elfkickers,
  sdl3,
  zig,
}:
stdenv.mkDerivation (
  finalAttrs: {
    name = "falling";
    version = "0.0.1";
    src = lib.cleanSource ./.;
    nativeBuildInputs =
      [
        autoPatchelfHook
        copyDesktopItems
        zig.hook
      ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [elfkickers];

    buildInputs = [sdl3];

    deps = callPackage ./build.zig.zon.nix {name = "${finalAttrs.name}-${finalAttrs.version}";};

    preBuild = ''
      export NIX_CFLAGS_COMPILE="-isystem ${sdl3.dev}/include"
      unset C_INCLUDE_PATH
      unset CPATH
      unset CPLUS_INCLUDE_PATH
      unset NIX_CFLAGS_LINK
    '';

    zigBuildFlags = [
      "-Doptimize=ReleaseFast"
      "-Dlink_sdl"
      "--color off"
      "--system"
      "${finalAttrs.deps}"
    ];

    desktopItems = [
      (makeDesktopItem {
        name = "com.sadbeast.falling";
        desktopName = "Falling";
        exec = "falling";
        icon = "falling";
        categories = ["Game" "ArcadeGame"];
      })
    ];

    postInstall = ''
      install -Dm644 assets/icon.png $out/share/icons/hicolor/128x128/apps/falling.png
    '';

    meta = {
      mainProgram = finalAttrs.name;
      license = lib.licenses.mit;
    };
  }
)
