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
        in {
          devShells.${system}.default = pkgs.mkShell {
            packages = with pkgs;
              [
                zig
              ]
              ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [kcov]);
          };

          formatter.${system} = pkgs.alejandra;
        }
      )
      systems
    );
}
