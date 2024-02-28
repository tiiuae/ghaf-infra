<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Installing NixOS with nixos-anywhere
This document outlines the use of nixos-anywhere in this repository, aiming to help those who plan to apply the NixOS configurations in this repository (or something based on them) on a new environment.

[Ghaf-infra](../README.md) uses [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to bootstrap NixOS on target hosts. This repository includes example [template](../hosts/templates/targets.nix) configurations for targets, such as: `generic-x86_64-linux` and `azure-x86_64-linux`. Each of these example configurations will require some manual modifications to make the configuration usable in your environment. In this document, we will show how to use the template configurations to bootstrap NixOS on an azure VM.

There are various other ways to install NixOS on your target server that you might want to explore in case [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) doesn't fit your use-case. Other installation methods include, for instance: [nixos-infect](https://github.com/elitak/nixos-infect) or [manual installation from NixOS ISO](https://nixos.wiki/wiki/NixOS_Installation_Guide).

**Important**: [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) automatically partitions and re-formats the target host hard drive, meaning all data on the target will be completely overwritten with no option to rollback.

**Important**: Test the bootstrap configuration in your environment on a target host you can easily revert to a known working state (or throw away) in case something goes wrong.

## Pre-requisites
Main requirement is an SSH access to the target server, authenticated with keys. Initial SSH access must allow sudo with NOPASSWD for the `nixos-anywhere` to work. The target system must also support [`kexec`](https://linux.die.net/man/8/kexec).

See detailed pre-requisites at: https://github.com/nix-community/nixos-anywhere#prerequisites.

Also, see: [nixos-anywhere: known issues](#nixos-anywhere-known-issues).

## Example: NixOS on azure

This section covers applying the bootstrap configuration from this repository on an azure VM. However, the instructions from this document are written such that it should be easy to apply them on other environments too.

For the sake of example, we will modify the `template-azure-x86_64-linux` configuration defined in [templates/targets.nix](../hosts/templates/targets.nix) and imported in the main [flake.nix](../flake.nix):

```bash
# Run in nix-shell on your host (in the repository root)
$ nix flake show
...
└───nixosConfigurations
    ...
    ├───template-azure-x86_64-linux: NixOS configuration     # <== HERE, we will use this as a template
    └───template-generic-x86_64-linux: NixOS configuration
```

### Azure VM requirements
The azure example configuration in this repository has been tested on the following azure x86_64 Gen2 VMs with "Standard" security type:
- Ubuntu 22_04-lts-gen2, Standard B2s
- Ubuntu 22_04-lts-gen2, Standard B4ms
- Ubuntu 22_04-lts-gen2, Standard B8ms
- Debian 12-gen2, Standard B2s

There are some known issues with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) and secure boot. Azure "Trusted Launch" enables secure boot and IMA (Integrity Measurement Architecture). Therefore, we need to use azure VM with "Standard" security type which disables the secure boot on the VM. For more details, see: [issue](https://github.com/nix-community/nixos-anywhere/issues/143), [comment](https://github.com/nix-community/nixos-anywhere/issues/189#issuecomment-1693762691), and [another issue](https://github.com/nix-community/nixos-images/issues/128).

In addition, not all azure image sizes are compatible with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere). We have tested the configurations in this repository on various azure 'B'-series VMs.

### Check azure VM target configuration
At this point, you should have an azure VM with an SSH access to the target, using key-based authentication.
The commands in this section are run on the azure target VM.

#### Temporarily allow sudo without password on the target
You need to temporarily enable sudo without password on the target host, otherwise nixos-anyhwere [fails](https://github.com/nix-community/nixos-anywhere/issues/178) to run on the target.
Note: generally on azure VMs, sudo with no password is enabled by default.

In case it's not enabled yet, use `visudo` to modify the `/etc/sudoers` to add an entry like:

```bash
# On the target:
# Replace 'your-username-here' with your username
your-username-here ALL=(ALL) NOPASSWD: ALL
```
#### Temporarily set a static IP on the target

You may need to temporarily set a static IP address on you target host if your configuration assumes the target host is reachable from a specific IP address.

Note: azure VMs by default use static IP configuration, so this step should not be required.

Log in to the target with SSH and check if your ssh connection is established via an interface that uses dynamic addressing:
```bash
# SSH on the target and run:
# Check if the interface you are connected via the ssh on the target uses dhcp:
ip a | grep dynamic
  ...
  inet 192.168.1.112/24 brd 192.168.1.255 scope global dynamic noprefixroute eth0
  ...

# If the address is dynamic, and you are using the specified address to access
# the target (192.168.1.112 in the above example case), you may need to make
# the configuration static for nixos-anywhere to reach your host
# after kexec system switch.
```

See more details in https://github.com/nix-community/nixos-anywhere/issues/112.

#### Check the target disk layout

[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) needs to partition, format, and mount your disks. For simple installation, you can re-use the example disk-configuration at [generic-disk-config.nix](../hosts/generic-disk-config.nix) which is based on the example configuration at [nixos-anywhere-examples](https://github.com/numtide/nixos-anywhere-examples/blob/main/disk-config.nix).

For the bare minimum, you need to check the disk device matches your current system with `lsblk`:
```bash
# On the target:
# Check the disk layout:
$ lsblk
NAME    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0     7:0    0  63.5M  1 loop /snap/core20/2015
loop1     7:1    0  40.8M  1 loop /snap/snapd/20092
loop2     7:2    0 111.9M  1 loop /snap/lxd/24322
sda       8:0    0    30G  0 disk 
├─sda1    8:1    0  29.9G  0 part /           # <== rootfs
├─sda14   8:14   0     4M  0 part 
└─sda15   8:15   0   106M  0 part /boot/efi
sdb       8:16   0     8G  0 disk             # <== temporary storage
└─sdb1    8:17   0     8G  0 part /mnt
```

Above example shows the rootfs on disk `/dev/sda` and an additional disk on `/dev/sdb`. On some image types, azure includes temporary storage mounted on `/mnt` as shown above. Target `azure-x86_64-linux` in [targets.nix](../hosts/templates/targets.nix) shows an example of how to mount both the main disk on `/dev/sda` as well as the temporary storage on `/dev/sdb`.

If needed, modify the device name on [targets.nix](../hosts/templates/targets.nix) based on your disk device configuration:
```bash
# Make sure the device name on targets.nix matches your target:
disko.devices.disk.disk1.device = "/dev/sda";
```

For more complex disk layout configuration examples, see the [`disko`](https://github.com/nix-community/disko/tree/master/example) repository.

#### Check the network configuration

Check the network configuration on the target:
```bash
# On the target:
$ ip addr
    ...
    inet 10.3.0.4/24 metric 100 brd 10.3.0.255 scope global eth0
    ...

$ netstat -rn
Kernel IP routing table
Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
0.0.0.0         10.3.0.1        0.0.0.0         UG        0 0          0 eth0
10.3.0.0        0.0.0.0         255.255.255.0   U         0 0          0 eth0
```

Modify the network configuration in [targets.nix](../hosts/templates/targets.nix) so that it matches the expected target configuration:
```bash
  # Make sure the network configuration in targets.nix matches your target:
  networking.nameservers = ["8.8.8.8"];
  networking.defaultGateway = "10.3.0.1";
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.3.0.4";
      prefixLength = 24;
    }
  ];
```

#### Add yourself as user
Copy one of the user configurations under [users](../users/) as template for your user, and modify the username and the ssh key to match yours:
```bash
# On the root of this repository
$ cp users/tester.nix users/your-username-here.nix
# Modify the username and public ssh key to match
# the public key you are going to use to access the server
$ vim users/your-username-here.nix
```

The end result should look something like:
```bash
$ cat users/your-username-here.nix
{...}: {
  users.users = {
    tester = {
    # ^^^^^ Change the username
      initialPassword = "changemeonfirstlogin";
      isNormalUser = true;
      # Change the ssh public key:
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFbxhIZjGU6JuMBMMyeaYNXSltPCjYzGZ2WSOpegPuQ"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
```

Modify the user configuration in template [configuration.nix](../hosts/templates/configuration.nix), adding your user to the configuration:
```bash
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ../hosts/generic-disk-config.nix
    ../services/openssh/openssh.nix
    ../users/hrosten.nix               # <== HERE, import your user
  ];
```

#### Quick sanity checks

After adding your configuration, check nix formatting and fix possible issues.
Run the following command in the root of this repository:

```bash
# Run in nix-shell on your host (in the repository root)
$ nix fmt
```

Similarly, make sure the pre-push checks on your configuration pass and fix possible issues:
```bash
# Run in nix-shell on your host (in the repository root)
$ inv pre-push
```

### Install NixOS using template configuration
At this point, we are ready to bootstrap your azure VM target with NixOS.

As described in main [README](../README.md), this project uses [pyinvoke](https://www.pyinvoke.org/) to help with common deployment [tasks](../tasks.py). In this section, we show how to install the configuration you have now created both using pyinvoke `install` helper task, as well as running nixos-anywhere manually.

#### Option 1: installing with pyinvoke helper

```bash
# Run on the host, example azure VM target is 20.13.163.33
inv install --target template-azure-x86_64-linux --hostname 20.13.163.33
...
### Uploading install SSH keys ###
### Gathering machine facts ###
### Switching system into kexec ###
### Formatting hard drive with disko ###
### Uploading the system closure ###
### Installing NixOS ###
...
installation finished!
Connection to 20.13.163.33 closed by remote host.
### Waiting for the machine to become reachable again ###
kex_exchange_identification: read: Connection reset by peer
### Done! ###
```

#### Option 2: running nixos-anywhere manually

```bash
# Run on the host, example azure VM target is 20.13.163.33
$ nix run github:numtide/nixos-anywhere -- --flake .#template-azure-x86_64-linux your-username-here@20.13.163.33
...
### Uploading install SSH keys ###
### Gathering machine facts ###
### Switching system into kexec ###
### Formatting hard drive with disko ###
### Uploading the system closure ###
### Installing NixOS ###
...
installation finished!
Connection to 20.13.163.33 closed by remote host.
### Waiting for the machine to become reachable again ###
kex_exchange_identification: read: Connection reset by peer
### Done! ###
```

#### Confirm NixOS installation

Now, you should be able to login to the target with SSH and confirm that the target is now running NixOS:
```bash
$ ssh your-username-here@20.13.163.33
# You should see a warning about host identification changed, since
# you previously accessed the server when it was still running the
# initial azure image. Follow the instructions from the warning
# to remove the old entry from ssh_known_hosts.
```

```bash
$ uname -a
Linux nixos 6.1.57 #1-NixOS SMP PREEMPT_DYNAMIC Tue Oct 10 20:00:46 UTC 2023 x86_64 GNU/Linux
```

## Nixos-anywhere: known issues
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) requires root login or sudo with no password for the initial SSH access: [issue](https://github.com/nix-community/nixos-anywhere/issues/178).
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) uses `kexec` which has some known issues on systems with secure boot enabled, see: [issue](https://github.com/nix-community/nixos-anywhere/issues/143), [comment](https://github.com/nix-community/nixos-anywhere/issues/189#issuecomment-1693762691), and [another issue](https://github.com/nix-community/nixos-images/issues/128). If possible, disable secure boot on the initial target system. Check if secure boot is enabled on your initial configuration with: `sudo mokutil --sb-state`.
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) may fail to connect to the target after `kexec` if the target network configuration initially used DHCP. The problem is that if the target IP address changes after `kexec` system switch, the SSH connection to the `kexec` image might fail. [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) restores the original network config after `kexec` switch, but it [skips](https://github.com/nix-community/nixos-images/blob/c4c73bce65306a1e747684dd0d4bcf0ab2779585/nix/kexec-installer/restore_routes.py#L22) DHCP addresses, which might lead to problems in some cases, see: [issue](https://github.com/nix-community/nixos-anywhere/issues/112).
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) requires direct SSH access, jumphosts are not properly supported: [issue](https://github.com/nix-community/nixos-anywhere/issues/201).


## Debug tips

<details>
<summary>Secure boot, IMA</summary>

```bash
# Am I booted in UEFI or Legacy (BIOS)?
# See: https://nixos.wiki/wiki/Bootloader
[ -d /sys/firmware/efi/efivars ] && echo "UEFI" || echo "Legacy"

# Is secure boot enabled?
$ sudo mokutil --sb-state
SecureBoot enabled

# Is IMA enabled?
$ sudo dmesg | grep -i  -e EVM -e IMA
[    1.260205] ima: Allocated hash algorithm: sha1
[    1.266459] evm: Initialising EVM extended attributes:
[    1.273515] evm: security.selinux
[    1.279541] evm: security.SMACK64
[    1.281542] evm: security.SMACK64EXEC
[    1.284098] evm: security.SMACK64TRANSMUTE
[    1.286468] evm: security.SMACK64MMAP
[    1.288522] evm: security.apparmor
[    1.290434] evm: security.ima

# Add option 'ima_appraise=off' to kernel cmdline  ...
$ cat /etc/default/grub.d/50-cloudimg-settings.cfg | grep ima_appraise
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX console=tty1 console=ttyS0 earlyprintk=ttyS0 ima_appraise=off"

$ sudo update-grub && sudo reboot now

# ... however, disabling IMA is not allowed if secure boot is enabled:
$ cat /proc/cmdline 
BOOT_IMAGE=/boot/vmlinuz-6.2.0-1014-azure root=PARTUUID=c621eaf2-7308-403f-b164-8b75e44d7028 ro console=tty1 console=ttyS0 earlyprintk=ttyS0 ima_appraise=off panic=-1

$ sudo dmesg | grep -i  -e EVM -e IMA
...
[    1.360141] ima: Secure boot enabled: ignoring ima_appraise=off option
...

```

</details>
