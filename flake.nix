{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs.lib)
        genAttrs
        importTOML
        optionals
        ;

      eachSystem = f: genAttrs
        [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-darwin"
          "x86_64-linux"
        ]
        (system: f nixpkgs.legacyPackages.${system});

      packageFor = pkgs:
        pkgs.rustPlatform.buildRustPackage {
          pname = "bin";
          inherit ((importTOML ./Cargo.toml).package) version;

          src = "${self}";

          cargoLock = {
            lockFile = ./Cargo.lock;
            # allowBuiltinFetchGit = true;
          };

          buildInputs = optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang}/lib";

          GEN_ARTIFACTS = "artifacts";
        };
    in
    {
      packages = eachSystem (pkgs: {
        default = packageFor pkgs;
      });

      nixosModules.default = { config, lib, pkgs, ... }:

        with lib;

        let

          cfg = config.services.bin-paste;

        in
        {
          options.services.bin-paste = {
            enable = mkEnableOption "bin-paste";
            bindAddress = mkOption {
              default = "[::]:8000";
              description = "Address and port to listen on";
              type = types.str;
            };
            package = mkOption {
              default = packageFor pkgs;
              defaultText = "pkgs.bin-paste";
              description = "Which bin derivation to use";
              type = types.package;
            };
            maxPasteSize = mkOption {
              default = 32768;
              description = "Max allowed size of an individual paste";
              type = types.int;
            };
            bufferSize = mkOption {
              default = 1000;
              description = "Maximum amount of pastes to store at a time";
              type = types.int;
            };
          };

          config = mkIf cfg.enable {
            systemd.services.bin-paste = {
              enable = true;
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "exec";
                ExecStart = "${cfg.package}/bin/bin --buffer-size ${toString cfg.bufferSize} --max-paste-size ${toString cfg.maxPasteSize} ${cfg.bindAddress}";
                Restart = "on-failure";

                CapabilityBoundingSet = "";
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                PrivateUsers = true;
                PrivateMounts = true;
                ProtectHome = true;
                ProtectClock = true;
                ProtectProc = "noaccess";
                ProcSubset = "pid";
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectControlGroups = true;
                ProtectHostname = true;
                RestrictSUIDSGID = true;
                RestrictRealtime = true;
                RestrictNamespaces = true;
                LockPersonality = true;
                RemoveIPC = true;
                RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
                SystemCallFilter = [ "@system-service" "~@privileged" ];
              };
            };
          };
        };
    };
}
