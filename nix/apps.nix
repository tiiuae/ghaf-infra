# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  self,
  ...
}:
let
  decrypt-sops-key =
    pkgs:
    (pkgs.writeShellScript "decrypt-sops-key" ''
      set -eu
      on_err () {
        printf "\n[+] Failed decrypting sops key: VM will boot-up without secrets\n"
        # Wait for user input if stdout is to a terminal (and not to file or pipe)
        if [ -t 1 ]; then
          echo; read -n 1 -srp "Press any key to continue"; echo
        fi
        exit 1
      }
      trap on_err ERR
      if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
        on_err
      fi
      secret="$1"
      todir="$2"
      umask 077; mkdir -p "$todir"
      rm -fr "$todir/ssh_host_ed25519_key"
      tofile="$todir/ssh_host_ed25519_key"
      umask 377
      ${pkgs.lib.getExe pkgs.sops} --extract '["ssh_host_ed25519_key"]' --decrypt "$secret" >"$tofile"
      echo "[+] Decrypted sops key '$tofile'"
    '');

  run-vm-with-share =
    pkgs: cfg: secret:
    (pkgs.writeShellScriptBin "run-vm-with-share" ''
      set -u
      echo "[+] Running '$(realpath "$0")'"
      # Host path of the shr share directory
      sharedir="${cfg.virtualisation.vmVariant.virtualisation.sharedDirectories.shr.source}"
      # See nixpkgs: virtualisation/qemu-vm.nix
      export TMPDIR="$sharedir"
      on_exit () {
        printf "\n[+] Removing '$sharedir'\n"
        rm -fr "$sharedir"
      }
      trap on_exit EXIT

      # Decrypt vm secret(s)
      todir="$sharedir/secrets"
      ${decrypt-sops-key pkgs} "${secret}" "$todir"

      # Run vm with the share mounted inside the virtual machine
      ${pkgs.lib.getExe cfg.system.build.vm}
    '');
in
{
  flake.apps."x86_64-linux" =
    let
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
    in
    {
      run-hetzci-vm = {
        type = "app";
        meta.description = "Run the hetzci VM";
        program =
          run-vm-with-share pkgs self.nixosConfigurations.hetzci-vm.config
            "${self.outPath}/hosts/hetzci/vm/secrets.yaml";
      };
    };
}
