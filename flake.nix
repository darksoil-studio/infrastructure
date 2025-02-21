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
    demo-launcher.url = "github:darksoil-studio/demo-launcher";

  };

  outputs = { nixpkgs, cachix-deploy-flake, srvos, disko, demo-launcher, ... }:
    let
      # change these 
      machineName = "file-storage-provider-aon";
      sshPubKeys = {
        guillem =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDTE+RwRfcG3UNTOZwGmQOKd5R+9jN0adH4BIaZvmWjO guillem.cordoba@gmail.com";
      };

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
          (import ./disko-hetzner-cloud.nix { disks = [ "/dev/sda" ]; })
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
                imports = modules;

                config = {
                  # here comes all your NixOS configuration
                  systemd.services.aon = let
                    aon =
                      demo-launcher.outputs.packages."x86_64-linux".file-storage-provider;
                  in {
                    enable = true;
                    path = [ aon ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      ExecStart =
                        "${aon}/bin/always-online-node --data-dir /root --lan-only";
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
