# SPDX-FileCopyrightText: 2003-2024 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-License-Identifier: MIT
{
  stdenv,
  lib,
  autoPatchelfHook,
  fetchFromGitHub,
  curl,
  systemd,
  zlib,
  writeText,
  withUpdater ? true,
  ...
}: let
  version = "2.9.25";
  # Upstream has a udev.sh script asking for mode and group, but with uaccess we
  # don't need any of that and can make it entirely static.
  # For any rule adding the uaccess tag to be effective, the name of the file it
  # is defined in has to lexically precede 73-seat-late.rules.
  udevRule = writeText "60-brainstem.rules" ''
    # Acroname Brainstem control devices
    SUBSYSTEM=="usb", ATTRS{idVendor}=="24ff", TAG+="uaccess"

    # Acroname recovery devices (pb82, pb242, pb167)
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="274e", TAG+="uaccess"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="0130", TAG+="uaccess"
  '';

  # 2.9.25 seems to be gone from the official servers.
  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "ci-test-automation";
    rev = "7b44c09b2663666d83dc4764a67114ea6708e26b";
    hash = "sha256-1Xq+J4IEsdGI+nOvyrxES5L0SZw+yA9nwVBN1lOGU20=";
  };
in
  stdenv.mkDerivation {
    pname = "brainstem";
    inherit version src;
    sourceRoot = "source/BrainStem_dev_kit";

    nativeBuildInputs = [autoPatchelfHook];
    buildInputs =
      [
        # libudev
        (lib.getLib systemd)
        # libstdc++.so libgcc_s.so
        stdenv.cc.cc.lib
      ]
      ++ lib.optionals withUpdater [
        # libcurl.so.4
        curl
        # libz.so.1
        zlib
      ];

    # Unpack the CLI tools.
    installPhase = ''
      mkdir -p $out/bin
      install -m744 bin/AcronameHubCLI $out/bin
      install -m744 bin/Updater $out/bin/AcronameHubUpdater

      mkdir -p $out/lib/udev/rules.d
      cp ${udevRule} $out/lib/udev/rules.d/60-brainstem.rules

      mkdir -p $doc
      cp {license,version}.txt $doc/
    '';

    outputs = ["out" "doc"];

    meta = with lib; {
      description = "BrainStem Software Development Kit";
      longDescription = ''
        The BrainStem SDK provides a library to access and control Acroname smart
        USB switches, as well as a CLI interface, and a firmware updater.
      '';
      homepage = "https://acroname.com/software/brainstem-development-kit";
      platforms = ["x86_64-linux"];
      license = licenses.unfree;
      maintainers = with maintainers; [flokli];
      mainProgram = "AcronameHubCLI";
    };
  }
