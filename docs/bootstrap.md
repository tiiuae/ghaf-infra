<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: Apache-2.0
-->

# WIP: Starting off in a new environment

This section attempts to outline the required initial manual setup to help those who plan to apply these configurations (or something based on them) on a new environment.

We will do this with a help of example: the following sections show how to setup a simple infra with one azure VM that runs hydra with an example jobset. The intention is to show the initial manual setup required to start configuring your own infra.

We use the term **host** to refer the host system you will be using to setup and deploy the configurations. The only requirement for the host system is that it has [nix](https://nixos.org/download.html) package manager installed. My own host system is currently based on Ubuntu.

We use the term **target** to refer to the target system to which the configurations will be applied. For this example configuration, we will use an azure VM as target. You should be able to apply these instructions to any target system on  which you can install NixOS. These instructions show how to bootstrap the target with NixOS using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere), but you can use any way you prefer to install NixOS on your targets.

TODO: add outline here

## Host setup
If you still don't have nix pakcage manager, install it following the package manager installation instructions from https://nixos.org/download.html.

Clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra
```

Bootstrap nix shell with `flakes` and `nix-command` as well as other commands that we will be using.
```bash
# All commands in this section are run in nix-shell:
$ nix-shell
```

### Add your admin sops key
You will need a key for your admin user to encrypt and decrypt sops secrets. We will use an age key converted from your ssh ed25519 key:
```bash
# In nix-shell
$ mkdir -p ~/.config/sops/age
# if you don't have ed25519 key, generate one with:
$ ssh-keygen -t ed25519 -a 100
# convert the ed25519 key to an age key:
$ ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
# print the age public key
$ ssh-to-age < ~/.ssh/id_ed25519.pub
age18jtr8nw8dw7qqgx0wl2547u805y7m7ay73a8xlhfxedksrujhgrsu5ftwe
```
Add the above age public key to the `.sops.yaml` with your username. You will also want to remove all the other keys from that file.

### Generate and add server sops key
```bash
# In nix-shell
# generate a new ssh server key for the taget system:
ssh-keygen -t ed25519 -a 100 -C mytarget -f ~/.ssh/mytarget_id_ed25519
# print the host age public key
$ ssh-to-age < ~/.ssh/mytarget_id_ed25519.pub
age15jhcpmj00hqha52l82vecf7gzr8l3ka3sdt63dx8pzkwdteff5vqs4a6c3
```

Now, add the above age public key to the `.sops.yaml` with the host name you are planning use for the target.

At this point, your `.sops.yaml` should look something like (we'll use `mytarget` and `myadmin` for the new target and admin user names):

```bash
keys:
  - &myadmin age18jtr8nw8dw7qqgx0wl2547u805y7m7ay73a8xlhfxedksrujhgrsu5ftwe
  - &mytarget age15jhcpmj00hqha52l82vecf7gzr8l3ka3sdt63dx8pzkwdteff5vqs4a6c3
creation_rules:
  - path_regex: secrets.yaml$
    key_groups:
    - age:
      - *myadmin
      - *mytarget
```

### Add yourself as user
Copy one of the user configurations under ['users'](../users/) as template for your admin user, and modify the username and the ssh key to match yours:
```bash
$ cp users/tester.nix users/myadmin.nix
# Modify the username and 'myadmin' public ssh key to match
# the public key you are going to use to access the server
$ vim users/myadmin.nix
```

The end result should look something like:
```bash
$ cat users/myadmin.nix
{...}: {
  users.users = {
    myadmin = {
    # ^^^^^ Change the username
      initialPassword = "changemeonfirstlogin";
      isNormalUser = true;
      # Change the ssh public key:
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFuB+uEjhoSdakwiKLD3TbNpbjnlXerEfZQbtRgvdSz"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
```

### Add your target configuration 
Copy one of the system configurations under ['hosts'](./hosts/) as template for your target, or directly edit one of the existing configurations. For this example, we'll use the 'ghafhydra' as a basis of our target configuration.

```bash
$ cp -r hosts/ghafhydra hosts/mytarget
```

You will also need to add your new target configuration to the [`flake.nix`](../flake.nix):
```
    ...
    # NixOS configuration entrypoint
    nixosConfigurations = {
      ...
      # ==> HERE: Add your new host config:
      mytarget = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [./hosts/mytarget/configuration.nix];
      };
    ...
   };
   ...
```

### Modify your host configuration 
Modify the server 'mytarget' configuration based on your needs. For this example, since our target is an azure VM, we will copy the relevant configuration from the 'azure-x86_64-linux' target in [./hosts/templates/targets.nix]. The final configuration in `hosts/mytarget/configuration.nix` becomes something like:

```bash
$ cat hosts/mytarget/configuration.nix 
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # We'll create the secrets in the next section, but you need to add them
  # here if you are planning to configure hydra and nix-serve for your target
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets.hydra-admin-password.owner = "hydra";
  sops.secrets.id_buildfarm = {};
  sops.secrets.id_buildfarm.owner = "hydra-queue-runner";
  sops.secrets.cache-sig-key.owner = "root";
  # Define e.g. the services you want to run on your target, and the users
  # who can access the target with ssh:
  imports = [
    inputs.nix-serve-ng.nixosModules.default
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    ../generic-disk-config.nix
    ../common.nix
    ../../services/hydra/hydra.nix
    ../../services/openssh/openssh.nix
    ../../services/binarycache/binary-cache.nix
    ../../users/myadmin.nix
  ];
  # Assuming your target is x86_64
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  # Following settings are required to make your target bootable in an azure VM
  boot.kernelParams = ["console=ttyS0" "earlyprintk=ttyS0" "rootdelay=300" "panic=1" "boot.panic_on_fail"];
  boot.initrd.kernelModules = ["hv_vmbus" "hv_netvsc" "hv_utils" "hv_storvsc"];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 0;
  boot.loader.grub.configurationLimit = 0;
  boot.growPartition = true;
  # TODO: make sure the below network and disk configuration matches your azure target:
  disko.devices.disk.disk1.device = "/dev/sda";
  networking.useDHCP = false;
  networking.nameservers = ["8.8.8.8"];
  networking.defaultGateway = "10.3.0.1";
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.3.0.4";
      prefixLength = 24;
    }
  ];
}
```

Ensure the network configuration in `hosts/mytarget/configuration.nix` is what you expect based on your target azure network configuration.

While editing the `hosts/mytarget/configuration.nix`, you might want to remove some of the configured services, or add your own services based on what you are planning to use the server for. For instance, if you don't want to configure hydra for your target, simply remove the line that imports `../../services/hydra/hydra.nix`.

### Generate and encrypt your secrets
At this point, the configuration is otherwise ready, but you have not generated any secrets yet.

First, remove possible earlier secrets you might have copied from ghafhydra. 
(Note: you will obviously not be able to decrypt the secrets from the original ghafhydra '[`secrets.yaml`](./hosts/ghafhydra/secrets.yaml)' since you don't have the private key that matches one of the age keys in the original '[`.sops.yaml`](.sops.yaml)' file.)
```bash
$ rm hosts/mytarget/secrets.yaml
```
If you are using the ghafhydra as a template configuration, you are going to need at least the following secrets:
- `ssh_host_ed25519_key`: this will specify the ssh private key for target server ('mytarget')
- `hydra-admin-password`: this will specify the admin password for hydra
- `cache-sig-key`: this will specify the nix binary cache private signing key
- `id_buildfarm`: this specifies the private key that allows access to the remote builders

We generated the target server private key for `mytarget` earlier at path `~/.ssh/mytarget_id_ed25519`. The contents of this file will be the value of the `ssh_host_ed25519_key` key in sops.

Run the following command to generate your `cache-sig-key`:

```bash
$ nix-store --generate-binary-cache-key cache.mytarget ../cache-secret ../cache-public
$ cat ../cache-secret
$ cache.mytarget:vnZqh8F/L4HQKyxXc2moCLIKzFpfwlFeD6c+6PiX5qa5G1z2XnmMK+Su8216hJET8Iwwg6O1hxAVTyxEYzfesQ==
```
The contents of `../cache-secret` will be the value of the `cache-sig-key` key in sops.

Side note: to use your binary cache, you would configure the substituters as follows:

```bash
$ cat ../cache-public
cache.mytarget:uRtc9l55jCvkrvNteoSRE/CMMIOjtYcQFU8sRGM33rE=

# To use your binary cache, configure the substituters
# Replace with mytarget IP:
substituters = http://10.3.0.4:5000
# Replace with your content from ../cache-public:
trusted-public-keys = cache.mytarget:uRtc9l55jCvkrvNteoSRE/CMMIOjtYcQFU8sRGM33rE=
```

We will not cover the remote builders in this document, however, the contents of the key `id_buildfarm` specifies the private key that allows access to the remote builders.

Now, you are ready to generate your secrets for target `mytarget`:

```bash
# This will open the secrets.yaml in an editor:
$ sops hosts/mytarget/secrets.yaml
```
The above command opens an editor, where you can edit the secrets.
Remove the example content, and replace with your secrets, so the content would look something like:

```bash
hydra-admin-password: do_not_use_any_of_these_same_values_in_your_secrets
cache-sig-key: ache.mytarget:vnZqh8F/L4HQKyxXc2moCLIKzFpfwlFeD6c+6PiX5qa5G1z2XnmMK+Su8216hJET8Iwwg6O1hxAVTyxEYzfesQ==
id_buildfarm: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    YOUR_BUILD_FARM_PRIVATE_KEY_HERE_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    -----END OPENSSH PRIVATE KEY-----
ssh_host_ed25519_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    YOUR_SERVER_PRIVATE_KEY_HERE_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    -----END OPENSSH PRIVATE KEY-----
```

When you save and exit the editor, sops will encrypt your secrets and saves them to the file you specified: `hosts/mytarget/secrets.yaml`.
Notice: the example sops configuration we defined in `.sops.yaml`, both `myadmin` and `mytarget` can decrypt all the secrets. For production setups, you would want to apply the principle of least privilege and only allow decryption for the servers or users who need access to the specific secret content. See, for instance, [nix-community/infra](https://github.com/nix-community/infra/blob/master/.sops.yaml) for a more complete example.

Now, if you re-run `sops hosts/mytarget/secrets.yaml`, sops will again decrypt the file allowing you to edit or add new secrets.

Finally, `git add` your changes (and consider starting off with your new configuration in your own repository).

### Quick sanity checks

After adding your configuration, check nix formatting and fix possible issues:
```bash
# Run in nix-shell (in the repo root)
$ nix fmt
```

Similarly, check the pre-push checks on your configuration pass and fix possible issues:
```bash
# Run in nix-shell (in the repo root)
$ inv pre-push
```

## Target setup
## Deploy target configuration



## Nixos-anywhere
We use [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to bootstarp NixOS. This repository includes example [template](../hosts/templates/targets.nix) configurations for targets, such as: `generic-x86_64-linux` and `azure-x86_64-linux`. Each of these example configurations will require some manual modifications to make the configuration usable in your environment. In the following sections, we will show how to modify the configurations to bootstrap NixOS on an azure VM.

There are various other ways to install NixOS on your host that you might want to explore in case [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) doesn't fit your use-case. Other installation methods include, for instance: [nixos-infect](https://github.com/elitak/nixos-infect) or [manual installation from NixOS ISO](https://nixos.wiki/wiki/NixOS_Installation_Guide).


**Important**: [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) automatically partitions and re-formats the target host hard drive, meaning all data on the target will be completely overwritten with no option to rollback.

**Important**: Test the bootstrap configuration in your environment on a target host you can easily revert to a known working state (or throw away) in case something goes wrong.

## Pre-requisites
Main requirement is an SSH access to the target server, authenticated with keys. Initial SSH access must allow sudo with NOPASSWD for the `nixos-anywhere` to work. The target system must also support [`kexec`](https://linux.die.net/man/8/kexec).

See detailed pre-requisites at: https://github.com/nix-community/nixos-anywhere#prerequisites.

Also, see: [nixos-anywhere: known issues](#nixos-anywhere-known-issues).

## Example: NixOS on azure

This section covers applying the bootstrap configuration from this repository on an azure VM. However, the instructions from this section are written such that it should be easy to apply the example on other environments too.

For the sake of example, we will modify the `bootstrap-azure-x86_64-linux` configuration defined in [targets.nix](./targets.nix) and imported in the main [flake.nix](../flake.nix):

```bash
# Run on the root of this repo:
$ nix flake show

git+file:///your/path/to/ghaf-infra
├───devShells
│   └───x86_64-linux
│       └───default: development environment 'nix-shell'
├───formatter
│   └───x86_64-linux: package 'alejandra-3.0.0'
└───nixosConfigurations
    ├───bootstrap-azure-x86_64-linux: NixOS configuration     # <== HERE, we will use this as a template
    └───bootstrap-generic-x86_64-linux: NixOS configuration
```

### Azure VM requirements
The bootstrap configuration on this repository has been tested on the following azure x86_64 Gen2 images with "Standard" security type:
- Ubuntu 20_04-lts-gen2
- Ubuntu 22_04-lts-gen2
- Debian 12-gen2

It should be possible to make the configuration work on any Gen2 x86_64 VM, but for the sake of example we will use **Ubuntu 22_04-lts-gen2** VM image.

There are some known issues with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) and secure boot. Azure "Trusted Launch" enables secure boot and IMA (Integrity Measurement Architecture) which can not be disabled from inside the booted-up VM. Therefore, we use the azure "Standard" security type which disables the secure boot on the VM. For more details, see: [issue](https://github.com/nix-community/nixos-anywhere/issues/143), [comment](https://github.com/nix-community/nixos-anywhere/issues/189#issuecomment-1693762691), and [another issue](https://github.com/nix-community/nixos-images/issues/128).

### Check azure VM target configuration
At this point, you should have an azure VM with an SSH access to the taret, using key-based authentication.
All the commands in this section are run on the azure target VM.

#### Temporarily allow sudo without password on the target
You need to temporarily enable sudo without password on the target host, otherwise nixos-anyhwere [fails](https://github.com/nix-community/nixos-anywhere/issues/178) to run on the target.
Note: on Ubuntu 22_04-lts-gen2 azure image, sudo with no password should be enabled by default.

In case it's not enabled yet, use `visudo` to modify the `/etc/sudoers` to add an entry like:

```bash
# On the target:
# Replace 'your-username-here' with your username
your-username-here ALL=(ALL) NOPASSWD: ALL
```
#### Temporarily set a static IP on the target

You may need to temporarily set a static IP address on you target host if your configuration assumes the target host is reachable from a specific IP address.

Note: azure VMs by default use static IP configuration also internally, so this step should not be required.

Log in to the target with SSH and check the following:
```bash
# On the target:
# Check if the interface you are connected via the ssh on the target uses dhcp
# (assumes net-tools is installed: sudo apt update && sudo apt install net-tools)
# (assumes you are running ssh on port 22):
$ ip address show | grep $(sudo netstat -tpn | grep -P "ESTABLISHED.*sshd.*$(whoami)" | head -n1 | grep -oP "[^ ]+:22" | cut -d":" -f1) 2>/dev/null | grep dynamic

# If the above command returns something like below, it means your ssh connection
# is established via an interface that uses dynamic addresses (e.g. dhcp):

  inet 192.168.1.112/24 brd 192.168.1.255 scope global dynamic noprefixroute eth0

# If the address is dynamic, and you are using the specified address to access
# the target (192.168.1.112 in the above example case), you may need to make
# the configuration static for nixos-anywhere to reach your host
# after kexec system switch.
# Make sure you change $TARGET_DEV, IP, and GW based on your config:
export TARGET_DEV=eth0; \
export TARGET_IP=192.168.1.112/24; \
export TARGET_GW=192.168.1.1; \
sudo ip address flush dev "$TARGET_DEV"; \
sudo ip route flush dev "$TARGET_DEV"; \
sleep 5; \
sudo ip address add "$TARGET_IP" brd + dev "$TARGET_DEV"; \
sudo route add default gw "$TARGET_GW" "$TARGET_DEV"; \
sudo ip address show;
```

#### Check the target disk layout

[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) needs to partition, format, and mount your disks. For simple installation, you can re-use the example disk-configuration at [generic-disk-config.nix](./hosts/generic-disk-config.nix) which is based on the example configuration at [nixos-anywhere-examples](https://github.com/numtide/nixos-anywhere-examples/blob/main/disk-config.nix).

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
├─sda1    8:1    0  29.9G  0 part /
├─sda14   8:14   0     4M  0 part 
└─sda15   8:15   0   106M  0 part /boot/efi
sdb       8:16   0     8G  0 disk 
└─sdb1    8:17   0     8G  0 part /mnt
```

Above example shows main disk on `/dev/sda` and an additional disk on `/dev/sdb`. On some image types azure includes temporary storage mounted on `/mnt` as shown above. Target `azure-x86_64-linux` in [target.nix](./target.nix) shows an example of how to mount both the main disk on `/dev/sda` as well as the temporary storage on `/dev/sdb`.

Note: for azure configurations - if you include the azure agent (waagent) on the NixOS target, it might impact the disk layout and mount options. In that case, the final layout (once waagent is running) might not match what you configured in [target.nix](./target.nix).

If needed, modify the device name on [target.nix](./target.nix) based on your disk device configuration:
```bash
# Make sure the device name on target.nix matches your target:
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

Modify the network configuration in [target.nix](./target.nix) so that it matches the expected target configuration:
```bash
  # Make sure the network configuration in target.nix matches your target:
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

Modify the user configuration in bootstrap [configuration.nix](./configuration.nix), adding your user to the configuration:
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
$ nix fmt
```

Similarly, check that your configuration evaluates properly and fix possible issues:
```bash
$ nix flake show
```

### Install NixOS using bootstrap configuration
At this point, we are ready to bootstarp our example azure VM target with NixOS:

```bash
# Run on the host, example azure VM target is 20.13.163.33
$ nix run github:numtide/nixos-anywhere -- --flake .#bootstrap-azure-x86_64-linux your-username-here@20.13.163.33
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

Now, you should be able to SSH to the target and confirm that the target is now running NixOS:
```bash
$ ssh your-username-here@20.13.163.33
# You should see a warning about host identification changed, since
# you previously accessed the server when it was still running the
# initial azure image. Follow the instructions from the warning
# to remove the old entry from known_hosts.
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
