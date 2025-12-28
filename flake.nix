{
  description = "A remake of NS-SHAFT";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
  };

  outputs = {nixpkgs, ...}: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  in
    builtins.foldl' nixpkgs.lib.recursiveUpdate {} (
      builtins.map (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};

          libPath = with pkgs;
            lib.makeLibraryPath ([
                libGL
                vulkan-headers
                vulkan-loader
              ]
              ++ lib.optionals stdenv.isLinux [
                libxkbcommon
                wayland
                libdecor

                xorg.libX11
                xorg.libXScrnSaver
                xorg.libXtst
                xorg.libXcursor
                xorg.libXext
                xorg.libXfixes
                xorg.libXi
                xorg.libXrandr

                libjack2
                pipewire
              ]);
        in {
          devShells.${system}.default = pkgs.mkShell {
            packages = with pkgs;
              [
                emscripten
                zig
                sdl3
              ]
              ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [elfkickers kcov]);

            LD_LIBRARY_PATH = libPath;

            shellHook = ''
              source ./tools/sysroot.sh
            '';
          };

          formatter.${system} = pkgs.alejandra;

          packages.${system}.default = pkgs.callPackage ./package.nix {};
        }
      )
      systems
    );
}
