# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.git.credentials;
in
{
  options.programs.git.credentials = lib.mkOption {
    default = { };
    description = ''
      Background HTTPS Git credentials keyed by URL. Runtime secret-file permissions
      determine which users can authenticate. Matching host credentials take precedence
      over Jenkins job credentials; an insufficiently scoped host token can block
      checkout even when the job's token has access.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          username = lib.mkOption {
            type = lib.types.strMatching "[^\r\n]+";
            default = "x-access-token";
            description = "Git authentication username.";
          };
          passwordFile = lib.mkOption {
            type = lib.types.strMatching "/[^\r\n]+";
            description = "Absolute runtime path to a password or token file. Its contents are never read during Nix evaluation.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg != { }) {
    assertions = [
      {
        assertion = lib.all (url: lib.hasPrefix "https://" url) (lib.attrNames cfg);
        message = "programs.git.credentials URLs must use HTTPS.";
      }
    ];
    programs.git = {
      enable = true;
      config.credential = lib.mapAttrs (_: credential: {
        useHttpPath = true;
        helper = [
          ""
          (lib.getExe (
            pkgs.writeShellApplication {
              name = "git-credential-file";
              runtimeInputs = [ pkgs.coreutils ];
              text = ''
                if [[ $1 != get || ! -r ${lib.escapeShellArg credential.passwordFile} ]]; then
                  exit 0
                fi
                printf '%s\n' ${lib.escapeShellArg "username=${credential.username}"}
                printf 'password='
                cat ${lib.escapeShellArg credential.passwordFile}
                printf '\n'
              '';
            }
          ))
        ];
      }) cfg;
    };
  };
}
