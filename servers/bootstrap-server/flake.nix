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

    kitsune2.url = "github:holochain/kitsune2/v0.1.6";
  };

  outputs = inputs@{ nixpkgs, cachix-deploy-flake, srvos, disko, ... }:
    let
      # change these 
      machineName = "bootstrap-server";
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
                imports = modules;

                config = {
                  # here comes all your NixOS configuration
                  systemd.services.bootstrap-server = let
                    bootstrap-server =
                      inputs.kitsune2.outputs.packages.${system}.bootstrap-srv;

                  in {
                    enable = true;
                    path = [ bootstrap-server ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      ExecStart =
                        "${bootstrap-server}/bin/kitsune2-bootstrap-srv --production";
                      # RuntimeMaxSec = "3600"; # Restart every hour

                      Restart = "always";
                      RestartSec = 5;
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
