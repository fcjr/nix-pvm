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

  # Neutralize the Fedora module-signing key path so the nixpkgs build generates
  # its own; everything else in the config is left as-validated.
  configfile = pkgs.runCommand "pvm-host-${version}.config" { } ''
    sed -E 's@^(CONFIG_MODULE_SIG_KEY)=.*@\1=""@' ${config} > $out
  '';
in
pkgs.linuxManualConfig {
  inherit version src configfile;
  allowImportFromDerivation = true;
}
