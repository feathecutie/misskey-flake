{ config
, pkgs
, lib
, ...
}:

let
  cfg = config.services.misskey;
  settingsFormat = pkgs.formats.yaml { };
in

{
  options = {
    services.misskey = {
      enable = lib.mkEnableOption "misskey";
      package = lib.mkPackageOption pkgs "misskey" { };
      settings = lib.mkOption {
        type = settingsFormat.type;
        default = { };
        description = ''
          Configuration for Misskey, see
          <link xlink:href="https://github.com/misskey-dev/misskey/blob/develop/.config/example.yml"/>
          for supported settings.
        '';
      };
      database = {
        createLocally = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Create the PostgreSQL database locally";
        };
      };
      redis = {
        createLocally = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Create and use a local Redis instance";
        };
        port = lib.mkOption { };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.misskey = {
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        MISSKEY_CONFIG_YML = settingsFormat.generate "misskey-config.yml" (
          lib.recursiveUpdate
            (lib.recursiveUpdate cfg.settings (lib.optionalAttrs cfg.database.createLocally {
              db = {
                db = "misskey";
                host = "/var/run/postgresql";
                port = config.services.postgresql.settings.port;
                user = "misskey";
                pass = null;
              };
            }))
            (lib.optionalAttrs cfg.redis.createLocally {
              redis = {
                host = "localhost";
                port = 6379;
              };
            })
        );
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/misskey migrateandstart";
        # StateDirectory = "misskey";
        # StateDirectoryMode = "700";
        # RuntimeDirectory = "misskey";
        # RuntimeDirectoryMode = "700";
        TimeoutSec = 60;
        DynamicUser = true;
        User = "misskey";
        # LockPersonality = true;
        # PrivateDevices = true;
        # PrivateUsers = true;
        # ProtectClock = true;
        # ProtectControlGroups = true;
        # ProtectHome = true;
        # ProtectHostname = true;
        # ProtectKernelLogs = true;
        # ProtectProc = "invisible";
        # ProtectKernelModules = true;
        # ProtectKernelTunables = true;
        # RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX AF_NETLINK";
        # RestrictNamespaces = true;
        # RestrictRealtime = true;
        # SystemCallArchitectures = "native";
        # SystemCallFilter = "@system-service";
        # UMask = "0077";
      };
    };

    services.postgresql = lib.mkIf cfg.database.createLocally {
      enable = true;
      ensureDatabases = [ "misskey" ];
      ensureUsers = [
        {
          name = "misskey";
          ensureDBOwnership = true;
        }
      ];
    };

    services.redis.servers = lib.mkIf cfg.redis.createLocally {
      misskey = {
        enable = true;
        port = 6379;
      };
    };
  };
}

