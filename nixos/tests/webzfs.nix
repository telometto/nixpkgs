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
    machine.start()
    machine.wait_for_unit("webzfs.service")
    machine.wait_for_open_port(${toString port})

    machine.succeed("curl --fail --silent --show-error http://127.0.0.1:${toString port}/login/ | grep 'ZFS Management'")
    machine.succeed("curl --fail --silent --show-error http://127.0.0.1:${toString port}/static/css/styles.css | grep -- '--tw-border-spacing-x'")
    machine.succeed("curl --fail --silent --show-error http://127.0.0.1:${toString port}/static/css/themes/webzfs-theme-carbon-blue.css | grep 'WebZFS Theme'")
    machine.succeed("test -s /var/lib/webzfs/secret-key")

    pid = machine.succeed("systemctl show -p MainPID --value webzfs.service").strip()
    environ = machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/environ")
    assert "WEBZFS_TEST_ENV=from-env-file" in environ
    assert "CAPTION=NixOS WebZFS Test" in environ
    assert "AUTH_SESSION_EXPIRES_SECONDS=7200" in environ
  '';
}
