{
  description = "Generic PVM host kernel (Linux 6.7.12 + CONFIG_KVM_PVM) for cloud VMs without native KVM";

  # Consumers add these so they SUBSTITUTE the prebuilt kernel instead of compiling.
  nixConfig = {
    extra-substituters = [ "https://nix-pvm.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-pvm.cachix.org-1:Nf9cU+dJIq7XpVPE9SMD4UWeXqO1u0U4m6ApnN3CtRg="
    ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Build the kernel with any config. The source is cloud-agnostic.
      mkKernel = config: import ./kernel.nix { inherit pkgs config; lib = nixpkgs.lib; };
    in
    {
      packages.${system} = {
        # Broad config — validated booting on Hetzner cx23, expected to work on most
        # cloud VMs. Add configs/<provider>.config + a line here to specialize.
        pvm-kernel = mkKernel ./configs/generic.config;
        default = self.packages.${system}.pvm-kernel;
      };

      # Reusable builder so consumers can build with their own config if needed.
      lib.mkKernel = { pkgs, config }: import ./kernel.nix { inherit pkgs config; lib = pkgs.lib; };

      # Drop-in NixOS module: import this and your host runs the PVM kernel with
      # /dev/kvm available — no native nested virt needed. PVM is x86_64-only.
      nixosModules.default =
        { pkgs, ... }:
        {
          boot.kernelPackages = pkgs.linuxPackagesFor self.packages.${system}.pvm-kernel;
          # PVM is incompatible with page-table isolation (no-op on Meltdown-immune CPUs).
          boot.kernelParams = [ "pti=off" ];
          # kvm_pvm replaces kvm_intel as the KVM backend.
          boot.kernelModules = [ "kvm-pvm" ];
          boot.blacklistedKernelModules = [ "kvm_intel" ];

          # Wire the host to substitute the prebuilt kernel (compiling it is ~1h+).
          # These append to the defaults, so cache.nixos.org still applies.
          nix.settings.substituters = [ "https://nix-pvm.cachix.org" ];
          nix.settings.trusted-public-keys = [
            "nix-pvm.cachix.org-1:Nf9cU+dJIq7XpVPE9SMD4UWeXqO1u0U4m6ApnN3CtRg="
          ];
        };
    };
}
