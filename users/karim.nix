# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  users.users = {
    karim = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDe5L8iOqhNPsYz5eh9Bz/URYguG60JjMGmKG0wwLIb6Gf2M8Txzk24ESGbMR/F5RYsV1yWYOocL47ngDWQIbO6MGJ7ftUr7slWoUA/FSVwh/jsG681mRqIuJXjKM/YQhBkI9k6+eVxRfLDTs5XZfbwdm7T4aP8ZI2609VY0guXfa/F7DSE1BxN7IJMn0CWLQJanBpoYUxqyQXCUXgljMokdPjTrqAxlBluMsVTP+ZKDnjnpHcVE/hCKk5BxaU6K97OdeIOOEWXAd6uEHssomjtU7+7dhiZzjhzRPKDiSJDF9qtIw50kTHz6ZTdH8SAZmu0hsS6q8OmmDTAnt24dFJV karim@nixos"
      ];
      extraGroups = ["wheel" "networkmanager"];
    };
  };
}
