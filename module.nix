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
          description = "Create the PostgreSQL database locally. Overrides `settings.db.{db,host,port,user,pass}`.";
        };
      };
      redis = {
        createLocally = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Create and use a local Redis instance. Overrides `settings.redis.host`";
        };
        # pubSub.createLocally = lib.mkOption {
        #   type = lib.types.bool;
        #   default = false;
        #   description = "Create and use a local Redis instance. Overrides `settings.redisForPubSub.host`";
        # };
        # jobQueue.createLocally = lib.mkOption {
        #   type = lib.types.bool;
        #   default = false;
        #   description = "Create and use a local Redis instance. Overrides `settings.redisForJobQueue.host`";
        # };
        # timelines.createLocally = lib.mkOption {
        #   type = lib.types.bool;
        #   default = false;
        #   description = "Create and use a local Redis instance. Overrides `settings.redisForTimelines.host`";
        # };
      };
      reverseProxy = {
        enable = lib.mkEnableOption "a HTTP proxy for Misskey";
        webserver = lib.mkOption {
          type = lib.types.enum [ "caddy" /*"nginx"*/ ];
          default = "caddy";
          description = "The webserver to use as a reverse proxy.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.misskey = {
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        MISSKEY_CONFIG_YML = settingsFormat.generate "misskey-config.yml"
          (
            lib.recursiveUpdate cfg.settings {
              db = lib.optionalAttrs cfg.database.createLocally {
                db = "misskey";
                # Use unix socket instead of localhost to allow PostgreSQL peer authentication,
                # required for `services.postgresql.ensureUsers`
                host = "/var/run/postgresql";
                port = config.services.postgresql.settings.port;
                user = "misskey";
                pass = null;
              };
              redis = lib.optionalAttrs cfg.redis.createLocally {
                host = "localhost";
              };
            }
          )
        ;
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/misskey migrateandstart";
        StateDirectory = "misskey";
        StateDirectoryMode = "700";
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
        port = cfg.settings.redis.port;
      };
    };

    services.caddy = lib.mkIf (cfg.reverseProxy.enable && cfg.reverseProxy.webserver == "caddy") {
      enable = true;
      virtualHosts.${cfg.settings.url} = {
        extraConfig = ''
          reverse_proxy localhost:${toString cfg.settings.port}
        '';
      };
    };

    # services.nginx = lib.mkIf (cfg.reverseProxy.enable && cfg.reverseProxy.webserver == "nginx") {
    #   enable = true;
    #   virtualHosts.${cfg.settings.url} = {
    #     enableACME = true;
    #     locations."/" = {
    #       proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
    #       recommendedProxySettings = true;
    #     };
    #   };
    # };
  };
}

