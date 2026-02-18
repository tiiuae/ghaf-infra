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
      on_decrypt_err () {
        printf "\n[+] Failed decrypting sops key: VM will boot-up without secrets\n"
        # Wait for user input if stdout is to a terminal (and not to file or pipe)
        if [ -t 1 ]; then
          echo; read -n 1 -srp "Press any key to continue"; echo
        fi
        exit 0
      }
      if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
        echo "error: expected <secret-file> <target-dir>" >&2
        exit 2
      fi
      secret="$1"
      todir="$2"
      umask 077; mkdir -p "$todir"
      rm -fr "$todir/ssh_host_ed25519_key"
      tofile="$todir/ssh_host_ed25519_key"
      umask 377
      if ! ${pkgs.lib.getExe pkgs.sops} --extract '["ssh_host_ed25519_key"]' --decrypt "$secret" >"$tofile"; then
        rm -f "$tofile"
        on_decrypt_err
      fi
      echo "[+] Decrypted sops key '$tofile'"
    '');

  run-vm-with-share =
    pkgs: cfg: secret:
    (pkgs.writeShellScriptBin "run-vm-with-share" ''
      set -eu
      cleanup_disk=1
      disk_image=''${NIX_DISK_IMAGE:-./${cfg.networking.hostName}.qcow2}

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --keep-disk)
            cleanup_disk=0
            shift
            ;;
          --disk-image)
            disk_image="$2"
            shift 2
            ;;
          --help|-h)
            cat <<'EOF'
      Usage: nix run .#run-hetzci-vm -- [OPTIONS] [-- VM_ARGS...]

      Options:
        --keep-disk        Keep disk image after VM exits
        --disk-image PATH  Disk image path (default: ./hetzci-vm.qcow2)
        --help, -h         Show this help text
      EOF
            exit 0
            ;;
          --)
            shift
            break
            ;;
          *)
            break
            ;;
        esac
      done

      export NIX_DISK_IMAGE="$disk_image"
      echo "[+] Running '$(realpath "$0")'"
      # Host path of the shr share directory
      sharedir="${cfg.virtualisation.vmVariant.virtualisation.sharedDirectories.shr.source}"
      # See nixpkgs: virtualisation/qemu-vm.nix
      export TMPDIR="$sharedir"
      on_exit () {
        status="$?"
        printf "\n[+] Removing '$sharedir'\n"
        rm -fr "$sharedir"
        if [ "$cleanup_disk" -eq 1 ] && [ -f "$disk_image" ]; then
          printf "[+] Removing '$disk_image'\n"
          rm -f -- "$disk_image"
        fi
        exit "$status"
      }
      trap on_exit EXIT INT TERM

      # Decrypt vm secret(s)
      todir="$sharedir/secrets"
      ${decrypt-sops-key pkgs} "${secret}" "$todir"

      # Run vm with the share mounted inside the virtual machine
      ${pkgs.lib.getExe cfg.system.build.vm} "$@"
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
        meta.description = "Run hetzci VM - 'nix run .#run-hetzci-vm -- --help'";
        program =
          run-vm-with-share pkgs self.nixosConfigurations.hetzci-vm.config
            "${self.outPath}/hosts/hetzci/vm/secrets.yaml";
      };
    };
}
