{
  description = "BeeOS - ComputerCraft bee automation system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "beeos-dev";

          buildInputs = with pkgs; [
            # Lua 5.1 (CC:Tweaked runtime)
            lua5_1

            # Lua tooling
            luajitPackages.luacheck  # linter

            # Docs site
            python3  # simple HTTP server for testing docs locally

            # Git & GitHub
            git
            gh

            # Node.js (docs site)
            nodejs_22

            # General utilities
            jq
          ];

          shellHook = ''
            echo "BeeOS dev environment loaded"
            echo "  lua5.1    - CC:Tweaked compatible Lua"
            echo "  luacheck  - Lua linter"
            echo "  python3   - docs preview server (python3 -m http.server -d docs)"
            echo "  gh        - GitHub CLI"
          '';
        };
      });
}
