{
  description = "Oxion ISP Platform - Hermetic dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Gleam + Erlang/OTP
            gleam
            erlang_28
            rebar3

            # Node.js for frontend + scripts
            nodejs_22
            pnpm

            # Bazel
            bazelisk

            # Just command runner
            just

            # Git
            git
          ];

          shellHook = ''
            echo "=== Oxion Dev Environment ==="
            echo "Gleam:  $(gleam --version)"
            echo "Erlang: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell)"
            echo "Node:   $(node --version)"
            echo "Bazel:  $(bazel --version | head -1)"
            echo "============================"
          '';
        };
      });
}
