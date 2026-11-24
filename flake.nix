{
  description = "A remake of NS-SHAFT";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  in
    builtins.foldl' nixpkgs.lib.recursiveUpdate {} (
      builtins.map (
        system: let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              android_sdk.accept_license = true;
            };
          };

          androidComposition = pkgs.androidenv.composeAndroidPackages {
            cmdLineToolsVersion = "20.0";
            platformToolsVersion = "37.0.3";
            buildToolsVersions = ["36.1.0"];
            platformVersions = ["35"]; # Android 15
            ndkVersions = ["29.0.14206865"];
            includeNDK = true;
            includeEmulator = false;
            includeSystemImages = false;
            includeSources = false;
          };

          androidSdk = androidComposition.androidsdk;

          libs = with pkgs;
            [
              libGL
              vulkan-headers
              vulkan-loader
            ]
            ++ lib.optionals stdenv.isLinux [
              libgbm
              libxkbcommon
              wayland
              libdecor
              libdrm
              systemdLibs

              libx11
              libxscrnsaver
              libxtst
              libxcursor
              libxext
              libxfixes
              libxi
              libxrandr

              libjack2
              pipewire
            ];

          libPath = with pkgs;
            lib.makeLibraryPath libs;
        in {
          devShells.${system} = {
            default = pkgs.mkShell {
              LD_LIBRARY_PATH = libPath;
              ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
              JAVA_HOME = pkgs.jdk17.home;

              packages = with pkgs;
                [
                  androidSdk
                  emscripten
                  jdk17
                  sdl3
                  zip
                  zig
                ]
                ++ (pkgs.lib.optionals stdenv.hostPlatform.isLinux [elfkickers kcov]);

              shellHook = ''
                source ./tools/sysroot.sh
              '';
            };

            # Only what `zig build -Dandroid` needs, for CI: skips emscripten and
            # the sysroot the default shell builds on entry.
            android = pkgs.mkShell {
              ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
              JAVA_HOME = pkgs.jdk17.home;

              packages = [androidSdk pkgs.jdk17 pkgs.zig];
            };
          };

          formatter.${system} = pkgs.alejandra;

          packages.${system}.default = pkgs.callPackage ./package.nix {};
        }
      )
      systems
    );
}
