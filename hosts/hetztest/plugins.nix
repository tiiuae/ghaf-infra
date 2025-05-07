{ stdenv, fetchurl }:
let
  mkJenkinsPlugin =
    { name, src }:
    stdenv.mkDerivation {
      inherit name src;
      phases = "installPhase";
      installPhase = "cp \$src \$out";
    };
in
{
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
  asm-api = mkJenkinsPlugin {
    name = "asm-api";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/asm-api/9.8-135.vb_2239d08ee90/asm-api.hpi";
      sha256 = "95e71f7c5e1e98b6dacb4371d51cb6c4443922ec0f88c37409c366a1e4ba37d4";
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
      url = "https://updates.jenkins-ci.org/download/plugins/branch-api/2.1217.v43d8b_b_d8b_2c7/branch-api.hpi";
      sha256 = "93e82ce77389ccef4202f4c2d5ed2c49e4feffe61168ea3c77c927d907afa0b5";
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
      url = "https://updates.jenkins-ci.org/download/plugins/checks-api/370.vb_61a_c57328f3/checks-api.hpi";
      sha256 = "18cb385a4bd6f570279d61f6706b83b1ff3535d42c0daaf5f488506da3f1e3fb";
    };
  };
  cloudbees-folder = mkJenkinsPlugin {
    name = "cloudbees-folder";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/cloudbees-folder/6.1012.v79a_86a_1ea_c1f/cloudbees-folder.hpi";
      sha256 = "095ab2e6409c39a442d5a0c86e51dd375283e427ad8ac2be14a7d08100d55c9c";
    };
  };
  command-launcher = mkJenkinsPlugin {
    name = "command-launcher";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/command-launcher/123.v37cfdc92ef67/command-launcher.hpi";
      sha256 = "79068415d65ad7f8fb639f9f5a78f3fa14607340e89e9c6a94004d44af06f9ab";
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
      url = "https://updates.jenkins-ci.org/download/plugins/configuration-as-code/1958.vddc0d369b_e16/configuration-as-code.hpi";
      sha256 = "99a0cb6001e4e131a0e215374b141a5ee4ed9bd91a4794f9dbd14e863755dd28";
    };
  };
  credentials = mkJenkinsPlugin {
    name = "credentials";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/credentials/1415.v831096eb_5534/credentials.hpi";
      sha256 = "a1a61da5bef93e405154fd2af9798cdcd03b7f60fb086b9534a74f8175b9c290";
    };
  };
  credentials-binding = mkJenkinsPlugin {
    name = "credentials-binding";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/credentials-binding/687.v619cb_15e923f/credentials-binding.hpi";
      sha256 = "3a589c067bfc21e3792f2f60efa63a5a46ceedcb13af2b1ad4b1f631e4f37d0d";
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
      url = "https://updates.jenkins-ci.org/download/plugins/echarts-api/5.6.0-4/echarts-api.hpi";
      sha256 = "52083b883eecf33beb739ebeab874f66a02d596ae3f78c5a8061f74558909e2c";
    };
  };
  eddsa-api = mkJenkinsPlugin {
    name = "eddsa-api";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/eddsa-api/0.3.0.1-19.vc432d923e5ee/eddsa-api.hpi";
      sha256 = "35c7decb2c08accb96a7a4d54cac7d0af6713c242192142dad56cec50949143a";
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
      url = "https://updates.jenkins-ci.org/download/plugins/git-client/6.1.3/git-client.hpi";
      sha256 = "cd1c1c4d8d8310235915f89b8e7fa19b89ebca731d9a0d9d59596547e3e8c521";
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
  gson-api = mkJenkinsPlugin {
    name = "gson-api";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/gson-api/2.13.1-139.v4569c2ef303f/gson-api.hpi";
      sha256 = "324330ac703a26f24918166c92864c0023d6a60a39821bdc4b4c98eaa750e467";
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
      url = "https://updates.jenkins-ci.org/download/plugins/javadoc/327.vdfe586651ee0/javadoc.hpi";
      sha256 = "690f54ee252486f72e1eb03e7de3b3c57df5aca44f30209c2445927a465cc6d9";
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
      url = "https://updates.jenkins-ci.org/download/plugins/job-dsl/1.92/job-dsl.hpi";
      sha256 = "f32b7d899c2da0871404540b56bc03a43941458af5d3721e4df3166dcf985da0";
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
  jsoup = mkJenkinsPlugin {
    name = "jsoup";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/jsoup/1.19.1-38.v216a_f3721b_3c/jsoup.hpi";
      sha256 = "fe7807ef63b0f39432dd0c153a0756983cb4791c8c9ce10c4db9ac0984dabed9";
    };
  };
  junit = mkJenkinsPlugin {
    name = "junit";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/junit/1322.v1556dc1c59a_f/junit.hpi";
      sha256 = "a64859399ddb300c176fbf95abda32e198c4c1320e8687435232aba913eda078";
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
  matrix-project = mkJenkinsPlugin {
    name = "matrix-project";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/matrix-project/849.v0cd64ed7e531/matrix-project.hpi";
      sha256 = "b8c7f15e9094be993d1b3b6ef1c6a1e7d5e245aeba6248fd36ac9978b3d78266";
    };
  };
  maven-plugin = mkJenkinsPlugin {
    name = "maven-plugin";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/maven-plugin/3.26/maven-plugin.hpi";
      sha256 = "2e110d157a5ef0b3afaf1e0759ab2d4951ac10afdf08d9be72a53a7f72bfbdb1";
    };
  };
  metrics = mkJenkinsPlugin {
    name = "metrics";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/metrics/4.2.30-471.v55fa_495f2b_f5/metrics.hpi";
      sha256 = "6cca64e68c25e33716c38802b4d909946812124a8e643f3607464f5a11bcfc6a";
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
      url = "https://updates.jenkins-ci.org/download/plugins/oss-symbols-api/324.v432cce4172ca_/oss-symbols-api.hpi";
      sha256 = "8b61eb828de459116e91ff8baef6f22c5f85e6c8881843045779c57be8163e74";
    };
  };
  parameterized-trigger = mkJenkinsPlugin {
    name = "parameterized-trigger";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/parameterized-trigger/859.vb_e3907a_07a_16/parameterized-trigger.hpi";
      sha256 = "3844bc3889daf019b8c608a15400021402ac5b392307c63948c491e362f1d3f3";
    };
  };
  pipeline-build-step = mkJenkinsPlugin {
    name = "pipeline-build-step";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/pipeline-build-step/567.vea_ce550ece97/pipeline-build-step.hpi";
      sha256 = "2d771cf9ba51efd6ee45e1a66047bf850de6267304e014590d842f0e6c62eef1";
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
      url = "https://updates.jenkins-ci.org/download/plugins/pipeline-graph-view/468.vf1b_4ec0fe463/pipeline-graph-view.hpi";
      sha256 = "a1cf652202b7cb344f09f8933ef09d7ad9719c6fb9dc01c4f81aac924c0ea0e5";
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
      url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-api/2.2254.v2a_978de46f35/pipeline-model-api.hpi";
      sha256 = "6a1e210201b57ed2935d10689601b0cfac5b5ac749f2a08a33f325dbfafb6fb4";
    };
  };
  pipeline-model-definition = mkJenkinsPlugin {
    name = "pipeline-model-definition";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-definition/2.2254.v2a_978de46f35/pipeline-model-definition.hpi";
      sha256 = "c8dbe70aadd4be0e50899df55881313b24e1ac786a2946d5587363206996ce3a";
    };
  };
  pipeline-model-extensions = mkJenkinsPlugin {
    name = "pipeline-model-extensions";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-extensions/2.2254.v2a_978de46f35/pipeline-model-extensions.hpi";
      sha256 = "875b3573b293608d83802f2417d5204d83cde853ba73c16460287862ceac5775";
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
      url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-tags-metadata/2.2254.v2a_978de46f35/pipeline-stage-tags-metadata.hpi";
      sha256 = "c854581a16341a07f5c9920d2049d232c84869892edf2c6be84d4358ee8ee0ea";
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
      url = "https://updates.jenkins-ci.org/download/plugins/promoted-builds/992.va_00888f21b_74/promoted-builds.hpi";
      sha256 = "c09df9eb876d2ae7e84f14a0f26b671891ed9653b71bc5216d52ab160eb82c86";
    };
  };
  rebuild = mkJenkinsPlugin {
    name = "rebuild";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/rebuild/338.va_0a_b_50e29397/rebuild.hpi";
      sha256 = "47c7a5096791c9186546b4b302aeb0bc3b98bbdb9ae0ba9030ceb76732ef9b05";
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
  snakeyaml-api = mkJenkinsPlugin {
    name = "snakeyaml-api";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/snakeyaml-api/2.3-125.v4d77857a_b_402/snakeyaml-api.hpi";
      sha256 = "8995f229e7e1558fd8482229ed132353cbb3258009f3b9f1845d617f0ac17e42";
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
      url = "https://updates.jenkins-ci.org/download/plugins/support-core/1725.va_2a_9f06eed61/support-core.hpi";
      sha256 = "fc996e768a25baa7567294d5baa8bf5769d39da825457b01f316a88263128b35";
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
      url = "https://updates.jenkins-ci.org/download/plugins/trilead-api/2.209.v0e69b_c43c245/trilead-api.hpi";
      sha256 = "7e8c00767ac24d017e262665d676ccd74b1b22028f7210f85520ff139bd821ed";
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
      url = "https://updates.jenkins-ci.org/download/plugins/workflow-api/1371.ve334280b_d611/workflow-api.hpi";
      sha256 = "0557f6cea9e5f4658e0685a614ac41340df3e1181669facc1e6b4f7c61eeb183";
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
      url = "https://updates.jenkins-ci.org/download/plugins/workflow-cps/4106.v7a_8a_8176d450/workflow-cps.hpi";
      sha256 = "827733d216af52214b32a0f8e270232281fa90599cd22f6027cb56830e70c929";
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
      url = "https://updates.jenkins-ci.org/download/plugins/workflow-job/1520.v56d65e3b_4566/workflow-job.hpi";
      sha256 = "349392a7dbd1dc3b668bb61f3f0b8f268b2ea30e29029af98341dac3317f8457";
    };
  };
  workflow-multibranch = mkJenkinsPlugin {
    name = "workflow-multibranch";
    src = fetchurl {
      url = "https://updates.jenkins-ci.org/download/plugins/workflow-multibranch/806.vb_b_688f609ee9/workflow-multibranch.hpi";
      sha256 = "647058cdd2fdcc28a539d8f3634e2568136d49dcbacc0a6773dfa39e0a0635be";
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
      url = "https://updates.jenkins-ci.org/download/plugins/workflow-support/968.v8f17397e87b_8/workflow-support.hpi";
      sha256 = "5f515bcd51f7ed69cf3d35c7eab4b6918888a8f881a41e3ff1e95c05be082444";
    };
  };
}
