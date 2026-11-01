{
  description = "systema - a neofetch-style system information tool";

  inputs.zig2nix.url = "github:Cloudef/zig2nix";

  outputs =
    { self, zig2nix, ... }:
    let
      # `minimum_zig_version` in build.zig.zon is the single source of truth for
      # the toolchain, so this file never has to be bumped alongside it.
      zon = builtins.readFile ./build.zig.zon;
      zonFlat = builtins.replaceStrings [ "\n" "\r" ] [ " " " " ] zon;
      minZig = builtins.match ".*\\.minimum_zig_version[[:space:]]*=[[:space:]]*\"([^\"]+)\".*" zonFlat;
      zigAttr =
        if minZig == null then
          throw "flake.nix: build.zig.zon does not declare minimum_zig_version"
        else
          "zig-" + builtins.replaceStrings [ "." ] [ "_" ] (builtins.head minZig);
    in
    zig2nix.inputs.flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        # Without this the failure is "attribute 'zig-0_17_0' missing", which
        # says nothing about what to do about it.
        zig =
          zig2nix.outputs.packages.${system}.${zigAttr}
            or (throw "flake.nix: zig2nix has no ${zigAttr}; run `nix flake update zig2nix`");

        env = zig2nix.outputs.zig-env.${system} { inherit zig; };
        lib = env.pkgs.lib;

        # Shared by every variant. pname and version come from build.zig.zon, so
        # they are not repeated here.
        base = {
          src = self;
          meta = {
            description = "A neofetch-style system information tool";
            homepage = "https://github.com/badwatt/systema";
            mainProgram = "systema";
            platforms = lib.platforms.linux;
            # TODO: add `license` once the repository has a LICENSE file.
          };
        };

        # Statically linked against musl: one file, no loader, and the fastest
        # startup measured here (~2.2x the glibc dynamic build).
        systema = env.package (
          base
          // {
            zigPreferMusl = true;
            zigDisableWrap = true;
          }
        );

        # Kept for the name it has always had; both variants are identical now
        # that the glibc build is no longer shipped.
        default = systema;
        foreign = systema;

        appFor = pkg: {
          type = "app";
          program = "${pkg}/bin/systema";
          meta = pkg.meta;
        };
      in
      {
        packages = {
          inherit default foreign;
        };

        checks.default = default;

        formatter = env.pkgs.nixfmt;

        # Static binaries for other architectures: Zig cross-compiles them, so no
        # binfmt registration or remote builder is involved.
        legacyPackages.cross = {
          x86_64-linux-musl = env.package (
            base
            // {
              zigPreferMusl = true;
              zigTarget = "x86_64-linux-musl";
            }
          );
          aarch64-linux-musl = env.package (
            base
            // {
              zigPreferMusl = true;
              zigTarget = "aarch64-linux-musl";
            }
          );
        };

        apps = {
          # `nix run .` runs the packaged binary; `nix run .#dev` compiles and runs.
          default = appFor default;
          static = appFor foreign;
          dev = env.app [ ] "zig build run --release=fast -- \"$@\"";
          build = env.app [ ] "zig build --release=fast \"$@\"";
          # No --release: the tests must keep runtime safety checks on.
          test = env.app [ ] "zig build test -- \"$@\"";
          zig2nix = env.app [ ] "zig2nix \"$@\"";
        };

        devShells.default = env.mkShell { };
      }
    );
}
