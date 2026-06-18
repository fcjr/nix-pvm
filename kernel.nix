# Build a PVM host kernel (Linux 6.7.12 + CONFIG_KVM_PVM) from the generic PVM
# source with a chosen kernel config. The source is cloud-agnostic; only the
# config tunes drivers for a given environment.
#
#   config: path to a full kernel .config (defaults to the broad generic one).
{
  pkgs,
  lib,
  config ? ./configs/generic.config,
}:
let
  version = "6.7.12";

  src = pkgs.fetchFromGitHub {
    owner = "virt-pvm";
    repo = "linux";
    rev = "51ee0edb884b3372c168f58244de58507c99b2f7";
    hash = "sha256-QO1nBtG/IIfVyEnisbwUyy76gPTgLqJrRsEwCZHWoLg=";
  };

  # Tweaks needed to build this distro config under nixpkgs (everything else as-validated):
  #  - MODULE_SIG_KEY: drop the Fedora cert path so the build generates its own key.
  #  - UAPI_HEADER_TEST: the PVM patch's exported asm/pvm_para.h uses kernel types
  #    (u64/u32) so it fails the self-contained-header lint. The kernel builds fine;
  #    only the lint trips, so disable it (matches the prebuilt build).
  configfile = pkgs.runCommand "pvm-host-${version}.config" { } ''
    sed -E \
      -e 's@^(CONFIG_MODULE_SIG_KEY)=.*@\1=""@' \
      -e 's@^CONFIG_UAPI_HEADER_TEST=.*@# CONFIG_UAPI_HEADER_TEST is not set@' \
      ${config} > $out
  '';
in
pkgs.linuxManualConfig {
  inherit version src configfile;
  allowImportFromDerivation = true;
}
