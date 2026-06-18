# nix-pvm

A **generic** Nix build of the **PVM kernels** (Linux 6.7.12), published to a binary
cache so any project can run Cloud-Hypervisor microVMs on cloud VMs that have **no
native `/dev/kvm`** (e.g. Hetzner Cloud, and other providers) without compiling a
kernel themselves. Two packages, both from one source:

- **`pvm-kernel`** — the **host** kernel (`CONFIG_KVM_PVM`). Run it on the cloud VM and
  `kvm-pvm` exposes `/dev/kvm` with no hardware nested virt.
- **`pvm-guest-kernel`** — the **guest** kernel (`CONFIG_PVM_GUEST` + `CONFIG_PVH`) that
  the microVM boots. A PVM guest runs paravirtualized, so a stock kernel can't boot
  under PVM — the hypervisor must boot this one.

## Generic by design

- The **kernel source** (`virt-pvm/linux@51ee0edb884b`, the PVM patches) is fully
  cloud-agnostic and carries both host and guest support.
- Only the **kernel config** tunes a build. `configs/generic.config` is a broad
  Fedora-derived host config — **validated booting on a Hetzner `cx23`** (`/dev/kvm`
  via `kvm-pvm`); `configs/guest.config` is the lean PVM guest config (virtio + serial
  + ext4, `CONFIG_PVH` for cloud-hypervisor's boot protocol).
- Need a leaner/different target? Drop a `configs/<name>.config` and expose it as
  another package (see `flake.nix`), or build one ad-hoc with `lib.mkKernel`.

## Layout

| File | Role |
|---|---|
| `kernel.nix` | `mkKernel`: `linuxManualConfig` from the pinned PVM source + a config |
| `configs/generic.config` | Broad **host** config validated on Hetzner cx23 |
| `configs/guest.config` | Lean **guest** config the microVM boots (PVM guest + PVH) |
| `flake.nix` | `packages.x86_64-linux.{pvm-kernel,pvm-guest-kernel}` (+ `lib.mkKernel`); cache in `nixConfig` |
| `.github/workflows/build.yml` | Builds both kernels + pushes to Cachix on push |

## One-time cache setup

1. Create a binary cache at <https://app.cachix.org> (e.g. `nix-pvm`).
2. Put its **public key** in `flake.nix` (`extra-trusted-public-keys`).
3. Add a write **auth token** as the repo secret `CACHIX_AUTH_TOKEN`.

## Build

```sh
nix build .#pvm-kernel             # host kernel  (x86_64-linux only — CI or an x86 box)
nix build .#pvm-guest-kernel       # guest kernel (the microVM boots this)
```

First host build ~1h, guest ~20 min; CI builds both and pushes them to the cache so
consumers substitute them instantly.

## Consume it (e.g. a Hetzner Cloud VM)

Add the input and import the module — that's the whole integration. The module sets
the PVM kernel, `pti=off`, `kvm-pvm`, **and** points the host at this cache, so future
rebuilds pull the prebuilt kernel instead of compiling it:

```nix
{
  inputs.nix-pvm.url = "github:fcjr/nix-pvm";

  outputs = { nixpkgs, nix-pvm, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-pvm.nixosModules.default   # ← PVM kernel + pti=off + kvm-pvm + cache
        ./configuration.nix
      ];
    };
  };
}
```

After it boots, `ls -l /dev/kvm` shows the device via `kvm-pvm`.

### Keep the cache hit: don't make nix-pvm follow your nixpkgs

`nix-pvm` pins its own `nixpkgs` (in `flake.lock`) and CI builds + caches the kernel
against *exactly* that pin. If you override it with
`inputs.nix-pvm.inputs.nixpkgs.follows = "nixpkgs"`, the kernel is rebuilt against
**your** nixpkgs — a different derivation hash, so it's a cache miss and compiles
locally (~1h+). Leave nix-pvm's nixpkgs as-is and the prebuilt kernel substitutes
byte-for-byte. Run `nix flake update nix-pvm` when you want a newer build.

### The first build needs the cache trusted up front

The module configures the cache on the *resulting* system, but the **first** build
(e.g. `nixos-anywhere`, or any `nix build` before that config is live) runs on a
builder that doesn't trust the cache yet. Nix only reads `nixConfig` from the flake
you build — not from dependencies — so add the cache to **your own** flake:

```nix
{
  nixConfig = {
    extra-substituters = [ "https://nix-pvm.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-pvm.cachix.org-1:Nf9cU+dJIq7XpVPE9SMD4UWeXqO1u0U4m6ApnN3CtRg="
    ];
  };
  inputs.nix-pvm.url = "github:fcjr/nix-pvm";
  # outputs = ...
}
```

then build with `--accept-flake-config`. Equivalently, drop the same two lines into
the builder's `/etc/nix/nix.conf` (or `nix.settings` if the builder is NixOS).

Install on a fresh Hetzner VM with `nixos-anywhere` (created from any cloud image,
then this flake takes over).

### Boot a microVM (the guest kernel)

The module above configures the **host**. To boot a guest, point your hypervisor at
the **guest** kernel package — e.g. with cloud-hypervisor:

```sh
cloud-hypervisor \
  --kernel ${nix-pvm.packages.x86_64-linux.pvm-guest-kernel}/bzImage \
  --initramfs <your-initramfs> \
  --cmdline "console=ttyS0" \
  --cpus boot=1 --memory size=512M --serial tty --console off
```

The guest kernel is built with `CONFIG_PVH`, so cloud-hypervisor boots it via its PVH
entry point. Both kernels come from the same cache, so neither is ever compiled
locally.

Lower-level: the bare packages are `inputs.nix-pvm.packages.x86_64-linux.pvm-kernel`
(host) and `…pvm-guest-kernel` (guest).

## License

The packaging in this repo (flake, `kernel.nix`, configs) is [MIT](./LICENSE). The
Linux kernel it builds remains GPL-2.0, licensed by its respective authors.

## Notes

- Long-term we may track `virt-pvm/linux@pvm-612` (6.12.33); 6.7.12 is what's
  *proven*, so we start there.
- Per-provider configs can be added under `configs/` if a specific cloud needs
  driver tuning the generic config lacks.
