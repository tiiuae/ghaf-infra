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
        url = "https://updates.jenkins-ci.org/download/plugins/antisamy-markup-formatter/162.v0e6ec0fcfcf6/antisamy-markup-formatter.hpi";
        sha256 = "3d4144a78b14ccc4a8f370ccea82c93bd56fadd900b2db4ebf7f77ce2979efd6";
        };
      };
    apache-httpcomponents-client-4-api = mkJenkinsPlugin {
      name = "apache-httpcomponents-client-4-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/apache-httpcomponents-client-4-api/4.5.14-208.v438351942757/apache-httpcomponents-client-4-api.hpi";
        sha256 = "9ed0ccda20a0ea11e2ba5be299f03b30692dd5a2f9fdc7853714507fda8acd0f";
        };
      };
    apache-httpcomponents-client-5-api = mkJenkinsPlugin {
      name = "apache-httpcomponents-client-5-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/apache-httpcomponents-client-5-api/5.4-136.v5a_21779c63f8/apache-httpcomponents-client-5-api.hpi";
        sha256 = "7ee83144eb1dd6d48a41f66d699a85f1bec6c7ab97c3752b70f983408e5417f3";
        };
      };
    asm-api = mkJenkinsPlugin {
      name = "asm-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/asm-api/9.7.1-97.v4cc844130d97/asm-api.hpi";
        sha256 = "7f26c33883ea995b90a6e5c0f60cd1b4af0f863380ea42f7da4518960e04c393";
        };
      };
    authentication-tokens = mkJenkinsPlugin {
      name = "authentication-tokens";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/authentication-tokens/1.119.v50285141b_7e1/authentication-tokens.hpi";
        sha256 = "684940806687a6dd9a7932d45d806d5c355c1c35bd725a74d04010cff229d39d";
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
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean/1.27.16/blueocean.hpi";
        sha256 = "eb7d7dc3a01dfc67805bce43f4ec440a8e5b2bb7fa62a119d87940b30239137f";
        };
      };
    blueocean-bitbucket-pipeline = mkJenkinsPlugin {
      name = "blueocean-bitbucket-pipeline";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-bitbucket-pipeline/1.27.16/blueocean-bitbucket-pipeline.hpi";
        sha256 = "e381bbd820b4d9cf4b1402635c014dcfad72c926a59f5197aafa8f1c293ad6d9";
        };
      };
    blueocean-commons = mkJenkinsPlugin {
      name = "blueocean-commons";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-commons/1.27.16/blueocean-commons.hpi";
        sha256 = "87423be995d6c1e5f1f213cd871aa9ffda9ea047f77c365c298ce6249a6a1ece";
        };
      };
    blueocean-config = mkJenkinsPlugin {
      name = "blueocean-config";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-config/1.27.16/blueocean-config.hpi";
        sha256 = "8270628428ac68f2b223280eaabb3739f19fa98a27c5e7b765a2db6298ef9d97";
        };
      };
    blueocean-core-js = mkJenkinsPlugin {
      name = "blueocean-core-js";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-core-js/1.27.16/blueocean-core-js.hpi";
        sha256 = "fd4bc5b219bbd35d420b09df295990155d4296384b7e299abdb90a736c1b946f";
        };
      };
    blueocean-dashboard = mkJenkinsPlugin {
      name = "blueocean-dashboard";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-dashboard/1.27.16/blueocean-dashboard.hpi";
        sha256 = "32d6046476621f4645fdabdfb7a5f454dba5fc7f694daf6aa645c7799531276b";
        };
      };
    blueocean-display-url = mkJenkinsPlugin {
      name = "blueocean-display-url";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-display-url/2.4.3/blueocean-display-url.hpi";
        sha256 = "b011ac2fba0060ca5fd32e83287df216d6801d5df22ba96d25467c421c233c1b";
        };
      };
    blueocean-events = mkJenkinsPlugin {
      name = "blueocean-events";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-events/1.27.16/blueocean-events.hpi";
        sha256 = "72b44195c43b515125590ba198d0645d338aef603dc2ed835dab7826f31dbfa5";
        };
      };
    blueocean-executor-info = mkJenkinsPlugin {
      name = "blueocean-executor-info";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-executor-info/1.27.16/blueocean-executor-info.hpi";
        sha256 = "f9cf3b02962c6058d955abaf241a71275b1712ebe3c2284bf3d9030ad36069f2";
        };
      };
    blueocean-git-pipeline = mkJenkinsPlugin {
      name = "blueocean-git-pipeline";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-git-pipeline/1.27.16/blueocean-git-pipeline.hpi";
        sha256 = "3840332ebd41d92a37cb300406112bc0ad1f88014b4ad194ea41eadb7336ae01";
        };
      };
    blueocean-github-pipeline = mkJenkinsPlugin {
      name = "blueocean-github-pipeline";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-github-pipeline/1.27.16/blueocean-github-pipeline.hpi";
        sha256 = "472f3a6a34047175e9a28d00a52054a2b5a5d8a7f0aa9df68a78d82643e7981f";
        };
      };
    blueocean-i18n = mkJenkinsPlugin {
      name = "blueocean-i18n";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-i18n/1.27.16/blueocean-i18n.hpi";
        sha256 = "6bfd533fe46b1f43945e395b891e1d82259aba869c07aa6b317493f1e52de506";
        };
      };
    blueocean-jwt = mkJenkinsPlugin {
      name = "blueocean-jwt";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-jwt/1.27.16/blueocean-jwt.hpi";
        sha256 = "7bbd786d0f60b9a93ba67c2b71f05adf46f2345dcc944ce5b8af40052b2f146d";
        };
      };
    blueocean-personalization = mkJenkinsPlugin {
      name = "blueocean-personalization";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-personalization/1.27.16/blueocean-personalization.hpi";
        sha256 = "25e230d6281bfb7f0135faf98fd42c0b86b804b015ffd5fdc0eeecaa1305d211";
        };
      };
    blueocean-pipeline-api-impl = mkJenkinsPlugin {
      name = "blueocean-pipeline-api-impl";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-pipeline-api-impl/1.27.16/blueocean-pipeline-api-impl.hpi";
        sha256 = "bfefb0e67c9a15c413038f8ffdba9d585df499873d1e4a93835db8f51a6af3c2";
        };
      };
    blueocean-pipeline-editor = mkJenkinsPlugin {
      name = "blueocean-pipeline-editor";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-pipeline-editor/1.27.16/blueocean-pipeline-editor.hpi";
        sha256 = "0c6ead53fd016162d63fbc85b21ad772cbacc25bd78d42d5abf1eba6472c308a";
        };
      };
    blueocean-pipeline-scm-api = mkJenkinsPlugin {
      name = "blueocean-pipeline-scm-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-pipeline-scm-api/1.27.16/blueocean-pipeline-scm-api.hpi";
        sha256 = "df805ebc306b42061220ef3dde37e027cfc06fb336d5ed28f3274e8885396806";
        };
      };
    blueocean-rest = mkJenkinsPlugin {
      name = "blueocean-rest";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-rest/1.27.16/blueocean-rest.hpi";
        sha256 = "a0faf9f3232566c5291e9d95b5c3137297612104b80f09dde64f2946bb1b50ba";
        };
      };
    blueocean-rest-impl = mkJenkinsPlugin {
      name = "blueocean-rest-impl";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-rest-impl/1.27.16/blueocean-rest-impl.hpi";
        sha256 = "cfb9b7b5ecf0f16713fa33c5164272e9d12d0f569bd830b1af97e32ccf9752b4";
        };
      };
    blueocean-web = mkJenkinsPlugin {
      name = "blueocean-web";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/blueocean-web/1.27.16/blueocean-web.hpi";
        sha256 = "b80ecca19d915b5903bc09f502e8fcd43fdabf964412da9283d649c281587611";
        };
      };
    bootstrap5-api = mkJenkinsPlugin {
      name = "bootstrap5-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/bootstrap5-api/5.3.3-1/bootstrap5-api.hpi";
        sha256 = "e0d0f7c92dae2f7977c28ceb6a5b2562b7012d1704888bff3bc176abda0cb269";
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
        url = "https://updates.jenkins-ci.org/download/plugins/branch-api/2.1208.vf528356feca_4/branch-api.hpi";
        sha256 = "a28044c5041fa9dc4af77e1c2acd2c55eba4c2b5f4190f6ffa71c1ed8f6af0c3";
        };
      };
    caffeine-api = mkJenkinsPlugin {
      name = "caffeine-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/caffeine-api/3.1.8-133.v17b_1ff2e0599/caffeine-api.hpi";
        sha256 = "a6c614655bc507345bf16b5c4615bb09b1a20f934c9bf0b15c02ccea4a5c0400";
        };
      };
    checks-api = mkJenkinsPlugin {
      name = "checks-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/checks-api/2.2.1/checks-api.hpi";
        sha256 = "2dc1e51c86e4b16c17e66a45d94ced9d0ee4a0b247df77a4a796bd3c93471b98";
        };
      };
    cloudbees-bitbucket-branch-source = mkJenkinsPlugin {
      name = "cloudbees-bitbucket-branch-source";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/cloudbees-bitbucket-branch-source/934.4.1/cloudbees-bitbucket-branch-source.hpi";
        sha256 = "6f0c71b2ea6079b9078126bf4eff527e8a8c090164799ffd6e2b50fce62be1f2";
        };
      };
    cloudbees-folder = mkJenkinsPlugin {
      name = "cloudbees-folder";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/cloudbees-folder/6.980.v5a_cc0cb_25881/cloudbees-folder.hpi";
        sha256 = "5d4a027db92ac8b7a1e30be2ff2b8c36ece84f65c87f78b1e55c627032924760";
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
        url = "https://updates.jenkins-ci.org/download/plugins/commons-compress-api/1.26.1-2/commons-compress-api.hpi";
        sha256 = "2a1579c2a952009f241b5cf5c854093c5dd86971b80fc78d19d07697cc00fd17";
        };
      };
    commons-lang3-api = mkJenkinsPlugin {
      name = "commons-lang3-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/commons-lang3-api/3.17.0-84.vb_b_938040b_078/commons-lang3-api.hpi";
        sha256 = "90b15521b21ad1462b18a6f8894ff1a2c1080c5d398ca8bb928c062c992c3fc4";
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
        url = "https://updates.jenkins-ci.org/download/plugins/configuration-as-code/1929.v036b_5a_e1f123/configuration-as-code.hpi";
        sha256 = "addd485a5c8c6959c458119d507b9e3f770d849caac255576b6680b1985629c8";
        };
      };
    copyartifact = mkJenkinsPlugin {
      name = "copyartifact";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/copyartifact/761.vea_2b_25523e84/copyartifact.hpi";
        sha256 = "3ec8426e9c4eccc4d578a69989edbe26085c2926ec6e2ec19e7de2e6fa69d4c7";
        };
      };
    credentials = mkJenkinsPlugin {
      name = "credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/credentials/1405.vb_cda_74a_f8974/credentials.hpi";
        sha256 = "faaf55e8735973b835b2d45385c8ed85980f1d139832a73432652a714d16c7e1";
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
        url = "https://updates.jenkins-ci.org/download/plugins/data-tables-api/2.1.8-1/data-tables-api.hpi";
        sha256 = "799d733d41e9f0cf80b9e0a34cc11180f000e01c8a03c4fe2b74c38da1e205e2";
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
        url = "https://updates.jenkins-ci.org/download/plugins/durable-task/581.v299a_5609d767/durable-task.hpi";
        sha256 = "1ae83a72ef3ece1aebde350a704e025d8f7f035e1b102d0244c926a806fc916b";
        };
      };
    echarts-api = mkJenkinsPlugin {
      name = "echarts-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/echarts-api/5.5.1-5/echarts-api.hpi";
        sha256 = "926c7df86172b73491eae13d38e3bf1c8b76e3a7b624d6c2a7ee5dbecbdf1529";
        };
      };
    eddsa-api = mkJenkinsPlugin {
      name = "eddsa-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/eddsa-api/0.3.0-4.v84c6f0f4969e/eddsa-api.hpi";
        sha256 = "ab56adb71f31e5627ac6751c393e8692916c1b82bf6b5f8399f9a88cfd8cb944";
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
        url = "https://updates.jenkins-ci.org/download/plugins/font-awesome-api/6.6.0-2/font-awesome-api.hpi";
        sha256 = "6c0d5b6688372403f98c2ad63eb3269d3a04b2d4df511a6e38b20c1ca253b5b0";
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
        url = "https://updates.jenkins-ci.org/download/plugins/git-client/6.1.1/git-client.hpi";
        sha256 = "ff349e1b379d56e441d297f075b8db6a2082cf2a74d63b38a308e5f8a76f0eed";
        };
      };
    github = mkJenkinsPlugin {
      name = "github";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/github/1.41.0/github.hpi";
        sha256 = "deaf2e1e3b34d39d0bd513827573248176ca282665599121bc68e0c1408a9e92";
        };
      };
    github-api = mkJenkinsPlugin {
      name = "github-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/github-api/1.321-478.vc9ce627ce001/github-api.hpi";
        sha256 = "eea82a4c0d7573757988523f2ebf96318815fd4b149d1d2a56d9c958376aa524";
        };
      };
    github-branch-source = mkJenkinsPlugin {
      name = "github-branch-source";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/github-branch-source/1810.v913311241fa_9/github-branch-source.hpi";
        sha256 = "b1c88f6d096338fbb34413f87e6b339ce82f06aeb9bee3de5962aa76f95ccdfb";
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
        url = "https://updates.jenkins-ci.org/download/plugins/handy-uri-templates-2-api/2.1.8-30.v7e777411b_148/handy-uri-templates-2-api.hpi";
        sha256 = "d635f86d7bf90cfae400f589e61ed9decf354fb28aab8d9ba8552446a1c913f4";
        };
      };
    htmlpublisher = mkJenkinsPlugin {
      name = "htmlpublisher";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/htmlpublisher/1.37/htmlpublisher.hpi";
        sha256 = "531443a072eaaad17d5c49e95e7397fc453b9e8d9ec886d7e7ebea54167fa83d";
        };
      };
    instance-identity = mkJenkinsPlugin {
      name = "instance-identity";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/instance-identity/201.vd2a_b_5a_468a_a_6/instance-identity.hpi";
        sha256 = "c43dc01e201fd37a38a6307dacc84ace60e1608f96623691e1dbe1fdc6d8a911";
        };
      };
    ionicons-api = mkJenkinsPlugin {
      name = "ionicons-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ionicons-api/74.v93d5eb_813d5f/ionicons-api.hpi";
        sha256 = "681a9cc3083a089d52ef398206bfc521daabf3c682ef0a57be73e0feddc62e8f";
        };
      };
    jackson2-api = mkJenkinsPlugin {
      name = "jackson2-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jackson2-api/2.17.0-379.v02de8ec9f64c/jackson2-api.hpi";
        sha256 = "5e2d919724da0a47cd01bdb9f614c8fc90862c09ce506d9b2ca340252bad225e";
        };
      };
    jakarta-activation-api = mkJenkinsPlugin {
      name = "jakarta-activation-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jakarta-activation-api/2.1.3-1/jakarta-activation-api.hpi";
        sha256 = "ddc3df5d8c39a2a208661d69277120b1113373b04d06e2250615be2a65404b83";
        };
      };
    jakarta-mail-api = mkJenkinsPlugin {
      name = "jakarta-mail-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jakarta-mail-api/2.1.3-1/jakarta-mail-api.hpi";
        sha256 = "851ab22ff0647f4d82baab4e526c6d0ddb3e64ad4969c516116b374ef778e539";
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
        url = "https://updates.jenkins-ci.org/download/plugins/javax-activation-api/1.2.0-7/javax-activation-api.hpi";
        sha256 = "c60ab7240dded219e2cd3002b30579dd993832c5d4683dca710f0f426776b063";
        };
      };
    jaxb = mkJenkinsPlugin {
      name = "jaxb";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jaxb/2.3.9-1/jaxb.hpi";
        sha256 = "8c9f7f98d996ade98b7a5dd0cd9d0aba661acea1b99a33f75778bacf39a64659";
        };
      };
    jenkins-design-language = mkJenkinsPlugin {
      name = "jenkins-design-language";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jenkins-design-language/1.27.16/jenkins-design-language.hpi";
        sha256 = "e6c4eb93f31abf9903de5aa878b51ddda4cf90e19165cb7a294e251b254d0d18";
        };
      };
    jjwt-api = mkJenkinsPlugin {
      name = "jjwt-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jjwt-api/0.11.5-112.ve82dfb_224b_a_d/jjwt-api.hpi";
        sha256 = "339161525489ce8ab23d252b9399eda3b849a22faa3542be5ae7c559f9936e47";
        };
      };
    job-dsl = mkJenkinsPlugin {
      name = "job-dsl";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/job-dsl/1.90/job-dsl.hpi";
        sha256 = "9bc754201687143fa7fde6a2713e112635ce444927a39eeb03962e7f7a456334";
        };
      };
    joda-time-api = mkJenkinsPlugin {
      name = "joda-time-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/joda-time-api/2.13.1-115.va_6b_5f8efb_1d8/joda-time-api.hpi";
        sha256 = "62abbf3e633c94cb69334134aa90b8650f59a1233c76f579f83d9d405a581b57";
        };
      };
    jquery3-api = mkJenkinsPlugin {
      name = "jquery3-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jquery3-api/3.7.1-2/jquery3-api.hpi";
        sha256 = "322d01e14a368e3131ff388dbc6fe062abaa6cb0a2bb761bc46516f1f7ca1066";
        };
      };
    jsch = mkJenkinsPlugin {
      name = "jsch";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jsch/0.2.16-86.v42e010d9484b_/jsch.hpi";
        sha256 = "f0eb7f7ebaf374f7040e60a56ccd8af6fe471e883957df3a4fff116dda02dc12";
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
        url = "https://updates.jenkins-ci.org/download/plugins/json-path-api/2.9.0-138.vc943da_d833b_6/json-path-api.hpi";
        sha256 = "b93c0aa753f3640b04a5856840823832bd747a23b11c92bb8c122d32023e4905";
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
        url = "https://updates.jenkins-ci.org/download/plugins/junit/1312.v1a_235a_b_94a_31/junit.hpi";
        sha256 = "923ec47c5639e9f22f0fa428488d887705a4bdfd16b2344e40047ed26f7bb071";
        };
      };
    lockable-resources = mkJenkinsPlugin {
      name = "lockable-resources";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/lockable-resources/1342.v673282c325c0/lockable-resources.hpi";
        sha256 = "e37561b017da7021ad84b46d351c08cc3dc3fe2133beb6954c8501f179d96938";
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
        url = "https://updates.jenkins-ci.org/download/plugins/mapdb-api/1.0.9-40.v58107308b_7a_7/mapdb-api.hpi";
        sha256 = "0dfd7a97d4a3436a740c82195dcdf2e102a5f0d7845db49b525a2c85f065663a";
        };
      };
    matrix-project = mkJenkinsPlugin {
      name = "matrix-project";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/matrix-project/845.vffd7fa_f27555/matrix-project.hpi";
        sha256 = "a776d22da6c3aa8c0bc01455f6eabad0ee7c1c42f34264bf3a6afb3263a62f82";
        };
      };
    maven-plugin = mkJenkinsPlugin {
      name = "maven-plugin";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/maven-plugin/3.24/maven-plugin.hpi";
        sha256 = "200f92c766c04d9b609b742553e13041db3e2680e0ba655a1c6e405e583c49c6";
        };
      };
    metrics = mkJenkinsPlugin {
      name = "metrics";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/metrics/4.2.21-461.v881e35d8fa_b_a_/metrics.hpi";
        sha256 = "32464ca273cc4ea3345352a89434c6ab8277167547556e10a20544138f8ddfb4";
        };
      };
    mina-sshd-api-common = mkJenkinsPlugin {
      name = "mina-sshd-api-common";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mina-sshd-api-common/2.14.0-143.v2b_362fc39576/mina-sshd-api-common.hpi";
        sha256 = "7e3771d302a9b4ff7f84fedb62088173a2cd07e0f1f679ad9a2cf445c5a65b65";
        };
      };
    mina-sshd-api-core = mkJenkinsPlugin {
      name = "mina-sshd-api-core";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mina-sshd-api-core/2.14.0-143.v2b_362fc39576/mina-sshd-api-core.hpi";
        sha256 = "235d0f602be5b39e3f53f60e25e7437ba7e1a36a1161285132699f31210a1d45";
        };
      };
    node-iterator-api = mkJenkinsPlugin {
      name = "node-iterator-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/node-iterator-api/55.v3b_77d4032326/node-iterator-api.hpi";
        sha256 = "c9b2d8c7df2091a191f5562a35454ddc2343cfe9c274b1f6b5a83980f52b422f";
        };
      };
    okhttp-api = mkJenkinsPlugin {
      name = "okhttp-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/okhttp-api/4.11.0-183.va_87fc7a_89810/okhttp-api.hpi";
        sha256 = "a2ed9bd77f7098355fb47e6c1f760d1910b6c2c4998425479cb6d9eedd823c5b";
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
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-build-step/551.v178956c49ef8/pipeline-build-step.hpi";
        sha256 = "28b88ba21c4483b073bd85634d67bdbd7ceb6cf47cbc423d3d4635bd66a514e0";
        };
      };
    pipeline-graph-analysis = mkJenkinsPlugin {
      name = "pipeline-graph-analysis";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-graph-analysis/216.vfd8b_ece330ca_/pipeline-graph-analysis.hpi";
        sha256 = "068e50f8d01a2efad93a29df93aeb75d7c8cbc50bba2db5babfba7b397a97b23";
        };
      };
    pipeline-graph-view = mkJenkinsPlugin {
      name = "pipeline-graph-view";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-graph-view/407.v7857c9611b_44/pipeline-graph-view.hpi";
        sha256 = "52583a39794d0fe89079c991a186a93cf64b4ad19d26c9af0d2efb22c85fb873";
        };
      };
    pipeline-groovy-lib = mkJenkinsPlugin {
      name = "pipeline-groovy-lib";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-groovy-lib/749.v70084559234a_/pipeline-groovy-lib.hpi";
        sha256 = "21b853019d02c7883f860f075437b6f42d5a709568be05efd29a642ccfb9340a";
        };
      };
    pipeline-input-step = mkJenkinsPlugin {
      name = "pipeline-input-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-input-step/508.v584c0e9a_2177/pipeline-input-step.hpi";
        sha256 = "6a2025b06052b69872b7ac9c2744f52866ea7238f81abe4c1169a1aad10dd520";
        };
      };
    pipeline-milestone-step = mkJenkinsPlugin {
      name = "pipeline-milestone-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-milestone-step/119.vdfdc43fc3b_9a_/pipeline-milestone-step.hpi";
        sha256 = "0686e6f1b11bdd034cb1adbcbe6ecb65551c1f0e1cc4391066cde0d35197c7ec";
        };
      };
    pipeline-model-api = mkJenkinsPlugin {
      name = "pipeline-model-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-api/2.2221.vc657003fb_d93/pipeline-model-api.hpi";
        sha256 = "829e031d6ab975aa65e754528a1cdfb0c25e7e026f42aef5d03c05e8ec84c6d0";
        };
      };
    pipeline-model-definition = mkJenkinsPlugin {
      name = "pipeline-model-definition";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-definition/2.2221.vc657003fb_d93/pipeline-model-definition.hpi";
        sha256 = "c077f59a6a151783cf27f38a9189e0462371535006ada0f8f5d979e8ec6a865f";
        };
      };
    pipeline-model-extensions = mkJenkinsPlugin {
      name = "pipeline-model-extensions";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-extensions/2.2221.vc657003fb_d93/pipeline-model-extensions.hpi";
        sha256 = "f8a8b666449bb05bdebf86c008b9fa9a84d74e558bf6275a773fbf1e493c4ccd";
        };
      };
    pipeline-rest-api = mkJenkinsPlugin {
      name = "pipeline-rest-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-rest-api/2.34/pipeline-rest-api.hpi";
        sha256 = "b7db14bee545c46c37684a976a8c6063e555d213bed5d40fc35d91de6a61b77a";
        };
      };
    pipeline-stage-step = mkJenkinsPlugin {
      name = "pipeline-stage-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-step/312.v8cd10304c27a_/pipeline-stage-step.hpi";
        sha256 = "f254c8981de34c1a63f550c5ed374b885c25daf5df4d99555119a41b7a9f936c";
        };
      };
    pipeline-stage-tags-metadata = mkJenkinsPlugin {
      name = "pipeline-stage-tags-metadata";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-tags-metadata/2.2221.vc657003fb_d93/pipeline-stage-tags-metadata.hpi";
        sha256 = "06b4cff16e32febdf07804e9b668b2986723b3874c1cbbca5ca5c4a50c24ce98";
        };
      };
    pipeline-stage-view = mkJenkinsPlugin {
      name = "pipeline-stage-view";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-view/2.34/pipeline-stage-view.hpi";
        sha256 = "e9caa817ea2645250da1359097ca71f0ebb1e7bc40094d8331575aafb7290e5b";
        };
      };
    pipeline-utility-steps = mkJenkinsPlugin {
      name = "pipeline-utility-steps";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-utility-steps/2.18.0/pipeline-utility-steps.hpi";
        sha256 = "d1d78b2d4aed7bc350f9281d5da8dd7aa0be5821395a31ad28a7aa571027008c";
        };
      };
    plain-credentials = mkJenkinsPlugin {
      name = "plain-credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/plain-credentials/183.va_de8f1dd5a_2b_/plain-credentials.hpi";
        sha256 = "9422eaa765e6591e3c845bfec9c105f5600a058951a2940aec5be0ed76ea813a";
        };
      };
    plugin-util-api = mkJenkinsPlugin {
      name = "plugin-util-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/plugin-util-api/5.1.0/plugin-util-api.hpi";
        sha256 = "f3663009736c677afea03b566555459f8ef15164863743671e31f4f675474ceb";
        };
      };
    prism-api = mkJenkinsPlugin {
      name = "prism-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/prism-api/1.29.0-18/prism-api.hpi";
        sha256 = "ebaa9efa493822245929957137b430cd36adf1e43c344f941aa2429a0013507d";
        };
      };
    promoted-builds = mkJenkinsPlugin {
      name = "promoted-builds";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/promoted-builds/965.vcda_c6a_e0998f/promoted-builds.hpi";
        sha256 = "414dec09daee76811164966a1058307da65c8f9fb67f13cd7311d578d3ba15bf";
        };
      };
    pubsub-light = mkJenkinsPlugin {
      name = "pubsub-light";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pubsub-light/1.18/pubsub-light.hpi";
        sha256 = "73ef42ad025c64c6f9f91b0e1226a47feee2daa92dd565391675f84f0f18abe9";
        };
      };
    rebuild = mkJenkinsPlugin {
      name = "rebuild";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/rebuild/332.va_1ee476d8f6d/rebuild.hpi";
        sha256 = "60eb87df685c714c89a8a7b6315a0332c2edcb19d149dd2099ed0cb25f55ba41";
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
        url = "https://updates.jenkins-ci.org/download/plugins/scm-api/703.v72ff4b_259600/scm-api.hpi";
        sha256 = "f8188ca41b87236492618270d4609c68f6840049aa3d948baa97c9fb8778f449";
        };
      };
    script-security = mkJenkinsPlugin {
      name = "script-security";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/script-security/1369.v9b_98a_4e95b_2d/script-security.hpi";
        sha256 = "bf771fd9b14ff6a6c76b572832b8a7fa5824eb2a6e87392f6eb640224f5485e4";
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
        url = "https://updates.jenkins-ci.org/download/plugins/snakeyaml-api/2.3-123.v13484c65210a_/snakeyaml-api.hpi";
        sha256 = "d5b81a0d0cfd411de76daefd91b1dcdc0a573bc5be9ff6ed1f47411fadae13fe";
        };
      };
    sse-gateway = mkJenkinsPlugin {
      name = "sse-gateway";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/sse-gateway/1.27/sse-gateway.hpi";
        sha256 = "7ba358959e444d8d62b978601a65a30b6c0cc1b6ff8a51ba6d4360a3263c3295";
        };
      };
    ssh-credentials = mkJenkinsPlugin {
      name = "ssh-credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ssh-credentials/349.vb_8b_6b_9709f5b_/ssh-credentials.hpi";
        sha256 = "9794ef186ef33735522b1915cad95f5d11196c9bf9ca4d0e46e0b1ef0464a3e7";
        };
      };
    ssh-slaves = mkJenkinsPlugin {
      name = "ssh-slaves";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ssh-slaves/3.1021.va_cc11b_de26a_e/ssh-slaves.hpi";
        sha256 = "c345bffde13c37fa4a01cab13d080f574b232765636bcdb13dafa52ead113bd9";
        };
      };
    structs = mkJenkinsPlugin {
      name = "structs";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/structs/338.v848422169819/structs.hpi";
        sha256 = "7cae811a39788f58a954774631f0a279d4bf5e32672837268a85382267a8af66";
        };
      };
    subversion = mkJenkinsPlugin {
      name = "subversion";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/subversion/1283.vfc8b_92d49a_06/subversion.hpi";
        sha256 = "4c11b403da2cb7b1c7fc9dfbd78f3a5acb2a6b79498ef1070e6cf4af1b2481ed";
        };
      };
    support-core = mkJenkinsPlugin {
      name = "support-core";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/support-core/1557.v3435ec4057a_e/support-core.hpi";
        sha256 = "d069ee8f9cf1936a847f8756cb6ab3d1083c48864e9355aa55d44194e7bf61ea";
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
        url = "https://updates.jenkins-ci.org/download/plugins/token-macro/442.v4f452dc3c7c0/token-macro.hpi";
        sha256 = "a23bbece147c718fecfd71e786055a570395d3f967a1c065ab9904af4c111d97";
        };
      };
    trilead-api = mkJenkinsPlugin {
      name = "trilead-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/trilead-api/2.147.vb_73cc728a_32e/trilead-api.hpi";
        sha256 = "25b8858b595b75db10248f8a2dfdbedf049d4356f9b1c096573f845c9a962e4d";
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
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-aggregator/600.vb_57cdd26fdd7/workflow-aggregator.hpi";
        sha256 = "df9b911d1f35adcdf71046b77ab69ceabc612d06c3e55bec01c7a1eff0b24711";
        };
      };
    workflow-api = mkJenkinsPlugin {
      name = "workflow-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-api/1363.v03f731255494/workflow-api.hpi";
        sha256 = "132dde597187a54dbc6df5383266d5b7a2c540f64bbe0fa23cc29df343f776d4";
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
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-cps/4014.vcd7dc51d8b_30/workflow-cps.hpi";
        sha256 = "d5c83c789603506f4fcf2d08d84d0493d428839180f345e29d46d3fa2de474aa";
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
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-job/1498.v33a_0c6f3a_4b_4/workflow-job.hpi";
        sha256 = "4b8a9dec8d043661a203ad056f1ebfad7c65ae6ae1ebf87419a520decbe6b769";
        };
      };
    workflow-multibranch = mkJenkinsPlugin {
      name = "workflow-multibranch";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-multibranch/800.v5f0a_a_660950e/workflow-multibranch.hpi";
        sha256 = "9a1beb3af51f19d7b0c21af3fba4c19768803e75585dbffdf9ee1e9086624611";
        };
      };
    workflow-scm-step = mkJenkinsPlugin {
      name = "workflow-scm-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-scm-step/427.v4ca_6512e7df1/workflow-scm-step.hpi";
        sha256 = "4a06c4667e1bc437e89107abd9a316adaf51fca4fd504d12a525194777d34ad8";
        };
      };
    workflow-step-api = mkJenkinsPlugin {
      name = "workflow-step-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-step-api/686.v603d058a_e148/workflow-step-api.hpi";
        sha256 = "3dddba768bd0eaba8e7f0b5bf522f7d5ceb169c86ec12bbc156e44e6301a7d61";
        };
      };
    workflow-support = mkJenkinsPlugin {
      name = "workflow-support";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-support/944.v5a_859593b_98a_/workflow-support.hpi";
        sha256 = "fe0642e50e3b30c769c2b075a5df15828f7d0a6cbc8df9917a8db14813ba9532";
        };
      };
    }