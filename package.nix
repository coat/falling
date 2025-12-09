{
  callPackage,
  lib,
  stdenvNoCC,
  elfkickers,
  sdl3,
  zig,
}: let
  zig_hook = zig.hook.overrideAttrs {
    zig_default_flags = "-Dcpu=baseline -Doptimize=ReleaseSmall -Dsystem_sdl=true --color off";
  };
in
  stdenvNoCC.mkDerivation (
    finalAttrs: {
      name = "falling";
      version = "0.0.1";
      src = lib.cleanSource ./.;
      nativeBuildInputs =
        [
          zig_hook
        ]
        ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [elfkickers];

      buildInputs = [sdl3];

      deps = callPackage ./build.zig.zon.nix {name = "${finalAttrs.name}-${finalAttrs.version}";};

      zigBuildFlags = [
        "--system"
        "${finalAttrs.deps}"
        "--search-prefix"
        "${sdl3}"
        "--search-prefix"
        "${sdl3.dev}"
      ];

      meta = {
        mainProgram = finalAttrs.name;
        license = lib.licenses.mit;
      };
    }
  )
