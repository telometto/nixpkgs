{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.webzfs;

  envValue = value: if lib.isBool value then lib.boolToString value else toString value;

  serviceEnvironment =
    lib.mapAttrs (_: envValue) cfg.settings
    // {
      BIND_IP = cfg.host;
      PORT = toString cfg.port;
      SOCKET_UMASK = cfg.socketUmask;
      WORKERS = toString cfg.workers;
      HOME = cfg.dataDir;
    }
    // lib.optionalAttrs (cfg.bind != null) {
      BIND = cfg.bind;
    };

  generatedSecretKeyFile = "${cfg.dataDir}/secret-key";
  secretKeyFile = if cfg.secretKeyFile == null then generatedSecretKeyFile else cfg.secretKeyFile;

  servicePath = lib.concatStringsSep ":" (
    [ "/run/wrappers/bin" ]
    ++
      lib.optional (cfg.path != [ ])
        "${lib.makeBinPath cfg.path}:${lib.makeSearchPathOutput "bin" "sbin" cfg.path}"
  );
in
{
  meta.maintainers = with lib.maintainers; [ telometto ];

  options.services.webzfs = {
    enable = lib.mkEnableOption "WebZFS, a ZFS web management interface";

    package = lib.mkPackageOption pkgs "webzfs" { };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = ''
        IP address WebZFS listens on when {option}`services.webzfs.bind` is unset.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 26619;
      description = ''
        TCP port WebZFS listens on when {option}`services.webzfs.bind` is unset.
      '';
    };

    bind = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "unix:/run/webzfs/webzfs.sock";
      description = ''
        Gunicorn bind address. When set, this overrides {option}`services.webzfs.host`
        and {option}`services.webzfs.port`.
      '';
    };

    socketUmask = lib.mkOption {
      type = lib.types.strMatching "0o[0-7]{3}";
      default = "0o007";
      example = "0o077";
      description = ''
        Umask used by Gunicorn for Unix socket permissions.
      '';
    };

    workers = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = ''
        Number of Gunicorn worker processes.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open {option}`services.webzfs.port` in the firewall.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/webzfs";
      description = ''
        State directory used as WebZFS' home directory. WebZFS stores user
        settings, logs, and generated secrets below `.config/webzfs` here.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = ''
        User account under which WebZFS runs.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = ''
        Group account under which WebZFS runs.
      '';
    };

    settings = lib.mkOption {
      type =
        with lib.types;
        attrsOf (oneOf [
          bool
          int
          str
          path
        ]);
      default = { };
      example = {
        CAPTION = "WebZFS";
        AUTH_SESSION_EXPIRES_SECONDS = 3600;
        SMTP_ENABLED = false;
      };
      description = ''
        Additional environment variables passed to WebZFS. Do not put secrets
        here because these values are stored in the Nix store; use
        {option}`services.webzfs.environmentFile` or
        {option}`services.webzfs.secretKeyFile` for secrets.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/webzfs.env";
      description = ''
        Environment file passed to the WebZFS service. This can be used for
        secret or deployment-specific settings; see {manpage}`systemd.exec(5)`.
      '';
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/webzfs-secret-key";
      description = ''
        File containing the WebZFS `SECRET_KEY`. If unset, a persistent key is
        generated in {option}`services.webzfs.dataDir`.
      '';
    };

    path = lib.mkOption {
      type = with lib.types; listOf package;
      default = with pkgs; [
        config.boot.zfs.package
        coreutils
        diffutils
        gnugrep
        gnutar
        gzip
        iproute2
        kmod
        procps
        sanoid
        smartmontools
        systemd
        util-linux
      ];
      defaultText = lib.literalExpression ''
        with pkgs; [
          config.boot.zfs.package
          coreutils
          diffutils
          gnugrep
          gnutar
          gzip
          iproute2
          kmod
          procps
          sanoid
          smartmontools
          systemd
          util-linux
        ]
      '';
      description = ''
        Packages added to the WebZFS service `PATH`. `/run/wrappers/bin` is
        inserted before these package paths so wrapped privileged helpers are
        found first.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.webzfs.settings = {
      CAPTION = lib.mkDefault "webzfs ${cfg.package.version}";
      AUTH_SESSION_EXPIRES_SECONDS = lib.mkDefault 3600;
    };

    systemd.tmpfiles.settings."10-webzfs" = {
      ${cfg.dataDir}.d = {
        inherit (cfg) user group;
        mode = "0700";
      };
      "${cfg.dataDir}/.config".d = {
        inherit (cfg) user group;
        mode = "0700";
      };
      "${cfg.dataDir}/.config/webzfs".d = {
        inherit (cfg) user group;
        mode = "0700";
      };
    };

    systemd.services.webzfs = {
      description = "WebZFS";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      inherit (cfg) path;
      environment = serviceEnvironment // {
        PATH = lib.mkForce servicePath;
      };

      preStart = lib.optionalString (cfg.secretKeyFile == null) ''
        if [ ! -s ${lib.escapeShellArg generatedSecretKeyFile} ]; then
          umask 077
          ${pkgs.openssl}/bin/openssl rand -hex 32 > ${lib.escapeShellArg generatedSecretKeyFile}
        fi
      '';

      script = ''
        export SECRET_KEY="$(cat ${lib.escapeShellArg secretKeyFile})"
        exec ${lib.getExe cfg.package}
      '';

      serviceConfig = {
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        WorkingDirectory = "${cfg.package}/lib/webzfs";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RuntimeDirectory = "webzfs";
        UMask = "0077";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
