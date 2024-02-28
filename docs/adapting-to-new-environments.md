<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Starting off in a new environment

This document outlines the initial manual setup to help those who plan to apply the configurations from this repository - or something based on them - on a new environment.

We will do this with a help of an example: the following sections show how to setup a simple infra with one azure VM that runs hydra with an example jobset. 

This document uses the term **host** to refer the host system you use to setup and deploy the configurations. The only requirement for the host system is that it needs to have [nix](https://nixos.org/download.html) package manager installed - Ubuntu, Debian, NixOS, or any other system on which you can install nix package manager should all work fine.

Similarly, the term **target** refers the target system to which the configurations will be applied. For this example configuration, we will use an azure VM as target. You should be able to apply these instructions to any target system on which you can install NixOS. These instructions show how to bootstrap the target with NixOS using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere), but you can use any way you prefer to install NixOS on your targets.

Table of Contents
=================

This document is organized into following sections:

* [Host setup](#host-setup)
   * [Add your admin sops key](#add-your-admin-sops-key)
   * [Generate and add server sops key](#generate-and-add-server-sops-key)
   * [Add yourself as user to the target](#add-yourself-as-user-to-the-target)
   * [Add your target configuration](#add-your-target-configuration)
   * [Modify your target configuration](#modify-your-target-configuration)
   * [Generate and encrypt your secrets](#generate-and-encrypt-your-secrets)
   * [Quick sanity checks](#quick-sanity-checks)
* [Target setup](#target-setup)
* [Install/Deploy the target configuration](#installdeploy-the-target-configuration)

## Host setup
If you still don't have nix package manager on your local host, install it following the package manager installation instructions from https://nixos.org/download.html.

Then, clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra
```

Bootstrap nix shell with `flakes` and `nix-command` as well as all the other commands that we will be using:
```bash
# Run the following command in the root path of the cloned repository
# to start nix-shell on your host:
$ nix-shell
# Note: all commands in this section are run inside this nix-shell.
```

### Add your admin sops key
You will need a key for your admin user to encrypt and decrypt sops secrets. We will use an age key converted from your ssh ed25519 key:
```bash
# Run in nix-shell on your host
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
# Run in nix-shell on your host
# generate a new ssh server key for the taget system:
ssh-keygen -t ed25519 -a 100 -C mytarget -f ~/.ssh/mytarget_id_ed25519
# print the host age public key
$ ssh-to-age < ~/.ssh/mytarget_id_ed25519.pub
age15jhcpmj00hqha52l82vecf7gzr8l3ka3sdt63dx8pzkwdteff5vqs4a6c3
```

Now, add the above age public key to the `.sops.yaml` with the host name you are planning use for the target.

At this point, your `.sops.yaml` should look something like this (this document uses `mytarget` and `myadmin` for the new target and admin user names):

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

### Add yourself as user to the target
Copy one of the user configurations under [users](../users/) as template for your admin user, and modify the username and the ssh key to match yours:
```bash
# Run in nix-shell on your host
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
    # ^^^^^ Your username here
      initialPassword = "changemeonfirstlogin";
      isNormalUser = true;
      # Your ssh public key here:
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFuB+uEjhoSdakwiKLD3TbNpbjnlXerEfZQbtRgvdSz"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
```

### Add your target configuration 
Copy one of the system configurations under [hosts](./hosts/) as template for your target, or directly edit one of the existing configurations. For this example, we'll use the configuration 'ghafhydra' as a basis of our target configuration.

```bash
# Run in nix-shell on your host
$ cp -r hosts/ghafhydra hosts/mytarget
```

You will also need to add your new target configuration to the [`flake.nix`](../flake.nix):
```
    ...
    # NixOS configuration entrypoint
    nixosConfigurations = {
      ...
      # ==> HERE: Add your new target server config:
      mytarget = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [./hosts/mytarget/configuration.nix];
      };
    ...
   };
   ...
```

### Modify your target configuration 
Modify the server `mytarget` configuration based on your needs. For this example, since our target is an azure VM, we will copy the relevant configuration from the 'azure-x86_64-linux' target defined in [./hosts/templates/targets.nix](./hosts/templates/targets.nix). The final configuration in `hosts/mytarget/configuration.nix` becomes something like:

```bash
# Run in nix-shell on your host
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
  # Define the services you want to run on your target, as well as the users
  # who can access the target with ssh:
  imports = [
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
  # Following settings are required to make your target bootable in an azure VM:
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

While editing the `hosts/mytarget/configuration.nix`, you might want to remove some of the configured services, or add your own services based on what you are planning to use the server for. For instance, if you don't want to configure binary cache for your target, simply remove the line that imports `../../services/binarycache/binary-cache.nix`.

### Generate and encrypt your secrets
At this point, the configuration is otherwise ready, but you have not generated any secrets yet.

First, remove possible earlier secrets you might have copied from ghafhydra. 
(Note: you will obviously not be able to decrypt the secrets from the original ghafhydra [`secrets.yaml`](./hosts/ghafhydra/secrets.yaml) since you don't have the private key that matches one of the age keys in the original [`.sops.yaml`](.sops.yaml) file.)
```bash
$ rm hosts/mytarget/secrets.yaml
```
If you are using the ghafhydra as a template configuration, you are going to need the following secrets:
- `ssh_host_ed25519_key`: this will specify the ssh private key for target server ('mytarget')
- `hydra-admin-password`: this will specify the admin password for the hydra
- `cache-sig-key`: this will specify the nix binary cache private signing key
- `id_buildfarm`: this specifies the private key that allows access to the remote builders

We generated the target server private key for `mytarget` earlier, and it should now be on your host at path `~/.ssh/mytarget_id_ed25519`. The contents of this file will be the value of the `ssh_host_ed25519_key` key in sops.

Run the following command to generate your `cache-sig-key`:

```bash
# Run in nix-shell on your host
$ nix-store --generate-binary-cache-key cache.mytarget ../cache-secret ../cache-public
$ cat ../cache-secret
$ cache.mytarget:vnZqh8F/L4HQKyxXc2moCLIKzFpfwlFeD6c+6PiX5qa5G1z2XnmMK+Su8216hJET8Iwwg6O1hxAVTyxEYzfesQ==
```
The contents of `../cache-secret` will be the value of the `cache-sig-key` key in sops.

Side note: to use your binary cache, you would configure the substituters as follows:

```bash
# Run in nix-shell on your host
$ cat ../cache-public
cache.mytarget:uRtc9l55jCvkrvNteoSRE/CMMIOjtYcQFU8sRGM33rE=

# To use your binary cache, configure the substituters
# Replace with mytarget IP:
substituters = http://10.3.0.4:5000
# Replace with your content from ../cache-public:
trusted-public-keys = cache.mytarget:uRtc9l55jCvkrvNteoSRE/CMMIOjtYcQFU8sRGM33rE=
```

We will not cover the remote builders setup details in this document, however, the contents of the key `id_buildfarm` specifies the private key that allows access to the remote builders.

Now, you are ready to generate your secrets for target `mytarget`:

```bash
# Run in nix-shell on your host
# This will open the secrets.yaml in an editor:
$ sops hosts/mytarget/secrets.yaml
```
The above command opens an editor, where you can edit the secrets.
Remove the example content, and replace with your secrets, so the content would look something like:

```bash
hydra-admin-password: do_not_use_any_of_these_same_values_in_your_secrets
cache-sig-key: cache.mytarget:vnZqh8F/L4HQKyxXc2moCLIKzFpfwlFeD6c+6PiX5qa5G1z2XnmMK+Su8216hJET8Iwwg6O1hxAVTyxEYzfesQ==
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
Notice: in the example sops configuration we defined in `.sops.yaml`, both `myadmin` and `mytarget` can decrypt all the secrets. For production setups you would want to apply the principle of least privilege, that is, only allow decryption for the servers or users who need access to the specific secret content. See, for instance, [nix-community/infra](https://github.com/nix-community/infra/blob/master/.sops.yaml) for a more complete example.

Now, if you re-run the command `sops hosts/mytarget/secrets.yaml`, sops will again decrypt the file allowing you to modify or add new secrets in an editor.

Finally, `git add` your changes (and consider starting off with your new configuration in your own repository).

### Quick sanity checks

After adding your configuration, check nix formatting and fix possible issues:
```bash
# Run in nix-shell on your host (in the repository root)
$ nix fmt
```

Similarly, make sure the pre-push checks on your configuration pass and fix possible issues:
```bash
# Run in nix-shell on your host (in the repository root)
$ inv pre-push
```

## Target setup
If you followed the example in this document, your target setup is now configured in `hosts/mytarget/configuration.nix`. When you install the configuration (see next section), [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) automatically partitions and re-formats the target hard drive, as well as deploys the NixOS configuration you defined in the previous chapter.

In case you want to execute nixos-anywhere manually, or you run into issues executing the installation in your environment, see the documentation in [nixos-anywhere.md](./nixos-anywhere.md).

## Install the target configuration
Please see the documentation in the main [README](../README.md#install) for instructions on how to install the new configuration.

