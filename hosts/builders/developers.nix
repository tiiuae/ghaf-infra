# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
let
  groupName = "developers";

  # add new developers here
  developers = [
    {
      desc = "Aleksi Sitomaniemi";
      name = "aleksi";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMse5t/NY8NTs8TUwCWMtlZNU/6HD/p/qDPpmJxXA+uN root@aleksi-ThinkPad-T14-Gen-1"
      ];
    }
    {
      desc = "Alexander Nikolaev";
      name = "avnik";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFi/TNnF6Qvh9UhrHYocJE2CaL4TVZSg6Z+mX8F8LS/v avn@bulldozer"
      ];
    }
    {
      desc = "Mariia Azbeleva";
      name = "azbeleva";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMXq8i5FHMw7vRpAZeXnYux5e6xFgObJgq4+bnY/6s7f mariia@mariia-ThinkPad-T14-Gen-3"
      ];
    }
    {
      desc = "Brian McGillion";
      name = "bmg";
      keys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEJ9ewKwo5FLj6zE30KnTn8+nw7aKdei9SeTwaAeRdJDAAAABHNzaDo="
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo="
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILu6O3swRVWAjP7J8iYGT6st7NAa+o/XaemokmtKdpGa builder key"
      ];
    }
    {
      desc = "Emrah Billur";
      name = "emrah";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGV2WY76z7Ke6tQ19Rc0HnrC7SVS3WkgLHTDj8SVWk24 root@emrah-ThinkPad-P14s-Gen-3"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFGzGy5vw2+bdwcGpQ7gwyiNvZ1HlolSHTP3tEUpzpoC emrah.billur@unikie.com"
      ];
    }
    {
      desc = "Enes Özturk";
      name = "enes-ssh";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINviASH9mqnT59i0Nb6lC5z/e2enwq0k7d4NJK5R0NV5 enes@nixos"
      ];
    }
    {
      desc = "Eugeny Popko";
      name = "eugeny";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3EUPo+XgxgbgnG8ocGiKwI+FME5HgLYXdCwxETDC92 eugeny.popko@tii.ae"
      ];
    }
    {
      desc = "Fouzia Hussain";
      name = "fouzia";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICaNgsqHtgLhIRb7HlLHKhO1upnULaENOC4Kgp5wPuBE fouzia.hussain@tii.ae"
      ];
    }
    {
      desc = "Hai To";
      name = "haito";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjkuCarVGSwSY/DqTpCwIHo/mjEz1DSMK/YHrkAHGWG hai.to@unikie.com"
      ];
    }
    {
      desc = "Humaid Alqasimi";
      name = "humaid";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/iv9RWMN6D9zmEU85XkaU8fAWJreWkv3znan87uqTW"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUlaLlxVlm1KZtoG3R/nHl/KJzmKaIyckDVE2rDJYH+"
      ];
    }
    {
      desc = "Ivan Nikolaenko";
      name = "ivann";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEa7sgJ6XQ58B5bHAc8dahWhCRVOFZ2z5pOCk4g+RLfw ivan.nikolaenko@unikie.com"
      ];
    }
    {
      desc = "Jarek Kurowski";
      name = "jarek";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwGPH/oOrD1g15uiPV4gBKGk7f8ZBSyMEaptKOVs3NG jaroslawkurowski@TII-JaroslawKurowski"
      ];
    }
    {
      desc = "Jari Hodju";
      name = "jhodju";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB1iEdtYVHnkKhd6bCHOTgiYEGEVBTI7xsWJ++ro/PQ8 jhodju@jho-work"
      ];
    }
    {
      desc = "Joonas Loppi";
      name = "joonas";
      keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFjarWokQFXqh4FEMHoyWVjqYwRXoGIKJLHNulNv2bn1" ];
    }
    {
      desc = "Johanna Rautanen";
      name = "jrautanen";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTGKW0fxHUshYTYWRLAPIQe49Cpfg1WMDK+xXYT5FDm root@johanna-ThinkPad-T14-Gen-1"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDlNGpvoYLy2D4rmwOh+EcRJbPlYcn6bXj3xhMbCzntk root@johanna-ThinkPad-T14-Gen-1"
      ];
    }
    {
      desc = "Julius Koskela";
      name = "juliuskoskela";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP2RfxjbhBbdbfXto9dczC4LjE9uixYAReJ/e+dT/cAE julius.koskela@unikie.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJnY0KqTAiC3VwK5tG9SpYaPaK28K24w2dkkI4zoVOQM root@nova"
      ];
    }
    {
      desc = "Kajus Naujokaitis";
      name = "kajusn";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINlIpJ9Q1oW1KiFBa12N5K/ecGVeGSBbcD8M9ZjA0TYe kajus.naujokaitis@unikie.com"
      ];
    }
    {
      desc = "Samuli Leivo";
      name = "leivos";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPE/CgI8MXyHiiUyt7BXWjQG1pb25b4N3als/dKKPZyD samuli@samuli-ThinkPad-T14-Gen-3"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHRGczoQ78cjHdjEgKTyZeLKu/flWlvf+HepdUezZCDr root@nixos"
      ];
    }
    {
      desc = "Malavika Balakrishnan";
      name = "malavika";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFupULSDNZFi+5AtdkAMmVgFj3EaBGks+QSAIcbb9UgS malavika.balakrishnan@tii.ae"
      ];
    }
    {
      desc = "Milla Valio";
      name = "milval";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGll9sWYdGc2xi9oQ25TEcI1D3T4n8MMXoMT+lJdE/KC root@nixos"
      ];
    }
    {
      desc = "Matti Paasto";
      name = "mtpaasto";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDvu5b+k0eKoNE8QiocGaWqKq+E7apIHIie1Va5TM6yE mtpaasto"
      ];
    }
    {
      desc = "Rajkumar Ramasamy";
      name = "rajkumar";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmYFfUPwKkBybdsmjDi4irJMO//2A+sRPZSLOkDvDQN rajkumar.ramasamy@tii.ae"
      ];
    }
    {
      desc = "Renzo Bruzzone";
      name = "renzo";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ/e7vfzx0Sma0BtchhpQAlmAuIUiC11eWi7hOQiItZR renzo.bruzzone@tii.ae"
      ];
    }
    {
      desc = "Ola Rinta-Koski";
      name = "rockola";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOarfl/tww9HCteqvhB6UzbUJU1eC1n+YQUHY+M7l7V4 ola@sorvi"
      ];
    }
    {
      desc = "Omais Pandith";
      name = "omais";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKU0fEolhcsUoUpTNn/sPoN1FYrwPbAyapahTneBkRfG omais.shafi@tii.ae"
      ];
    }
    {
      desc = "Sakari Nousiainen";
      name = "sakarin";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4f1SPr1KZZXzEyUh7ui8AjDzCA6ESSlvs5xQ/Zne8a skr@LAPTOP-GOL8EQAD"
      ];
    }
    {
      desc = "Santtu Lakkala";
      name = "santtu";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlojd3W3lNq/M+j0uOehhGikuOyM3yy81pGdIoxiKOz root@nixos"
      ];
    }
    {
      desc = "Shamma Alblooshi";
      name = "shamma";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3w7NzqMuF+OAiIcYWyP9+J3kwvYMKQ+QeY9J8QjAXm shamma-alblooshi@tii.ae"
      ];
    }
    {
      desc = "Srikar Nayanara";
      name = "Srikar";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5wkbghZvvAps3jejIx4eKTzKx2cC/GjDMOoVvH3V2r root@nixos"
      ];
    }
    {
      desc = "Tanel Dettenborn";
      name = "tanel";
      keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEA7p7hHPvPT6uTU44Nb/p9/DT9mOi8mpqNllnpfawDE desk" ];
    }
    {
      desc = "Vadim Likholetov";
      name = "vadikas";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJKQ+6iZKKw0eMJbuMTIyoZ9940ecNlac6dqCpy3eiCq vadikas@c57bl6"
      ];
    }
    {
      desc = "Yuriy Nesterov";
      name = "yuriy";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPOiqwFk/BR8SKxrDAqadlnEQt5oLBaMyoZL3IQv0Nfj yuriy.nesterov@unikie.com"
      ];
    }
    {
      desc = "Vunny Sodhi";
      name = "vunnyso";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIstCgKDX1vVWI8MgdVwsEMhju6DQJubi3V0ziLcU/2h vunny.sodhi@unikie.com"
      ];
    }
    {
      desc = "Mikko Saarinen";
      name = "mikkos";
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILDvhfh9J9ac5+9QQ9FdSQe9XK5fiJf8z8kcWzQfjsWv root@nixos"
      ];
    }
  ];
in
{
  users = {
    groups."${groupName}" = { };

    users = builtins.listToAttrs (
      map (
        {
          desc,
          name,
          keys,
        }:
        lib.nameValuePair name {
          inherit name;

          description = desc;
          openssh.authorizedKeys.keys = keys;

          isNormalUser = true;
          extraGroups = [ groupName ];
        }
      ) developers
    );
  };

  nix.settings.trusted-users = [ "@${groupName}" ];
}
