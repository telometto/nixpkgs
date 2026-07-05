{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  nixosTests,
  python3Packages,
}:

let
  pythonPath = with python3Packages; [
    fastapi
    gunicorn
    humanize
    jinja2
    paramiko
    psutil
    pydantic-settings
    python-dotenv
    python-jose
    python-multipart
    python-pam
    rich
    typer
    uvicorn
  ];
in
buildNpmPackage (finalAttrs: {
  pname = "webzfs";
  version = "0.70.0-unstable-2026-05-24";

  src = fetchFromGitHub {
    owner = "webzfs";
    repo = "webzfs";
    rev = "1c2cbfe1229a6eef4182aad65ade099af1bcfd70";
    hash = "sha256-kypQUKPU3NZrXJlkRB6Dg2YqQ+kY/YRXpnuToj2lzmM=";
  };

  npmDepsHash = "sha256-27+8x4AbHayepOex/g/fhn/9DzkWPOqIATYyWszgdh4=";

  patches = [
    ./template-response-compat.patch
  ];

  npmBuildScript = "build:css";

  nativeBuildInputs = [
    makeWrapper
  ];

  postPatch = ''
    substituteInPlace services/theme.py services/corner_style.py \
      --replace-fail 'Path("/opt/webzfs/.config/webzfs")' 'Path.home() / ".config/webzfs"'

    substituteInPlace services/theme.py services/corner_style.py \
      --replace-fail '/opt/webzfs/.config/webzfs' '~/.config/webzfs'

    substituteInPlace views/utils_settings.py templates/utils/settings/index.jinja \
      --replace-fail '/opt/webzfs/.config/webzfs' '~/.config/webzfs'

    substituteInPlace services/storage.py \
      --replace-fail "temp_file = file_path.with_suffix('.tmp')" \
                     "temp_file = file_path.with_name(f'{file_path.name}.{os.getpid()}.{threading.get_ident()}.tmp')"

    substituteInPlace views/utils_scrub.py \
      --replace-fail 'import json' 'import json
    import os
    import threading' \
      --replace-fail "temp_file = self.schedules_file.with_suffix('.tmp')" \
                     "temp_file = self.schedules_file.with_name(f'{self.schedules_file.name}.{os.getpid()}.{threading.get_ident()}.tmp')"

    substituteInPlace services/smart_monitoring.py \
      --replace-fail 'import json' 'import json
    import os
    import threading' \
      --replace-fail "temp_file = file_path.with_suffix('.tmp')" \
                     "temp_file = file_path.with_name(f'{file_path.name}.{os.getpid()}.{threading.get_ident()}.tmp')"

    substituteInPlace services/health_analysis.py \
      --replace-fail 'import json' 'import json
    import os' \
      --replace-fail 'temp_file = file_path.with_suffix(".tmp")' \
                     'temp_file = file_path.with_name(f"{file_path.name}.{os.getpid()}.{threading.get_ident()}.tmp")'

    substituteInPlace services/backup_restore.py \
      --replace-fail 'tmp = target.with_suffix(target.suffix + ".tmp")' \
                     'tmp = target.with_name(f"{target.name}.{os.getpid()}.{time.time_ns()}.tmp")'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/webzfs $out/bin
    cp -r \
      auth \
      config \
      core \
      services \
      static \
      templates \
      views \
      $out/lib/webzfs/

    makeWrapper ${python3Packages.gunicorn}/bin/gunicorn $out/bin/webzfs \
      --prefix PYTHONPATH : "${placeholder "out"}/lib/webzfs:${python3Packages.makePythonPath pythonPath}" \
      --run "cd ${placeholder "out"}/lib/webzfs" \
      --add-flags "-c ${placeholder "out"}/lib/webzfs/config/gunicorn.conf.py"

    runHook postInstall
  '';

  passthru = {
    tests.webzfs = nixosTests.webzfs;
  };

  meta = {
    description = "ZFS web management interface";
    homepage = "https://github.com/webzfs/webzfs";
    changelog = "https://github.com/webzfs/webzfs/commits/${finalAttrs.src.rev}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ telometto ];
    mainProgram = "webzfs";
    platforms = lib.platforms.linux;
  };
})
