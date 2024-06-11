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
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.misskey = {
      after = [ "network-online.target" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      preStart =
        let
          configFile = settingsFormat.generate "misskey-config.yml" (
            lib.recursiveUpdate cfg.settings (lib.mkIf cfg.database.createLocally {
              db = {
                host = "localhost";
                port = config.services.postgresql.settings.port;
                user = "misskey";
              };
            })
          );
        in
        ''
          ${pkgs.envsubst}/bin/envsubst -i ${configFile} > /run/misskey/default.yml
        '';
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/misskey migrateandstart";
        WorkingDirectory = "${cfg.package} /data";
        StateDirectory = "misskey";
        StateDirectoryMode = "700";
        RuntimeDirectory = "misskey";
        RuntimeDirectoryMode = "700";
        TimeoutSec = 60;
        DynamicUser = true;
        User = "misskey";
        LockPersonality = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectProc = "invisible";
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX AF_NETLINK";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = "@system-service";
        UMask = "0077";
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
  };
}

