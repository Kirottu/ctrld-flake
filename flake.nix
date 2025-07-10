{
  description = "A highly configurable, multi-protocol DNS forwarding proxy";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      fsys =
        f:
        nixpkgs.lib.attrsets.genAttrs [
          "x86_64-linux"
          "armv7l-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ] (s: f s);
    in
    {
      formatter = fsys (a: nixpkgs.legacyPackages.${a}.alejandra);
      packages = fsys (
        a:
        let
          pkgs = nixpkgs.legacyPackages.${a};
          pkg = pkgs.buildGoModule rec {
            name = "ctrld";
            version = "1.4.4";
            src = pkgs.fetchFromGitHub {
              owner = "Control-D-Inc";
              repo = "ctrld";
              rev = "v${version}";
              hash = "sha256-S/mBDrLhvkO/vULYafLUAyOFsF4Rt5j72BKop0dV6Lw=";
            };
            vendorHash = "sha256-AVR+meUcjpExjUo7J1U6zUPY2B+9NOqBh7K/I8qrqL4=";
            proxyVendor = true;
            subPackages = [ "cmd/ctrld" ];
            meta.mainProgram = "ctrld";
            # doCheck = false;
          };
        in
        {
          ctrld = pkg;
          default = pkg;
        }
      );
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.ctrld;
        in
        {
          options.services.ctrld = {
            enable = lib.mkEnableOption "Enable the ctrld service";
            package = lib.mkPackageOption self.packages.${pkgs.system} "ctrld" { };
            settings = lib.mkOption {
              type = with lib.types; either attrs path;
              default = {
                listener = {
                  "0" = {
                    ip = "0.0.0.0";
                    port = 53;
                  };
                };
                upstream = {
                  "0" = {
                    type = "doh";
                    endpoint = "https://freedns.controld.com/p2";
                    timeout = 5000;
                  };
                };
              };
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [
              cfg.package
            ];
            systemd.services.ctrld = {
              enable = true;
              after = [ "network.target" ];
              before = [ "nss-lookup.target" ];
              wantedBy = [ "multi-user.target" ];
              restartTriggers = [ cfg.package ];
              serviceConfig = {
                Type = "exec";
                Restart = "always";
                RestartSec = 5;

                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [ "/var/run" ];

                RestrictAddressFamilies = [
                  "AF_UNIX"
                  "AF_INET"
                  "AF_INET6"
                  "AF_NETLINK"
                ];
                AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
                SystemCallArchitectures = "native";
                SystemCallFilter = "@system-service";

                MemoryDenyWriteExecute = true;
                ProtectControlGroups = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectClock = true;

                RestrictNamespaces = true;
                RestrictRealtime = true;
                PrivateDevices = true;
                LockPersonality = true;

                NoNewPrivileges = true;
                RestrictSUIDSGID = true;

                ExecStart =
                  let
                    path =
                      if !builtins.isAttrs cfg.settings then
                        cfg.settings
                      else
                        (pkgs.formats.toml { }).generate "ctrld.toml" cfg.settings;
                  in
                  "${lib.getExe cfg.package} run --config ${path}";
              };
            };
          };
        };

      nixosModules.ctrld = self.nixosModules.default;
    };
}
