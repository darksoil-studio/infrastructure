{
  description = "";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    cachix-deploy-flake.url = "github:cachix/cachix-deploy-flake";
    srvos = {
      url = "github:numtide/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aon.url = "github:darksoil-studio/always-online-nodes";
    demo-launcher.url = "github:darksoil-studio/demo-launcher/v0.2.14";
    dash-chat.url = "github:darksoil-studio/dash-chat/v0.2.8";
  };

  outputs = inputs@{ nixpkgs, cachix-deploy-flake, srvos, disko, ... }:
    let
      # change these 
      machineName = "aon1";
      sshPubKeys = {
        guillem =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDTE+RwRfcG3UNTOZwGmQOKd5R+9jN0adH4BIaZvmWjO guillem.cordoba@gmail.com";
      };
      bootstrapServerUrl = "http://157.180.93.55:8888";
      signalServerUrl = "ws://157.180.93.55:8888";

      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      common = system: rec {
        pkgs = nixpkgs.legacyPackages.${system};
        cachix-deploy-lib = cachix-deploy-flake.lib pkgs;
        modules = [
          srvos.nixosModules.hardware-hetzner-cloud
          srvos.nixosModules.server
          srvos.nixosModules.mixins-systemd-boot
          disko.nixosModules.disko
          (import ./../../disko-hetzner-cloud.nix { disks = [ "/dev/sda" ]; })
          ({
            system.stateVersion = "24.11";

            services.cachix-agent.enable = true;
            # boot.loader.efi.canTouchEfiVariables = true;
            networking.hostName = machineName;
            users.users.root.openssh.authorizedKeys.keys =
              builtins.attrValues sshPubKeys;
            services.openssh.settings.PermitRootLogin = "without-password";
          })
        ];
        bootstrapNixOS = lib.nixosSystem { inherit system modules; };
      };
    in {
      nixosConfigurations.${machineName} =
        (common "x86_64-linux").bootstrapNixOS;

      packages = forAllSystems (system:
        let inherit (common system) cachix-deploy-lib modules;
        in {

          default = cachix-deploy-lib.spec {
            agents = {
              "${machineName}" = cachix-deploy-lib.nixos {
                # here comes all your NixOS configuration
                imports = modules;

                config = let
                  aon = inputs.aon.outputs.builders.${system}.aon-for-happs {
                    happs = [
                      inputs.demo-launcher.outputs.packages."x86_64-linux".file-storage-provider_happ
                      inputs.dash-chat.outputs.packages."x86_64-linux".dash_chat_happ
                    ];
                  };
                in {
                  systemd.services.aon1 = {
                    enable = true;
                    path = [ aon ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      ExecStart =
                        "${aon}/bin/always-online-node --data-dir /root/aon1/v0.2.14 --bootstrap-url ${bootstrapServerUrl} --signal-url ${signalServerUrl}";
                      RuntimeMaxSec = "3600"; # Restart every hour

                      Restart = "always";
                      RestartSec = 10;
                    };
                  };
                  systemd.services.aon2 = {
                    enable = true;
                    path = [ aon ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      ExecStart =
                        "${aon}/bin/always-online-node --data-dir /root/aon2/v0.2.14 --bootstrap-url ${bootstrapServerUrl} --signal-url ${signalServerUrl}";
                      RuntimeMaxSec = "3600"; # Restart every hour

                      Restart = "always";
                      RestartSec = 10;
                    };
                  };
                };
              };
            };
          };
        });

      devShells = forAllSystems (system:
        let inherit (common system) pkgs;
        in {
          default = pkgs.mkShell {
            buildInputs =
              [ cachix-deploy-flake.packages.${system}.bootstrapHetzner ];
          };
        });
    };
}
