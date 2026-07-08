{
  description = "Grapefruit (igf) — mobile security testing suite dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      packages = forAll (pkgs: {
        default = self.packages.${pkgs.system}.igf;

        # Self-contained `igf` CLI: a bun-compiled standalone binary that embeds
        # gui/dist, agent/dist, drizzle and skills.
        #
        # This build fetches deps from npm, frida prebuilt binaries from GitHub,
        # and the radare2 WASI blob — so it needs network at build time and links
        # bun's ICU from the store. A fixed-output derivation can't express
        # either (no store refs allowed), so this is an ordinary derivation and
        # relies on the builder having network access (`sandbox = false`, the
        # default on macOS / Determinate Nix). On sandboxed Linux, build with
        # `--option sandbox false`.
        igf = pkgs.stdenv.mkDerivation {
          pname = "igf";
          version = "1.1.2";
          src = self;

          nativeBuildInputs = with pkgs; [
            bun
            nodejs_22 # prebuild-install (frida napi)
            git
            python3 # node-gyp / better-sqlite3
            cacert # TLS for the network fetches below
            gnutar
            unzip # fetch-r2-wasm unpacks the radare2 zip
          ];

          dontFixup = true; # never strip/patch the bun standalone

          buildPhase = ''
            runHook preBuild
            export HOME=$TMPDIR
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

            bun install
            ( cd agent && bun install && bun run build )
            ( cd gui && bun install && bun run build )
            bun run build:cli
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 build/Release/igf $out/bin/igf
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Grapefruit — open-source mobile security testing suite";
            homepage = "https://github.com/ChiChou/Grapefruit";
            license = licenses.mit;
            mainProgram = "igf";
            platforms = systems;
          };
        };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              bun # runtime + package manager
              nodejs_22 # prebuild-install (frida napi) + node-gyp
              git # submodules
              python3 # node-gyp / better-sqlite3 native build
              pkg-config
            ]
            # ponytail: Linux only — prebuilt frida/wasi binaries need a runnable
            # libstdc++; on NixOS also enable programs.nix-ld for the downloads.
            ++ lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];

          shellHook = ''
            export npm_config_nodedir=${pkgs.nodejs_22}
          '' + pkgs.lib.optionalString pkgs.stdenv.isLinux ''
            export LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH
          '';
        };
      });
    };
}
