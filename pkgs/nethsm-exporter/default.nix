{ python3Packages, ... }:
python3Packages.buildPythonApplication rec {
  pname = "nethsm-exporter";
  version = "0.1.0";
  pyproject = false;

  src = ./src;

  propagatedBuildInputs = with python3Packages; [
    prometheus-client
    loguru
    requests
  ];

  installPhase = ''
    install -Dm755 nethsm_exporter.py "$out/bin/${pname}"
  '';

  meta.mainProgram = pname;
}
