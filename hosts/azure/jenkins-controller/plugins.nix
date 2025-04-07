{ stdenv, fetchurl }:
  let
    mkJenkinsPlugin = { name, src }:
      stdenv.mkDerivation {
        inherit name src;
        phases = "installPhase";
        installPhase = "cp \$src \$out";
        };
  in {
    antisamy-markup-formatter = mkJenkinsPlugin {
      name = "antisamy-markup-formatter";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/antisamy-markup-formatter/173.v680e3a_b_69ff3/antisamy-markup-formatter.hpi";
        sha256 = "29b4765797f26c44574a2732ddf9d7d98ea0283295352497dd9eef84aed0102f";
        };
      };
    apache-httpcomponents-client-4-api = mkJenkinsPlugin {
      name = "apache-httpcomponents-client-4-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/apache-httpcomponents-client-4-api/4.5.14-269.vfa_2321039a_83/apache-httpcomponents-client-4-api.hpi";
        sha256 = "cea2f61cc72890b962fd4b767c31778c6cb30015b4a8758b4c26b62e51ca9533";
        };
      };
    apache-httpcomponents-client-5-api = mkJenkinsPlugin {
      name = "apache-httpcomponents-client-5-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/apache-httpcomponents-client-5-api/5.4.3-140.v2516ccde99e7/apache-httpcomponents-client-5-api.hpi";
        sha256 = "8eac147be1125f408bce9da8bd2794fbf4b7f0423515f080271569862324e589";
        };
      };
    asm-api = mkJenkinsPlugin {
      name = "asm-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/asm-api/9.8-135.vb_2239d08ee90/asm-api.hpi";
        sha256 = "95e71f7c5e1e98b6dacb4371d51cb6c4443922ec0f88c37409c366a1e4ba37d4";
        };
      };
    authentication-tokens = mkJenkinsPlugin {
      name = "authentication-tokens";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/authentication-tokens/1.131.v7199556c3004/authentication-tokens.hpi";
        sha256 = "9055ac45ef9ca8a84b89c734019ef86e06a526b487adcfa9c6320550cf766b4d";
        };
      };
    block-queued-job = mkJenkinsPlugin {
      name = "block-queued-job";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/block-queued-job/0.2.0/block-queued-job.hpi";
        sha256 = "146f92df5a747d77beb099e2f9edbebf32922303dd0970f1d2c80ad8c4740d01";
        };
      };
    blueocean = mkJenkinsPlugin {
      name = "blueocean";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean/1.27.17/blueocean.hpi";
        sha256 = "d149f0b5ebc195e386bddec0581e942f349e2abdce2a896f33f7dec0a2a75188";
        };
      };
    blueocean-bitbucket-pipeline = mkJenkinsPlugin {
      name = "blueocean-bitbucket-pipeline";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-bitbucket-pipeline/1.27.17/blueocean-bitbucket-pipeline.hpi";
        sha256 = "a8288a4fb07f26ef0c462a75da6d6dae87c89fe49ec508c8b2c7a0c61af638bd";
        };
      };
    blueocean-commons = mkJenkinsPlugin {
      name = "blueocean-commons";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-commons/1.27.17/blueocean-commons.hpi";
        sha256 = "a92557b92702aeaffa12d154293216be358022c97ff59616869ea28c8324f74f";
        };
      };
    blueocean-config = mkJenkinsPlugin {
      name = "blueocean-config";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-config/1.27.17/blueocean-config.hpi";
        sha256 = "4fada3b017bcf8c89cf60976ca5873d8a02d98a3edee4663ad8adad91d25b1f4";
        };
      };
    blueocean-core-js = mkJenkinsPlugin {
      name = "blueocean-core-js";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-core-js/1.27.17/blueocean-core-js.hpi";
        sha256 = "bd09717925acfba2ecc7c33d481e0ec4f56fe99907f890ef78a53e4afc68e9dc";
        };
      };
    blueocean-dashboard = mkJenkinsPlugin {
      name = "blueocean-dashboard";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-dashboard/1.27.17/blueocean-dashboard.hpi";
        sha256 = "efaaa3b993bea45ed3b0b5256cc0fe13f2a95eaef1f7b1d0e0a8b68ebbb00d6d";
        };
      };
    blueocean-display-url = mkJenkinsPlugin {
      name = "blueocean-display-url";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-display-url/2.4.4/blueocean-display-url.hpi";
        sha256 = "02436c6cc8b35dd9a4f925a13b547bf163703233e7061703e428e98cd8e0d17a";
        };
      };
    blueocean-events = mkJenkinsPlugin {
      name = "blueocean-events";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-events/1.27.17/blueocean-events.hpi";
        sha256 = "ed680581eec16e1417692bcc05368cfbce1e4e704a497c0224d2f364ada548e1";
        };
      };
    blueocean-executor-info = mkJenkinsPlugin {
      name = "blueocean-executor-info";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-executor-info/1.27.17/blueocean-executor-info.hpi";
        sha256 = "9322e1b29ad7c8ac0bebf0e988c4cb1471c432cb1f244182f5deb827548bdb01";
        };
      };
    blueocean-git-pipeline = mkJenkinsPlugin {
      name = "blueocean-git-pipeline";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-git-pipeline/1.27.17/blueocean-git-pipeline.hpi";
        sha256 = "eb370eec677a674c141daaf832d92e23f408244d9041c8568f5f9b4c45b52a4d";
        };
      };
    blueocean-github-pipeline = mkJenkinsPlugin {
      name = "blueocean-github-pipeline";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-github-pipeline/1.27.17/blueocean-github-pipeline.hpi";
        sha256 = "3f07435deb46d1caf8570ea178a40dd92cb873b9e3a220c0ee25d287a315c23d";
        };
      };
    blueocean-i18n = mkJenkinsPlugin {
      name = "blueocean-i18n";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-i18n/1.27.17/blueocean-i18n.hpi";
        sha256 = "11d2965f8bbc64a11e77864aa50fc80b6c9705996a39d1a0acc2d4cf4396123d";
        };
      };
    blueocean-jwt = mkJenkinsPlugin {
      name = "blueocean-jwt";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-jwt/1.27.17/blueocean-jwt.hpi";
        sha256 = "120a40cbe38cdd9d969ad5b66baebfdce1e7a42278fd09cbe0f28de0b15cbdb7";
        };
      };
    blueocean-personalization = mkJenkinsPlugin {
      name = "blueocean-personalization";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-personalization/1.27.17/blueocean-personalization.hpi";
        sha256 = "b8be9cb2da0bb3eb002c2e8df923037b0218d6a289b80d227b1ef6b4ce9117ed";
        };
      };
    blueocean-pipeline-api-impl = mkJenkinsPlugin {
      name = "blueocean-pipeline-api-impl";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-pipeline-api-impl/1.27.17/blueocean-pipeline-api-impl.hpi";
        sha256 = "a3e464b90e257f858286bfab7137d7c6cd20de65e715820af9a28347d2f52aad";
        };
      };
    blueocean-pipeline-editor = mkJenkinsPlugin {
      name = "blueocean-pipeline-editor";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-pipeline-editor/1.27.17/blueocean-pipeline-editor.hpi";
        sha256 = "618e6369797aad5bce4976921c57f08162ee5f647cce140ea085c659cac1805e";
        };
      };
    blueocean-pipeline-scm-api = mkJenkinsPlugin {
      name = "blueocean-pipeline-scm-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-pipeline-scm-api/1.27.17/blueocean-pipeline-scm-api.hpi";
        sha256 = "e5335b680a70d57ee64d8fb654b1108696a4ea5c08f0ead67b3a39052d720344";
        };
      };
    blueocean-rest = mkJenkinsPlugin {
      name = "blueocean-rest";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-rest/1.27.17/blueocean-rest.hpi";
        sha256 = "2a5afc92fd4ec848c3ed29cc28cd81735a1f8c9c4c322ab694693c532dad802e";
        };
      };
    blueocean-rest-impl = mkJenkinsPlugin {
      name = "blueocean-rest-impl";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-rest-impl/1.27.17/blueocean-rest-impl.hpi";
        sha256 = "e8a82cd0fb44d3983e90a673150c097e682e6a92ec405b5aec535001cc986182";
        };
      };
    blueocean-web = mkJenkinsPlugin {
      name = "blueocean-web";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-web/1.27.17/blueocean-web.hpi";
        sha256 = "417c84bc841d40b2dcd9ad1e16356eac290413494485a04a7a98079bc8647938";
        };
      };
    bootstrap5-api = mkJenkinsPlugin {
      name = "bootstrap5-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/bootstrap5-api/5.3.3-2/bootstrap5-api.hpi";
        sha256 = "b3bebc1e4590e15b6b2aa4286940b5b9d312699487c32c84c9278f8bb159151b";
        };
      };
    bouncycastle-api = mkJenkinsPlugin {
      name = "bouncycastle-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/bouncycastle-api/2.30.1.80-256.vf98926042a_9b_/bouncycastle-api.hpi";
        sha256 = "164ba1481c6efc98f28e1242977a83c251fdbc98efadf542affd40b5e0738e7b";
        };
      };
    branch-api = mkJenkinsPlugin {
      name = "branch-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/branch-api/2.1214.v3f652804588d/branch-api.hpi";
        sha256 = "ad384d818a301c44a634e2a23a6716e88f61d39eb1a2610a550be69d2caeb2c9";
        };
      };
    caffeine-api = mkJenkinsPlugin {
      name = "caffeine-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/caffeine-api/3.2.0-166.v72a_6d74b_870f/caffeine-api.hpi";
        sha256 = "d95ee34910e5c965636fc04bb61f1d4d8cb6c457aa3c32ca953243fe2d3df013";
        };
      };
    checks-api = mkJenkinsPlugin {
      name = "checks-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/checks-api/367.v18b_7f530e54a_/checks-api.hpi";
        sha256 = "e94990b4bdaa7fe3754d897a0452c2d079b458d89ffd7c4d665650f96a2b1c56";
        };
      };
    cloudbees-bitbucket-branch-source = mkJenkinsPlugin {
      name = "cloudbees-bitbucket-branch-source";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/cloudbees-bitbucket-branch-source/935.1.3/cloudbees-bitbucket-branch-source.hpi";
        sha256 = "d856524885a7f5db8b58f66f10bb00d07c60583e024656e385a954da0c73d85b";
        };
      };
    cloudbees-folder = mkJenkinsPlugin {
      name = "cloudbees-folder";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/cloudbees-folder/6.999.v42253c105443/cloudbees-folder.hpi";
        sha256 = "66b97318dbb531a726bf3a9a7e620d848d7b50990840f12acf7dc79a8e481537";
        };
      };
    command-launcher = mkJenkinsPlugin {
      name = "command-launcher";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/command-launcher/118.v72741845c17a_/command-launcher.hpi";
        sha256 = "421e6a0afe1f2e8283343af60ac51843b7b2508aeeff9af0e9d6a34b6307eafa";
        };
      };
    commons-compress-api = mkJenkinsPlugin {
      name = "commons-compress-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/commons-compress-api/1.27.1-3/commons-compress-api.hpi";
        sha256 = "d8bfea27e58bdc098bf9a9a044fe90d21f09fd8ccb56acd730d61de8a7b87c29";
        };
      };
    commons-lang3-api = mkJenkinsPlugin {
      name = "commons-lang3-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/commons-lang3-api/3.17.0-87.v5cf526e63b_8b_/commons-lang3-api.hpi";
        sha256 = "d654d467dbb60d7af0b7641d972abff40b1509a2379b2350b2774e00a1df54cf";
        };
      };
    commons-text-api = mkJenkinsPlugin {
      name = "commons-text-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/commons-text-api/1.13.0-153.v91dcd89e2a_22/commons-text-api.hpi";
        sha256 = "90806f02ee4b06bf49d1a113d64a0c5da56a50d1eabd47853538a5dd9f0c94c2";
        };
      };
    conditional-buildstep = mkJenkinsPlugin {
      name = "conditional-buildstep";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/conditional-buildstep/1.5.0/conditional-buildstep.hpi";
        sha256 = "eb6cdd4191eb4405949c7b6c0289d90552f47f5e2dd4a41624769e91fb1f8b52";
        };
      };
    config-file-provider = mkJenkinsPlugin {
      name = "config-file-provider";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/config-file-provider/982.vb_a_e458a_37021/config-file-provider.hpi";
        sha256 = "97d2a01c8403553b9619b346a635cb4d3ec3d8a423226c5054e16420115feb55";
        };
      };
    configuration-as-code = mkJenkinsPlugin {
      name = "configuration-as-code";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/configuration-as-code/1950.v506f96a_69516/configuration-as-code.hpi";
        sha256 = "9f12d795704085264fd8e71af0e71087d89cc91496a5f5bf4ab4e8f3ded2d3bb";
        };
      };
    copyartifact = mkJenkinsPlugin {
      name = "copyartifact";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/copyartifact/765.v0357cc6e6eb_3/copyartifact.hpi";
        sha256 = "881b918d8b97feb9c80163ceb5840e0d5ef03b1e1cf30ef42607a8e0de283e00";
        };
      };
    credentials = mkJenkinsPlugin {
      name = "credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/credentials/1413.va_51c53703df1/credentials.hpi";
        sha256 = "ce061bebaf12de45fa7a5ec7a4033b5e247d93b54eee0df7384e908281616007";
        };
      };
    credentials-binding = mkJenkinsPlugin {
      name = "credentials-binding";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/credentials-binding/687.v619cb_15e923f/credentials-binding.hpi";
        sha256 = "3a589c067bfc21e3792f2f60efa63a5a46ceedcb13af2b1ad4b1f631e4f37d0d";
        };
      };
    data-tables-api = mkJenkinsPlugin {
      name = "data-tables-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/data-tables-api/2.2.2-1/data-tables-api.hpi";
        sha256 = "0c3320e62c22e927d182aa92ed066db6281a23512082e4f5259838607c5d620a";
        };
      };
    display-url-api = mkJenkinsPlugin {
      name = "display-url-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/display-url-api/2.209.v582ed814ff2f/display-url-api.hpi";
        sha256 = "413075f95bb93769708a5d4d660ca454f10005f10af26f5213f788e9750e6825";
        };
      };
    durable-task = mkJenkinsPlugin {
      name = "durable-task";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/durable-task/587.v84b_877235b_45/durable-task.hpi";
        sha256 = "f44a5d865767fbf8b37c68c9f7ff5fa26ae76964784f1e2e426ac5e2d6b939b4";
        };
      };
    echarts-api = mkJenkinsPlugin {
      name = "echarts-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/echarts-api/5.6.0-2/echarts-api.hpi";
        sha256 = "24a9cf2b169651956218dfac1df6553dab1099b90b8996cfe01d488a7a64effa";
        };
      };
    eddsa-api = mkJenkinsPlugin {
      name = "eddsa-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/eddsa-api/0.3.0.1-19.vc432d923e5ee/eddsa-api.hpi";
        sha256 = "35c7decb2c08accb96a7a4d54cac7d0af6713c242192142dad56cec50949143a";
        };
      };
    email-ext = mkJenkinsPlugin {
      name = "email-ext";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/email-ext/1876.v28d8d38315b_d/email-ext.hpi";
        sha256 = "c0fc6b34b133fd2c8d293d9d02933cf410c5d37fceeca29a7c351f692d806168";
        };
      };
    favorite = mkJenkinsPlugin {
      name = "favorite";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/favorite/2.225.v68765b_b_a_1fa_3/favorite.hpi";
        sha256 = "c609d80b0b3616fb15564ed0af161893f909e5edfb293f1231deecd67868cec8";
        };
      };
    font-awesome-api = mkJenkinsPlugin {
      name = "font-awesome-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/font-awesome-api/6.7.2-1/font-awesome-api.hpi";
        sha256 = "039c676c61f45cc256e7759abdc5c3c8d46533895e403cf1128895ad4b19dd3f";
        };
      };
    git = mkJenkinsPlugin {
      name = "git";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/git/5.7.0/git.hpi";
        sha256 = "20f7121b7cfda1d31b0c447b3e3598dc9e5f04fd5fe7e9e784122a496c2e5cea";
        };
      };
    git-client = mkJenkinsPlugin {
      name = "git-client";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/git-client/6.1.2/git-client.hpi";
        sha256 = "877642422e79247956bf8e0ce857132a2ba60a1482fae822b769a3233c484f49";
        };
      };
    github = mkJenkinsPlugin {
      name = "github";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/github/1.43.0/github.hpi";
        sha256 = "b283571c612f19f6788e72d4129b580661d526a0d645e3d3b9a09fde01b20d45";
        };
      };
    github-api = mkJenkinsPlugin {
      name = "github-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/github-api/1.321-488.v9b_c0da_9533f8/github-api.hpi";
        sha256 = "14ee4a2c87df8a0fa9d5ac1d51b3d9e58962b1d0e6e74e62bc0ba3b19f656891";
        };
      };
    github-branch-source = mkJenkinsPlugin {
      name = "github-branch-source";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/github-branch-source/1815.v9152b_2ff7a_1b_/github-branch-source.hpi";
        sha256 = "d1abfd49d60870af0cf32b51b2ad9436262ff92e496cdd191c09fa806917050d";
        };
      };
    github-pullrequest = mkJenkinsPlugin {
      name = "github-pullrequest";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/github-pullrequest/0.7.2/github-pullrequest.hpi";
        sha256 = "edcad949225a207be97bf275c5f76dc3277cf58be3e2cb358d03035d6f6ffa3e";
        };
      };
    gson-api = mkJenkinsPlugin {
      name = "gson-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/gson-api/2.12.1-113.v347686d6729f/gson-api.hpi";
        sha256 = "831d5ccb408f5f646eb08fa3dc4ce16958fcc72da3c27ed2b1a721642879524d";
        };
      };
    handy-uri-templates-2-api = mkJenkinsPlugin {
      name = "handy-uri-templates-2-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/handy-uri-templates-2-api/2.1.8-36.v85e4cb_234a_13/handy-uri-templates-2-api.hpi";
        sha256 = "3521bf7b304ab606ff12aaf3ccbad2317f9e752b783fa2263266f1759e6a71e1";
        };
      };
    htmlpublisher = mkJenkinsPlugin {
      name = "htmlpublisher";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/htmlpublisher/425/htmlpublisher.hpi";
        sha256 = "83acb548eaa5ab4f4a5f41edabe55376c120df097d832f5480713135d7da75c3";
        };
      };
    instance-identity = mkJenkinsPlugin {
      name = "instance-identity";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/instance-identity/203.v15e81a_1b_7a_38/instance-identity.hpi";
        sha256 = "df2b3205a6177248f12b294650a60405f65ba2cd503ca9599b2dcb72c1de5018";
        };
      };
    ionicons-api = mkJenkinsPlugin {
      name = "ionicons-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ionicons-api/82.v0597178874e1/ionicons-api.hpi";
        sha256 = "ec8e414ae2a325e070bff80522f013189936150d620e8cad018edb766c47f893";
        };
      };
    jackson2-api = mkJenkinsPlugin {
      name = "jackson2-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jackson2-api/2.18.3-402.v74c4eb_f122b_2/jackson2-api.hpi";
        sha256 = "7ca2d68754c44b79c8137fb60df3c89b9b9cb42342a42477b1b26dbe47903278";
        };
      };
    jakarta-activation-api = mkJenkinsPlugin {
      name = "jakarta-activation-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jakarta-activation-api/2.1.3-2/jakarta-activation-api.hpi";
        sha256 = "784887a95486dfdc37c31fb7a67539fd2ed55fcf5f0d13ccf300488e2b776753";
        };
      };
    jakarta-mail-api = mkJenkinsPlugin {
      name = "jakarta-mail-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jakarta-mail-api/2.1.3-2/jakarta-mail-api.hpi";
        sha256 = "85ed32925d9e4aca4f7e23b73c61c7c9a643a0accf17f9bdf3f42385217e34c2";
        };
      };
    javadoc = mkJenkinsPlugin {
      name = "javadoc";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/javadoc/310.v032f3f16b_0f8/javadoc.hpi";
        sha256 = "a51bff9a3eb584f95d6db8551635e8e728a672c24fb4e436151664078cef3f63";
        };
      };
    javax-activation-api = mkJenkinsPlugin {
      name = "javax-activation-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/javax-activation-api/1.2.0-8/javax-activation-api.hpi";
        sha256 = "e96e88c52edf07ba00fb45b26cc411a7a95fa3d4491aaa1a5d36637665880560";
        };
      };
    jaxb = mkJenkinsPlugin {
      name = "jaxb";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jaxb/2.3.9-133.vb_ec76a_73f706/jaxb.hpi";
        sha256 = "62eddf7775e5b729841a9697625ccd1a5134e754cc476a0098b53b64e0591ee8";
        };
      };
    jenkins-design-language = mkJenkinsPlugin {
      name = "jenkins-design-language";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jenkins-design-language/1.27.17/jenkins-design-language.hpi";
        sha256 = "4960656871527e58880f798c3091ebcbf79678003a7bc9be27ddb7e18a162512";
        };
      };
    jjwt-api = mkJenkinsPlugin {
      name = "jjwt-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jjwt-api/0.11.5-120.v0268cf544b_89/jjwt-api.hpi";
        sha256 = "c88bcbd7573ccb31ed9d819ee2611eb019d733a9d51cd1b70ad53a61aaf52489";
        };
      };
    job-dsl = mkJenkinsPlugin {
      name = "job-dsl";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/job-dsl/1.91/job-dsl.hpi";
        sha256 = "8d453e056014ef71e2870fa960c9da4d085a06558406816d05b802fd26c3e05e";
        };
      };
    joda-time-api = mkJenkinsPlugin {
      name = "joda-time-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/joda-time-api/2.14.0-127.v7d9da_295a_d51/joda-time-api.hpi";
        sha256 = "c273898fb627a13743e7b6e37b13d911b3ec37a8ffef515b218409a0fb54b05c";
        };
      };
    jquery3-api = mkJenkinsPlugin {
      name = "jquery3-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jquery3-api/3.7.1-3/jquery3-api.hpi";
        sha256 = "1823f32895013b8c75adfa975265482968a12aad768c71c66b69960a96e52a34";
        };
      };
    jsch = mkJenkinsPlugin {
      name = "jsch";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jsch/0.2.16-95.v3eecb_55fa_b_78/jsch.hpi";
        sha256 = "2c61d204ed4d2c0ee3a208bfc3c68f52031d4942b9693cca1d0849db4cde0616";
        };
      };
    json-api = mkJenkinsPlugin {
      name = "json-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/json-api/20250107-125.v28b_a_ffa_eb_f01/json-api.hpi";
        sha256 = "71ac9158623ca2703cf408f90cc3d8c5aa1806facab0964220148d127886ea38";
        };
      };
    json-path-api = mkJenkinsPlugin {
      name = "json-path-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/json-path-api/2.9.0-148.v22a_7ffe323ce/json-path-api.hpi";
        sha256 = "93fcc1f46b6c292dfc465ae45f094d5e0eb7ad37a60a9976ad43f0f4b5b55991";
        };
      };
    jucies = mkJenkinsPlugin {
      name = "jucies";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jucies/0.2.1/jucies.hpi";
        sha256 = "98845519bdb8cc0969d84cf5ab9096ad960a39c0267a7dbf8685736181ef93d3";
        };
      };
    junit = mkJenkinsPlugin {
      name = "junit";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/junit/1319.v000471ca_e5e2/junit.hpi";
        sha256 = "59af8c6b79bf06e1ea23e7896035ebb23810d7a772f2ae612e1d9be069b52b4c";
        };
      };
    lockable-resources = mkJenkinsPlugin {
      name = "lockable-resources";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/lockable-resources/1349.v8b_ccb_c5487f7/lockable-resources.hpi";
        sha256 = "289789038919ca4a11df09e03c1d5a4e53c2c7573f31cc47c2b1914f2920d285";
        };
      };
    mailer = mkJenkinsPlugin {
      name = "mailer";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mailer/489.vd4b_25144138f/mailer.hpi";
        sha256 = "1d836fe30c6515f3918f951d12a4f4aad1d9108eeaa059ff8beaae5e44527da0";
        };
      };
    mapdb-api = mkJenkinsPlugin {
      name = "mapdb-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mapdb-api/1.0.9-44.va_1e1310c9118/mapdb-api.hpi";
        sha256 = "e9ef3c650728b9b8d391966281811a0e326b231167d8ef7e3761f7f985196baa";
        };
      };
    matrix-auth = mkJenkinsPlugin {
      name = "matrix-auth";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/matrix-auth/3.2.6/matrix-auth.hpi";
        sha256 = "723e7c8f732eadfcea2446c3b70fad349fddca868c47ea2383de34855c9271bc";
        };
      };
    matrix-project = mkJenkinsPlugin {
      name = "matrix-project";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/matrix-project/847.v88a_f90ff9f20/matrix-project.hpi";
        sha256 = "f4a4aeadf50e2e86492873cb5ff35f115bd2b3c6f1e9bc227b373c249a642511";
        };
      };
    maven-plugin = mkJenkinsPlugin {
      name = "maven-plugin";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/maven-plugin/3.25/maven-plugin.hpi";
        sha256 = "d9e2db3a05aeacd20d60480945a753295a97d6431980e92e4f57e66136525b8f";
        };
      };
    metrics = mkJenkinsPlugin {
      name = "metrics";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/metrics/4.2.21-464.vc9fa_a_0d6265d/metrics.hpi";
        sha256 = "3f2be787bf505c97a92e91c431139d9800f401d50a7d15b3a3a25f039543273e";
        };
      };
    mina-sshd-api-common = mkJenkinsPlugin {
      name = "mina-sshd-api-common";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mina-sshd-api-common/2.15.0-161.vb_200831a_c15b_/mina-sshd-api-common.hpi";
        sha256 = "c8c7b80c3cfd6a6ab40effff19d2f43338ee12345f51774c43b9628be4256960";
        };
      };
    mina-sshd-api-core = mkJenkinsPlugin {
      name = "mina-sshd-api-core";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mina-sshd-api-core/2.15.0-161.vb_200831a_c15b_/mina-sshd-api-core.hpi";
        sha256 = "4e55944cda37658d692215740c842850d11b4baef79b5aa9bcb4085b66ba1a59";
        };
      };
    node-iterator-api = mkJenkinsPlugin {
      name = "node-iterator-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/node-iterator-api/72.vc90e81737df1/node-iterator-api.hpi";
        sha256 = "3e58cdffaff51d4b0b0e33032b629756d16e5a0df91fcf61df9e83cc0d543bd6";
        };
      };
    okhttp-api = mkJenkinsPlugin {
      name = "okhttp-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/okhttp-api/4.11.0-189.v976fa_d3379d6/okhttp-api.hpi";
        sha256 = "f08cd625c7316d9f2cea3e968bd7579cbca53fb54a4251b6afa2064b2eefd077";
        };
      };
    oss-symbols-api = mkJenkinsPlugin {
      name = "oss-symbols-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/oss-symbols-api/308.v0c48656b_15c1/oss-symbols-api.hpi";
        sha256 = "61ac4385c8ebc62f9bda348df3f4d7a8e5d1c8cabad7130341072095df557d4a";
        };
      };
    parameterized-trigger = mkJenkinsPlugin {
      name = "parameterized-trigger";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/parameterized-trigger/840.v3c7d4a_a_5e6c7/parameterized-trigger.hpi";
        sha256 = "6498279150bf59320f7ae9c0c5405592221f4a6a659ccfc198e3bb82eafa7a33";
        };
      };
    pipeline-build-step = mkJenkinsPlugin {
      name = "pipeline-build-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-build-step/557.v95d96f77b_2b_8/pipeline-build-step.hpi";
        sha256 = "d5f932fc140132f09a9c36be0c61dfd7b8cc697273e08ddb44abb7f37fc60051";
        };
      };
    pipeline-graph-analysis = mkJenkinsPlugin {
      name = "pipeline-graph-analysis";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-graph-analysis/235.vb_a_a_36b_f248c2/pipeline-graph-analysis.hpi";
        sha256 = "1246a578551938dcf14ba9d9167f0cddcc1887a4e452c03f6254853a8b4c8053";
        };
      };
    pipeline-graph-view = mkJenkinsPlugin {
      name = "pipeline-graph-view";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-graph-view/423.v765c49ca_da_3f/pipeline-graph-view.hpi";
        sha256 = "47585536f6e141299cff9746e79687768bdae40ab7fd6a67b2c5fdc86c5a92b7";
        };
      };
    pipeline-groovy-lib = mkJenkinsPlugin {
      name = "pipeline-groovy-lib";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-groovy-lib/752.vdddedf804e72/pipeline-groovy-lib.hpi";
        sha256 = "ed150d08dacd67abeebb90a9996eceb8e2610ddb544adfd57148d0729eb997dc";
        };
      };
    pipeline-input-step = mkJenkinsPlugin {
      name = "pipeline-input-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-input-step/517.vf8e782ee645c/pipeline-input-step.hpi";
        sha256 = "534a02cb1dcfb859e6ed6b3b7150f49fb66f0d7db7535352f6e72cb71d25b099";
        };
      };
    pipeline-milestone-step = mkJenkinsPlugin {
      name = "pipeline-milestone-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-milestone-step/127.vb_52887ca_3b_6d/pipeline-milestone-step.hpi";
        sha256 = "8a9f3d00b24f927324a225dbb4a58fa17466a1629c953a636c659dbd56809439";
        };
      };
    pipeline-model-api = mkJenkinsPlugin {
      name = "pipeline-model-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-api/2.2247.va_423189a_7dff/pipeline-model-api.hpi";
        sha256 = "0d5e59a75be9661b40ae53121973d00c52c4e9ae22a4545c74c55b28da98aa19";
        };
      };
    pipeline-model-definition = mkJenkinsPlugin {
      name = "pipeline-model-definition";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-definition/2.2247.va_423189a_7dff/pipeline-model-definition.hpi";
        sha256 = "843a9c0cdaf35bb59e55f507b44516e636154e5fde5a4f3829cc07f86b6d92dd";
        };
      };
    pipeline-model-extensions = mkJenkinsPlugin {
      name = "pipeline-model-extensions";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-extensions/2.2247.va_423189a_7dff/pipeline-model-extensions.hpi";
        sha256 = "d1a9c5a0bc05b1ead2e5fb31f1d8b118c695b86108c8b91db872b89e78260fd2";
        };
      };
    pipeline-rest-api = mkJenkinsPlugin {
      name = "pipeline-rest-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-rest-api/2.37/pipeline-rest-api.hpi";
        sha256 = "73db2513aee2d2307ed52461a247655874e5dd177d54d7ddec01bb5ff582956c";
        };
      };
    pipeline-stage-step = mkJenkinsPlugin {
      name = "pipeline-stage-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-step/322.vecffa_99f371c/pipeline-stage-step.hpi";
        sha256 = "e4ed6438ff6073156bc4269d362129b34099a0da7f2abb279b2e39e7dc0a75ca";
        };
      };
    pipeline-stage-tags-metadata = mkJenkinsPlugin {
      name = "pipeline-stage-tags-metadata";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-tags-metadata/2.2247.va_423189a_7dff/pipeline-stage-tags-metadata.hpi";
        sha256 = "3c2e2e0b66dd4cc182f8aaa8e83dfd9745b50e22407435563801a2cd026de6ea";
        };
      };
    pipeline-stage-view = mkJenkinsPlugin {
      name = "pipeline-stage-view";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-view/2.37/pipeline-stage-view.hpi";
        sha256 = "5c82408038e2eba30f477aa87a0f14a38ace4cd3a6edcee0cf717434bc66726e";
        };
      };
    pipeline-utility-steps = mkJenkinsPlugin {
      name = "pipeline-utility-steps";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-utility-steps/2.19.0/pipeline-utility-steps.hpi";
        sha256 = "14733e0b9adcd2bb97c1672b41e7fceafcdef08ef3b7349012943be291c9b3c7";
        };
      };
    plain-credentials = mkJenkinsPlugin {
      name = "plain-credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/plain-credentials/195.vb_906e9073dee/plain-credentials.hpi";
        sha256 = "ea6b3b4da3fcc73cab79703364735c18d6777c80c8b4511e55eb0767d33c9756";
        };
      };
    plugin-util-api = mkJenkinsPlugin {
      name = "plugin-util-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/plugin-util-api/6.1.0/plugin-util-api.hpi";
        sha256 = "8a05d7920ecde96f45406a926ff6708ce70aa7c830444ecaffc9ebe1220a45d0";
        };
      };
    prism-api = mkJenkinsPlugin {
      name = "prism-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/prism-api/1.30.0-1/prism-api.hpi";
        sha256 = "b23e28bce3a429bf715c81a950190b132085d5762d2fedbc4546d14b8439ec3a";
        };
      };
    promoted-builds = mkJenkinsPlugin {
      name = "promoted-builds";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/promoted-builds/984.v90b_eb_99fc7b_4/promoted-builds.hpi";
        sha256 = "ef3d4977701e913c14b77ca72e3557e432a93ae701821e196d6db41e78e2f198";
        };
      };
    pubsub-light = mkJenkinsPlugin {
      name = "pubsub-light";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pubsub-light/1.19/pubsub-light.hpi";
        sha256 = "c06fa0da18d5586fe934fa30f84a7f96f23297c491fce3dfcf7326adfbc04d0d";
        };
      };
    rebuild = mkJenkinsPlugin {
      name = "rebuild";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/rebuild/338.va_0a_b_50e29397/rebuild.hpi";
        sha256 = "47c7a5096791c9186546b4b302aeb0bc3b98bbdb9ae0ba9030ceb76732ef9b05";
        };
      };
    reverse-proxy-auth-plugin = mkJenkinsPlugin {
      name = "reverse-proxy-auth-plugin";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/reverse-proxy-auth-plugin/238.v82ceca_8417a_6/reverse-proxy-auth-plugin.hpi";
        sha256 = "5219e4554d411fb53f215ff0f27e3bd4dc2c7d5c76afe810ffa19f8b6a9baaa1";
        };
      };
    robot = mkJenkinsPlugin {
      name = "robot";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/robot/5.0.0/robot.hpi";
        sha256 = "e62b39f08d59397b8b8f6fcc62885a43e4eede150ae6854b8141691aef0df579";
        };
      };
    run-condition = mkJenkinsPlugin {
      name = "run-condition";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/run-condition/243.v3c3f94e46a_8b_/run-condition.hpi";
        sha256 = "1ec8909eccc7c698858e6918660ddc0fcfc530391417d249b36409cf1abbf6e3";
        };
      };
    scm-api = mkJenkinsPlugin {
      name = "scm-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/scm-api/704.v3ce5c542825a_/scm-api.hpi";
        sha256 = "ee7223516ab011f8431f93dd50fd22718c60ecde50eeffebf295554221da10c9";
        };
      };
    script-security = mkJenkinsPlugin {
      name = "script-security";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/script-security/1373.vb_b_4a_a_c26fa_00/script-security.hpi";
        sha256 = "7199fe62124b15776595331bcafe3f4c3d48293a535dfdaaf44df6f1b5efc427";
        };
      };
    slack = mkJenkinsPlugin {
      name = "slack";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/slack/761.v2a_8770f0d169/slack.hpi";
        sha256 = "c63385f616d0a27689ee013ff140b0ec102dd17203aec733aeea73aca39644ad";
        };
      };
    snakeyaml-api = mkJenkinsPlugin {
      name = "snakeyaml-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/snakeyaml-api/2.3-125.v4d77857a_b_402/snakeyaml-api.hpi";
        sha256 = "8995f229e7e1558fd8482229ed132353cbb3258009f3b9f1845d617f0ac17e42";
        };
      };
    sse-gateway = mkJenkinsPlugin {
      name = "sse-gateway";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/sse-gateway/1.28/sse-gateway.hpi";
        sha256 = "3ce1f9e6df199d090e1ab5030672b26e6a1dbee52f352400271a71066036ad13";
        };
      };
    ssh-credentials = mkJenkinsPlugin {
      name = "ssh-credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ssh-credentials/355.v9b_e5b_cde5003/ssh-credentials.hpi";
        sha256 = "1486161e2344f347827ba991b7a7b8db1bdb3030f65c4a960c609bf364dc6b6c";
        };
      };
    ssh-slaves = mkJenkinsPlugin {
      name = "ssh-slaves";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ssh-slaves/3.1031.v72c6b_883b_869/ssh-slaves.hpi";
        sha256 = "94bf50f15b18df3a0c43029b7473095103aab2844c5d94002c8d8fc6c1b0f07c";
        };
      };
    structs = mkJenkinsPlugin {
      name = "structs";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/structs/343.vdcf37b_a_c81d5/structs.hpi";
        sha256 = "10708c30f652ace243ab0401f39139c51a870adda76ed73387ac072eed61428b";
        };
      };
    subversion = mkJenkinsPlugin {
      name = "subversion";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/subversion/1287.vd2d507146906/subversion.hpi";
        sha256 = "820e144e2a2b3a358792942e5c7ee98890d70df0991e9b004d6ed1297c0f5b87";
        };
      };
    support-core = mkJenkinsPlugin {
      name = "support-core";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/support-core/1692.v61f53ff4a_63b_/support-core.hpi";
        sha256 = "f82208bb138e14c12f656d0b75413eb0e8863dbc232025a8413ddb823c2063a6";
        };
      };
    timestamper = mkJenkinsPlugin {
      name = "timestamper";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/timestamper/1.28/timestamper.hpi";
        sha256 = "ae70f001f26fef032d0bfee7104443712b2d82e87ce8a7517cd0f8e721ac57ee";
        };
      };
    token-macro = mkJenkinsPlugin {
      name = "token-macro";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/token-macro/444.v52de7e9c573d/token-macro.hpi";
        sha256 = "1b0f9b14beb5358a03dedc32eff09c81b3696b9dd2547a4a236f9888f7579e6a";
        };
      };
    trilead-api = mkJenkinsPlugin {
      name = "trilead-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/trilead-api/2.192.vc50a_d147e369/trilead-api.hpi";
        sha256 = "dd29d98ed02e4dbe7b0aab0c117eb460e386657c50e3ebf459bb223acf8863a7";
        };
      };
    variant = mkJenkinsPlugin {
      name = "variant";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/variant/70.va_d9f17f859e0/variant.hpi";
        sha256 = "12e214ea694469a4461b55881ecb4074ae5dfb04797dbc0dad390f6f4bc75aaf";
        };
      };
    vsphere-cloud = mkJenkinsPlugin {
      name = "vsphere-cloud";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/vsphere-cloud/2.27/vsphere-cloud.hpi";
        sha256 = "b584e8c515cdf41fa47740087677e11af80c402ef6c4fb5f153b9d8e05ccbdea";
        };
      };
    workflow-aggregator = mkJenkinsPlugin {
      name = "workflow-aggregator";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-aggregator/608.v67378e9d3db_1/workflow-aggregator.hpi";
        sha256 = "7b94227c1afa01bb262c14919ad4a333412f1b51d947c0f21909ec2daff357dc";
        };
      };
    workflow-api = mkJenkinsPlugin {
      name = "workflow-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-api/1366.vf1fb_e1a_f6b_22/workflow-api.hpi";
        sha256 = "f9a24dc6616ce898a0694aa9f304d0ac7b5ea4836abbfd3117646deba4c89afb";
        };
      };
    workflow-basic-steps = mkJenkinsPlugin {
      name = "workflow-basic-steps";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-basic-steps/1079.vce64b_a_929c5a_/workflow-basic-steps.hpi";
        sha256 = "4a12c1de5895318f78af0b547f20405a79dee62ca05fc3dd6ce52c479c5d1182";
        };
      };
    workflow-cps = mkJenkinsPlugin {
      name = "workflow-cps";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-cps/4080.va_15b_44a_91525/workflow-cps.hpi";
        sha256 = "db83549a9f143e9053b8d338c65eb788ef03e77c0650f2e5394b14fc73241c28";
        };
      };
    workflow-durable-task-step = mkJenkinsPlugin {
      name = "workflow-durable-task-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-durable-task-step/1405.v1fcd4a_d00096/workflow-durable-task-step.hpi";
        sha256 = "82f1b7e2d5c863d0aa204011373b8dc0923bf2f64e3e751884d3ed19d463e275";
        };
      };
    workflow-job = mkJenkinsPlugin {
      name = "workflow-job";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-job/1508.v9cb_c3a_a_89dfd/workflow-job.hpi";
        sha256 = "81d1df27ef3eb64362ac0e658a3d55738d33749f558bc540ed821ef93d9da024";
        };
      };
    workflow-multibranch = mkJenkinsPlugin {
      name = "workflow-multibranch";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-multibranch/803.v08103b_87c280/workflow-multibranch.hpi";
        sha256 = "e36074c566731582d7c71a1c2d47e9351f53f1a95ebc61127313a0aa53fde367";
        };
      };
    workflow-scm-step = mkJenkinsPlugin {
      name = "workflow-scm-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-scm-step/437.v05a_f66b_e5ef8/workflow-scm-step.hpi";
        sha256 = "72fe9cb99f48d0d1233b281285919959233b7b60fac62af33a1137325a235016";
        };
      };
    workflow-step-api = mkJenkinsPlugin {
      name = "workflow-step-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-step-api/700.v6e45cb_a_5a_a_21/workflow-step-api.hpi";
        sha256 = "201e30f69706b98bfe80eaf24f0f735f3f5d7a1e0cd069243d15a3de22007e48";
        };
      };
    workflow-support = mkJenkinsPlugin {
      name = "workflow-support";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-support/963.va_600813d04a_a_/workflow-support.hpi";
        sha256 = "8afa718dcbf41c616c196fb5d7de6d8c23eb2eb37f66ef0b1e8eda760d91f24b";
        };
      };
    }