{
  config,
  lib,
  pkgs,
  ...
}:

let
  port = 26620;
  envFile = pkgs.writeText "webzfs-test.env" ''
    WEBZFS_TEST_ENV=from-env-file
  '';
in
{
  name = "webzfs";

  meta.maintainers = with lib.maintainers; [ telometto ];

  nodes.machine =
    { ... }:
    {
      services.webzfs = {
        enable = true;
        inherit port;
        settings = {
          CAPTION = "NixOS WebZFS Test";
          AUTH_SESSION_EXPIRES_SECONDS = 7200;
        };
        environmentFile = envFile;
      };
    };

  testScript = ''
    import base64
    import hashlib
    import hmac
    import json
    import time

    machine.start()
    machine.wait_for_unit("webzfs.service")
    machine.wait_for_open_port(${toString port})

    machine.succeed("curl --fail --silent --show-error http://127.0.0.1:${toString port}/login/ | grep 'ZFS Management'")
    machine.succeed("curl --fail --silent --show-error http://127.0.0.1:${toString port}/static/css/styles.css | grep -- '--tw-border-spacing-x'")
    machine.succeed("curl --fail --silent --show-error http://127.0.0.1:${toString port}/static/css/themes/webzfs-theme-carbon-blue.css | grep 'WebZFS Theme'")
    machine.succeed("test -s /var/lib/webzfs/secret-key")

    secret = machine.succeed("cat /var/lib/webzfs/secret-key").strip()
    def base64url(data):
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    header = base64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = base64url(json.dumps({"username": "root", "exp": int(time.time()) + 3600}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    signature = base64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
    token = f"{header}.{payload}.{signature}"
    machine.succeed(f"curl --fail --silent --show-error --cookie token={token} http://127.0.0.1:${toString port}/utils/files/ | grep 'File Browser'")

    pid = machine.succeed("systemctl show -p MainPID --value webzfs.service").strip()
    environ = machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/environ")
    assert "WEBZFS_TEST_ENV=from-env-file" in environ
    assert "CAPTION=NixOS WebZFS Test" in environ
    assert "AUTH_SESSION_EXPIRES_SECONDS=7200" in environ

    path = next(line.split("=", 1)[1] for line in environ.splitlines() if line.startswith("PATH="))
    path_entries = path.split(":")
    wrappers_index = path_entries.index("/run/wrappers/bin")
    assert wrappers_index < path_entries.index("${pkgs.coreutils}/bin"), path
    assert wrappers_index < path_entries.index("${pkgs.sanoid}/bin"), path
    assert "${pkgs.sudo}/bin" not in path_entries, path
  '';
}
