# nix-pvm

A **generic** Nix build of the **PVM host kernel** (Linux 6.7.12 + `CONFIG_KVM_PVM`),
published to a binary cache so any project can run Firecracker / Cloud-Hypervisor
microVMs on cloud VMs that have **no native `/dev/kvm`** (e.g. Hetzner Cloud, and
other providers) without compiling a kernel themselves.

## Generic by design

- The **kernel source** (`virt-pvm/linux@51ee0edb884b`, the PVM patches) is fully
  cloud-agnostic.
- Only the **kernel config** tunes drivers for an environment. The default
  `configs/generic.config` is a broad Fedora-derived config — **validated booting on
  a Hetzner `cx23`** (`/dev/kvm` via `kvm-pvm`) and broad enough to be expected to
  boot on most cloud VMs.
- Need a leaner/different target? Drop a `configs/<name>.config` and expose it as
  another package (see `flake.nix`), or build one ad-hoc with `lib.mkKernel`.

## Layout

| File | Role |
|---|---|
| `kernel.nix` | `mkKernel`: `linuxManualConfig` from the pinned PVM source + a config |
| `configs/generic.config` | Broad config validated on Hetzner cx23 |
| `flake.nix` | `packages.x86_64-linux.pvm-kernel` (+ `lib.mkKernel`); cache in `nixConfig` |
| `.github/workflows/build.yml` | Builds + pushes to Cachix on push |

## One-time cache setup

1. Create a binary cache at <https://app.cachix.org> (e.g. `nix-pvm`).
2. Put its **public key** in `flake.nix` (`extra-trusted-public-keys`).
3. Add a write **auth token** as the repo secret `CACHIX_AUTH_TOKEN`.

## Build

```sh
nix build .#pvm-kernel             # x86_64-linux only (CI or an x86 box)
```

First build ~30–60 min; CI pushes it to the cache so consumers substitute it instantly.

## Consume it (e.g. a Hetzner Cloud VM)

One line — import the module and your host runs the PVM kernel with `/dev/kvm`:

```nix
{
  inputs.nix-pvm.url = "github:fcjr/nix-pvm";

  outputs = { nixpkgs, nix-pvm, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-pvm.nixosModules.default   # ← PVM kernel + pti=off + kvm-pvm
        ./configuration.nix
      ];
    };
  };
}
```

Install it on a fresh Hetzner VM with `nixos-anywhere` (the box is created with any
cloud image, then this flake takes over). After it boots: `ls -l /dev/kvm` shows the
device via `kvm-pvm`.

Add the same `extra-substituters` / `extra-trusted-public-keys` to the consumer so
the kernel is **pulled, not rebuilt** (or set `nixpkgs.follows` and let CI keep the
cache warm). Keep `nixpkgs` aligned with the consumer's so the module set around the
kernel also hits the cache.

Lower-level: `inputs.nix-pvm.packages.x86_64-linux.pvm-kernel` if you want the bare
kernel package.

## License

The packaging in this repo (flake, `kernel.nix`, configs) is [MIT](./LICENSE). The
Linux kernel it builds remains GPL-2.0, licensed by its respective authors.

## Notes

- Long-term we may track `virt-pvm/linux@pvm-612` (6.12.33); 6.7.12 is what's
  *proven*, so we start there.
- Per-provider configs can be added under `configs/` if a specific cloud needs
  driver tuning the generic config lacks.
